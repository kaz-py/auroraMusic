//! Qué frases entiende Aurora por voz y cuándo cuentan como una orden.
//!
//! La gramática que se le da al reconocedor sale de la misma tabla que usa el
//! analizador, así que no pueden divergir. Una orden solo vale si va tras la
//! palabra de activación «aurora» (en la misma frase o, como mucho, 4 s
//! antes); lo demás se ignora.

use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Intent {
    /// «Reproduce música»: empieza a sonar lo que toque.
    Play,
    Pause,
    /// «Continúa»: sigue por donde iba.
    Resume,
    Next,
    Previous,
}

pub const WAKE_WORD: &str = "aurora";
/// Tras oír solo «aurora», una orden suelta vale durante este tiempo.
pub const ARMED_FOR: Duration = Duration::from_secs(4);
/// Confianza mínima de cada palabra (0–1) para aceptar una orden.
pub const MIN_CONFIDENCE: f32 = 0.6;
/// Entre dos órdenes iguales seguidas (eco, repetición del reconocedor).
pub const COOLDOWN: Duration = Duration::from_millis(1500);

const PHRASES: &[(Intent, &[&str])] = &[
    (
        Intent::Pause,
        &[
            "pausa",
            "pausar",
            "pausa la música",
            "detén la música",
            "para la música",
            "alto",
        ],
    ),
    (
        Intent::Resume,
        &[
            "continúa",
            "continuar",
            "continúa la música",
            "sigue",
            "sigue la música",
            "reanuda",
            "reanudar",
        ],
    ),
    (
        Intent::Play,
        &[
            "reproduce",
            "reproducir",
            "reproduce música",
            "reproduce una canción",
            "pon música",
            "pon una canción",
            "toca música",
        ],
    ),
    (
        Intent::Next,
        &[
            "siguiente",
            "siguiente canción",
            "salta",
            "saltar",
            "salta la canción",
            "pasa a la siguiente",
            "próxima canción",
            "cambia de canción",
        ],
    ),
    (
        Intent::Previous,
        &["anterior", "canción anterior", "regresa", "vuelve atrás"],
    ),
];

/// Todas las frases (sin la palabra de activación), para mostrarlas.
pub fn phrases() -> Vec<(Intent, &'static [&'static str])> {
    PHRASES.to_vec()
}

/// Palabras que debe conocer el modelo.
pub fn vocabulary() -> Vec<String> {
    let mut words: Vec<String> = vec![WAKE_WORD.to_string()];
    for (_, list) in PHRASES {
        for phrase in *list {
            words.extend(phrase.split_whitespace().map(str::to_string));
        }
    }
    words.sort();
    words.dedup();
    words
}

/// Gramática de Vosk (arreglo JSON): «aurora <orden>», «aurora» sola, la orden
/// suelta (para cuando se dice tras una pausa) y `[unk]` para todo lo demás.
pub fn grammar_json() -> String {
    let mut items: Vec<String> = vec![WAKE_WORD.to_string()];
    for (_, list) in PHRASES {
        for phrase in *list {
            items.push(format!("{WAKE_WORD} {phrase}"));
            items.push((*phrase).to_string());
        }
    }
    items.push("[unk]".to_string());
    serde_json::to_string(&items).expect("la gramática es JSON válido")
}

fn lookup(phrase: &str) -> Option<Intent> {
    PHRASES
        .iter()
        .find(|(_, list)| list.contains(&phrase))
        .map(|(intent, _)| *intent)
}

/// Una palabra reconocida con su confianza.
#[derive(Debug, Clone, PartialEq)]
pub struct Word {
    pub text: String,
    pub confidence: f32,
    /// Segundos desde el inicio del audio entregado al reconocedor.
    pub start: f32,
    pub end: f32,
}

/// Lo que se concluye de un resultado final del reconocedor.
#[derive(Debug, Clone, PartialEq)]
pub enum Heard {
    Command(Intent),
    /// Solo «aurora»: espera la orden.
    Wake,
    Ignored,
}

/// Aplica la regla de activación. Tiempo inyectable para probarla.
#[derive(Debug, Default)]
pub struct Gate {
    armed_until: Option<Instant>,
    last: Option<(Intent, Instant)>,
}

impl Gate {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, words: &[Word], now: Instant) -> Heard {
        let armed = self.armed_until.is_some_and(|until| now <= until);
        self.armed_until = None;
        if words.is_empty()
            || words
                .iter()
                .any(|w| w.text == "[unk]" || w.confidence < MIN_CONFIDENCE)
        {
            return Heard::Ignored;
        }
        let text = words
            .iter()
            .map(|w| w.text.as_str())
            .collect::<Vec<_>>()
            .join(" ");
        if text == WAKE_WORD {
            self.armed_until = Some(now + ARMED_FOR);
            return Heard::Wake;
        }
        let spoken = text
            .strip_prefix(WAKE_WORD)
            .and_then(|rest| rest.strip_prefix(' '));
        let phrase = match spoken {
            Some(rest) => rest,
            None if armed => text.as_str(),
            None => return Heard::Ignored,
        };
        let Some(intent) = lookup(phrase) else {
            return Heard::Ignored;
        };
        if let Some((previous, at)) = self.last {
            if previous == intent && now.duration_since(at) < COOLDOWN {
                return Heard::Ignored;
            }
        }
        self.last = Some((intent, now));
        Heard::Command(intent)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(text: &str, confidence: f32) -> Vec<Word> {
        text.split_whitespace()
            .map(|t| Word {
                text: t.to_string(),
                confidence,
                start: 0.0,
                end: 0.0,
            })
            .collect()
    }

