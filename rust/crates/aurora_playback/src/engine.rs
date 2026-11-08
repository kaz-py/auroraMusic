//! Motor de reproducción: un hilo decodifica hacia un anillo de PCM y la
//! devolución de llamada de salida lo consume (volumen, EQ, espectro, posición).
//!
//! La salida es un parámetro: el dispositivo real (`device.rs`) y las pruebas
//! (`Engine::headless`) llaman a la misma función [`Engine::pull`].

use std::fs::File;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use aurora_audio::{EqBand, ParametricEqualizer};
use rtrb::{Consumer, Producer, RingBuffer};
use rustfft::num_complex::Complex;
use rustfft::FftPlanner;

use crate::decode::{OpenError, PcmStream};
use crate::http::HttpSource;

/// Segundos de audio ya decodificado que espera en el anillo.
const RING_SECONDS: f64 = 1.0;
const SPECTRUM_WINDOW: usize = 512;
const SPECTRUM_RING: usize = 2048;

#[derive(Debug, Clone)]
pub struct LoadSpec {
    /// Ruta de archivo o `http://127.0.0.1:…` (proxy local).
    pub input: String,
    pub headers: Vec<(String, String)>,
    pub start_secs: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LoadInfo {
    pub duration_secs: Option<f64>,
    pub sample_rate: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PlayerState {
    pub playing: bool,
    /// Sin datos que reproducir todavía (cargando o por cortes de red).
    pub buffering: bool,
    /// Se vació el anillo tras un final de flujo limpio.
    pub ended: bool,
    /// Tiempo reproducido desde el inicio de la carga (sin el desplazamiento).
    pub consumed_us: i64,
    /// Audio decodificado desde el inicio de la carga.
    pub decoded_us: i64,
    pub error: Option<String>,
    /// La salida de audio se perdió: hay que crear un motor nuevo y recargar.
    pub device_lost: bool,
    /// Cambia con cada carga/parada.
    pub generation: u64,
}

struct EqConfig {
    enabled: bool,
    bands: Vec<EqBand>,
    preamp: f64,
}

pub(crate) struct Shared {
    sample_rate: u32,
    playing: AtomicBool,
    volume: AtomicU32,
    consumed_frames: AtomicU64,
    decoded_frames: AtomicU64,
    buffered_samples: AtomicUsize,
    generation: AtomicU64,
    decoder_done: AtomicBool,
    eof_clean: AtomicBool,
    ended: AtomicBool,
    error: Mutex<Option<String>>,
    consumer: Mutex<Option<Consumer<f32>>>,
    eq_pending: Mutex<Option<EqConfig>>,
    /// El dispositivo de salida falló o desapareció (auriculares desenchufados…).
    device_lost: AtomicBool,
    visualization: AtomicBool,
    spectrum: Vec<AtomicU32>,
    spectrum_pos: AtomicUsize,
}

impl Shared {
    fn frames_to_us(&self, frames: u64) -> i64 {
        (frames as u128 * 1_000_000 / self.sample_rate as u128) as i64
    }
}

/// Estado propio de la devolución de llamada de salida.
pub(crate) struct OutputState {
    shared: Arc<Shared>,
    eq: ParametricEqualizer,
    gain: f32,
}

impl OutputState {
    /// Cierre que avisa de que el dispositivo falló; lo llama el hilo de `cpal`.
    pub(crate) fn device_lost_notifier(&self) -> impl Fn() + Send + 'static {
        let shared = self.shared.clone();
        move || shared.device_lost.store(true, Ordering::SeqCst)
    }

    /// Rellena `out` (estéreo intercalado) con el siguiente audio.
    pub(crate) fn fill(&mut self, out: &mut [f32]) {
        let shared = &self.shared;
        if let Ok(mut pending) = shared.eq_pending.try_lock() {
            if let Some(cfg) = pending.take() {
                self.eq.configure(cfg.enabled, &cfg.bands, cfg.preamp);
            }
        }
        let playing = shared.playing.load(Ordering::Relaxed);
        let target = if playing {
            f32::from_bits(shared.volume.load(Ordering::Relaxed))
        } else {
            0.0
        };
        let frames = out.len() / 2;
        if frames == 0 {
            return;
        }
        let mut got = 0;
        // Muestras que quedan en el anillo tras este relleno; `None` si no se pudo ver.
        let mut ring_left: Option<usize> = None;
        if let Ok(mut guard) = shared.consumer.try_lock() {
            if let Some(consumer) = guard.as_mut() {
                // Mudo no es pausa: con volumen 0 la posición sigue avanzando.
                if playing || self.gain > 0.0 {
                    let available = consumer.slots().min(out.len());
                    for slot in out.iter_mut().take(available) {
                        match consumer.pop() {
                            Ok(sample) => {
                                *slot = sample;
                                got += 1;
                            }
                            Err(_) => break,
                        }
                    }
                }
                // Foto exacta, no un contador: no acumula errores entre cargas.
                let left = consumer.slots();
                shared.buffered_samples.store(left, Ordering::Relaxed);
                ring_left = Some(left);
            }
        }
        out[got..].fill(0.0);
        if got > 0 {
            shared
                .consumed_frames
                .fetch_add((got / 2) as u64, Ordering::Relaxed);
            self.eq.process(&mut out[..got]);
        }
        // Rampa lineal de ganancia: sin clics al pausar, reanudar o mover el volumen.
        let step = (target - self.gain) / frames as f32;
        let mut gain = self.gain;
        for frame in out.chunks_exact_mut(2) {
            gain += step;
            frame[0] *= gain;
            frame[1] *= gain;
        }
        self.gain = target;
        if shared.visualization.load(Ordering::Relaxed) {
            let mut pos = shared.spectrum_pos.load(Ordering::Relaxed);
            for frame in out.chunks_exact(2) {
                shared.spectrum[pos % SPECTRUM_RING]
                    .store(((frame[0] + frame[1]) * 0.5).to_bits(), Ordering::Relaxed);
                pos = pos.wrapping_add(1);
            }
            shared.spectrum_pos.store(pos, Ordering::Relaxed);
        }
        if playing
            && got == 0
            && shared.decoder_done.load(Ordering::Acquire)
            && shared.eof_clean.load(Ordering::Acquire)
            && ring_left == Some(0)
        {
            shared.ended.store(true, Ordering::Release);
        }
    }
}

pub struct Engine {
    shared: Arc<Shared>,
    /// Solo sin dispositivo: con dispositivo la devolución de llamada es la dueña.
    output: Option<Arc<Mutex<OutputState>>>,
    load_lock: Mutex<()>,
    fft: Mutex<(Arc<dyn rustfft::Fft<f32>>, Vec<f32>)>,
    _device: Option<crate::device::DeviceHandle>,
}

fn new_shared(sample_rate: u32) -> Arc<Shared> {
    Arc::new(Shared {
        sample_rate,
        playing: AtomicBool::new(false),
        volume: AtomicU32::new(0.8f32.to_bits()),
        consumed_frames: AtomicU64::new(0),
        decoded_frames: AtomicU64::new(0),
        buffered_samples: AtomicUsize::new(0),
        generation: AtomicU64::new(0),
        decoder_done: AtomicBool::new(true),
        eof_clean: AtomicBool::new(false),
        ended: AtomicBool::new(false),
        error: Mutex::new(None),
        consumer: Mutex::new(None),
        eq_pending: Mutex::new(None),
        device_lost: AtomicBool::new(false),
        visualization: AtomicBool::new(true),
        spectrum: (0..SPECTRUM_RING).map(|_| AtomicU32::new(0)).collect(),
        spectrum_pos: AtomicUsize::new(0),
    })
}

fn hann(n: usize) -> Vec<f32> {
    (0..n)
        .map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (n - 1) as f32).cos())
        .collect()
}

