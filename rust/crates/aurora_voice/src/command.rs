//! Qué frases entiende Aurora por voz y cuándo cuentan como una orden.
//!
//! Whisper entrega texto libre; aquí se decide si es una orden. Solo vale si va
//! tras la palabra de activación «aurora» (en la misma frase o, como mucho, 4 s
//! antes); lo demás se ignora. La comparación tolera una letra de error por
//! palabra («bon música» por «pon música»), pero «Laura» o «aurora boreal» no
//! activan nada.

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
/// Por encima de esta probabilidad de «no hay voz», la frase se descarta.
pub const MAX_NO_SPEECH: f32 = 0.6;
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

/// Minúsculas, sin acentos ni puntuación, en palabras.
pub fn words_of(text: &str) -> Vec<String> {
    let mut plain = String::with_capacity(text.len());
    for c in text.chars().flat_map(char::to_lowercase) {
        plain.push(match c {
            'á' | 'à' | 'ä' | 'â' => 'a',
            'é' | 'è' | 'ë' | 'ê' => 'e',
            'í' | 'ì' | 'ï' | 'î' => 'i',
            'ó' | 'ò' | 'ö' | 'ô' => 'o',
            'ú' | 'ù' | 'ü' | 'û' => 'u',
            'ñ' => 'n',
            c if c.is_alphanumeric() => c,
            _ => ' ',
        });
    }
    plain.split_whitespace().map(str::to_string).collect()
}

/// Distancia de edición (inserciones, borrados, sustituciones).
pub fn edit_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut row: Vec<usize> = (0..=b.len()).collect();
    for (i, ca) in a.iter().enumerate() {
        let mut diagonal = row[0];
        row[0] = i + 1;
        for (j, cb) in b.iter().enumerate() {
            let above = row[j + 1];
            row[j + 1] = (diagonal + usize::from(ca != cb))
                .min(row[j] + 1)
                .min(above + 1);
            diagonal = above;
        }
    }
    row[b.len()]
}

/// Dos palabras cuentan como la misma si son iguales o, siendo de 3 o más
/// letras, difieren en una.
pub fn same_word(heard: &str, wanted: &str) -> bool {
    heard == wanted || (wanted.chars().count() >= 3 && edit_distance(heard, wanted) <= 1)
}

fn same_phrase(heard: &[String], phrase: &str) -> bool {
    let wanted = words_of(phrase);
    heard.len() == wanted.len() && heard.iter().zip(&wanted).all(|(h, w)| same_word(h, w))
}

fn lookup(heard: &[String]) -> Option<Intent> {
    PHRASES
        .iter()
        .find(|(_, list)| list.iter().any(|p| same_phrase(heard, p)))
        .map(|(intent, _)| *intent)
}

const FILLERS_BEFORE: &[&str] = &["oye", "hey", "ey", "ok", "okay", "hola"];
const FILLERS_AFTER: &[&[&str]] = &[&["por", "favor"], &["porfa"], &["gracias"]];

