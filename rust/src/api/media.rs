//! Herramientas de archivos de audio de escritorio (`aurora_playback`): duración,
//! validación por decodificación completa y copia sin pérdida de Opus a Ogg. Sustituyen a
//! `ffprobe` y `ffmpeg`. Corren en el grupo de hilos de FRB (no bloquean la
//! interfaz) y se pueden cancelar y consultar desde Dart con un [`MediaJob`].
//! En Android no están (allí lo hace youtubedl-android).

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Arc;

use flutter_rust_bridge::frb;

pub struct MediaResult {
    pub ok: bool,
    pub message: String,
    /// Duración en segundos del audio comprobado o convertido.
    pub seconds: Option<f64>,
}

impl MediaResult {
    #[cfg(not(target_os = "android"))]
    fn from(result: Result<f64, aurora_playback::OpenError>) -> Self {
        match result {
            Ok(seconds) => Self {
                ok: true,
                message: String::new(),
                seconds: Some(seconds),
            },
            Err(e) => Self {
                ok: false,
                message: e.to_string(),
                seconds: None,
            },
        }
    }

    #[cfg(target_os = "android")]
    fn unavailable() -> Self {
        Self {
            ok: false,
            message: "No disponible en Android.".into(),
            seconds: None,
        }
    }
}

/// Una operación cancelable con progreso (0–1).
#[frb(opaque)]
pub struct MediaJob {
    cancel: Arc<AtomicBool>,
    progress: Arc<AtomicU32>,
}

impl MediaJob {
    #[frb(sync)]
    pub fn create() -> MediaJob {
        MediaJob {
            cancel: Arc::new(AtomicBool::new(false)),
            progress: Arc::new(AtomicU32::new(0)),
        }
    }

    #[frb(sync)]
    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
    }

    #[frb(sync)]
    pub fn progress(&self) -> f64 {
        self.progress.load(Ordering::Relaxed) as f64 / 1000.0
    }

    /// Decodifica el archivo entero; un paquete dañado o un archivo más corto de
    /// lo que declara es un error.
    pub fn validate(&self, path: String) -> MediaResult {
        #[cfg(not(target_os = "android"))]
        {
            MediaResult::from(
                aurora_playback::validate_decode(std::path::Path::new(&path), &self.cancel)
                    .map(|report| report.decoded_secs),
            )
        }
        #[cfg(target_os = "android")]
        {
            let _ = path;
            MediaResult::unavailable()
        }
    }

    /// Copia el Opus de `src` (WebM/Ogg) a un Ogg Opus en `dst` sin recodificar:
    /// misma calidad que sirve YouTube. `seconds` es la duración del resultado.
    pub fn remux_opus(&self, src: String, dst: String) -> MediaResult {
        #[cfg(not(target_os = "android"))]
        {
            MediaResult::from(aurora_playback::remux_opus_to_ogg(
                std::path::Path::new(&src),
                std::path::Path::new(&dst),
                &self.cancel,
                &self.progress,
            ))
        }
        #[cfg(target_os = "android")]
        {
            let _ = (src, dst);
            MediaResult::unavailable()
        }
    }
}

/// Duración de un archivo de audio (falla si no tiene pista de audio).
pub fn media_probe_duration(path: String) -> MediaResult {
    #[cfg(not(target_os = "android"))]
    {
        MediaResult::from(aurora_playback::probe_duration(std::path::Path::new(&path)))
    }
    #[cfg(target_os = "android")]
    {
        let _ = path;
        MediaResult::unavailable()
    }
}