impl Engine {
    /// Abre el dispositivo de salida predeterminado.
    pub fn new() -> Result<Self, String> {
        let rate = crate::device::default_rate()?;
        let shared = new_shared(rate);
        let device = crate::device::start(new_output(shared.clone()))?;
        Ok(Self::build(shared, None, Some(device)))
    }

    /// Sin dispositivo: el llamador consume el audio con [`Engine::pull`]. Para pruebas.
    pub fn headless(sample_rate: u32) -> Self {
        let shared = new_shared(sample_rate);
        let output = Arc::new(Mutex::new(new_output(shared.clone())));
        Self::build(shared, Some(output), None)
    }

    /// Sin dispositivo pero con reloj propio: un hilo consume el audio en
    /// tiempo real (y se detiene al soltar el motor). Para pruebas de Dart.
    pub fn silent(sample_rate: u32) -> Self {
        let engine = Self::headless(sample_rate);
        let weak = Arc::downgrade(engine.output.as_ref().expect("headless"));
        let frames = (sample_rate / 100) as usize;
        let _ = thread::Builder::new()
            .name("aurora-silent-clock".into())
            .spawn(move || {
                let mut buffer = vec![0f32; frames * 2];
                while let Some(output) = weak.upgrade() {
                    output.lock().unwrap().fill(&mut buffer);
                    drop(output);
                    thread::sleep(Duration::from_millis(10));
                }
            });
        engine
    }

