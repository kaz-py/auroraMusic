//! Comprobaciones de archivos de audio sin reproducirlos: duración y
//! decodificación completa. Sustituyen a `ffprobe` y a `ffmpeg -xerror -f null`.

use std::fs::File;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

use crate::decode::{OpenError, PcmStream};

fn open_native(path: &Path) -> Result<PcmStream, OpenError> {
    let file = File::open(path).map_err(|e| OpenError::Failed(e.to_string()))?;
    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .map(str::to_ascii_lowercase);
    PcmStream::open_strict(Box::new(file), extension.as_deref())
}

/// Duración en segundos de un archivo con pista de audio. Si el contenedor no la
/// declara se suman las de los paquetes (sin decodificar).
pub fn probe_duration(path: &Path) -> Result<f64, OpenError> {
    let mut stream = open_native(path)?;
    let seconds = match stream.duration_secs() {
        Some(s) => Some(s),
        None => stream.scan_duration(),
    };
    match seconds {
        Some(s) if s.is_finite() && s > 0.0 => Ok(s),
        _ => Err(OpenError::Failed(
            "el archivo no tiene una duración de audio".into(),
        )),
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ValidateReport {
    /// Audio realmente decodificado, en segundos.
    pub decoded_secs: f64,
}

/// Decodifica el archivo entero: cualquier paquete dañado o un archivo más corto
/// de lo que declara (descarga cortada) es un error. `cancel` se mira entre trozos.
pub fn validate_decode(path: &Path, cancel: &AtomicBool) -> Result<ValidateReport, OpenError> {
    let mut stream = open_native(path)?;
    let rate = stream.out_rate() as f64;
    let declared = stream.duration_secs();
    let mut frames = 0u64;
    let mut chunk = Vec::with_capacity(32 * 1024);
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err(OpenError::Failed("validación cancelada".into()));
        }
        chunk.clear();
        let more = stream.next_chunk(&mut chunk)?;
        frames += (chunk.len() / 2) as u64;
        if !more {
            break;
        }
    }
    let decoded_secs = frames as f64 / rate;
    if frames == 0 {
        return Err(OpenError::Failed("el archivo no contiene audio".into()));
    }
    if let Some(expected) = declared {
        if decoded_secs + 0.5 < expected {
            return Err(OpenError::Failed(format!(
                "el audio está cortado: {decoded_secs:.1} s de {expected:.1} s"
            )));
        }
    }
    Ok(ValidateReport { decoded_secs })
}
