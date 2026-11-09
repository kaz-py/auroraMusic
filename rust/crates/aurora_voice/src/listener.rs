//! Hilo de escucha: micrófono → Vosk (gramática cerrada) → regla de activación.

use std::collections::VecDeque;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::capture::{self, Downmix, MODEL_RATE};
use crate::command::{grammar_json, vocabulary, Gate, Heard, Intent, WAKE_WORD};
use crate::vosk::{Model, Vosk};
use crate::VoiceError;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Command(Intent),
    /// Se dijo «aurora» y se espera la orden.
    Wake,
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

fn load(lib: &Path, model_dir: &Path) -> Result<Arc<Model>, VoiceError> {
    let vosk = Vosk::load(lib)?;
    let model = Arc::new(vosk.model(model_dir)?);
    // Vosk ignora sin avisar una palabra que el modelo no conoce: la orden
    // simplemente nunca se reconocería. Mejor decirlo al activar.
    let unknown: Vec<String> = vocabulary()
        .into_iter()
        .filter(|w| !model.knows(w))
        .collect();
    if unknown.iter().any(|w| w == WAKE_WORD) {
        return Err(VoiceError::Model(
            "El modelo de voz no conoce la palabra «aurora».".into(),
        ));
    }
    if !unknown.is_empty() {
        eprintln!("Aurora voz: el modelo no conoce {unknown:?}");
    }
    Ok(model)
}

impl Listener {
    /// Carga la biblioteca y el modelo y abre el micrófono; espera a que todo
    /// esté listo (puede tardar unos segundos): llamar desde un hilo de trabajo.
    pub fn start(lib: &Path, model_dir: &Path) -> Result<Self, VoiceError> {
        let shared = Arc::new(Shared {
            stop: AtomicBool::new(false),
            events: Mutex::new(VecDeque::new()),
            level: AtomicU32::new(0),
        });
        let (ready_tx, ready_rx) = mpsc::channel::<Result<(), VoiceError>>();
        let worker = shared.clone();
        let (lib, model_dir) = (lib.to_path_buf(), model_dir.to_path_buf());
        let thread = thread::Builder::new()
            .name("aurora-voice".into())
            .spawn(move || run(worker, &lib, &model_dir, ready_tx))
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

fn run(
    shared: Arc<Shared>,
    lib: &Path,
    model_dir: &Path,
    ready: mpsc::Sender<Result<(), VoiceError>>,
) {
    let setup = || -> Result<_, VoiceError> {
        let model = load(lib, model_dir)?;
        let recognizer = model.recognizer(MODEL_RATE as f32, Some(&grammar_json()))?;
        let mic = capture::open()?;
        let downmix = Downmix::new(mic.rate)?;
        Ok((model, recognizer, mic, downmix))
    };
    let (_model, mut recognizer, mut mic, mut downmix) = match setup() {
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
    let mut block: Vec<f32> = Vec::with_capacity(4096);
    let mut pcm: Vec<i16> = Vec::with_capacity(2048);
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
        if recognizer.accept(&pcm) {
            match gate.feed(&recognizer.result(), Instant::now()) {
                Heard::Command(intent) => push(&shared, Event::Command(intent)),
                Heard::Wake => push(&shared, Event::Wake),
                Heard::Ignored => {}
            }
        }
    }
}

/// Analiza audio ya grabado (16 kHz, mono) como si llegara del micrófono.
/// Para pruebas y diagnóstico; el tiempo de la regla de activación es el del audio.
pub fn analyze_pcm(lib: &Path, model_dir: &Path, pcm: &[i16]) -> Result<Vec<Heard>, VoiceError> {
    let model = load(lib, model_dir)?;
    let mut recognizer = model.recognizer(MODEL_RATE as f32, Some(&grammar_json()))?;
    let mut gate = Gate::new();
    let start = Instant::now();
    let mut heard = Vec::new();
    let mut fed = 0usize;
    let chunk = MODEL_RATE as usize / 10;
    // Un segundo de silencio al final cierra la última frase.
    let tail = vec![0i16; MODEL_RATE as usize];
    for part in pcm.chunks(chunk).chain(tail.chunks(chunk)) {
        fed += part.len();
        if recognizer.accept(part) {
            let now = start + Duration::from_secs_f64(fed as f64 / MODEL_RATE as f64);
            heard.push(gate.feed(&recognizer.result(), now));
        }
    }
    let rest = recognizer.final_result();
    if !rest.is_empty() {
        let now = start + Duration::from_secs_f64(fed as f64 / MODEL_RATE as f64);
        heard.push(gate.feed(&rest, now));
    }
    Ok(heard)
}
