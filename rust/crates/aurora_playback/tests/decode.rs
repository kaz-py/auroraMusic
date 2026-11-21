//! Decodificación de los formatos que Aurora reproduce, con archivos generados
//! con FFmpeg: canal izquierdo 440 Hz y derecho 880 Hz a amplitud 0,0625 (la de `sine` de lavfi, 0,125, por `volume=0.5`; dos
//! segundos). Se comprueba duración, frecuencia y nivel de cada canal.

use std::fs::File;
use std::path::PathBuf;

use aurora_playback::{OpenError, PcmStream};

/// Nivel nominal de los tonos de prueba.
const LEVEL: f64 = 0.0625;

fn media(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../aurora_audio/tests/fixtures/media")
        .join(name)
}

fn decode(name: &str, out_rate: u32, start: f64) -> Result<(Vec<f32>, PcmStream), OpenError> {
    let path = media(name);
    let extension = path.extension().and_then(|e| e.to_str()).map(str::to_owned);
    let file = File::open(&path).unwrap();
    let mut stream = PcmStream::open(Box::new(file), extension.as_deref(), out_rate, start, None)?;
    let mut pcm = Vec::new();
    while stream.next_chunk(&mut pcm)? {}
    Ok((pcm, stream))
}

/// Amplitud y frecuencia dominante (Goertzel en una rejilla) de un canal.
fn analyse(pcm: &[f32], channel: usize, rate: u32) -> (f64, f64) {
    let samples: Vec<f64> = pcm
        .iter()
        .skip(channel)
        .step_by(2)
        .map(|&s| s as f64)
        .collect();
    // Se ignora el principio y el final (retardos de filtro y cola del códec).
    let margin = rate as usize / 10;
    let body = &samples[margin..samples.len() - margin];
    let mut best = (0.0, 0.0);
    for hz in (100..4000).step_by(5) {
        let w = 2.0 * std::f64::consts::PI * hz as f64 / rate as f64;
        let (mut re, mut im) = (0.0, 0.0);
        for (n, s) in body.iter().enumerate() {
            re += s * (w * n as f64).cos();
            im += s * (w * n as f64).sin();
        }
        let amp = 2.0 * (re * re + im * im).sqrt() / body.len() as f64;
        if amp > best.0 {
            best = (amp, hz as f64);
        }
    }
    best
}

fn check(name: &str, rate: u32, tolerance: f64) {
    let (pcm, stream) = decode(name, rate, 0.0).unwrap_or_else(|e| panic!("{name}: {e}"));
    let frames = pcm.len() / 2;
    let secs = frames as f64 / rate as f64;
    assert!((secs - 2.0).abs() < tolerance, "{name}: dura {secs} s");
    let (left_amp, left_hz) = analyse(&pcm, 0, rate);
    let (right_amp, right_hz) = analyse(&pcm, 1, rate);
    assert!(
        (left_hz - 440.0).abs() <= 10.0,
        "{name}: izquierdo {left_hz} Hz"
    );
    assert!(
        (right_hz - 880.0).abs() <= 10.0,
        "{name}: derecho {right_hz} Hz"
    );
    assert!(
        (left_amp - LEVEL).abs() < 0.008,
        "{name}: nivel izquierdo {left_amp}"
    );
    assert!(
        (right_amp - LEVEL).abs() < 0.008,
        "{name}: nivel derecho {right_amp}"
    );
    assert!(
        pcm.iter().all(|s| s.is_finite() && s.abs() <= 1.001),
        "{name}: fuera de rango"
    );
    assert_eq!(stream.out_rate(), rate);
}

#[test]
fn wav_at_native_rate() {
    check("tone.wav", 48_000, 0.01);
}

#[test]
fn flac_is_resampled_from_44100() {
    check("tone-44k.flac", 48_000, 0.05);
}

#[test]
fn mp3_is_resampled_from_44100() {
    check("tone.mp3", 48_000, 0.1);
}

#[test]
fn vorbis_in_ogg() {
    check("tone.ogg", 48_000, 0.05);
}

#[test]
fn aac_in_m4a() {
    check("tone.m4a", 48_000, 0.1);
}

#[test]
fn opus_in_webm() {
    check("tone-opus.webm", 48_000, 0.05);
}

#[test]
fn opus_in_ogg() {
    check("tone-opus.ogg", 48_000, 0.05);
}

#[test]
fn output_at_another_device_rate() {
    check("tone.wav", 44_100, 0.05);
    check("tone-opus.webm", 96_000, 0.05);
}

#[test]
fn mono_input_is_duplicated_to_both_channels() {
    let (pcm, _) = decode("mono-22k.wav", 48_000, 0.0).unwrap();
    let (left, left_hz) = analyse(&pcm, 0, 48_000);
    let (right, right_hz) = analyse(&pcm, 1, 48_000);
    assert!((left_hz - 660.0).abs() <= 10.0 && (right_hz - 660.0).abs() <= 10.0);
    assert!((left - right).abs() < 1e-3);
}

#[test]
fn starting_offset_skips_the_beginning() {
    for name in [
        "tone.wav",
        "tone-44k.flac",
        "tone.mp3",
        "tone.ogg",
        "tone.m4a",
        "tone-opus.webm",
        "tone-opus.ogg",
    ] {
        let (pcm, _) = decode(name, 48_000, 1.0).unwrap_or_else(|e| panic!("{name}: {e}"));
        let secs = pcm.len() as f64 / 2.0 / 48_000.0;
        assert!(
            (secs - 1.0).abs() < 0.08,
            "{name}: tras saltar a 1 s quedan {secs} s"
        );
        let (amp, hz) = analyse(&pcm, 0, 48_000);
        assert!(
            (hz - 440.0).abs() <= 10.0 && (amp - LEVEL).abs() < 0.01,
            "{name}: {amp} a {hz} Hz"
        );
    }
}

#[test]
fn garbage_is_not_mistaken_for_audio() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("noise.mp3");
    std::fs::write(&path, vec![0x5Au8; 4096]).unwrap();
    let file = File::open(&path).unwrap();
    let result = PcmStream::open(Box::new(file), Some("mp3"), 48_000, 0.0, None);
    assert!(result.is_err());
}
