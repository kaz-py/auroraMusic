//! Alineación de letras con el audio (`aurora_voice` + `aurora_playback`).
//!
//! Decodifica los primeros segundos de la canción (archivo o proxy local de
//! YouTube) sin tocar el reproductor y mide, con Whisper, cuándo suena cada
//! línea. Corre en el grupo de hilos de FRB; tarda unos segundos. En Android no
//! existe.

use anyhow::{anyhow, Result};

pub struct AlignLine {
    pub text: String,
    /// Hora de la línea en la letra sincronizada; `None` si la letra no tiene tiempos.
    pub at_ms: Option<i64>,
}

pub struct AlignHeader {
    pub name: String,
    pub value: String,
}

pub struct LyricsAlignment {
    /// `true` si se midió algo fiable.
    pub found: bool,
    /// Hora (ms) a la que empieza cada línea según el audio; misma longitud que
    /// la letra. Con letra sincronizada son sus tiempos ya corregidos.
    pub starts_ms: Vec<i64>,
    /// Líneas ancladas directamente al audio.
    pub anchored: u32,
    /// Con letra sincronizada: desplazamiento mediano (audio − letra) en ms.
    pub shift_ms: Option<i64>,
}

#[cfg(not(target_os = "android"))]
fn decode_head(input: &str, headers: Vec<(String, String)>, secs: usize) -> Result<Vec<f32>> {
    use aurora_playback::{HttpSource, MediaSource, PcmStream};
    let lower = input.to_ascii_lowercase();
    let (source, extension, broken): (Box<dyn MediaSource>, Option<String>, _) =
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
    let mut mono: Vec<f32> = Vec::with_capacity(rate as usize * secs);
    let mut chunk: Vec<f32> = Vec::new();
    while mono.len() < rate as usize * secs {
        chunk.clear();
        let more = stream.next_chunk(&mut chunk).map_err(|e| anyhow!("{e}"))?;
        mono.extend(chunk.chunks_exact(2).map(|f| (f[0] + f[1]) * 0.5));
        if !more {
            break;
        }
    }
    Ok(mono)
}

/// Mide cuándo suena cada línea de `lines` en el audio de `input`, analizando
/// sus primeros `scan_secs` segundos. `language`: código de dos letras o `None`
/// (se deduce de la letra).
pub fn lyrics_align(
    model_path: String,
    input: String,
    headers: Vec<AlignHeader>,
    lines: Vec<AlignLine>,
    scan_secs: i64,
    language: Option<String>,
) -> Result<LyricsAlignment> {
    #[cfg(not(target_os = "android"))]
    {
        let pcm = decode_head(
            &input,
            headers.into_iter().map(|h| (h.name, h.value)).collect(),
            scan_secs.clamp(10, 400) as usize,
        )?;
        let lines: Vec<aurora_voice::LyricLine> = lines
            .into_iter()
            .map(|l| aurora_voice::LyricLine {
                text: l.text,
                at_secs: l.at_ms.map(|ms| ms as f64 / 1000.0),
            })
            .collect();
        let cancel = std::sync::atomic::AtomicBool::new(false);
        let result = aurora_voice::align_lyrics(
            std::path::Path::new(&model_path),
            &pcm,
            &lines,
            language.as_deref(),
            &cancel,
        )
        .map_err(|e| anyhow!("{e}"))?;
        Ok(match result {
            Some(a) => LyricsAlignment {
                found: true,
                starts_ms: a
                    .starts
                    .iter()
                    .map(|s| (s * 1000.0).round() as i64)
                    .collect(),
                anchored: a.anchored as u32,
                shift_ms: a.shift_secs.map(|s| (s * 1000.0).round() as i64),
            },
            None => LyricsAlignment {
                found: false,
                starts_ms: Vec::new(),
                anchored: 0,
                shift_ms: None,
            },
        })
    }
    #[cfg(target_os = "android")]
    {
        let _ = (model_path, input, headers, lines, scan_secs, language);
        Err(anyhow!(
            "La alineación de letras no está disponible en Android."
        ))
    }
}
