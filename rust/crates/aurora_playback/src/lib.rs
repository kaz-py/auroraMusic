//! Reproductor de escritorio de Aurora: decodifica con Symphonia (y Opus con
//! libopus), remuestrea y entrega PCM al dispositivo de salida.
//!
//! En construcción: ver `MIGRATION_PENDIENTES.md` (fase 2b).

mod decode;
mod device;
mod engine;
mod http;
mod opus;
mod probe;
mod remux;

pub use decode::{OpenError, PcmStream};
pub use engine::{Engine, LoadInfo, LoadSpec, PlayerState};
pub use http::HttpSource;
pub use probe::{probe_duration, validate_decode, ValidateReport};
pub use remux::remux_opus_to_ogg;
pub use symphonia::core::io::MediaSource;