    fn build(
        shared: Arc<Shared>,
        output: Option<Arc<Mutex<OutputState>>>,
        device: Option<crate::device::DeviceHandle>,
    ) -> Self {
        let fft = FftPlanner::<f32>::new().plan_fft_forward(SPECTRUM_WINDOW);
        Self {
            shared,
            output,
            load_lock: Mutex::new(()),
            fft: Mutex::new((fft, hann(SPECTRUM_WINDOW))),
            _device: device,
        }
    }

    pub fn sample_rate(&self) -> u32 {
        self.shared.sample_rate
    }

    /// Consume `out.len() / 2` tramas como lo haría el dispositivo.
    pub fn pull(&self, out: &mut [f32]) {
        self.output
            .as_ref()
            .expect("pull solo existe sin dispositivo")
            .lock()
            .unwrap()
            .fill(out);
    }

    /// Abre el origen y empieza a decodificar. Bloquea hasta reconocer el
    /// formato (puede tardar si es red): llamar desde un hilo de trabajo.
    pub fn load(&self, spec: &LoadSpec) -> Result<LoadInfo, OpenError> {
        let _serial = self.load_lock.lock().unwrap();
        let shared = &self.shared;
        let generation = shared.generation.fetch_add(1, Ordering::SeqCst) + 1;
        self.reset_state();
        let (source, extension, broken): (
            Box<dyn symphonia::core::io::MediaSource>,
            Option<String>,
            _,
        ) = if spec.input.to_ascii_lowercase().starts_with("http://")
            || spec.input.to_ascii_lowercase().starts_with("https://")
        {
            let (http, broken) =
                HttpSource::open(&spec.input, spec.headers.clone()).map_err(|e| {
                    if e.kind() == std::io::ErrorKind::Unsupported {
                        OpenError::Unsupported(e.to_string())
                    } else {
                        OpenError::Failed(e.to_string())
                    }
                })?;
            (Box::new(http), None, Some(broken))
        } else {
            let path = Path::new(&spec.input);
            let file = File::open(path).map_err(|e| OpenError::Failed(e.to_string()))?;
            let ext = path
                .extension()
                .and_then(|e| e.to_str())
                .map(|e| e.to_ascii_lowercase());
            (Box::new(file), ext, None)
        };
        let stream = PcmStream::open(
            source,
            extension.as_deref(),
            shared.sample_rate,
            spec.start_secs,
            broken,
        )?;
        if shared.generation.load(Ordering::SeqCst) != generation {
            return Err(OpenError::Failed("carga cancelada".into()));
        }
        let info = LoadInfo {
            duration_secs: stream.duration_secs(),
            sample_rate: shared.sample_rate,
        };
        let capacity = (shared.sample_rate as f64 * 2.0 * RING_SECONDS) as usize;
        let (producer, consumer) = RingBuffer::<f32>::new(capacity);
        shared.decoder_done.store(false, Ordering::SeqCst);
        *shared.consumer.lock().unwrap() = Some(consumer);
        let worker = shared.clone();
        thread::Builder::new()
            .name("aurora-decoder".into())
            .spawn(move || run_decoder(worker, generation, stream, producer))
            .map_err(|e| OpenError::Failed(e.to_string()))?;
        Ok(info)
    }

    fn reset_state(&self) {
        let shared = &self.shared;
        *shared.consumer.lock().unwrap() = None;
        shared.consumed_frames.store(0, Ordering::SeqCst);
        shared.decoded_frames.store(0, Ordering::SeqCst);
        shared.buffered_samples.store(0, Ordering::SeqCst);
        shared.decoder_done.store(true, Ordering::SeqCst);
        shared.eof_clean.store(false, Ordering::SeqCst);
        shared.ended.store(false, Ordering::SeqCst);
        *shared.error.lock().unwrap() = None;
    }

    pub fn stop(&self) {
        self.shared.generation.fetch_add(1, Ordering::SeqCst);
        self.shared.playing.store(false, Ordering::SeqCst);
        self.reset_state();
    }

    pub fn play(&self) {
        self.shared.playing.store(true, Ordering::SeqCst);
    }

    pub fn pause(&self) {
        self.shared.playing.store(false, Ordering::SeqCst);
    }

    pub fn set_volume(&self, volume: f32) {
        self.shared
            .volume
            .store(volume.clamp(0.0, 1.0).to_bits(), Ordering::Relaxed);
    }

