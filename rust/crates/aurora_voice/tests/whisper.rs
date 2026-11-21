//! Reconocimiento real con Whisper sobre voz sintética en español (dos voces).
//! Necesita el modelo, que no está en el repositorio:
//! `AURORA_WHISPER_MODEL=<ruta a ggml-base-q5_1.bin>`. Sin él se omiten (avisando).

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;

use aurora_voice::{align_lyrics, listen_offline, Heard, Intent, LyricLine};

fn model() -> Option<PathBuf> {
    let path = PathBuf::from(std::env::var_os("AURORA_WHISPER_MODEL")?);
    path.is_file().then_some(path)
}

fn wav(name: &str) -> Vec<f32> {
    let path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name);
    let bytes = fs::read(path).unwrap();
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let size = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
        if &bytes[at..at + 4] == b"data" {
            return bytes[at + 8..(at + 8 + size).min(bytes.len())]
                .chunks_exact(2)
                .map(|b| i16::from_le_bytes([b[0], b[1]]) as f32 / 32768.0)
                .collect();
        }
        at += 8 + size + (size & 1);
    }
    panic!("{name}: sin trozo data");
}

fn commands(heard: &[(String, Heard)]) -> Vec<Intent> {
    heard
        .iter()
        .filter_map(|(_, h)| match h {
            Heard::Command(i) => Some(*i),
            _ => None,
        })
        .collect()
}

fn scaled(pcm: &[f32], gain: f32) -> Vec<f32> {
    pcm.iter().map(|s| s * gain).collect()
}

macro_rules! need_model {
    () => {
        match model() {
            Some(m) => m,
            None => {
                eprintln!("OMITIDA: falta AURORA_WHISPER_MODEL");
                return;
            }
        }
    };
}

#[test]
fn spoken_commands_are_understood_even_from_far_away() {
    let model = need_model!();
    let cases = [
        ("pos_pausa", Intent::Pause),
        ("pos_siguiente", Intent::Next),
        ("pos_continua", Intent::Resume),
        ("pos_reproduce", Intent::Play),
        ("pos_anterior", Intent::Previous),
        ("pos_salta", Intent::Next),
        ("pos_pon", Intent::Play),
    ];
    let mut wrong = Vec::new();
    for (name, want) in cases {
        for voice in ["d", "a"] {
            let audio = wav(&format!("{name}_{voice}.wav"));
            // Normal y como con el micrófono lejos (−30 dB y −40 dB).
            for gain in [1.0f32, 0.03, 0.01] {
                let heard = listen_offline(&model, &scaled(&audio, gain)).unwrap();
                if commands(&heard) != vec![want] {
                    wrong.push(format!("{name}_{voice} x{gain}: {heard:?}"));
                }
            }
        }
    }
    assert!(wrong.is_empty(), "no reconocidas:\n{}", wrong.join("\n"));
}

#[test]
fn speech_without_the_wake_word_never_triggers() {
    let model = need_model!();
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
            let heard = listen_offline(&model, &wav(&format!("{name}_{voice}.wav"))).unwrap();
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
    let model = need_model!();
    assert!(commands(&listen_offline(&model, &vec![0.0; 16_000 * 5]).unwrap()).is_empty());
    let mut seed = 12345u32;
    let noise: Vec<f32> = (0..16_000 * 8)
        .map(|_| {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            ((seed >> 16) as f32 / 65535.0 - 0.5) * 0.6
        })
        .collect();
    assert!(commands(&listen_offline(&model, &noise).unwrap()).is_empty());
}

const SONG: [(&str, f64); 4] = [
    ("Caminando por la calle sin rumbo", 2.0),
    ("Buscando un sueño que se perdió", 7.0),
    ("Y el viento me dice que vuelva", 12.0),
    ("A la casa donde nací", 17.0),
];

#[test]
fn the_intro_the_lyrics_lack_is_measured() {
    let model = need_model!();
    let lines: Vec<LyricLine> = SONG
        .iter()
        .map(|(t, a)| LyricLine {
            text: t.to_string(),
            at_secs: Some(*a),
        })
        .collect();
    for file in ["song_shift12_d.wav", "song_shift12_a.wav"] {
        let started = std::time::Instant::now();
        let found = align_lyrics(
            &model,
            &wav(file),
            &lines,
            Some("es"),
            &AtomicBool::new(false),
        )
        .unwrap()
        .unwrap_or_else(|| panic!("{file}: sin alineación"));
        println!("{file}: {found:?} en {:?}", started.elapsed());
        assert!(
            (found.shift_secs.unwrap() - 12.0).abs() < 0.8,
            "{file}: {found:?}"
        );
        assert!(found.anchored >= 2, "{file}: {found:?}");
    }
}

#[test]
fn another_song_or_silence_gives_no_alignment() {
    let model = need_model!();
    let other: Vec<LyricLine> = [
        "La luna llena brilla sobre el mar",
        "Nadie sabe lo que escondes tú",
        "Dime si volverás a esperarme",
    ]
    .iter()
    .map(|t| LyricLine {
        text: t.to_string(),
        at_secs: None,
    })
    .collect();
    let cancel = AtomicBool::new(false);
    assert_eq!(
        align_lyrics(
            &model,
            &wav("song_shift12_d.wav"),
            &other,
            Some("es"),
            &cancel
        )
        .unwrap(),
        None
    );
    let lines: Vec<LyricLine> = SONG
        .iter()
        .map(|(t, _)| LyricLine {
            text: t.to_string(),
            at_secs: None,
        })
        .collect();
    assert_eq!(
        align_lyrics(&model, &vec![0.0; 16_000 * 20], &lines, Some("es"), &cancel).unwrap(),
        None
    );
}

#[test]
fn a_missing_model_is_a_clear_error_and_analysis_can_be_cancelled() {
    let error = listen_offline(Path::new("no-existe.bin"), &[0.0; 100])
        .err()
        .unwrap()
        .to_string();
    assert!(error.contains("modelo de voz"), "{error}");
    let Some(model) = model() else { return };
    let cancel = AtomicBool::new(true);
    let lines = vec![LyricLine {
        text: "hola mundo cruel".into(),
        at_secs: None,
    }];
    assert!(align_lyrics(
        &model,
        &wav("song_shift12_d.wav"),
        &lines,
        Some("es"),
        &cancel
    )
    .is_err());
}
