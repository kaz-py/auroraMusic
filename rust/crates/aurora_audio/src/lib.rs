//! DSP de audio de Aurora: ecualizador paramétrico, barras de espectro y la
//! regla de «fin de flujo completo».
//!
//! Port de `lib/audio/eq_dsp.dart`, `eq_model.dart` (`peakingCoefficients`) y
//! `audio_math.dart` (v1.4.0). Las pruebas de `tests/golden.rs` comparan con la
//! salida de esa versión Dart.

mod eq;
mod spectrum;
mod stream;

pub use eq::{
    peaking_coefficients, soft_limit, EqBand, ParametricEqualizer, BAND_COUNT, BLOCK_FRAMES,
    DEFAULT_FREQUENCIES, LIMITER_KNEE,
};
pub use spectrum::{spectrum_bars, SPECTRUM_BARS};
pub use stream::{is_complete_audio_stream, StreamState};
