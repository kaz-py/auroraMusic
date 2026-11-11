//! Pone hora a una letra con el audio de la canción.
//!
//! Whisper transcribe el canto con la hora de cada palabra; esa transcripción
//! (con errores, huecos y palabras de más) se alinea con el texto de la letra
//! mediante programación dinámica, y cada línea con suficientes palabras en
//! común queda anclada a un instante. Las demás se reparten entre las ancladas.
//!
//! - Letra **sin tiempos**: el resultado son las horas de cada línea.
//! - Letra **sincronizada**: se conservan sus tiempos relativos (más precisos
//!   que los de Whisper) y solo se corrige su desplazamiento: constante si todas
//!   las anclas coinciden y, si no, interpolado entre ellas.

use std::path::Path;
use std::sync::atomic::AtomicBool;

use crate::capture::MODEL_RATE;
use crate::command::{edit_distance, words_of};
use crate::whisper::{TimedWord, Transcriber};
use crate::VoiceError;

#[derive(Debug, Clone)]
pub struct LyricLine {
    pub text: String,
    /// Hora de la línea en la letra sincronizada; `None` si la letra no tiene tiempos.
    pub at_secs: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Alignment {
    /// Hora (s) a la que empieza cada línea según el audio; misma longitud que la letra.
    pub starts: Vec<f64>,
    /// Líneas ancladas directamente al audio.
    pub anchored: usize,
    /// Con letra sincronizada: mediana del desplazamiento (audio − letra).
    pub shift_secs: Option<f64>,
}

/// Palabras «de relleno» que no cuentan como prueba de que una línea suena ahí.
const WEAK_LEN: usize = 3;
/// Un ancla cuyo desplazamiento se aparta tanto de la mediana es una coincidencia falsa.
const OUTLIER_SECS: f64 = 3.0;
/// Hasta aquí todas las anclas se consideran el mismo desplazamiento.
const CONSTANT_SHIFT_SECS: f64 = 1.5;
/// Segundos por palabra para retrasar el inicio de una línea anclada por una palabra intermedia.
const WORD_SECS: f64 = 0.3;

struct Token {
    text: String,
    time: f64,
}

fn eq(heard: &str, wanted: &str) -> bool {
    let (a, b) = (heard.chars().count(), wanted.chars().count());
    if heard == wanted {
        return true;
    }
    if a < 4 || b < 4 {
        return false;
    }
    // «wash» por «washed»: una es el comienzo de la otra.
    let (short, long) = if a <= b {
        (heard, wanted)
    } else {
        (wanted, heard)
    };
    long.starts_with(short) && long.chars().count() - short.chars().count() <= 3
        || edit_distance(heard, wanted) <= if a.max(b) >= 8 { 2 } else { 1 }
}

/// Alinea dos secuencias de palabras (Needleman–Wunsch). Devuelve, para cada
/// palabra de la letra, el índice de la palabra transcrita con la que casa.
fn match_words(heard: &[Token], lyric: &[(usize, String)]) -> Vec<Option<usize>> {
    let (n, m) = (heard.len(), lyric.len());
    let score_match = |i: usize, j: usize| -> Option<f32> {
        if eq(&heard[i].text, &lyric[j].1) {
            Some(if lyric[j].1.chars().count() > WEAK_LEN {
                2.0
            } else {
                0.5
            })
        } else {
            None
        }
    };
    const GAP: f32 = -0.7;
    const MISS: f32 = -1.0;
    let width = m + 1;
    let mut score = vec![0.0f32; (n + 1) * width];
    let mut trace = vec![0u8; (n + 1) * width]; // 1 diagonal, 2 arriba, 3 izquierda
    for i in 1..=n {
        score[i * width] = i as f32 * GAP;
        trace[i * width] = 2;
    }
    for j in 1..=m {
        score[j] = j as f32 * GAP;
        trace[j] = 3;
    }
    for i in 1..=n {
        for j in 1..=m {
            let diagonal =
                score[(i - 1) * width + j - 1] + score_match(i - 1, j - 1).unwrap_or(MISS);
            let up = score[(i - 1) * width + j] + GAP;
            let left = score[i * width + j - 1] + GAP;
            let (best, from) = if diagonal >= up && diagonal >= left {
                (diagonal, 1)
            } else if up >= left {
                (up, 2)
            } else {
                (left, 3)
            };
            score[i * width + j] = best;
            trace[i * width + j] = from;
        }
    }
    let mut matched = vec![None; m];
    let (mut i, mut j) = (n, m);
    while i > 0 || j > 0 {
        match trace[i * width + j] {
            1 => {
                if score_match(i - 1, j - 1).is_some() {
                    matched[j - 1] = Some(i - 1);
                }
                i -= 1;
                j -= 1;
            }
            2 => i -= 1,
            _ => j -= 1,
        }
    }
    matched
}

fn median(values: &mut [f64]) -> f64 {
    values.sort_by(f64::total_cmp);
    values[values.len() / 2]
}

/// Reparte las horas de las líneas sin ancla entre las ancladas, según su largo.
fn fill_plain(anchors: &[Option<f64>], chars: &[usize]) -> Vec<f64> {
    let known: Vec<usize> = (0..anchors.len())
        .filter(|&i| anchors[i].is_some())
        .collect();
    // Segundos por carácter: de lo que se ve entre anclas; si no, un valor de canción.
    let mut rates: Vec<f64> = known
        .windows(2)
        .filter_map(|w| {
            let span: usize = chars[w[0]..w[1]].iter().sum();
            let secs = anchors[w[1]]? - anchors[w[0]]?;
            (span > 0 && secs > 0.0).then_some(secs / span as f64)
        })
        .collect();
    let rate = if rates.is_empty() {
        0.08
    } else {
        median(&mut rates)
    }
    .clamp(0.03, 0.25);
    let mut starts = vec![0.0; anchors.len()];
    for (line, start) in starts.iter_mut().enumerate() {
        let before = known.iter().rev().find(|&&k| k <= line).copied();
        let after = known.iter().find(|&&k| k >= line).copied();
        *start = match (before, after) {
            (Some(b), _) if b == line => anchors[b].unwrap(),
            (Some(b), Some(a)) => {
                let span: usize = chars[b..a].iter().sum();
                let part: usize = chars[b..line].iter().sum();
                let (t0, t1) = (anchors[b].unwrap(), anchors[a].unwrap());
                t0 + (t1 - t0) * part as f64 / span.max(1) as f64
            }
            (Some(b), None) => {
                anchors[b].unwrap() + chars[b..line].iter().sum::<usize>() as f64 * rate
            }
            (None, Some(a)) => {
                (anchors[a].unwrap() - chars[line..a].iter().sum::<usize>() as f64 * rate).max(0.0)
            }
            (None, None) => 0.0,
        };
    }
    // Nunca hacia atrás.
    for i in 1..starts.len() {
        starts[i] = starts[i].max(starts[i - 1]);
    }
    starts
}

/// Núcleo puro: transcripción con horas + letra → horas de las líneas.
pub fn align_words(words: &[TimedWord], lines: &[LyricLine]) -> Option<Alignment> {
    let heard: Vec<Token> = words
        .iter()
        .flat_map(|w| {
            words_of(&w.text).into_iter().map(move |text| Token {
                text,
                time: w.start,
            })
        })
        .collect();
    let lyric: Vec<(usize, String)> = lines
        .iter()
        .enumerate()
        .flat_map(|(line, l)| words_of(&l.text).into_iter().map(move |w| (line, w)))
        .collect();
    if heard.len() < 4 || lyric.len() < 4 {
        return None;
    }
    let matched = match_words(&heard, &lyric);

    // Ancla de cada línea: la hora de su primera palabra reconocida, retrasada
    // por las palabras de la línea que la preceden.
    let mut anchors: Vec<Option<f64>> = vec![None; lines.len()];
    let mut first_of_line = vec![0usize; lines.len()];
    for (j, (line, _)) in lyric.iter().enumerate().rev() {
        first_of_line[*line] = j;
    }
    for (line, anchor) in anchors.iter_mut().enumerate() {
        let total = lyric.iter().filter(|(l, _)| *l == line).count();
        if total == 0 {
            continue;
        }
        let range = first_of_line[line]..first_of_line[line] + total;
        let hits: Vec<usize> = range.clone().filter(|&j| matched[j].is_some()).collect();
        let strong = hits
            .iter()
            .filter(|&&j| lyric[j].1.chars().count() > WEAK_LEN)
            .count();
        let enough = strong >= 2 || (total <= 4 && strong >= 1 && hits.len() * 2 >= total);
        if !enough || hits.len() * 5 < total * 2 {
            continue;
        }
        let j = hits[0];
        let time = heard[matched[j].unwrap()].time - (j - range.start) as f64 * WORD_SECS;
        *anchor = Some(time.max(0.0));
    }
    // Las anclas avanzan siempre.
    let mut last = f64::MIN;
    for anchor in anchors.iter_mut().flatten() {
        if *anchor < last {
            *anchor = last;
        }
        last = *anchor;
    }
    let count = anchors.iter().flatten().count();
    if count < 2 {
        return None;
    }
    let chars: Vec<usize> = lines
        .iter()
        .map(|l| words_of(&l.text).join(" ").chars().count().max(1))
        .collect();

    if lines.iter().all(|l| l.at_secs.is_some()) {
        // Letra sincronizada: desplazamiento (audio − letra) de cada ancla.
        let shifts: Vec<Option<f64>> = anchors
            .iter()
            .zip(lines)
            .map(|(a, l)| Some((*a)? - l.at_secs?))
            .collect();
        let mut all: Vec<f64> = shifts.iter().flatten().copied().collect();
        let global = median(&mut all);
        let kept: Vec<(usize, f64)> = shifts
            .iter()
            .enumerate()
            .filter_map(|(i, s)| {
                s.filter(|s| (s - global).abs() <= OUTLIER_SECS)
                    .map(|s| (i, s))
            })
            .collect();
        if kept.len() < 2 {
            return None;
        }
        let (lo, hi) = kept.iter().fold((f64::MAX, f64::MIN), |(lo, hi), (_, s)| {
            (lo.min(*s), hi.max(*s))
        });
        let mut sorted: Vec<f64> = kept.iter().map(|(_, s)| *s).collect();
        let constant = median(&mut sorted);
        let starts = lines
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let at = l.at_secs.unwrap();
                let shift = if hi - lo <= CONSTANT_SHIFT_SECS {
                    constant
                } else {
                    interpolate_shift(&kept, i)
                };
                (at + shift).max(0.0)
            })
            .collect();
        return Some(Alignment {
            starts,
            anchored: kept.len(),
            shift_secs: Some(constant),
        });
    }
    Some(Alignment {
        starts: fill_plain(&anchors, &chars),
        anchored: count,
        shift_secs: None,
    })
}

