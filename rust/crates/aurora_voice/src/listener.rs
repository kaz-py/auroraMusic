//! Hilo de escucha: micrófono → frases (VAD) → Whisper → regla de activación.

use std::collections::VecDeque;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::capture::{self, Downmix, MODEL_RATE};
use crate::command::{Gate, Heard, Intent};
use crate::vad::Segmenter;
use crate::whisper::Transcriber;
use crate::VoiceError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Command(Intent),
    /// Se dijo «aurora» y se espera la orden.
    Wake,
    /// Lo último que se entendió (cualquier frase), para diagnosticar.
    Heard(String),
    /// La escucha se detuvo (micrófono perdido…).
    Stopped(String),
}

struct Shared {
    stop: AtomicBool,
    events: Mutex<VecDeque<Event>>,
    /// Nivel del micrófono ×1000.
    level: AtomicU32,
}

pub struct Listener {
    shared: Arc<Shared>,
    thread: Option<JoinHandle<()>>,
}

/// Hilos para la inferencia: la mitad de los núcleos, entre 2 y 4.
pub(crate) fn worker_threads() -> i32 {
    thread::available_parallelism().map_or(2, |n| (n.get() / 2).clamp(2, 4)) as i32
}

impl Listener {
    /// Carga el modelo y abre el micrófono; espera a que todo esté listo.
    /// Llamar desde un hilo de trabajo.
    pub fn start(model: &Path) -> Result<Self, VoiceError> {
        let shared = Arc::new(Shared {
            stop: AtomicBool::new(false),
            events: Mutex::new(VecDeque::new()),
            level: AtomicU32::new(0),
        });
        let (ready_tx, ready_rx) = mpsc::channel::<Result<(), VoiceError>>();
        let worker = shared.clone();
        let model = model.to_path_buf();
        let thread = thread::Builder::new()
            .name("aurora-voice".into())
            .spawn(move || run(worker, &model, ready_tx))
            .map_err(|e| VoiceError::Audio(e.to_string()))?;
        match ready_rx.recv() {
            Ok(Ok(())) => Ok(Self {
                shared,
                thread: Some(thread),
            }),
            Ok(Err(e)) => {
                let _ = thread.join();
                Err(e)
            }
            Err(_) => Err(VoiceError::Audio("La escucha terminó al iniciarse.".into())),
        }
    }

    /// Eventos desde la última consulta.
    pub fn poll(&self) -> Vec<Event> {
        self.shared.events.lock().unwrap().drain(..).collect()
    }

    /// Nivel actual del micrófono (0–1).
    pub fn level(&self) -> f32 {
        self.shared.level.load(Ordering::Relaxed) as f32 / 1000.0
    }

    pub fn is_running(&self) -> bool {
        self.thread.as_ref().is_some_and(|t| !t.is_finished())
    }

    pub fn stop(&mut self) {
        self.shared.stop.store(true, Ordering::Relaxed);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

impl Drop for Listener {
    fn drop(&mut self) {
        self.stop();
    }
}

fn push(shared: &Shared, event: Event) {
    let mut queue = shared.events.lock().unwrap();
    // Nadie consulta (la interfaz se cerró): no crece sin límite.
    if queue.len() >= 32 {
        queue.pop_front();
    }
    queue.push_back(event);
}

fn run(shared: Arc<Shared>, model: &Path, ready: mpsc::Sender<Result<(), VoiceError>>) {
    let setup = || -> Result<_, VoiceError> {
        let transcriber = Transcriber::load(model, worker_threads(), false)?;
        let mic = capture::open()?;
        let downmix = Downmix::new(mic.rate)?;
        Ok((transcriber, mic, downmix))
    };
    let (mut transcriber, mut mic, mut downmix) = match setup() {
        Ok(parts) => {
            let _ = ready.send(Ok(()));
            parts
        }
        Err(e) => {
            let _ = ready.send(Err(e));
            return;
        }
    };
    let mut gate = Gate::new();
    let mut segmenter = Segmenter::new();
    let mut block: Vec<f32> = Vec::with_capacity(4096);
    let mut pcm: Vec<f32> = Vec::with_capacity(2048);
    while !shared.stop.load(Ordering::Relaxed) {
        if mic.lost.load(Ordering::Relaxed) {
            push(
                &shared,
                Event::Stopped("El micrófono dejó de responder.".into()),
            );
            return;
        }
        block.clear();
        while let Ok(sample) = mic.samples.pop() {
            block.push(sample);
            if block.len() >= 4096 {
                break;
            }
        }
        if block.is_empty() {
            thread::sleep(Duration::from_millis(20));
            continue;
        }
        shared
            .level
            .store((capture::level(&block) * 1000.0) as u32, Ordering::Relaxed);
        pcm.clear();
        downmix.push(&block, &mut pcm);
        for utterance in segmenter.push(&pcm) {
            match transcriber.command(&utterance) {
                Ok(heard) => {
                    if !heard.text.is_empty() {
                        push(&shared, Event::Heard(heard.text.clone()));
                    }
                    match gate.feed(&heard.text, heard.no_speech, Instant::now()) {
                        Heard::Command(intent) => push(&shared, Event::Command(intent)),
                        Heard::Wake => push(&shared, Event::Wake),
                        Heard::Ignored => {}
                    }
                }
                Err(e) => push(&shared, Event::Stopped(e.to_string())),
            }
        }
    }
}

/// Analiza audio ya grabado (16 kHz, mono) como si llegara del micrófono: lo
/// que se entendió de cada frase y lo que Aurora haría con ella. Para pruebas
/// y diagnóstico; el reloj de la regla de activación es el del audio.
pub fn listen_offline(model: &Path, pcm: &[f32]) -> Result<Vec<(String, Heard)>, VoiceError> {
    let mut transcriber = Transcriber::load(model, worker_threads(), false)?;
    let mut gate = Gate::new();
    let mut segmenter = Segmenter::new();
    let start = Instant::now();
    let mut heard = Vec::new();
    let mut fed = 0usize;
    let chunk = MODEL_RATE as usize / 10;
    // Un segundo de silencio al final cierra la última frase.
    let tail = vec![0.0f32; MODEL_RATE as usize * 2];
    for part in pcm.chunks(chunk).chain(tail.chunks(chunk)) {
        fed += part.len();
        for utterance in segmenter.push(part) {
            let said = transcriber.command(&utterance)?;
            let now = start + Duration::from_secs_f64(fed as f64 / MODEL_RATE as f64);
            let what = gate.feed(&said.text, said.no_speech, now);
            heard.push((said.text, what));
        }
    }
    Ok(heard)
}
