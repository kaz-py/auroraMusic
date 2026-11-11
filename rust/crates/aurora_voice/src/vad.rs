//! Corta el micrófono en frases: detecta cuándo alguien habla y cuándo calla.
//!
//! Barato a propósito (RMS cada 20 ms): Whisper solo trabaja cuando hay voz. El
//! umbral sigue al ruido de fondo, así que funciona igual con un micrófono muy
//! bajo o muy alto; la frase se normaliza antes de entregarla, de modo que no
//! hace falta hablar pegado al micrófono.

use std::collections::VecDeque;

use crate::capture::MODEL_RATE;

const FRAME: usize = (MODEL_RATE / 50) as usize; // 20 ms
/// Veces por encima del ruido de fondo para contar como voz.
const SPEECH_RATIO: f32 = 3.0;
/// Mínimo absoluto (−62 dBFS): por debajo no hay nada que oír aunque no haya ruido.
const MIN_THRESHOLD: f32 = 0.0008;
const START_FRAMES: usize = 2;
const END_SILENCE_FRAMES: usize = 35; // 700 ms
const PRE_ROLL_FRAMES: usize = 15; // 300 ms
const MIN_FRAMES: usize = 18; // 360 ms
const MAX_FRAMES: usize = 300; // 6 s
/// Ganancia máxima al normalizar una frase.
const MAX_GAIN: f32 = 60.0;

pub struct Segmenter {
    floor: f32,
    pending: Vec<f32>,
    pre_roll: VecDeque<Vec<f32>>,
    utterance: Vec<f32>,
    in_speech: bool,
    loud_run: usize,
    quiet_run: usize,
    frames: usize,
}

impl Default for Segmenter {
    fn default() -> Self {
        Self {
            floor: MIN_THRESHOLD / SPEECH_RATIO,
            pending: Vec::new(),
            pre_roll: VecDeque::new(),
            utterance: Vec::new(),
            in_speech: false,
            loud_run: 0,
            quiet_run: 0,
            frames: 0,
        }
    }
}

fn rms(frame: &[f32]) -> f32 {
    (frame.iter().map(|s| s * s).sum::<f32>() / frame.len().max(1) as f32).sqrt()
}

/// Lleva el pico a ~0,8 con un tope de ganancia.
pub fn normalize(pcm: &mut [f32]) {
    let peak = pcm.iter().fold(0.0f32, |m, s| m.max(s.abs()));
    if peak > 1e-4 {
        let gain = (0.8 / peak).min(MAX_GAIN);
        pcm.iter_mut().for_each(|s| *s *= gain);
    }
}

impl Segmenter {
    pub fn new() -> Self {
        Self::default()
    }

    fn threshold(&self) -> f32 {
        (self.floor * SPEECH_RATIO).max(MIN_THRESHOLD)
    }

    /// Entrega audio; devuelve las frases completas que se cerraron (ya
    /// normalizadas).
    pub fn push(&mut self, samples: &[f32]) -> Vec<Vec<f32>> {
        self.pending.extend_from_slice(samples);
        let mut done = Vec::new();
        while self.pending.len() >= FRAME {
            let frame: Vec<f32> = self.pending.drain(..FRAME).collect();
            if let Some(utterance) = self.frame(frame) {
                done.push(utterance);
            }
        }
        done
    }

    fn frame(&mut self, frame: Vec<f32>) -> Option<Vec<f32>> {
        let level = rms(&frame);
        let loud = level > self.threshold();
        // El ruido de fondo baja rápido y sube despacio (no confundir una voz
        // sostenida con ruido).
        if !self.in_speech {
            self.floor = if level < self.floor {
                self.floor + (level - self.floor) * 0.2
            } else {
                self.floor + (level - self.floor) * 0.004
            };
        }
        if !self.in_speech {
            self.pre_roll.push_back(frame);
            while self.pre_roll.len() > PRE_ROLL_FRAMES {
                self.pre_roll.pop_front();
            }
            self.loud_run = if loud { self.loud_run + 1 } else { 0 };
            if self.loud_run >= START_FRAMES {
                self.in_speech = true;
                self.quiet_run = 0;
                self.frames = self.pre_roll.len();
                self.utterance = self.pre_roll.drain(..).flatten().collect();
            }
            return None;
        }
        self.utterance.extend_from_slice(&frame);
        self.frames += 1;
        // Histéresis: dentro de la frase basta con superar el 60 % del umbral.
        self.quiet_run = if level > self.threshold() * 0.6 {
            0
        } else {
            self.quiet_run + 1
        };
        if self.frames >= MAX_FRAMES && self.quiet_run < END_SILENCE_FRAMES {
            // Seis segundos sin una pausa no son una orden: es ruido continuo,
            // televisión o música. Se sube el listón para no volver a empezar
            // de inmediato (cada frase cuesta CPU en Whisper).
            let level = rms(&self.utterance);
            self.floor = self.floor.max(level * 0.7);
            self.in_speech = false;
            self.loud_run = 0;
            self.quiet_run = 0;
            self.frames = 0;
            self.utterance.clear();
            return None;
        }
        if self.quiet_run >= END_SILENCE_FRAMES {
            return self.finish();
        }
        None
    }

