//! Puente del DSP de audio (`aurora_audio`). Funciones `sync`; ver `database.rs`.

use aurora_audio as audio;
use flutter_rust_bridge::frb;

/// Una banda del ecualizador, ya acotada por Dart (`EqBand`).
pub struct EqBandParams {
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
}

#[frb(sync)]
pub fn audio_spectrum_bars(fft: Vec<f64>) -> Vec<f64> {
    audio::spectrum_bars(&fft)
}

#[frb(sync)]
pub fn audio_is_complete_stream(
    is_playing: bool,
    is_buffering: bool,
    clean_eof: bool,
    decoded_us: i64,
    consumed_us: i64,
    expected_us: i64,
) -> bool {
    audio::is_complete_audio_stream(&audio::StreamState {
        is_playing,
        is_buffering,
        clean_eof,
        decoded_us,
        consumed_us,
        expected_us,
    })
}
