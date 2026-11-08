//! Motor de reproducción sin dispositivo (`Engine::headless`): la prueba hace
//! de dispositivo y consume el audio con `pull`.

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use aurora_audio::EqBand;
use aurora_playback::{Engine, LoadSpec, OpenError};

const RATE: u32 = 48_000;
const LEVEL: f64 = 0.0625;

fn media(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../aurora_audio/tests/fixtures/media")
        .join(name)
}

fn spec(name: &str, start: f64) -> LoadSpec {
    LoadSpec {
        input: media(name).to_string_lossy().into_owned(),
        headers: vec![],
        start_secs: start,
    }
}

/// Consume el audio como un dispositivo hasta el final (o `limit`) y devuelve
/// solo las tramas reales (sin el silencio de los cortes por falta de datos).
fn drain(engine: &Engine, limit: Duration) -> Vec<f32> {
    let started = Instant::now();
    let mut audio = Vec::new();
    let mut last_frames = 0i64;
    loop {
        let mut buffer = vec![0f32; 480 * 2];
        engine.pull(&mut buffer);
        let state = engine.state();
        let frames = state.consumed_us * RATE as i64 / 1_000_000;
        let real = ((frames - last_frames).max(0) as usize * 2).min(buffer.len());
        audio.extend_from_slice(&buffer[..real]);
        last_frames = frames;
        if state.ended || state.error.is_some() || started.elapsed() > limit {
            return audio;
        }
        if real == 0 {
            thread::sleep(Duration::from_millis(1));
        }
    }
}