/// Lo que se concluye de una frase.
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

    /// `text`: lo que transcribió Whisper; `no_speech`: su probabilidad de que
    /// no hubiera voz.
    pub fn feed(&mut self, text: &str, no_speech: f32, now: Instant) -> Heard {
        let armed = self.armed_until.is_some_and(|until| now <= until);
        self.armed_until = None;
        if no_speech > MAX_NO_SPEECH {
            return Heard::Ignored;
        }
        let mut words = words_of(text);
        while words
            .first()
            .is_some_and(|w| FILLERS_BEFORE.contains(&w.as_str()))
        {
            words.remove(0);
        }
        for tail in FILLERS_AFTER {
            if words.len() > tail.len()
                && words[words.len() - tail.len()..]
                    .iter()
                    .map(String::as_str)
                    .eq(tail.iter().copied())
            {
                words.truncate(words.len() - tail.len());
            }
        }
        let woke = words
            .first()
            .is_some_and(|w| w.chars().count() >= 5 && edit_distance(w, WAKE_WORD) <= 1);
        let command: &[String] = if woke {
            &words[1..]
        } else if armed {
            &words
        } else {
            return Heard::Ignored;
        };
        if command.is_empty() {
            if woke {
                self.armed_until = Some(now + ARMED_FOR);
                return Heard::Wake;
            }
            return Heard::Ignored;
        }
        let Some(intent) = lookup(command) else {
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

    fn hear(gate: &mut Gate, text: &str, at: Instant) -> Heard {
        gate.feed(text, 0.0, at)
    }

    #[test]
    fn a_command_needs_the_wake_word() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(
            hear(&mut gate, "Aurora, pausa.", t),
            Heard::Command(Intent::Pause)
        );
        let t = t + Duration::from_secs(10);
        assert_eq!(hear(&mut gate, "Pausa.", t), Heard::Ignored);
        assert_eq!(hear(&mut gate, "Siguiente canción.", t), Heard::Ignored);
        assert_eq!(
            hear(&mut gate, "Hola, buenas, aurora pausa", t),
            Heard::Ignored
        );
    }

    #[test]
    fn near_misses_of_the_wake_word_and_commands_still_work() {
        let mut gate = Gate::new();
        let mut t = Instant::now();
        for (text, want) in [
            ("Aurora, bon música.", Intent::Play),
            ("aurora pon musica", Intent::Play),
            ("¡Aurora, PAUSA!", Intent::Pause),
            ("Oye Aurora, siguiente", Intent::Next),
            ("Aurora, siguiente canción por favor", Intent::Next),
            ("Auroras, continúa", Intent::Resume),
            ("Aurora, cancion anterior.", Intent::Previous),
        ] {
            t += Duration::from_secs(5);
            assert_eq!(hear(&mut gate, text, t), Heard::Command(want), "{text}");
        }
    }

    #[test]
    fn similar_sounding_words_and_chatter_never_trigger() {
        let mut gate = Gate::new();
        let t = Instant::now();
        for text in [
            "Laura, pausa.",
            "La aurora boreal es muy hermosa en invierno.",
            "Ponle pausa al video que ya me cansé de verlo",
            "Aurora, baila",
            "Aurora, pausa pausa",
            "Aurora, pon pausa a todo",
            "Hola, ¿qué tal estuvo tu día de hoy?",
            "Subtítulos realizados por la comunidad de Amara.org",
            "",
            "   ",
        ] {
            assert_eq!(hear(&mut gate, text, t), Heard::Ignored, "{text:?}");
        }
    }

    #[test]
    fn every_phrase_maps_to_its_intent() {
        let mut gate = Gate::new();
        let mut t = Instant::now();
        for (intent, list) in PHRASES {
            for phrase in *list {
                t += Duration::from_secs(5);
                assert_eq!(
                    hear(&mut gate, &format!("Aurora, {phrase}."), t),
                    Heard::Command(*intent),
                    "{phrase}"
                );
            }
        }
    }

    #[test]
    fn wake_then_command_within_the_window() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(hear(&mut gate, "Aurora.", t), Heard::Wake);
        assert_eq!(
            hear(&mut gate, "Siguiente.", t + Duration::from_secs(2)),
            Heard::Command(Intent::Next)
        );
        // La activación se gasta con la primera orden.
        assert_eq!(
            hear(&mut gate, "Pausa.", t + Duration::from_secs(3)),
            Heard::Ignored
        );
        // Fuera de la ventana no cuenta.
        assert_eq!(
            hear(&mut gate, "Aurora.", t + Duration::from_secs(10)),
            Heard::Wake
        );
        assert_eq!(
            hear(&mut gate, "Pausa.", t + Duration::from_secs(15)),
            Heard::Ignored
        );
    }

    #[test]
    fn a_frame_that_is_probably_not_speech_is_dropped() {
        let mut gate = Gate::new();
        assert_eq!(
            gate.feed("Aurora, pausa.", 0.9, Instant::now()),
            Heard::Ignored
        );
        assert_eq!(
            gate.feed("Aurora, pausa.", 0.2, Instant::now()),
            Heard::Command(Intent::Pause)
        );
    }

    #[test]
    fn the_same_command_twice_in_a_row_fires_once() {
        let mut gate = Gate::new();
        let t = Instant::now();
        assert_eq!(
            hear(&mut gate, "Aurora siguiente", t),
            Heard::Command(Intent::Next)
        );
        assert_eq!(
            hear(
                &mut gate,
                "Aurora siguiente",
                t + Duration::from_millis(600)
            ),
            Heard::Ignored
        );
        assert_eq!(
            hear(&mut gate, "Aurora siguiente", t + Duration::from_secs(3)),
            Heard::Command(Intent::Next)
        );
        assert_eq!(
            hear(&mut gate, "Aurora pausa", t + Duration::from_millis(3200)),
            Heard::Command(Intent::Pause)
        );
    }

    #[test]
    fn text_helpers() {
        assert_eq!(words_of("¡Continúa, Ñandú!"), ["continua", "nandu"]);
        assert_eq!(edit_distance("aurora", "laura"), 3);
        assert_eq!(edit_distance("pon", "bon"), 1);
        assert!(same_word("bon", "pon"));
        assert!(
            !same_word("no", "un"),
            "las palabras de dos letras son exactas"
        );
        assert!(same_word("musica", "musica") && same_word("reproduse", "reproduce"));
    }
}
