//! Comandos de voz de Aurora: escucha el micrófono y reconoce, sin red, órdenes
//! que empiezan por «Aurora» (pausa, siguiente, continúa, reproduce…).
//!
//! Reconocimiento con Vosk (modelo español pequeño, gramática cerrada).
//! `libvosk` se carga al activar la función; el audio no se guarda ni sale
//! del equipo.

pub mod align;
mod capture;
pub mod command;
mod listener;
mod model;
pub mod vosk;

pub use align::{align_lyrics, Alignment, LyricLine};
pub use command::{grammar_json, phrases, vocabulary, Gate, Heard, Intent, Word};
pub use listener::{analyze_pcm, Event, Listener};
pub use model::{install_model, model_is_installed};

use std::fmt;

#[derive(Debug)]
pub enum VoiceError {
    /// `libvosk` no se encontró o no es compatible.
    Library(String),
    Model(String),
    /// Sin micrófono o fallo del dispositivo.
    Audio(String),
}

impl fmt::Display for VoiceError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Library(m) | Self::Model(m) | Self::Audio(m) => f.write_str(m),
        }
    }
}

impl std::error::Error for VoiceError {}