fn tone(pcm: &[f32], channel: usize) -> (f64, f64) {
    let samples: Vec<f64> = pcm
        .iter()
        .skip(channel)
        .step_by(2)
        .map(|&s| s as f64)
        .collect();
    let margin = RATE as usize / 10;
    let body = &samples[margin..samples.len() - margin];
    let mut best = (0.0, 0.0);
    for hz in (100..4000).step_by(5) {
        let w = 2.0 * std::f64::consts::PI * hz as f64 / RATE as f64;
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

fn rms(pcm: &[f32]) -> f64 {
    (pcm.iter().map(|&s| (s as f64).powi(2)).sum::<f64>() / pcm.len() as f64).sqrt()
}

fn engine() -> Engine {
    let engine = Engine::headless(RATE);
    engine.set_volume(1.0);
    engine
}

#[test]
fn plays_a_file_to_the_end() {
    let engine = engine();
    let info = engine.load(&spec("tone.wav", 0.0)).unwrap();
    assert_eq!(info.sample_rate, RATE);
    engine.play();
    let audio = drain(&engine, Duration::from_secs(20));
    let state = engine.state();
    assert!(state.ended && state.error.is_none(), "{state:?}");
    assert!(!state.buffering);
    let secs = audio.len() as f64 / 2.0 / RATE as f64;
    assert!((secs - 2.0).abs() < 0.05, "sonó {secs} s");
    let (left, left_hz) = tone(&audio, 0);
    let (right, right_hz) = tone(&audio, 1);
    assert!((left_hz - 440.0).abs() <= 10.0 && (right_hz - 880.0).abs() <= 10.0);
    assert!(
        (left - LEVEL).abs() < 0.01 && (right - LEVEL).abs() < 0.01,
        "{left} {right}"
    );
    // Lo decodificado y lo reproducido coinciden (regla de fin de flujo de Dart).
    assert!((state.decoded_us - state.consumed_us).abs() < 25_000);
}

#[test]
fn every_format_plays() {
    for name in [
        "tone-44k.flac",
        "tone.mp3",
        "tone.ogg",
        "tone.m4a",
        "tone-opus.webm",
        "tone-opus.ogg",
    ] {
        let engine = engine();
        engine
            .load(&spec(name, 0.0))
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        engine.play();
        let audio = drain(&engine, Duration::from_secs(20));
        let state = engine.state();
        assert!(state.ended && state.error.is_none(), "{name}: {state:?}");
        let secs = audio.len() as f64 / 2.0 / RATE as f64;
        assert!((secs - 2.0).abs() < 0.1, "{name}: {secs} s");
    }
}

#[test]
fn paused_engine_is_silent_and_does_not_consume() {
    let engine = engine();
    engine.load(&spec("tone.wav", 0.0)).unwrap();
    thread::sleep(Duration::from_millis(100));
    let mut buffer = vec![1f32; 960];
    engine.pull(&mut buffer);
    assert!(buffer.iter().all(|&s| s == 0.0));
    assert_eq!(engine.state().consumed_us, 0);
    engine.play();
    let mut played = vec![0f32; 4800];
    engine.pull(&mut played);
    assert!(rms(&played) > 0.01);
    let consumed = engine.state().consumed_us;
    assert!(consumed > 0);
    engine.pause();
    // La rampa de salida dura una trama de callback; la siguiente es silencio.
    let mut fade = vec![0f32; 960];
    engine.pull(&mut fade);
    let mut after = vec![1f32; 960];
    engine.pull(&mut after);
    assert!(after.iter().all(|&s| s == 0.0));
    let paused_at = engine.state().consumed_us;
    engine.pull(&mut after);
    assert_eq!(engine.state().consumed_us, paused_at);
}

#[test]
fn gain_changes_are_ramped_without_jumps() {
    let engine = engine();
    engine.load(&spec("tone.wav", 0.0)).unwrap();
    thread::sleep(Duration::from_millis(100));
    engine.play();
    let mut warm = vec![0f32; 2400];
    engine.pull(&mut warm);
    engine.set_volume(0.0);
    let mut ramp = vec![0f32; 2400];
    engine.pull(&mut ramp);
    let max_step = ramp
        .chunks_exact(2)
        .zip(ramp.chunks_exact(2).skip(1))
        .map(|(a, b)| (b[0] - a[0]).abs())
        .fold(0.0f32, f32::max);
    assert!(max_step < 0.02, "salto de {max_step}");
    assert!(ramp.chunks_exact(2).last().unwrap()[0].abs() < 0.002);
}

#[test]
fn volume_scales_the_output() {
    let measure = |volume: f32| {
        let engine = engine();
        engine.set_volume(volume);
        engine.load(&spec("tone.wav", 0.0)).unwrap();
        engine.play();
        rms(&drain(&engine, Duration::from_secs(20)))
    };
    let (full, half) = (measure(1.0), measure(0.5));
    assert!((half / full - 0.5).abs() < 0.03, "{full} {half}");
}

#[test]
fn starting_offset_plays_only_the_rest() {
    let engine = engine();
    engine.load(&spec("tone-opus.webm", 1.0)).unwrap();
    engine.play();
    let audio = drain(&engine, Duration::from_secs(20));
    let secs = audio.len() as f64 / 2.0 / RATE as f64;
    assert!((secs - 1.0).abs() < 0.08, "{secs}");
}

#[test]
fn stop_discards_the_track_and_new_loads_replace_it() {
    let engine = engine();
    engine.load(&spec("tone.wav", 0.0)).unwrap();
    engine.play();
    let generation = engine.state().generation;
    engine.stop();
    let state = engine.state();
    assert!(state.generation > generation && !state.playing && state.consumed_us == 0);
    engine.load(&spec("tone.mp3", 0.0)).unwrap();
    engine.play();
    let audio = drain(&engine, Duration::from_secs(20));
    assert!((audio.len() as f64 / 2.0 / RATE as f64 - 2.0).abs() < 0.1);
}

#[test]
fn unknown_and_missing_inputs_report_why() {
    let engine = engine();
    let dir = tempfile::tempdir().unwrap();
    let junk = dir.path().join("junk.mp3");
    std::fs::write(&junk, vec![0x11u8; 5000]).unwrap();
    let result = engine.load(&LoadSpec {
        input: junk.to_string_lossy().into_owned(),
        headers: vec![],
        start_secs: 0.0,
    });
    assert!(
        matches!(result, Err(OpenError::Unsupported(_))),
        "{result:?}"
    );
    let missing = engine.load(&LoadSpec {
        input: "no-existe.mp3".into(),
        headers: vec![],
        start_secs: 0.0,
    });
    assert!(matches!(missing, Err(OpenError::Failed(_))));
    // Un https (o un host remoto) se rechaza para que lo atienda el motor anterior.
    for url in ["https://example.com/a.mp3", "http://example.com/a.mp3"] {
        let remote = engine.load(&LoadSpec {
            input: url.into(),
            headers: vec![],
            start_secs: 0.0,
        });
        assert!(
            matches!(remote, Err(OpenError::Unsupported(_))),
            "{url}: {remote:?}"
        );
    }
}

#[test]
fn equalizer_boosts_and_reverts_to_untouched() {
    let level = |boost: f64| {
        let engine = engine();
        let mut bands: Vec<EqBand> = [60.0, 170.0, 310.0, 600.0, 1000.0, 3000.0, 6000.0, 12000.0]
            .iter()
            .map(|&f| EqBand {
                frequency: f,
                gain_db: 0.0,
                q: 1.0,
            })
            .collect();
        bands[2] = EqBand {
            frequency: 440.0,
            gain_db: boost,
            q: 1.0,
        };
        engine.set_equalizer(boost != 0.0, bands, 1.0);
        engine.load(&spec("tone.wav", 0.0)).unwrap();
        engine.play();
        tone(&drain(&engine, Duration::from_secs(20)), 0).0
    };
    let flat = level(0.0);
    let boosted = level(9.0);
    assert!((flat - LEVEL).abs() < 0.01);
    assert!(
        boosted / flat > 2.5 && boosted / flat < 3.2,
        "{flat} -> {boosted}"
    );
}

#[test]
fn spectrum_peaks_at_the_tone() {
    let engine = engine();
    engine.load(&spec("tone.wav", 0.0)).unwrap();
    engine.play();
    let mut buffer = vec![0f32; 4800];
    for _ in 0..4 {
        thread::sleep(Duration::from_millis(20));
        engine.pull(&mut buffer);
    }
    let bins = engine.spectrum();
    assert_eq!(bins.len(), 256);
    let (peak, value) = bins
        .iter()
        .enumerate()
        .fold((0, 0.0), |a, (i, &v)| if v > a.1 { (i, v) } else { a });
    // 512 puntos a 48 kHz: 93,75 Hz por bin; 440 y 880 Hz caen en los bins 4-5 y 9-10.
    assert!(matches!(peak, 4 | 5 | 9 | 10), "pico en {peak}");
    assert!(value > LEVEL * 0.3 && value < LEVEL * 1.3, "{value}");
    engine.set_visualization(false);
    assert!(engine.spectrum().iter().all(|&v| v == 0.0));
}

// ---- HTTP local con Range ---------------------------------------------------

struct Server {
    port: u16,
}

fn serve(body: Arc<Vec<u8>>, truncate_after: Option<usize>, ranges: bool) -> Server {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let body = body.clone();
            thread::spawn(move || handle(stream, &body, truncate_after, ranges));
        }
    });
    Server { port }
}

