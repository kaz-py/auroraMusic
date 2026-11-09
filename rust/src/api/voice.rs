//! Puente de los comandos de voz (`aurora_voice`).
//!
//! `start` carga el modelo y abre el micrófono (tarda unos segundos), así que
//! corre en el grupo de hilos de FRB y Dart lo espera con `await`; el resto es
//! `sync`. En Android no existe: allí `start` devuelve un error.

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

#[cfg(not(target_os = "android"))]
type Inner = std::sync::Mutex<aurora_voice::Listener>;
#[cfg(target_os = "android")]
type Inner = ();

/// Qué se oyó.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VoiceIntent {
    Play,
    Pause,
    Resume,
    Next,
    Previous,
}

pub struct VoiceEvent {
    /// `None` si no es una orden (aviso de «aurora» o parada).
    pub intent: Option<VoiceIntent>,
    /// Se dijo «aurora» y se espera la orden.
    pub wake: bool,
    /// La escucha se detuvo: motivo.
    pub stopped: Option<String>,
}

pub struct VoicePhrases {
    pub intent: VoiceIntent,
    pub phrases: Vec<String>,
}

#[frb(opaque)]
pub struct VoiceListener(Inner);

#[cfg(not(target_os = "android"))]
fn map_intent(intent: aurora_voice::Intent) -> VoiceIntent {
    use aurora_voice::Intent as I;
    match intent {
        I::Play => VoiceIntent::Play,
        I::Pause => VoiceIntent::Pause,
        I::Resume => VoiceIntent::Resume,
        I::Next => VoiceIntent::Next,
        I::Previous => VoiceIntent::Previous,
    }
}

impl VoiceListener {
    /// Carga `libvosk` (`lib_path`) y el modelo (`model_dir`) y empieza a escuchar.
    pub fn start(lib_path: String, model_dir: String) -> Result<VoiceListener> {
        #[cfg(not(target_os = "android"))]
        {
            let listener = aurora_voice::Listener::start(
                std::path::Path::new(&lib_path),
                std::path::Path::new(&model_dir),
            )
            .map_err(|e| anyhow!("{e}"))?;
            Ok(VoiceListener(std::sync::Mutex::new(listener)))
        }
        #[cfg(target_os = "android")]
        {
            let _ = (lib_path, model_dir);
            Err(anyhow!(
                "Los comandos de voz no están disponibles en Android."
            ))
        }
    }

    /// Eventos desde la última consulta.
    #[frb(sync)]
    pub fn poll(&self) -> Vec<VoiceEvent> {
        #[cfg(not(target_os = "android"))]
        {
            use aurora_voice::Event;
            self.0
                .lock()
                .map(|l| l.poll())
                .unwrap_or_default()
                .into_iter()
                .map(|event| match event {
                    Event::Command(intent) => VoiceEvent {
                        intent: Some(map_intent(intent)),
                        wake: false,
                        stopped: None,
                    },
                    Event::Wake => VoiceEvent {
                        intent: None,
                        wake: true,
                        stopped: None,
                    },
                    Event::Stopped(reason) => VoiceEvent {
                        intent: None,
                        wake: false,
                        stopped: Some(reason),
                    },
                })
                .collect()
        }
        #[cfg(target_os = "android")]
        {
            Vec::new()
        }
    }

    /// Nivel del micrófono (0–1).
    #[frb(sync)]
    pub fn level(&self) -> f64 {
        #[cfg(not(target_os = "android"))]
        {
            self.0.lock().map_or(0.0, |l| l.level() as f64)
        }
        #[cfg(target_os = "android")]
        {
            0.0
        }
    }

    #[frb(sync)]
    pub fn is_running(&self) -> bool {
        #[cfg(not(target_os = "android"))]
        {
            self.0.lock().is_ok_and(|l| l.is_running())
        }
        #[cfg(target_os = "android")]
        {
            false
        }
    }

    /// Deja de escuchar y libera el micrófono.
    #[frb(sync)]
    pub fn stop(&self) {
        #[cfg(not(target_os = "android"))]
        if let Ok(mut listener) = self.0.lock() {
            listener.stop();
        }
    }
}

/// ¿Hay un modelo de voz utilizable en `dir`?
#[frb(sync)]
pub fn voice_model_installed(dir: String) -> bool {
    #[cfg(not(target_os = "android"))]
    {
        aurora_voice::model_is_installed(std::path::Path::new(&dir))
    }
    #[cfg(target_os = "android")]
    {
        let _ = dir;
        false
    }
}

/// Descomprime el ZIP del modelo en `dest` (reemplaza lo que hubiera).
pub fn voice_install_model(archive: String, dest: String) -> Result<()> {
    #[cfg(not(target_os = "android"))]
    {
        aurora_voice::install_model(std::path::Path::new(&archive), std::path::Path::new(&dest))
            .map_err(|e| anyhow!("{e}"))
    }
    #[cfg(target_os = "android")]
    {
        let _ = (archive, dest);
        Err(anyhow!(
            "Los comandos de voz no están disponibles en Android."
        ))
    }
}

/// La palabra de activación y las frases que se entienden, para mostrarlas.
#[frb(sync)]
pub fn voice_wake_word() -> String {
    "aurora".to_string()
}

#[frb(sync)]
pub fn voice_phrases() -> Vec<VoicePhrases> {
    #[cfg(not(target_os = "android"))]
    {
        aurora_voice::phrases()
            .into_iter()
            .map(|(intent, list)| VoicePhrases {
                intent: map_intent(intent),
                phrases: list.iter().map(|s| s.to_string()).collect(),
            })
            .collect()
    }
    #[cfg(target_os = "android")]
    {
        Vec::new()
    }
}
