//! Alinea una letra sincronizada con el audio de la canción.
//!
//! La letra de otra versión (la de estudio) llega adelantada o atrasada
//! respecto al vídeo. Se reconoce el audio con una gramática cerrada hecha con
//! las primeras líneas de la letra —así el reconocedor solo tiene que decidir
//! *cuándo* suena cada línea, no *qué* dice— y, de cada línea reconocida, sale
//! un desfase (momento en el audio − tiempo de la línea en la letra). Vale la
//! mediana de los que coinciden.

use std::path::Path;

use crate::capture::MODEL_RATE;
use crate::vosk::Vosk;
use crate::VoiceError;

/// Líneas de la letra que entran en la gramática.
const MAX_LINES: usize = 10;
/// Desfases que difieren menos que esto se consideran el mismo.
const AGREE_SECS: f64 = 1.5;
/// Confianza media mínima de una línea sola (sin otra que la confirme).
const LONE_CONFIDENCE: f32 = 0.8;
const LONE_MIN_WORDS: usize = 4;

#[derive(Debug, Clone)]
pub struct LyricLine {
    pub text: String,
    /// Tiempo de la línea en la letra, en segundos.
    pub at_secs: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Alignment {
    /// Segundos que el audio va por detrás (+) o por delante (−) de la letra.
    pub shift_secs: f64,
    /// Líneas reconocidas que coinciden con este desfase.
    pub anchors: usize,
}

/// Palabras en minúsculas, sin puntuación.
pub fn normalize(text: &str) -> Vec<String> {
    text.to_lowercase()
        .split(|c: char| !c.is_alphanumeric())
        .filter(|w| !w.is_empty())
        .map(str::to_string)
        .collect()
}

/// Mediana de los desfases que se confirman entre sí. `None` si ninguno lo hace
/// y no hay una sola línea lo bastante fiable.
pub fn consensus(found: &[(f64, f32, usize)]) -> Option<Alignment> {
    // (desfase, confianza media, nº de palabras)
    let mut best: Option<Vec<f64>> = None;
    for (center, _, _) in found {
        let group: Vec<f64> = found
            .iter()
            .map(|(s, _, _)| *s)
            .filter(|s| (s - center).abs() <= AGREE_SECS)
            .collect();
        if best.as_ref().is_none_or(|b| group.len() > b.len()) {
            best = Some(group);
        }
    }
    let mut group = best?;
    if group.len() < 2 {
        // Una línea sola solo vale si es larga y el reconocedor estaba seguro.
        let (shift, conf, words) = found.iter().max_by(|a, b| a.1.total_cmp(&b.1)).copied()?;
        return (conf >= LONE_CONFIDENCE && words >= LONE_MIN_WORDS).then_some(Alignment {
            shift_secs: shift,
            anchors: 1,
        });
    }
    group.sort_by(f64::total_cmp);
    Some(Alignment {
        shift_secs: group[group.len() / 2],
        anchors: group.len(),
    })
}

/// `pcm`: audio mono a 16 kHz desde el principio de la canción.
pub fn align_lyrics(
    lib: &Path,
    model_dir: &Path,
    pcm: &[i16],
    lines: &[LyricLine],
) -> Result<Option<Alignment>, VoiceError> {
    let vosk = Vosk::load(lib)?;
    let model = std::sync::Arc::new(vosk.model(model_dir)?);
    // Cada línea como frase; las palabras que el modelo no conoce se quitan
    // (Vosk las ignoraría sin avisar) y una línea que se queda corta se descarta.
    let mut phrases: Vec<(String, f64)> = Vec::new();
    for line in lines.iter().take(MAX_LINES) {
        let words: Vec<String> = normalize(&line.text)
            .into_iter()
            .filter(|w| model.knows(w))
            .collect();
        if words.len() >= 3 {
            phrases.push((words.join(" "), line.at_secs));
        }
    }
    if phrases.is_empty() {
        return Ok(None);
    }
    let mut grammar: Vec<&str> = phrases.iter().map(|(p, _)| p.as_str()).collect();
    grammar.push("[unk]");
    let grammar = serde_json::to_string(&grammar).expect("JSON válido");
    let mut recognizer = model.recognizer(MODEL_RATE as f32, Some(&grammar))?;

    let mut found: Vec<(f64, f32, usize)> = Vec::new();
    let mut handle = |words: Vec<crate::command::Word>| {
        if words.is_empty() || words.iter().any(|w| w.text == "[unk]") {
            return;
        }
        let text = words
            .iter()
            .map(|w| w.text.as_str())
            .collect::<Vec<_>>()
            .join(" ");
        // La línea de la letra más temprana con ese texto (los estribillos se repiten).
        let Some((_, at)) = phrases.iter().find(|(p, _)| *p == text) else {
            return;
        };
        let confidence = words.iter().map(|w| w.confidence).sum::<f32>() / words.len() as f32;
        found.push((words[0].start as f64 - at, confidence, words.len()));
    };
    for chunk in pcm.chunks(MODEL_RATE as usize / 10) {
        if recognizer.accept(chunk) {
            handle(recognizer.result());
        }
    }
    handle(recognizer.final_result());
    Ok(consensus(&found))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_is_lowercased_without_punctuation() {
        assert_eq!(
            normalize("¡Caminando, por la calle! (Ñandú)"),
            ["caminando", "por", "la", "calle", "ñandú"]
        );
    }

    #[test]
    fn agreeing_lines_give_their_median() {
        let found = [
            (12.1, 0.9, 5),
            (12.4, 0.8, 6),
            (11.9, 0.7, 4),
            (40.0, 0.95, 7),
        ];
        let a = consensus(&found).unwrap();
        assert_eq!(a.anchors, 3);
        assert!((a.shift_secs - 12.1).abs() < 1e-9);
    }

    #[test]
    fn a_lone_line_needs_to_be_long_and_sure() {
        assert!(consensus(&[(5.0, 0.95, 6)]).is_some());
        assert!(consensus(&[(5.0, 0.6, 6)]).is_none());
        assert!(consensus(&[(5.0, 0.95, 3)]).is_none());
        assert!(consensus(&[]).is_none());
        // Dos que no coinciden tampoco se confirman: cuenta la más fiable si cumple.
        assert!(consensus(&[(1.0, 0.5, 3), (30.0, 0.5, 3)]).is_none());
    }
}
