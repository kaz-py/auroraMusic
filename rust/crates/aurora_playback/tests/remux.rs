//! Opus sin pérdida: lo que sale es el mismo audio, paquete por paquete.

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use aurora_playback::{probe_duration, remux_opus_to_ogg, validate_decode, OpenError, PcmStream};

fn media(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../aurora_audio/tests/fixtures/media")
        .join(name)
}

fn decode(path: &std::path::Path, ext: &str) -> Vec<f32> {
    let file = fs::File::open(path).unwrap();
    let mut stream = PcmStream::open(Box::new(file), Some(ext), 48_000, 0.0, None).unwrap();
    let mut pcm = Vec::new();
    while stream.next_chunk(&mut pcm).unwrap() {}
    pcm
}

#[test]
fn webm_opus_becomes_an_ogg_opus_with_identical_audio() {
    let dir = tempfile::tempdir().unwrap();
    let out = dir.path().join("a.opus");
    let progress = AtomicU32::new(0);
    let secs = remux_opus_to_ogg(
        &media("tone-opus.webm"),
        &out,
        &AtomicBool::new(false),
        &progress,
    )
    .unwrap();
    assert!((secs - 2.0).abs() < 0.1, "{secs}");
    assert_eq!(progress.load(Ordering::Relaxed), 1000);
    // Es un Ogg de verdad y el archivo entero se decodifica sin errores.
    let bytes = fs::read(&out).unwrap();
    assert_eq!(&bytes[..4], b"OggS");
    assert!(
        bytes.windows(8).any(|w| w == b"OpusHead") && bytes.windows(8).any(|w| w == b"OpusTags")
    );
    let report = validate_decode(&out, &AtomicBool::new(false)).unwrap();
    assert!(
        (report.decoded_secs - 2.0).abs() < 0.1,
        "{}",
        report.decoded_secs
    );
    assert!((probe_duration(&out).unwrap() - 2.0).abs() < 0.1);
    // Mismas muestras que el original (sin recodificar no hay diferencia alguna).
    let original = decode(&media("tone-opus.webm"), "webm");
    let copy = decode(&out, "opus");
    assert_eq!(original.len(), copy.len());
    assert!(
        original.iter().zip(&copy).all(|(a, b)| a == b),
        "el audio cambió"
    );
}

#[test]
fn an_ogg_opus_source_also_passes_through() {
    let dir = tempfile::tempdir().unwrap();
    let out = dir.path().join("b.opus");
    remux_opus_to_ogg(
        &media("tone-opus.ogg"),
        &out,
        &AtomicBool::new(false),
        &AtomicU32::new(0),
    )
    .unwrap();
    assert_eq!(decode(&media("tone-opus.ogg"), "ogg"), decode(&out, "opus"));
}

#[test]
fn other_codecs_cancellation_and_junk_are_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let out = dir.path().join("c.opus");
    let run = |src: PathBuf, cancel: bool| {
        remux_opus_to_ogg(&src, &out, &AtomicBool::new(cancel), &AtomicU32::new(0))
    };
    assert!(matches!(
        run(media("tone.m4a"), false),
        Err(OpenError::Unsupported(_))
    ));
    assert!(run(media("tone.mp3"), false).is_err());
    assert!(run(media("tone-opus.webm"), true).is_err());
    let junk = dir.path().join("junk.webm");
    fs::write(&junk, vec![7u8; 3000]).unwrap();
    assert!(run(junk, false).is_err());
    assert!(run(dir.path().join("nope.webm"), false).is_err());
}
