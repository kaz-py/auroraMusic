//! Reconocimiento real con Vosk sobre voz sintética en español (dos voces).
//!
//! Necesita `libvosk` y el modelo, que no están en el repositorio:
//! `AURORA_VOSK_LIB=<ruta a libvosk.dll|.so>` y `AURORA_VOSK_MODEL=<carpeta del
//! modelo>`. Sin ellas las pruebas se omiten (avisando).

use std::fs;
use std::path::{Path, PathBuf};

use aurora_voice::{analyze_pcm, install_model, model_is_installed, vocabulary, Heard, Intent};

fn setup() -> Option<(PathBuf, PathBuf)> {
    let lib = PathBuf::from(std::env::var_os("AURORA_VOSK_LIB")?);
    let model = PathBuf::from(std::env::var_os("AURORA_VOSK_MODEL")?);
    (lib.is_file() && model_is_installed(&model)).then_some((lib, model))
}

fn wav(name: &str) -> Vec<i16> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name);
    let bytes = fs::read(path).unwrap();
    // Cabecera RIFF: se busca el trozo `data`.
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let size = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
        if &bytes[at..at + 4] == b"data" {
            let end = (at + 8 + size).min(bytes.len());
            return bytes[at + 8..end]
                .chunks_exact(2)
                .map(|b| i16::from_le_bytes([b[0], b[1]]))
                .collect();
        }
        at += 8 + size + (size & 1);
    }
    panic!("{name}: sin trozo data");
}

fn commands(heard: &[Heard]) -> Vec<Intent> {
    heard
        .iter()
        .filter_map(|h| match h {
            Heard::Command(i) => Some(*i),
            _ => None,
        })
        .collect()
}

#[test]
fn spoken_commands_with_aurora_are_understood_by_two_voices() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    let cases = [
        ("pos_pausa", Intent::Pause),
        ("pos_siguiente", Intent::Next),
        ("pos_continua", Intent::Resume),
        ("pos_reproduce", Intent::Play),
        ("pos_anterior", Intent::Previous),
        ("pos_salta", Intent::Next),
        ("pos_sigue", Intent::Resume),
        ("pos_pon", Intent::Play),
    ];
    let mut wrong = Vec::new();
    for (name, want) in cases {
        for voice in ["d", "a"] {
            let heard = analyze_pcm(&lib, &model, &wav(&format!("{name}_{voice}.wav"))).unwrap();
            if commands(&heard) != vec![want] {
                wrong.push(format!("{name}_{voice}: {heard:?}"));
            }
        }
    }
    assert!(wrong.is_empty(), "no reconocidas:\n{}", wrong.join("\n"));
}

#[test]
fn speech_without_the_wake_word_never_triggers() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    let mut wrong = Vec::new();
    for name in [
        "neg_sin_aurora_pausa",
        "neg_sin_aurora_siguiente",
        "neg_charla",
        "neg_video",
        "neg_laura",
        "neg_boreal",
        "neg_musica",
    ] {
        for voice in ["d", "a"] {
            let heard = analyze_pcm(&lib, &model, &wav(&format!("{name}_{voice}.wav"))).unwrap();
            if !commands(&heard).is_empty() {
                wrong.push(format!("{name}_{voice}: {heard:?}"));
            }
        }
    }
    assert!(
        wrong.is_empty(),
        "activaciones falsas:\n{}",
        wrong.join("\n")
    );
}

#[test]
fn silence_and_noise_never_trigger() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    let silence = vec![0i16; 16_000 * 5];
    assert!(commands(&analyze_pcm(&lib, &model, &silence).unwrap()).is_empty());
    // Ruido pseudoaleatorio fuerte.
    let mut seed = 12345u32;
    let noise: Vec<i16> = (0..16_000 * 5)
        .map(|_| {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            ((seed >> 16) as i16) / 3
        })
        .collect();
    assert!(commands(&analyze_pcm(&lib, &model, &noise).unwrap()).is_empty());
}

#[test]
fn the_model_knows_every_word_of_the_grammar() {
    let Some((lib, model_dir)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    let vosk = aurora_voice::vosk::Vosk::load(&lib).unwrap();
    let model = vosk.model(&model_dir).unwrap();
    let unknown: Vec<String> = vocabulary()
        .into_iter()
        .filter(|w| !model.knows(w))
        .collect();
    assert!(unknown.is_empty(), "el modelo no conoce: {unknown:?}");
}

#[test]
fn a_missing_library_or_model_is_a_clear_error() {
    let missing = Path::new("no-existe/libvosk.dll");
    let error = aurora_voice::vosk::Vosk::load(missing)
        .err()
        .unwrap()
        .to_string();
    assert!(error.contains("biblioteca de voz"), "{error}");
    let dir = tempfile::tempdir().unwrap();
    assert!(!model_is_installed(dir.path()));
    assert!(install_model(&dir.path().join("no.zip"), &dir.path().join("m")).is_err());
}

fn copy_dir(from: &Path, to: &Path) {
    fs::create_dir_all(to).unwrap();
    for entry in fs::read_dir(from).unwrap() {
        let entry = entry.unwrap();
        let target = to.join(entry.file_name());
        if entry.path().is_dir() {
            copy_dir(&entry.path(), &target);
        } else {
            fs::copy(entry.path(), target).unwrap();
        }
    }
}

#[test]
fn a_model_in_a_folder_with_accents_loads() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    // Nombres de cuenta como «José» o «Ñandú» son corrientes en español.
    let root = std::env::temp_dir().join(format!("José Ñandú {}", std::process::id()));
    let copy = root.join("modelo");
    copy_dir(&model, &copy);
    let heard = analyze_pcm(&lib, &copy, &wav("pos_pausa_d.wav"));
    fs::remove_dir_all(&root).unwrap();
    assert_eq!(commands(&heard.unwrap()), vec![Intent::Pause]);
}
