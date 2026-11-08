//! Puente del DSP de audio (`aurora_audio`). Funciones `sync`; ver `database.rs`.

use aurora_audio as audio;
use flutter_rust_bridge::frb;

/// Una banda del ecualizador, ya acotada por Dart (`EqBand`).
pub struct EqBandParams {
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
}

/// Ecualizador paramétrico de 8 bandas; el estado de los filtros vive en Rust.
#[frb(opaque)]
pub struct Equalizer(audio::ParametricEqualizer);

impl Equalizer {
    #[frb(sync)]
    pub fn create(sample_rate: f64, channels: u32, time_constant_ms: f64) -> Equalizer {
        Equalizer(audio::ParametricEqualizer::new(
            sample_rate,
            channels as usize,
            time_constant_ms,
        ))
    }

    /// `target_preamp`: ganancia lineal de compensación ya calculada (1 = ninguna).
    #[frb(sync)]
    pub fn configure(&mut self, enabled: bool, bands: Vec<EqBandParams>, target_preamp: f64) {
        let bands: Vec<audio::EqBand> = bands
            .into_iter()
            .map(|b| audio::EqBand {
                frequency: b.frequency,
                gain_db: b.gain_db,
                q: b.q,
            })
            .collect();
        self.0.configure(enabled, &bands, target_preamp);
    }

    /// El EQ no modifica el audio y no hay rampa pendiente.
    #[frb(sync)]
    pub fn is_idle(&self) -> bool {
        self.0.is_idle()
    }

    /// PCM `f32` entrelazado: devuelve el bloque procesado, de la misma longitud.
    #[frb(sync)]
    pub fn process(&mut self, mut pcm: Vec<f32>) -> Vec<f32> {
        self.0.process(&mut pcm);
        pcm
    }
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