fn handle(mut stream: TcpStream, body: &[u8], truncate_after: Option<usize>, ranges: bool) {
    let mut request = Vec::new();
    let mut byte = [0u8; 1];
    while !request.ends_with(b"\r\n\r\n") {
        if stream.read(&mut byte).unwrap_or(0) == 0 {
            return;
        }
        request.push(byte[0]);
    }
    let text = String::from_utf8_lossy(&request).to_lowercase();
    let start = text
        .lines()
        .find_map(|l| l.strip_prefix("range: bytes="))
        .and_then(|r| {
            r.trim_end_matches('-')
                .split('-')
                .next()
                .and_then(|n| n.parse::<usize>().ok())
        })
        .filter(|_| ranges)
        .unwrap_or(0);
    let total = body.len();
    let payload = &body[start..];
    let head = if start > 0 {
        format!(
            "HTTP/1.1 206 Partial Content\r\nAccept-Ranges: bytes\r\nContent-Length: {}\r\nContent-Range: bytes {start}-{}/{total}\r\nConnection: close\r\n\r\n",
            payload.len(),
            total - 1
        )
    } else {
        format!(
            "HTTP/1.1 200 OK\r\n{}Content-Length: {}\r\nConnection: close\r\n\r\n",
            if ranges {
                "Accept-Ranges: bytes\r\n"
            } else {
                ""
            },
            payload.len()
        )
    };
    let _ = stream.write_all(head.as_bytes());
    let cut = truncate_after.map_or(payload.len(), |n| n.min(payload.len()));
    let _ = stream.write_all(&payload[..cut]);
    let _ = stream.flush();
}

fn http_spec(port: u16, start: f64) -> LoadSpec {
    LoadSpec {
        input: format!("http://127.0.0.1:{port}/tok/audio"),
        headers: vec![],
        start_secs: start,
    }
}

fn fixture_bytes(name: &str) -> Arc<Vec<u8>> {
    Arc::new(std::fs::read(media(name)).unwrap())
}

#[test]
fn plays_from_the_local_http_proxy() {
    for name in ["tone-opus.webm", "tone.m4a", "tone.mp3"] {
        let server = serve(fixture_bytes(name), None, true);
        let engine = engine();
        engine
            .load(&http_spec(server.port, 0.0))
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        engine.play();
        let audio = drain(&engine, Duration::from_secs(20));
        let state = engine.state();
        assert!(state.ended && state.error.is_none(), "{name}: {state:?}");
        assert!(
            (audio.len() as f64 / 2.0 / RATE as f64 - 2.0).abs() < 0.1,
            "{name}"
        );
    }
}

#[test]
fn http_seek_uses_range_requests() {
    let server = serve(fixture_bytes("tone-opus.webm"), None, true);
    let engine = engine();
    engine.load(&http_spec(server.port, 1.0)).unwrap();
    engine.play();
    let audio = drain(&engine, Duration::from_secs(20));
    assert!((audio.len() as f64 / 2.0 / RATE as f64 - 1.0).abs() < 0.1);
    assert!(engine.state().error.is_none());
}

#[test]
fn a_connection_cut_mid_stream_is_an_error_not_an_ending() {
    let bytes = fixture_bytes("tone.mp3");
    let server = serve(bytes.clone(), Some(bytes.len() * 6 / 10), true);
    let engine = engine();
    // MP3 no necesita índice final: se abre y el corte aparece al decodificar.
    engine
        .load(&http_spec(server.port, 0.0))
        .expect("la cabecera llega entera");
    engine.play();
    drain(&engine, Duration::from_secs(20));
    let state = engine.state();
    assert!(!state.ended, "no debe contarse como final: {state:?}");
    assert!(state.error.is_some(), "{state:?}");
}

#[test]
fn a_server_without_range_still_plays_from_the_start() {
    let server = serve(fixture_bytes("tone-opus.webm"), None, false);
    let engine = engine();
    engine.load(&http_spec(server.port, 0.0)).unwrap();
    engine.play();
    let audio = drain(&engine, Duration::from_secs(20));
    assert!((audio.len() as f64 / 2.0 / RATE as f64 - 2.0).abs() < 0.1);
}
