//! Whisper (whisper.cpp) sobre un modelo `ggml` local: transcribe frases cortas
//! (comandos) y canciones con la hora de cada palabra (letras).
//!
//! Se compila dentro de la biblioteca de Aurora: no hay nada más que instalar,
//! solo el archivo del modelo, que se descarga al activar la función.

use std::path::Path;

use whisper_rs::{
    DtwMode, DtwModelPreset, DtwParameters, FullParams, SamplingStrategy, WhisperContext,
    WhisperContextParameters, WhisperState,
};

use crate::VoiceError;

/// Lo que se le «recuerda» a Whisper en cada frase: sesga la transcripción hacia
/// las órdenes y el nombre (por ejemplo, «Aurora» y no «aurora boreal»).
const COMMAND_PROMPT: &str = "Aurora.";

pub struct Transcript {
    pub text: String,
    /// Probabilidad (0–1) de que en realidad no hubiera voz.
    pub no_speech: f32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TimedWord {
    pub text: String,
    /// Segundos desde el principio del audio entregado.
    pub start: f64,
    pub end: f64,
}

/// Whisper con su estado reutilizable (crear uno por frase costaría decenas de MB).
pub struct Transcriber {
    state: WhisperState,
    threads: i32,
}

/// El código de ggml está compilado con AVX2/FMA/F16C: en una CPU sin ellos
/// fallaría con una instrucción ilegal y cerraría la aplicación.
pub fn cpu_supported() -> bool {
    #[cfg(target_arch = "x86_64")]
    {
        is_x86_feature_detected!("avx2")
            && is_x86_feature_detected!("fma")
            && is_x86_feature_detected!("f16c")
    }
    #[cfg(not(target_arch = "x86_64"))]
    {
        true
    }
}

fn model_error(message: impl Into<String>) -> VoiceError {
    VoiceError::Model(message.into())
}

fn base_params(threads: i32) -> FullParams<'static, 'static> {
    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_n_threads(threads);
    params.set_translate(false);
    params.set_no_context(true);
    params.set_print_special(false);
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_suppress_blank(true);
    params.set_suppress_nst(true);
    // Sin reintentos a temperatura alta: más lentos y propensos a inventar.
    params.set_temperature(0.0);
    params.set_temperature_inc(0.0);
    params
}

impl Transcriber {
    /// `dtw`: marcas de tiempo precisas por palabra (para alinear letras); cuesta
    /// unos MB y algo de CPU, así que los comandos no las piden.
    pub fn load(model: &Path, threads: i32, dtw: bool) -> Result<Self, VoiceError> {
        if !cpu_supported() {
            return Err(VoiceError::Library(
                "Este procesador no admite AVX2, que necesita el reconocimiento de voz.".into(),
            ));
        }
        if !model.is_file() {
            return Err(model_error(format!(
                "No está el modelo de voz en {}. Vuelve a descargarlo desde Ajustes.",
                model.display()
            )));
        }
        let path = model
            .to_str()
            .ok_or_else(|| model_error("La ruta del modelo de voz no es texto válido."))?;
        let mut options = WhisperContextParameters::default();
        options.use_gpu(false);
        if dtw {
            let name = model
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default();
            let preset = if name.contains("tiny") {
                DtwModelPreset::Tiny
            } else if name.contains("small") {
                DtwModelPreset::Small
            } else {
                DtwModelPreset::Base
            };
            options.dtw_parameters(DtwParameters {
                mode: DtwMode::ModelPreset {
                    model_preset: preset,
                },
                dtw_mem_size: 64 * 1024 * 1024,
            });
        }
        let context = WhisperContext::new_with_params(path, options)
            .map_err(|e| model_error(format!("No se pudo cargar el modelo de voz: {e}")))?;
        let state = context
            .create_state()
            .map_err(|e| model_error(format!("No se pudo preparar el reconocedor: {e}")))?;
        Ok(Self {
            state,
            threads: threads.max(1),
        })
    }

    /// Una frase corta en español (audio mono 16 kHz).
    pub fn command(&mut self, pcm: &[f32]) -> Result<Transcript, VoiceError> {
        let mut params = base_params(self.threads);
        params.set_language(Some("es"));
        params.set_single_segment(true);
        params.set_initial_prompt(COMMAND_PROMPT);
        // Una orden son pocas palabras: si el modelo se pone a repetir, se corta.
        params.set_max_tokens(32);
        params.set_no_speech_thold(0.6);
        // El codificador procesa 30 s por defecto; a una frase de 2 s le basta
        // con una fracción (unidades de 20 ms) y sale varias veces más rápido.
        let units = (pcm.len() as f32 / 16_000.0 * 50.0).ceil() as i32 + 100;
        params.set_audio_ctx(units.clamp(300, 1500));
        self.state
            .full(params, pcm)
            .map_err(|e| model_error(format!("Falló el reconocimiento: {e}")))?;
        let mut text = String::new();
        let mut no_speech = 0.0f32;
        for segment in self.state.as_iter() {
            text.push_str(&segment.to_str_lossy().unwrap_or_default());
            no_speech = no_speech.max(segment.no_speech_probability());
        }
        Ok(Transcript {
            text: text.trim().to_string(),
            no_speech,
        })
    }

    /// Canto o habla larga con la hora de cada palabra. `language`: código de
    /// dos letras o `None` para que Whisper lo detecte. Trabaja en ventanas de
    /// 30 s; `pcm` es mono a 16 kHz.
    pub fn words(
        &mut self,
        pcm: &[f32],
        language: Option<&str>,
        cancel: &std::sync::atomic::AtomicBool,
    ) -> Result<Vec<TimedWord>, VoiceError> {
        const WINDOW: usize = 30 * 16_000;
        let mut out = Vec::new();
        for (index, chunk) in pcm.chunks(WINDOW).enumerate() {
            if cancel.load(std::sync::atomic::Ordering::Relaxed) {
                return Err(model_error("Análisis cancelado."));
            }
            if chunk.len() < 16_000 {
                break;
            }
            let mut params = base_params(self.threads);
            params.set_language(language.or(Some("auto")));
            params.set_token_timestamps(true);
            params.set_no_speech_thold(0.9);
            self.state
                .full(params, chunk)
                .map_err(|e| model_error(format!("Falló el reconocimiento: {e}")))?;
            let base = (index * WINDOW) as f64 / 16_000.0;
            for segment in self.state.as_iter() {
                let mut word: Option<TimedWord> = None;
                for i in 0..segment.n_tokens() {
                    let Some(token) = segment.get_token(i) else {
                        continue;
                    };
                    let text = token.to_str_lossy().unwrap_or_default();
                    // Marcas especiales: [_BEG_], [_TT_123], <|...|>, [MUSIC]…
                    if text.starts_with("[_") || text.starts_with("<|") || text.is_empty() {
                        continue;
                    }
                    let data = token.token_data();
                    let at = if data.t_dtw >= 0 { data.t_dtw } else { data.t0 };
                    let start = base + at as f64 / 100.0;
                    if text.starts_with(' ') || word.is_none() {
                        if let Some(mut done) = word.take() {
                            done.end = start;
                            out.push(done);
                        }
                        word = Some(TimedWord {
                            text: text.trim().to_string(),
                            start,
                            end: start + 0.3,
                        });
                    } else if let Some(current) = word.as_mut() {
                        current.text.push_str(&text);
                    }
                }
                out.extend(word);
            }
        }
        Ok(out)
    }
}
