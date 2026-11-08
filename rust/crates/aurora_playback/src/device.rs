//! Salida de audio por `cpal` (WASAPI en Windows, ALSA/PulseAudio en Linux).
//!
//! `cpal::Stream` no es `Send` en todas las plataformas, así que vive en un
//! hilo propio hasta que se suelta el [`DeviceHandle`].

use std::sync::mpsc;
use std::thread::{self, JoinHandle};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SampleFormat, SizedSample};

use crate::engine::OutputState;

pub struct DeviceHandle {
    stop: Option<mpsc::Sender<()>>,
    thread: Option<JoinHandle<()>>,
}

impl Drop for DeviceHandle {
    fn drop(&mut self) {
        drop(self.stop.take());
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn default_device() -> Result<cpal::Device, String> {
    cpal::default_host()
        .default_output_device()
        .ok_or_else(|| "No hay dispositivo de salida de audio.".to_string())
}

/// Frecuencia de muestreo que usará la salida predeterminada.
pub fn default_rate() -> Result<u32, String> {
    let config = default_device()?
        .default_output_config()
        .map_err(|e| format!("No se pudo leer la configuración de audio: {e}"))?;
    Ok(config.sample_rate().0)
}

pub fn start(state: OutputState) -> Result<DeviceHandle, String> {
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let thread = thread::Builder::new()
        .name("aurora-audio-out".into())
        .spawn(move || match build(state) {
            Ok(stream) => {
                let _ = ready_tx.send(Ok(()));
                // Espera a que se suelte el manejador (el emisor se cierra).
                let _ = stop_rx.recv();
                drop(stream);
            }
            Err(e) => {
                let _ = ready_tx.send(Err(e));
            }
        })
        .map_err(|e| e.to_string())?;
    match ready_rx.recv() {
        Ok(Ok(())) => Ok(DeviceHandle {
            stop: Some(stop_tx),
            thread: Some(thread),
        }),
        Ok(Err(e)) => {
            let _ = thread.join();
            Err(e)
        }
        Err(_) => Err("El hilo de audio terminó al abrirse.".into()),
    }
}

fn render<T: SizedSample + FromSample<f32>>(
    data: &mut [T],
    channels: usize,
    state: &mut OutputState,
    scratch: &mut Vec<f32>,
) {
    let frames = data.len() / channels;
    if scratch.len() < frames * 2 {
        scratch.resize(frames * 2, 0.0);
    }
    state.fill(&mut scratch[..frames * 2]);
    for (frame, out) in data.chunks_exact_mut(channels).enumerate() {
        let (left, right) = (scratch[frame * 2], scratch[frame * 2 + 1]);
        if channels == 1 {
            out[0] = T::from_sample((left + right) * 0.5);
        } else {
            out[0] = T::from_sample(left);
            out[1] = T::from_sample(right);
            out[2..].fill(T::EQUILIBRIUM);
        }
    }
}

fn build(mut state: OutputState) -> Result<cpal::Stream, String> {
    let device = default_device()?;
    let supported = device
        .default_output_config()
        .map_err(|e| format!("No se pudo leer la configuración de audio: {e}"))?;
    let format = supported.sample_format();
    let config: cpal::StreamConfig = supported.into();
    let channels = config.channels as usize;
    let mut scratch: Vec<f32> = vec![0.0; 16 * 1024];
    let lost = state.device_lost_notifier();
    let fail = move |e: cpal::StreamError| {
        eprintln!("Aurora audio: {e}");
        lost();
    };
    let stream = match format {
        SampleFormat::F32 => device.build_output_stream(
            &config,
            move |data: &mut [f32], _| render(data, channels, &mut state, &mut scratch),
            fail,
            None,
        ),
        SampleFormat::I16 => device.build_output_stream(
            &config,
            move |data: &mut [i16], _| render(data, channels, &mut state, &mut scratch),
            fail,
            None,
        ),
        SampleFormat::U16 => device.build_output_stream(
            &config,
            move |data: &mut [u16], _| render(data, channels, &mut state, &mut scratch),
            fail,
            None,
        ),
        other => return Err(format!("Formato de salida no admitido: {other:?}")),
    }
    .map_err(|e| format!("No se pudo abrir la salida de audio: {e}"))?;
    stream
        .play()
        .map_err(|e| format!("No se pudo iniciar la salida de audio: {e}"))?;
    Ok(stream)
}