    #[test]
    fn a_command_needs_the_wake_word() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(
            gate.feed(&words("aurora pausa", 1.0), t),
            Heard::Command(Intent::Pause)
        );
        // Sin «aurora» no hace nada, aunque la orden sea válida.
        let t = t + Duration::from_secs(10);
        assert_eq!(gate.feed(&words("pausa", 1.0), t), Heard::Ignored);
        assert_eq!(
            gate.feed(&words("siguiente canción", 1.0), t),
            Heard::Ignored
        );
        // «aurora» no al principio tampoco.
        assert_eq!(
            gate.feed(&words("hola aurora pausa", 1.0), t),
            Heard::Ignored
        );
    }

    #[test]
    fn every_phrase_maps_to_its_intent() {
        let mut gate = Gate::new();
        let mut t = Instant::now();
        for (intent, list) in PHRASES {
            for phrase in *list {
                t += Duration::from_secs(5);
                let heard = gate.feed(&words(&format!("aurora {phrase}"), 0.9), t);
                assert_eq!(heard, Heard::Command(*intent), "{phrase}");
            }
        }
    }

    #[test]
    fn wake_then_command_within_the_window() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(gate.feed(&words("aurora", 1.0), t), Heard::Wake);
        assert_eq!(
            gate.feed(&words("siguiente", 1.0), t + Duration::from_secs(2)),
            Heard::Command(Intent::Next)
        );
        // La activación se gasta con la primera orden.
        assert_eq!(
            gate.feed(&words("pausa", 1.0), t + Duration::from_secs(3)),
            Heard::Ignored
        );
        // Fuera de la ventana no cuenta.
        assert_eq!(
            gate.feed(&words("aurora", 1.0), t + Duration::from_secs(10)),
            Heard::Wake
        );
        assert_eq!(
            gate.feed(&words("pausa", 1.0), t + Duration::from_secs(15)),
            Heard::Ignored
        );
    }

    #[test]
    fn unknown_words_low_confidence_and_garbage_are_ignored() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(gate.feed(&words("aurora [unk]", 1.0), t), Heard::Ignored);
        assert_eq!(gate.feed(&words("aurora pausa", 0.4), t), Heard::Ignored);
        assert_eq!(gate.feed(&[], t), Heard::Ignored);
        assert_eq!(gate.feed(&words("aurora baila", 1.0), t), Heard::Ignored);
        assert_eq!(
            gate.feed(&words("aurora pausa pausa", 1.0), t),
            Heard::Ignored
        );
        // Una palabra dudosa dentro de una orden válida la anula entera.
        let mixed = vec![
            Word {
                text: "aurora".into(),
                confidence: 1.0,
                start: 0.0,
                end: 0.0,
            },
            Word {
                text: "pausa".into(),
                confidence: 0.3,
                start: 0.0,
                end: 0.0,
            },
        ];
        assert_eq!(gate.feed(&mixed, t), Heard::Ignored);
    }

    #[test]
    fn the_same_command_twice_in_a_row_fires_once() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(
            gate.feed(&words("aurora siguiente", 1.0), t),
            Heard::Command(Intent::Next)
        );
        assert_eq!(
            gate.feed(
                &words("aurora siguiente", 1.0),
                t + Duration::from_millis(600)
            ),
            Heard::Ignored
        );
        assert_eq!(
            gate.feed(&words("aurora siguiente", 1.0), t + Duration::from_secs(3)),
            Heard::Command(Intent::Next)
        );
        // Otra orden distinta no espera.
        assert_eq!(
            gate.feed(&words("aurora pausa", 1.0), t + Duration::from_millis(3200)),
            Heard::Command(Intent::Pause)
        );
    }

    #[test]
    fn the_grammar_lists_exactly_the_phrases() {
        let grammar: Vec<String> = serde_json::from_str(&grammar_json()).unwrap();
        assert!(grammar.contains(&"aurora".to_string()));
        assert!(grammar.contains(&"aurora pausa".to_string()));
        assert!(grammar.contains(&"pausa".to_string()));
        assert!(grammar.contains(&"[unk]".to_string()));
        let count: usize = PHRASES.iter().map(|(_, l)| l.len()).sum();
        assert_eq!(grammar.len(), 1 + count * 2 + 1);
        for word in vocabulary() {
            assert_eq!(word, word.to_lowercase());
        }
    }
}