fn interpolate_shift(kept: &[(usize, f64)], line: usize) -> f64 {
    let before = kept.iter().rev().find(|(i, _)| *i <= line);
    let after = kept.iter().find(|(i, _)| *i >= line);
    match (before, after) {
        (Some((b, sb)), Some((a, sa))) if a != b => {
            sb + (sa - sb) * (line - b) as f64 / (a - b) as f64
        }
        (Some((_, s)), _) | (_, Some((_, s))) => *s,
        _ => 0.0,
    }
}

const STOPWORDS: &[(&str, &[&str])] = &[
    (
        "es",
        &[
            "el", "la", "los", "las", "que", "de", "en", "y", "un", "una", "me", "te", "se", "mi",
            "tu", "por", "con", "no", "lo", "es", "para", "si", "yo", "mas", "pero", "como",
        ],
    ),
    (
        "en",
        &[
            "the", "and", "you", "to", "of", "in", "it", "is", "my", "me", "that", "i", "on",
            "for", "with", "this", "but", "your", "all", "we", "be", "not", "just",
        ],
    ),
    (
        "pt",
        &[
            "que", "de", "não", "nao", "você", "voce", "uma", "com", "para", "meu", "minha", "eu",
            "mais", "os", "as", "um", "do", "da",
        ],
    ),
    (
        "fr",
        &[
            "le", "la", "les", "des", "est", "je", "tu", "et", "un", "une", "que", "pas", "pour",
            "dans", "mon", "ton", "ce",
        ],
    ),
    (
        "it",
        &[
            "il", "di", "che", "non", "per", "una", "mi", "ti", "sono", "con", "le", "ma", "come",
            "sei",
        ],
    ),
];

