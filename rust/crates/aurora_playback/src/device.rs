//! Salida de audio por `cpal` (WASAPI en Windows, ALSA/PulseAudio en Linux).
//!
//! `cpal::Stream` no es `Send` en todas las plataformas, así que vive en un
//! hilo propio hasta que se suelta el [`DeviceHandle`].

use std::sync::mpsc;
use std::thread::{self, JoinHandle};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SampleFormat, SizedSample};

use crate::engine::OutputState;

/// Búfer de la salida: 1/20 s (50 ms). El de WASAPI por defecto ronda los 20 ms
/// y, en un equipo lento, cualquier retraso del hilo de salida se oye como un corte.
const OUTPUT_BUFFER_DIVISOR: u32 = 20;

/// cpal 0.15 intenta subir la prioridad del hilo de salida pasando un id de hilo
/// donde va un manejador, así que el hilo se queda en prioridad normal y compite
/// con la interfaz por la CPU. Aquí se registra en MMCSS ("Pro Audio", la
/// planificación de audio del sistema) y se sube a prioridad crítica.
#[cfg(windows)]
mod realtime {
    #[link(name = "kernel32")]
    extern "system" {
        fn GetCurrentThread() -> isize;
        fn SetThreadPriority(thread: isize, priority: i32) -> i32;
    }

    #[link(name = "avrt")]
    extern "system" {
        fn AvSetMmThreadCharacteristicsW(task: *const u16, index: *mut u32) -> isize;
        fn AvRevertMmThreadCharacteristics(handle: isize) -> i32;
    }

    const THREAD_PRIORITY_TIME_CRITICAL: i32 = 15;
    const PRO_AUDIO: [u16; 10] = {
        let name = b"Pro Audio\0";
        let mut wide = [0u16; 10];
        let mut i = 0;
        while i < name.len() {
            wide[i] = name[i] as u16;
            i += 1;
        }
        wide
    };

    /// Vive en la devolución de llamada: se suelta en el mismo hilo al cerrarse el flujo.
    pub struct Promotion(isize);

    impl Promotion {
        pub fn current_thread() -> Self {
            let mut index = 0u32;
            // SAFETY: llamadas Win32 sobre el hilo actual con una cadena terminada en 0.
            unsafe {
                SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
                Promotion(AvSetMmThreadCharacteristicsW(
                    PRO_AUDIO.as_ptr(),
                    &mut index,
                ))
            }
        }
    }

    impl Drop for Promotion {
        fn drop(&mut self) {
            if self.0 != 0 {
                // SAFETY: manejador devuelto por AvSetMmThreadCharacteristicsW.
                unsafe { AvRevertMmThreadCharacteristics(self.0) };
            }
        }
    }
}

#[cfg(not(windows))]
mod realtime {
    pub struct Promotion;

    impl Promotion {
        pub fn current_thread() -> Self {
            Promotion
        }
    }
}

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

/// `make_state` crea el estado de la devolución de llamada; se llama otra vez si
/// el dispositivo rechaza el búfer de [`OUTPUT_BUFFER_DIVISOR`] y se abre con el suyo.
pub fn start(
    make_state: impl Fn() -> OutputState + Send + 'static,
) -> Result<DeviceHandle, String> {
    let (ready_tx, ready_rx) = mpsc::channel::<Result<(), String>>();
    let (stop_tx, stop_rx) = mpsc::channel::<()>();
    let thread = thread::Builder::new()
        .name("aurora-audio-out".into())
        .spawn(move || match build(&make_state) {
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
    promotion: &mut Option<realtime::Promotion>,
) {
    if promotion.is_none() {
        *promotion = Some(realtime::Promotion::current_thread());
    }
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

fn build(make_state: &dyn Fn() -> OutputState) -> Result<cpal::Stream, String> {
    let device = default_device()?;
    let supported = device
        .default_output_config()
        .map_err(|e| format!("No se pudo leer la configuración de audio: {e}"))?;
    let format = supported.sample_format();
    let roomy = match *supported.buffer_size() {
        cpal::SupportedBufferSize::Range { min, max } => Some(cpal::BufferSize::Fixed(
            (supported.sample_rate().0 / OUTPUT_BUFFER_DIVISOR).clamp(min, max),
        )),
        cpal::SupportedBufferSize::Unknown => None,
    };
    let mut config: cpal::StreamConfig = supported.into();
    let stream = match roomy {
        Some(size) => {
            config.buffer_size = size;
            match open(&device, &config, format, make_state()) {
                Ok(stream) => stream,
                Err(_) => {
                    config.buffer_size = cpal::BufferSize::Default;
                    open(&device, &config, format, make_state())?
                }
            }
        }
        None => open(&device, &config, format, make_state())?,
    };
    stream
        .play()
        .map_err(|e| format!("No se pudo iniciar la salida de audio: {e}"))?;
    Ok(stream)
}

fn open(
    device: &cpal::Device,
    config: &cpal::StreamConfig,
    format: SampleFormat,
    mut state: OutputState,
) -> Result<cpal::Stream, String> {
    let channels = config.channels as usize;
    let buffer_frames = match config.buffer_size {
        cpal::BufferSize::Fixed(frames) => frames as usize,
        cpal::BufferSize::Default => 0,
    };
    let mut scratch: Vec<f32> = vec![0.0; (16 * 1024).max(buffer_frames * 2)];
    let mut promotion = None;
    let lost = state.device_lost_notifier();
    let fail = move |e: cpal::StreamError| {
        eprintln!("Aurora audio: {e}");
        lost();
    };
    match format {
        SampleFormat::F32 => device.build_output_stream(
            config,
            move |data: &mut [f32], _| {
                render(data, channels, &mut state, &mut scratch, &mut promotion)
            },
            fail,
            None,
        ),
        SampleFormat::I16 => device.build_output_stream(
            config,
            move |data: &mut [i16], _| {
                render(data, channels, &mut state, &mut scratch, &mut promotion)
            },
            fail,
            None,
        ),
        SampleFormat::U16 => device.build_output_stream(
            config,
            move |data: &mut [u16], _| {
                render(data, channels, &mut state, &mut scratch, &mut promotion)
            },
            fail,
            None,
        ),
        other => return Err(format!("Formato de salida no admitido: {other:?}")),
    }
    .map_err(|e| format!("No se pudo abrir la salida de audio: {e}"))
}