    /// `preamp` es la ganancia lineal de compensación (la calcula quien conoce la curva).
    pub fn set_equalizer(&self, enabled: bool, bands: Vec<EqBand>, preamp: f64) {
        *self.shared.eq_pending.lock().unwrap() = Some(EqConfig {
            enabled,
            bands,
            preamp,
        });
    }

    /// Marca la salida como perdida (lo hace el dispositivo al fallar; también sirve en pruebas).
    pub fn mark_device_lost(&self) {
        self.shared.device_lost.store(true, Ordering::SeqCst);
    }

    pub fn set_visualization(&self, enabled: bool) {
        self.shared.visualization.store(enabled, Ordering::Relaxed);
    }

    pub fn state(&self) -> PlayerState {
        let s = &self.shared;
        let playing = s.playing.load(Ordering::SeqCst);
        let done = s.decoder_done.load(Ordering::SeqCst);
        let has_source = s.consumer.lock().unwrap().is_some();
        PlayerState {
            playing,
            buffering: has_source && !done && s.buffered_samples.load(Ordering::Relaxed) == 0,
            ended: s.ended.load(Ordering::SeqCst),
            consumed_us: s.frames_to_us(s.consumed_frames.load(Ordering::Relaxed)),
            decoded_us: s.frames_to_us(s.decoded_frames.load(Ordering::Relaxed)),
            error: s.error.lock().unwrap().clone(),
            device_lost: s.device_lost.load(Ordering::SeqCst),
            generation: s.generation.load(Ordering::SeqCst),
        }
    }

    /// 256 magnitudes de una FFT de 512 muestras de lo último que sonó
    /// (una senoide a escala completa da ~1).
    pub fn spectrum(&self) -> Vec<f64> {
        let s = &self.shared;
        if !s.visualization.load(Ordering::Relaxed) {
            return vec![0.0; SPECTRUM_WINDOW / 2];
        }
        let pos = s.spectrum_pos.load(Ordering::Relaxed);
        let guard = self.fft.lock().unwrap();
        let (plan, window) = &*guard;
        let mut data: Vec<Complex<f32>> = (0..SPECTRUM_WINDOW)
            .map(|i| {
                let idx = pos.wrapping_sub(SPECTRUM_WINDOW).wrapping_add(i) % SPECTRUM_RING;
                Complex::new(
                    f32::from_bits(s.spectrum[idx].load(Ordering::Relaxed)) * window[i],
                    0.0,
                )
            })
            .collect();
        plan.process(&mut data);
        let norm = 2.0 / window.iter().sum::<f32>();
        data[..SPECTRUM_WINDOW / 2]
            .iter()
            .map(|c| (c.norm() * norm) as f64)
            .collect()
    }
}

pub(crate) fn new_output(shared: Arc<Shared>) -> OutputState {
    let eq = ParametricEqualizer::new(shared.sample_rate as f64, 2, 12.0);
    OutputState {
        shared,
        eq,
        gain: 0.0,
    }
}

fn run_decoder(
    shared: Arc<Shared>,
    generation: u64,
    mut stream: PcmStream,
    mut producer: Producer<f32>,
) {
    let capacity = producer.buffer().capacity();
    let mut chunk: Vec<f32> = Vec::with_capacity(16 * 1024);
    loop {
        if shared.generation.load(Ordering::SeqCst) != generation {
            return;
        }
        chunk.clear();
        match stream.next_chunk(&mut chunk) {
            Ok(more) => {
                let mut offset = 0;
                while offset < chunk.len() {
                    if shared.generation.load(Ordering::SeqCst) != generation {
                        return;
                    }
                    let room = producer.slots().min(chunk.len() - offset);
                    if room == 0 {
                        thread::sleep(Duration::from_millis(5));
                        continue;
                    }
                    for &sample in &chunk[offset..offset + room] {
                        let _ = producer.push(sample);
                    }
                    offset += room;
                    shared
                        .buffered_samples
                        .store(capacity - producer.slots(), Ordering::Relaxed);
                }
                shared
                    .decoded_frames
                    .fetch_add((chunk.len() / 2) as u64, Ordering::Relaxed);
                if !more {
                    if shared.generation.load(Ordering::SeqCst) == generation {
                        shared.eof_clean.store(true, Ordering::SeqCst);
                        shared.decoder_done.store(true, Ordering::SeqCst);
                    }
                    return;
                }
            }
            Err(e) => {
                if shared.generation.load(Ordering::SeqCst) == generation {
                    *shared.error.lock().unwrap() = Some(e.to_string());
                    shared.decoder_done.store(true, Ordering::SeqCst);
                }
                return;
            }
        }
    }
}