/// Idioma de la letra por palabras vacías; `None` si no está claro (Whisper lo detecta).
pub fn detect_language(lines: &[LyricLine]) -> Option<&'static str> {
    let tokens: Vec<String> = lines.iter().flat_map(|l| words_of(&l.text)).collect();
    let mut scores: Vec<(&'static str, usize)> = STOPWORDS
        .iter()
        .map(|(code, words)| {
            let plain: Vec<String> = words.iter().flat_map(|w| words_of(w)).collect();
            (*code, tokens.iter().filter(|t| plain.contains(t)).count())
        })
        .collect();
    scores.sort_by_key(|(_, n)| std::cmp::Reverse(*n));
    let (best, second) = (scores[0], scores[1]);
    (best.1 >= 6 && best.1 >= second.1 * 3 / 2).then_some(best.0)
}

/// Analiza `pcm` (mono, 16 kHz, desde el principio de la canción) y alinea la letra.
pub fn align_lyrics(
    model: &Path,
    pcm: &[f32],
    lines: &[LyricLine],
    language: Option<&str>,
    cancel: &AtomicBool,
) -> Result<Option<Alignment>, VoiceError> {
    debug_assert_eq!(MODEL_RATE, 16_000);
    let threads =
        std::thread::available_parallelism().map_or(2, |n| (n.get() / 2).clamp(2, 4)) as i32;
    let mut transcriber = Transcriber::load(model, threads, true)?;
    let detected = language.is_none().then(|| detect_language(lines)).flatten();
    let words = transcriber.words(pcm, language.or(detected), cancel)?;
    Ok(align_words(&words, lines))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn line(text: &str, at: Option<f64>) -> LyricLine {
        LyricLine {
            text: text.into(),
            at_secs: at,
        }
    }

    /// Palabras de `text` repartidas desde `start`, 0,4 s cada una.
    fn sung(text: &str, start: f64) -> Vec<TimedWord> {
        text.split_whitespace()
            .enumerate()
            .map(|(i, w)| TimedWord {
                text: format!(" {w}"),
                start: start + i as f64 * 0.4,
                end: start + i as f64 * 0.4 + 0.35,
            })
            .collect()
    }

    const SONG: [(&str, f64); 6] = [
        ("You washed right up", 2.0),
        ("I ran away from any chance to meet you", 6.0),
        ("Scared that you'd be everything to me", 11.0),
        ("I knew that you'd be the sun", 16.0),
        ("Every video reminds me of you too", 21.0),
        ("Now I'm left waiting for the next stop", 26.0),
    ];

    #[test]
    fn synced_lyrics_get_the_shift_of_a_long_intro_despite_mishearing() {
        let lyric: Vec<LyricLine> = SONG.iter().map(|(t, a)| line(t, Some(*a))).collect();
        // Cantado 30 s después, con errores y una línea que no se oye.
        let mut heard = Vec::new();
        heard.extend(sung("You wash right up", 32.0));
        heard.extend(sung("I ran away from any chants to meet you", 36.0));
        // (línea 3 no reconocida)
        heard.extend(sung("I knew that you be the sun", 46.0));
        heard.extend(sung("Every vid reminds me of you too", 51.0));
        heard.extend(sung("Now I'm left waiting for the next stop", 56.0));
        let a = align_words(&heard, &lyric).expect("alineación");
        assert!((a.shift_secs.unwrap() - 30.0).abs() < 0.7, "{a:?}");
        assert_eq!(a.anchored, 5);
        // Los tiempos relativos de la letra se conservan (la línea no oída incluida).
        assert!((a.starts[2] - 41.0).abs() < 0.7, "{:?}", a.starts);
        assert!(a.starts.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn plain_lyrics_get_times_from_the_anchors() {
        let lyric: Vec<LyricLine> = SONG.iter().map(|(t, _)| line(t, None)).collect();
        let mut heard = Vec::new();
        heard.extend(sung("You washed right up", 34.0));
        heard.extend(sung("I ran away from any chance to meet you", 38.0));
        heard.extend(sung("I knew that you'd be the sun", 49.0));
        heard.extend(sung("Now I'm left waiting for the next stop", 59.0));
        let a = align_words(&heard, &lyric).expect("alineación");
        assert_eq!(a.shift_secs, None);
        assert!((a.starts[0] - 34.0).abs() < 0.5);
        assert!((a.starts[1] - 38.0).abs() < 0.5);
        // Las líneas sin ancla caen entre sus vecinas.
        assert!(a.starts[2] > 38.0 && a.starts[2] < 49.0, "{:?}", a.starts);
        assert!(a.starts[4] > 49.0 && a.starts[4] < 59.0, "{:?}", a.starts);
        assert!(a.starts.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn the_language_of_a_lyric_is_guessed_from_its_common_words() {
        let es: Vec<LyricLine> = [
            "Caminando por la calle sin rumbo",
            "Y el viento me dice que vuelva",
            "No sé lo que te pasa",
        ]
        .iter()
        .map(|t| line(t, None))
        .collect();
        let en: Vec<LyricLine> = SONG.iter().map(|(t, _)| line(t, None)).collect();
        assert_eq!(detect_language(&es), Some("es"));
        assert_eq!(detect_language(&en), Some("en"));
        assert_eq!(detect_language(&[line("Oh oh ooh", None)]), None);
    }

    #[test]
    fn unrelated_transcripts_and_isolated_matches_give_nothing() {
        let lyric: Vec<LyricLine> = SONG.iter().map(|(t, _)| line(t, None)).collect();
        let other = sung(
            "la luna llena brilla sobre el mar dime si volverás a esperarme",
            5.0,
        );
        assert_eq!(align_words(&other, &lyric), None);
        // Palabras sueltas y comunes no son prueba de nada.
        let noise = sung("you the to me you the to me you the to me you", 5.0);
        assert_eq!(align_words(&noise, &lyric), None);
        assert_eq!(align_words(&[], &lyric), None);
    }

    #[test]
    fn a_false_match_far_from_the_rest_is_discarded() {
        let lyric: Vec<LyricLine> = SONG.iter().map(|(t, a)| line(t, Some(*a))).collect();
        let mut heard = Vec::new();
        heard.extend(sung("You wash right up", 14.0)); // +12
        heard.extend(sung("I ran away from any chance to meet you", 18.0)); // +12
        heard.extend(sung("Scared that you be everything to me", 23.0)); // +12
        heard.extend(sung("Every video reminds me of you too", 73.0)); // +52: falsa
        let a = align_words(&heard, &lyric).expect("alineación");
        assert!((a.shift_secs.unwrap() - 12.0).abs() < 0.7, "{a:?}");
        assert_eq!(a.anchored, 3);
    }

    #[test]
    fn a_drifting_recording_interpolates_the_shift() {
        let lyric: Vec<LyricLine> = SONG.iter().map(|(t, a)| line(t, Some(*a))).collect();
        // El audio va acelerando su retraso: +2 s al principio, +6 s al final.
        let mut heard = Vec::new();
        for (i, (t, a)) in SONG.iter().enumerate() {
            heard.extend(sung(t, a + 2.0 + i as f64 * 0.8));
        }
        let a = align_words(&heard, &lyric).expect("alineación");
        assert!(
            (a.starts[0] - 4.0).abs() < 0.7 && (a.starts[5] - 32.0).abs() < 0.9,
            "{:?}",
            a.starts
        );
    }
}
