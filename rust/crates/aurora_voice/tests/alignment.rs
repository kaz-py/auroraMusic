//! Alineación de una letra con el audio, con voz sintética sobre un acompañamiento
//! y 12 s de introducción que la letra no tiene. Necesita `libvosk` y el modelo
//! (ver `recognition.rs`).

use std::fs;
use std::path::{Path, PathBuf};

use aurora_voice::{align_lyrics, model_is_installed, LyricLine};

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
    let mut at = 12;
    while at + 8 <= bytes.len() {
        let size = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
        if &bytes[at..at + 4] == b"data" {
            return bytes[at + 8..(at + 8 + size).min(bytes.len())]
                .chunks_exact(2)
                .map(|b| i16::from_le_bytes([b[0], b[1]]))
                .collect();
        }
        at += 8 + size + (size & 1);
    }
    panic!("sin trozo data");
}

fn lyrics(rows: &[(&str, f64)]) -> Vec<LyricLine> {
    rows.iter()
        .map(|(text, at)| LyricLine {
            text: text.to_string(),
            at_secs: *at,
        })
        .collect()
}

const SONG: [(&str, f64); 4] = [
    ("Caminando por la calle sin rumbo", 2.0),
    ("Buscando un sueño que se perdió", 7.0),
    ("Y el viento me dice que vuelva", 12.0),
    ("A la casa donde nací", 17.0),
];

#[test]
fn the_intro_the_lyrics_lack_is_measured_with_two_voices() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    for file in ["song_shift12_d.wav", "song_shift12_a.wav"] {
        let started = std::time::Instant::now();
        let found = align_lyrics(&lib, &model, &wav(file), &lyrics(&SONG))
            .unwrap()
            .unwrap_or_else(|| panic!("{file}: sin alineación"));
        println!("{file}: {found:?} en {:?}", started.elapsed());
        assert!((found.shift_secs - 12.0).abs() < 0.6, "{file}: {found:?}");
        assert!(found.anchors >= 2, "{file}: {found:?}");
    }
}

#[test]
fn a_synced_lyric_that_is_already_right_measures_zero() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    // Mismas líneas, pero con los tiempos que de verdad tienen en el audio.
    let right: Vec<(&str, f64)> = SONG.iter().map(|(t, at)| (*t, at + 12.0)).collect();
    let found = align_lyrics(&lib, &model, &wav("song_shift12_d.wav"), &lyrics(&right))
        .unwrap()
        .expect("alineación");
    assert!(found.shift_secs.abs() < 0.6, "{found:?}");
}

#[test]
fn another_song_silence_or_noise_gives_no_alignment() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    let other = lyrics(&[
        ("La luna llena brilla sobre el mar", 3.0),
        ("Nadie sabe lo que escondes tú", 8.0),
        ("Dime si volverás a esperarme", 13.0),
    ]);
    assert_eq!(
        align_lyrics(&lib, &model, &wav("song_shift12_d.wav"), &other).unwrap(),
        None
    );
    // Otro idioma: ninguna palabra conocida, nada que alinear.
    let english = lyrics(&[("Walking down the street with no direction", 2.0)]);
    assert_eq!(
        align_lyrics(&lib, &model, &wav("song_shift12_d.wav"), &english).unwrap(),
        None
    );
    assert_eq!(
        align_lyrics(&lib, &model, &vec![0i16; 16_000 * 20], &lyrics(&SONG)).unwrap(),
        None
    );
    assert_eq!(
        align_lyrics(&lib, &model, &wav("song_shift12_d.wav"), &[]).unwrap(),
        None
    );
}

#[test]
fn loud_accompaniment_may_hide_the_voice_but_never_gives_a_wrong_answer() {
    let Some((lib, model)) = setup() else {
        eprintln!("OMITIDA: faltan AURORA_VOSK_LIB / AURORA_VOSK_MODEL");
        return;
    };
    for level in [4000.0f32, 9000.0, 16000.0] {
        let mut seed = 99u32;
        let noisy: Vec<i16> = wav("song_shift12_d.wav")
            .iter()
            .map(|&s| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                let noise = ((seed >> 16) as f32 / 65535.0 - 0.5) * level;
                (s as f32 + noise).clamp(-32768.0, 32767.0) as i16
            })
            .collect();
        match align_lyrics(&lib, &model, &noisy, &lyrics(&SONG)).unwrap() {
            None => println!("ruido {level}: sin alineación"),
            Some(found) => {
                println!("ruido {level}: {found:?}");
                assert!(
                    (found.shift_secs - 12.0).abs() < 1.0,
                    "ruido {level}: {found:?}"
                );
            }
        }
    }
}
