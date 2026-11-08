//! Puente del reproductor de escritorio (`aurora_playback`).
//!
//! `create`, `state`, `spectrum` y los controles son `sync` (µs, sin bloquear);
//! `load` no lo es: abre el origen (archivo o proxy local) y puede tardar, así
//! que corre en el grupo de hilos de FRB y Dart lo espera con `await`.
//! En Android el reproductor es Media3: aquí `create` devuelve un error.

use anyhow::{anyhow, Result};
use flutter_rust_bridge::frb;

use crate::api::audio::EqBandParams;

#[cfg(not(target_os = "android"))]
type Inner = aurora_playback::Engine;
#[cfg(target_os = "android")]
type Inner = ();

#[frb(opaque)]
pub struct PlayerEngine(Inner);

pub struct PlayerHeader {
    pub name: String,
    pub value: String,
}

pub struct PlayerLoadResult {
    pub ok: bool,
    /// Formato, códec o transporte que este motor no maneja: usar el anterior.
    pub unsupported: bool,
    pub message: String,
    pub duration_ms: Option<i64>,
}

pub struct PlayerStateInfo {
    pub playing: bool,
    pub buffering: bool,
    pub ended: bool,
    pub consumed_us: i64,
    pub decoded_us: i64,
    pub error: Option<String>,
    pub generation: i64,
}

impl PlayerEngine {
    /// Abre el dispositivo de salida predeterminado.
    #[frb(sync)]
    pub fn create() -> Result<PlayerEngine> {
        #[cfg(not(target_os = "android"))]
        {
            Ok(PlayerEngine(
                aurora_playback::Engine::new().map_err(|e| anyhow!(e))?,
            ))
        }
        #[cfg(target_os = "android")]
        {
            Err(anyhow!(
                "El reproductor de Rust no está disponible en Android."
            ))
        }
    }

    /// Sin dispositivo, con reloj propio en tiempo real: para las pruebas de Dart.
    #[frb(sync)]
    pub fn create_silent(sample_rate: u32) -> Result<PlayerEngine> {
        #[cfg(not(target_os = "android"))]
        {
            Ok(PlayerEngine(aurora_playback::Engine::silent(sample_rate)))
        }
        #[cfg(target_os = "android")]
        {
            let _ = sample_rate;
            Err(anyhow!(
                "El reproductor de Rust no está disponible en Android."
            ))
        }
    }

    /// Frecuencia de salida del dispositivo.
    #[frb(sync)]
    pub fn sample_rate(&self) -> u32 {
        #[cfg(not(target_os = "android"))]
        {
            self.0.sample_rate()
        }
        #[cfg(target_os = "android")]
        {
            0
        }
    }

    pub fn load(
        &self,
        input: String,
        headers: Vec<PlayerHeader>,
        start_ms: i64,
    ) -> PlayerLoadResult {
        #[cfg(not(target_os = "android"))]
        {
            let spec = aurora_playback::LoadSpec {
                input,
                headers: headers.into_iter().map(|h| (h.name, h.value)).collect(),
                start_secs: start_ms.max(0) as f64 / 1000.0,
            };
            match self.0.load(&spec) {
                Ok(info) => PlayerLoadResult {
                    ok: true,
                    unsupported: false,
                    message: String::new(),
                    duration_ms: info.duration_secs.map(|s| (s * 1000.0).round() as i64),
                },
                Err(aurora_playback::OpenError::Unsupported(message)) => PlayerLoadResult {
                    ok: false,
                    unsupported: true,
                    message,
                    duration_ms: None,
                },
                Err(aurora_playback::OpenError::Failed(message)) => PlayerLoadResult {
                    ok: false,
                    unsupported: false,
                    message,
                    duration_ms: None,
                },
            }
        }
        #[cfg(target_os = "android")]
        {
            let _ = (input, headers, start_ms);
            PlayerLoadResult {
                ok: false,
                unsupported: true,
                message: "Android".into(),
                duration_ms: None,
            }
        }
    }

    #[frb(sync)]
    pub fn play(&self) {
        #[cfg(not(target_os = "android"))]
        self.0.play();
    }

    #[frb(sync)]
    pub fn pause(&self) {
        #[cfg(not(target_os = "android"))]
        self.0.pause();
    }

    #[frb(sync)]
    pub fn stop(&self) {
        #[cfg(not(target_os = "android"))]
        self.0.stop();
    }

    #[frb(sync)]
    pub fn set_volume(&self, volume: f64) {
        #[cfg(not(target_os = "android"))]
        self.0.set_volume(volume as f32);
        #[cfg(target_os = "android")]
        let _ = volume;
    }

    /// `target_preamp`: ganancia lineal de compensación (1 = ninguna).
    #[frb(sync)]
    pub fn set_equalizer(&self, enabled: bool, bands: Vec<EqBandParams>, target_preamp: f64) {
        #[cfg(not(target_os = "android"))]
        {
            let bands = bands
                .into_iter()
                .map(|b| aurora_audio::EqBand {
                    frequency: b.frequency,
                    gain_db: b.gain_db,
                    q: b.q,
                })
                .collect();
            self.0.set_equalizer(enabled, bands, target_preamp);
        }
        #[cfg(target_os = "android")]
        let _ = (enabled, bands, target_preamp);
    }

    #[frb(sync)]
    pub fn set_visualization(&self, enabled: bool) {
        #[cfg(not(target_os = "android"))]
        self.0.set_visualization(enabled);
        #[cfg(target_os = "android")]
        let _ = enabled;
    }

    #[frb(sync)]
    pub fn state(&self) -> PlayerStateInfo {
        #[cfg(not(target_os = "android"))]
        {
            let s = self.0.state();
            PlayerStateInfo {
                playing: s.playing,
                buffering: s.buffering,
                ended: s.ended,
                consumed_us: s.consumed_us,
                decoded_us: s.decoded_us,
                error: s.error,
                generation: s.generation as i64,
            }
        }
        #[cfg(target_os = "android")]
        {
            PlayerStateInfo {
                playing: false,
                buffering: false,
                ended: false,
                consumed_us: 0,
                decoded_us: 0,
                error: None,
                generation: 0,
            }
        }
    }

    /// 256 magnitudes de la FFT de lo último que sonó.
    #[frb(sync)]
    pub fn spectrum(&self) -> Vec<f64> {
        #[cfg(not(target_os = "android"))]
        {
            self.0.spectrum()
        }
        #[cfg(target_os = "android")]
        {
            vec![0.0; 256]
        }
    }
}
