//! Voz de Aurora con Whisper (whisper.cpp, modelo `ggml` local, sin red):
//! comandos hablados que empiezan por «Aurora» y alineación de letras con el
//! audio. El audio no se guarda ni sale del equipo.

pub mod align;
mod capture;
pub mod command;
mod listener;
mod vad;
mod whisper;

pub use align::{align_lyrics, align_words, Alignment, LyricLine};
pub use command::{phrases, Gate, Heard, Intent};
pub use listener::{listen_offline, Event, Listener};
pub use whisper::{cpu_supported, TimedWord, Transcriber};

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
