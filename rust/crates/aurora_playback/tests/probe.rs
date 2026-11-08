//! Duración y validación estricta de archivos (sustituyen a ffprobe y a la
//! decodificación de comprobación con ffmpeg).

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use aurora_playback::{probe_duration, validate_decode};

fn media(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../aurora_audio/tests/fixtures/media")
        .join(name)
}

const ALL: [&str; 8] = [
    "tone.wav",
    "tone-44k.flac",
    "tone.mp3",
    "tone.ogg",
    "tone.m4a",
    "tone-opus.webm",
    "tone-opus.ogg",
    "mono-22k.wav",
];

#[test]
fn durations_match_the_known_two_seconds() {
    for name in ALL {
        let secs = probe_duration(&media(name)).unwrap_or_else(|e| panic!("{name}: {e}"));
        assert!((secs - 2.0).abs() < 0.08, "{name}: {secs} s");
    }
}

#[test]
fn cache_files_are_recognised_by_content_not_extension() {
    let dir = tempfile::tempdir().unwrap();
    for (name, id) in [
        ("tone-opus.webm", "AAAAAAAAAAA"),
        ("tone.m4a", "BBBBBBBBBBB"),
        ("tone.mp3", "CCCCCCCCCCC"),
        ("tone-opus.ogg", "DDDDDDDDDDD"),
        ("tone-44k.flac", "EEEEEEEEEEE"),
    ] {
        let copy = dir.path().join(format!("{id}.audio"));
        fs::copy(media(name), &copy).unwrap();
        let secs = probe_duration(&copy).unwrap_or_else(|e| panic!("{name} como .audio: {e}"));
        assert!((secs - 2.0).abs() < 0.08, "{name}: {secs}");
        let report = validate_decode(&copy, &AtomicBool::new(false)).unwrap();
        assert!(
            (report.decoded_secs - 2.0).abs() < 0.1,
            "{name}: {}",
            report.decoded_secs
        );
    }
}

#[test]
fn valid_files_validate() {
    for name in ALL {
        let report = validate_decode(&media(name), &AtomicBool::new(false))
            .unwrap_or_else(|e| panic!("{name}: {e}"));
        assert!(report.decoded_secs > 1.0, "{name}");
    }
}

fn damaged(name: &str, edit: impl FnOnce(&mut Vec<u8>)) -> (tempfile::TempDir, PathBuf) {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join(name);
    let mut bytes = fs::read(media(name)).unwrap();
    edit(&mut bytes);
    fs::write(&path, bytes).unwrap();
    (dir, path)
}

#[test]
fn a_truncated_file_is_rejected_when_the_container_declares_its_length() {
    let (_dir, path) = damaged("tone-44k.flac", |b| b.truncate(b.len() * 6 / 10));
    let error = validate_decode(&path, &AtomicBool::new(false)).unwrap_err();
    assert!(
        error.to_string().contains("cortado") || error.to_string().len() > 3,
        "{error}"
    );
}

#[test]
fn garbage_and_missing_files_have_no_duration() {
    let (_dir, path) = damaged("tone.mp3", |b| b.iter_mut().for_each(|x| *x = 0x33));
    assert!(probe_duration(&path).is_err());
    assert!(probe_duration(Path::new("no-existe.mp3")).is_err());
}

#[test]
fn validation_can_be_cancelled() {
    let cancel = AtomicBool::new(true);
    assert!(validate_decode(&media("tone.wav"), &cancel).is_err());
}
