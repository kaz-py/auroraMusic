//! Alineación de letras con el audio (`aurora_voice` + `aurora_playback`).
//!
//! Decodifica los primeros segundos de la canción (archivo o proxy local de
//! YouTube) sin tocar el reproductor y mide cuánto se desvía la letra. Corre en
//! el grupo de hilos de FRB; tarda unos segundos. En Android no existe.

use anyhow::{anyhow, Result};

pub struct AlignLine {
    pub text: String,
    pub at_ms: i64,
}

pub struct AlignHeader {
    pub name: String,
    pub value: String,
}

pub struct LyricsAlignment {
    /// `true` si se midió un desfase fiable.
    pub found: bool,
    /// Milisegundos que el audio va por detrás (+) o por delante (−) de la letra.
    pub shift_ms: i64,
    /// Líneas reconocidas que coinciden con ese desfase.
    pub anchors: u32,
}

/// Audio que se analiza: lo bastante para cubrir una introducción larga.
#[cfg(not(target_os = "android"))]
const ANALYZE_SECS: usize = 100;

#[cfg(not(target_os = "android"))]
fn decode_head(input: &str, headers: Vec<(String, String)>) -> Result<Vec<i16>> {
    use aurora_playback::{HttpSource, PcmStream};
    let lower = input.to_ascii_lowercase();
    let (source, extension, broken): (Box<dyn symphonia_media::MediaSource>, Option<String>, _) =
        if lower.starts_with("http://") || lower.starts_with("https://") {
            let (http, broken) = HttpSource::open(input, headers).map_err(|e| anyhow!("{e}"))?;
            (Box::new(http), None, Some(broken))
        } else {
            let path = std::path::Path::new(input);
            let file = std::fs::File::open(path).map_err(|e| anyhow!("{e}"))?;
            let ext = path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.to_ascii_lowercase());
            (Box::new(file), ext, None)
        };
    let rate = 16_000u32;
    let mut stream = PcmStream::open(source, extension.as_deref(), rate, 0.0, broken)
        .map_err(|e| anyhow!("{e}"))?;
    let mut mono: Vec<i16> = Vec::with_capacity(rate as usize * ANALYZE_SECS);
    let mut chunk: Vec<f32> = Vec::new();
    while mono.len() < rate as usize * ANALYZE_SECS {
        chunk.clear();
        let more = stream.next_chunk(&mut chunk).map_err(|e| anyhow!("{e}"))?;
        for frame in chunk.chunks_exact(2) {
            let mixed = (frame[0] + frame[1]) * 0.5;
            mono.push((mixed.clamp(-1.0, 1.0) * i16::MAX as f32) as i16);
        }
        if !more {
            break;
        }
    }
    Ok(mono)
}

#[cfg(not(target_os = "android"))]
mod symphonia_media {
    pub use aurora_playback::MediaSource;
}

/// Mide la desviación entre `lines` (letra sincronizada) y el audio de `input`.
pub fn lyrics_align(
    lib_path: String,
    model_dir: String,
    input: String,
    headers: Vec<AlignHeader>,
    lines: Vec<AlignLine>,
) -> Result<LyricsAlignment> {
    #[cfg(not(target_os = "android"))]
    {
        let pcm = decode_head(
            &input,
            headers.into_iter().map(|h| (h.name, h.value)).collect(),
        )?;
        let lines: Vec<aurora_voice::LyricLine> = lines
            .into_iter()
            .map(|l| aurora_voice::LyricLine {
                text: l.text,
                at_secs: l.at_ms as f64 / 1000.0,
            })
            .collect();
        let result = aurora_voice::align_lyrics(
            std::path::Path::new(&lib_path),
            std::path::Path::new(&model_dir),
            &pcm,
            &lines,
        )
        .map_err(|e| anyhow!("{e}"))?;
        Ok(match result {
            Some(a) => LyricsAlignment {
                found: true,
                shift_ms: (a.shift_secs * 1000.0).round() as i64,
                anchors: a.anchors as u32,
            },
            None => LyricsAlignment {
                found: false,
                shift_ms: 0,
                anchors: 0,
            },
        })
    }
    #[cfg(target_os = "android")]
    {
        let _ = (lib_path, model_dir, input, headers, lines);
        Err(anyhow!(
            "La alineación de letras no está disponible en Android."
        ))
    }
}