    fn finish(&mut self) -> Option<Vec<f32>> {
        self.in_speech = false;
        self.loud_run = 0;
        self.quiet_run = 0;
        let spoken = self
            .frames
            .saturating_sub(END_SILENCE_FRAMES.min(self.frames));
        let mut utterance = std::mem::take(&mut self.utterance);
        self.frames = 0;
        if spoken < MIN_FRAMES {
            return None;
        }
        normalize(&mut utterance);
        Some(utterance)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(secs: f32, amp: f32) -> Vec<f32> {
        (0..(secs * MODEL_RATE as f32) as usize)
            .map(|n| {
                amp * (2.0 * std::f32::consts::PI * 300.0 * n as f32 / MODEL_RATE as f32).sin()
            })
            .collect()
    }

    fn silence(secs: f32) -> Vec<f32> {
        vec![0.0; (secs * MODEL_RATE as f32) as usize]
    }

    fn run(parts: &[Vec<f32>]) -> Vec<Vec<f32>> {
        let mut segmenter = Segmenter::new();
        parts.iter().flat_map(|p| segmenter.push(p)).collect()
    }

    #[test]
    fn an_utterance_is_cut_after_a_pause_and_normalized() {
        let found = run(&[silence(1.0), tone(1.2, 0.02), silence(1.5)]);
        assert_eq!(found.len(), 1);
        let peak = found[0].iter().fold(0.0f32, |m, s| m.max(s.abs()));
        assert!((peak - 0.8).abs() < 0.01, "pico {peak}");
        let secs = found[0].len() as f32 / MODEL_RATE as f32;
        assert!(secs > 1.2 && secs < 2.6, "{secs} s");
    }

    #[test]
    fn a_very_quiet_voice_is_still_caught() {
        // Como un micrófono lejano: pico de 0,008 (≈ −42 dBFS).
        assert_eq!(
            run(&[silence(1.0), tone(1.0, 0.008), silence(1.5)]).len(),
            1
        );
    }

    #[test]
    fn silence_clicks_and_steady_hum_produce_nothing() {
        assert!(run(&[silence(5.0)]).is_empty());
        // Un golpe de 60 ms no es una frase.
        assert!(run(&[silence(1.0), tone(0.06, 0.3), silence(1.5)]).is_empty());
        // Un zumbido constante sube el ruido de fondo y deja de contar.
        let hum = tone(8.0, 0.004);
        let found = run(&[hum]);
        assert!(found.len() <= 1, "{}", found.len());
    }

    #[test]
    fn two_phrases_are_two_utterances() {
        let two = run(&[
            silence(1.0),
            tone(1.0, 0.1),
            silence(1.2),
            tone(1.0, 0.1),
            silence(1.5),
        ]);
        assert_eq!(two.len(), 2);
    }

    #[test]
    fn continuous_sound_is_dropped_and_stops_triggering() {
        // Una televisión: 25 s seguidos sin pausa no producen ninguna frase...
        let noise = tone(25.0, 0.05);
        assert!(run(&[silence(0.5), noise.clone()]).is_empty());
        // ...y después de acostumbrarse a ella, una voz claramente más fuerte sí pasa.
        let found = run(&[silence(0.5), noise, tone(1.0, 0.4), silence(1.5)]);
        assert_eq!(found.len(), 1);
    }

    #[test]
    fn the_threshold_follows_the_room_noise() {
        // En una habitación con ruido de fondo, la voz solo 4× por encima aún cuenta:
        // el ruido se apaga entre medias como en una habitación real.
        let noise = tone(0.04, 0.01);
        let mut parts = vec![silence(0.3)];
        for _ in 0..40 {
            parts.push(noise.clone());
        }
        parts.push(tone(1.0, 0.05));
        parts.push(silence(1.5));
        assert_eq!(run(&parts).len(), 1);
    }
}
