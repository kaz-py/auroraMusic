//! Banco de pruebas con canciones reales (no entra en CI): mide cuánto se
//! acerca la alineación a la letra sincronizada de LRCLIB frente a repartir las
//! líneas por igual.
//!
//! `AURORA_WHISPER_MODEL=<modelo> AURORA_BENCH_DIR=<carpeta con X.wav (16 kHz mono)
//! y X.json {"lang","lines":[{"at","text"}]}> cargo test -p aurora_voice --release
//! --test bench -- --ignored --nocapture`

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::time::Instant;

use aurora_voice::{align_lyrics, LyricLine};

fn wav(path: &Path) -> Vec<f32> {
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
    panic!("sin data");
}

fn median(mut v: Vec<f64>) -> f64 {
    v.sort_by(f64::total_cmp);
    v[v.len() / 2]
}

#[test]
#[ignore = "necesita canciones reales y el modelo"]
fn real_songs() {
    let model =
        PathBuf::from(std::env::var_os("AURORA_WHISPER_MODEL").expect("AURORA_WHISPER_MODEL"));
    let dir = PathBuf::from(std::env::var_os("AURORA_BENCH_DIR").expect("AURORA_BENCH_DIR"));
    let scan: f64 = std::env::var("AURORA_BENCH_SECS")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(200.0);
    let mut names: Vec<_> = fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| {
            e.ok()?
                .path()
                .file_stem()
                .map(|s| s.to_string_lossy().to_string())
        })
        .collect();
    names.sort();
    names.dedup();
    let (mut base_all, mut align_all) = (vec![], vec![]);
    for name in names {
        let (w, j) = (
            dir.join(format!("{name}.wav")),
            dir.join(format!("{name}.json")),
        );
        if !w.is_file() || !j.is_file() {
            continue;
        }
        let meta: serde_json_like::Meta = serde_json_like::parse(&fs::read_to_string(j).unwrap());
        let pcm = wav(&w);
        let pcm = &pcm[..((scan * 16_000.0) as usize).min(pcm.len())];
        let total = pcm.len() as f64 / 16_000.0;
        let lines: Vec<LyricLine> = meta
            .lines
            .iter()
            .map(|(_, t)| LyricLine {
                text: t.clone(),
                at_secs: None,
            })
            .collect();
        let truth: Vec<f64> = meta.lines.iter().map(|(a, _)| *a).collect();
        let in_scan = |i: usize| truth[i] < total - 3.0;
        // Línea base: la repartición uniforme que usa Aurora hoy.
        let full = meta.duration.max(total);
        let n = lines.len() as f64;
        let uniform: Vec<f64> = (0..lines.len())
            .map(|i| full * 0.06 + full * 0.88 * i as f64 / n)
            .collect();
        let started = Instant::now();
        let result = align_lyrics(
            &model,
            pcm,
            &lines,
            Some(&meta.lang),
            &AtomicBool::new(false),
        )
        .unwrap();
        let took = started.elapsed();
        let err = |est: &[f64]| -> Vec<f64> {
            (0..lines.len())
                .filter(|&i| in_scan(i))
                .map(|i| (est[i] - truth[i]).abs())
                .collect()
        };
        let base = err(&uniform);
        match result {
            Some(a) => {
                let e = err(&a.starts);
                let within = |v: &[f64], s: f64| {
                    v.iter().filter(|x| **x <= s).count() as f64 / v.len() as f64 * 100.0
                };
                println!(
                    "{name:<34} {:>3} líneas | uniforme: mediana {:>5.1}s, ≤2s {:>3.0}% | ALINEADA: mediana {:>5.1}s, ≤2s {:>3.0}%, ≤5s {:>3.0}% | ancladas {:>3}/{} | {:.1}s",
                    lines.len(), median(base.clone()), within(&base, 2.0), median(e.clone()), within(&e, 2.0), within(&e, 5.0), a.anchored, lines.len(), took.as_secs_f64()
                );
                base_all.extend(base);
                align_all.extend(e);
            }
            None => {
                println!("{name:<34} {:>3} líneas | uniforme: mediana {:>5.1}s | SIN ALINEACIÓN ({:.1}s)", lines.len(), median(base.clone()), took.as_secs_f64());
                base_all.extend(base.clone());
                align_all.extend(base);
            }
        }
    }
    println!(
        "TOTAL mediana uniforme {:.1}s -> alineada {:.1}s",
        median(base_all),
        median(align_all)
    );
}

/// JSON mínimo para no añadir dependencias solo al banco de pruebas.
mod serde_json_like {
    pub struct Meta {
        pub lang: String,
        pub duration: f64,
        pub lines: Vec<(f64, String)>,
    }
    fn str_after<'a>(s: &'a str, key: &str) -> &'a str {
        let i = s.find(key).expect(key) + key.len();
        &s[i..]
    }
    pub fn parse(s: &str) -> Meta {
        let lang = str_after(s, "\"lang\": \"")[..2].to_string();
        let duration = s.find("\"duration\":").map_or(0.0, |_| {
            let rest = str_after(s, "\"duration\":").trim_start();
            rest[..rest
                .find(|c: char| !(c.is_ascii_digit() || c == '.'))
                .unwrap()]
                .parse()
                .unwrap()
        });
        let mut lines = vec![];
        let mut rest = s;
        while let Some(i) = rest.find("{\"at\": ") {
            rest = &rest[i + 7..];
            let end = rest.find(',').unwrap();
            let at: f64 = rest[..end].parse().unwrap();
            let t0 = rest.find("\"text\": \"").unwrap() + 9;
            let mut text = String::new();
            let mut chars = rest[t0..].chars();
            while let Some(c) = chars.next() {
                match c {
                    '"' => break,
                    '\\' => match chars.next() {
                        Some('n') => text.push(' '),
                        Some('u') => {
                            let hex: String = chars.by_ref().take(4).collect();
                            text.push(
                                char::from_u32(u32::from_str_radix(&hex, 16).unwrap())
                                    .unwrap_or(' '),
                            );
                        }
                        Some(o) => text.push(o),
                        None => break,
                    },
                    c => text.push(c),
                }
            }
            lines.push((at, text));
            rest = &rest[t0..];
        }
        Meta {
            lang,
            duration,
            lines,
        }
    }
}
