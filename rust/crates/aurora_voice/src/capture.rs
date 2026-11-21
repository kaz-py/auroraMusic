//! Captura del micrófono predeterminado y conversión a 16 kHz mono de 16 bits.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, Sample, SampleFormat, SizedSample};
use rtrb::{Consumer, Producer, RingBuffer};
use rubato::{FftFixedIn, Resampler};

use crate::VoiceError;

pub const MODEL_RATE: u32 = 16_000;
const CHUNK: usize = 1024;

pub struct Capture {
    _stream: cpal::Stream,
    pub samples: Consumer<f32>,
    pub rate: u32,
    /// El dispositivo falló o desapareció.
    pub lost: Arc<AtomicBool>,
}

fn push_mono<T: SizedSample>(data: &[T], channels: usize, producer: &mut Producer<f32>)
where
    f32: FromSample<T>,
{
    for frame in data.chunks_exact(channels) {
        let sum: f32 = frame.iter().map(|s| f32::from_sample(*s)).sum();
        // Anillo lleno = el análisis va atrasado: se descarta lo más nuevo.
        let _ = producer.push(sum / channels as f32);
    }
}

/// Abre el micrófono predeterminado. El `Stream` no es `Send`: debe vivir en el
/// hilo que lo creó.
pub fn open() -> Result<Capture, VoiceError> {
    let device = cpal::default_host()
        .default_input_device()
        .ok_or_else(|| VoiceError::Audio("No hay un micrófono disponible.".into()))?;
    let supported = device
        .default_input_config()
        .map_err(|e| VoiceError::Audio(format!("No se pudo leer el micrófono: {e}")))?;
    let format = supported.sample_format();
    let rate = supported.sample_rate().0;
    let config: cpal::StreamConfig = supported.into();
    let channels = config.channels as usize;
    let (mut producer, samples) = RingBuffer::<f32>::new(rate as usize * 4);
    let lost = Arc::new(AtomicBool::new(false));
    let flag = lost.clone();
    let fail = move |_: cpal::StreamError| flag.store(true, Ordering::Relaxed);
    let stream = match format {
        SampleFormat::F32 => device.build_input_stream(
            &config,
            move |data: &[f32], _| push_mono(data, channels, &mut producer),
            fail,
            None,
        ),
        SampleFormat::I16 => device.build_input_stream(
            &config,
            move |data: &[i16], _| push_mono(data, channels, &mut producer),
            fail,
            None,
        ),
        SampleFormat::U16 => device.build_input_stream(
            &config,
            move |data: &[u16], _| push_mono(data, channels, &mut producer),
            fail,
            None,
        ),
        other => {
            return Err(VoiceError::Audio(format!(
                "Formato de micrófono no admitido: {other:?}"
            )))
        }
    }
    .map_err(|e| VoiceError::Audio(format!("No se pudo abrir el micrófono: {e}")))?;
    stream
        .play()
        .map_err(|e| VoiceError::Audio(format!("No se pudo iniciar el micrófono: {e}")))?;
    Ok(Capture {
        _stream: stream,
        samples,
        rate,
        lost,
    })
}

/// Convierte audio mono a [`MODEL_RATE`] (f32), por bloques.
pub struct Downmix {
    resampler: Option<FftFixedIn<f32>>,
    pending: Vec<f32>,
}

impl Downmix {
    pub fn new(rate: u32) -> Result<Self, VoiceError> {
        let resampler = if rate == MODEL_RATE {
            None
        } else {
            Some(
                FftFixedIn::<f32>::new(rate as usize, MODEL_RATE as usize, CHUNK, 2, 1)
                    .map_err(|e| VoiceError::Audio(format!("Remuestreo del micrófono: {e}")))?,
            )
        };
        Ok(Self {
            resampler,
            pending: Vec::new(),
        })
    }

    pub fn push(&mut self, input: &[f32], out: &mut Vec<f32>) {
        let Some(resampler) = self.resampler.as_mut() else {
            out.extend_from_slice(input);
            return;
        };
        self.pending.extend_from_slice(input);
        loop {
            let need = resampler.input_frames_next();
            if self.pending.len() < need {
                return;
            }
            let chunk: Vec<f32> = self.pending.drain(..need).collect();
            if let Ok(result) = resampler.process(&[chunk], None) {
                out.extend_from_slice(&result[0]);
            }
        }
    }
}

/// Nivel RMS (0–1) de un bloque.
pub fn level(block: &[f32]) -> f32 {
    if block.is_empty() {
        return 0.0;
    }
    let sum: f32 = block.iter().map(|s| s * s).sum();
    (sum / block.len() as f32).sqrt().min(1.0)
}
