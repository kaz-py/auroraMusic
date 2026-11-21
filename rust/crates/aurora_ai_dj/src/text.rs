//! Normalización de texto idéntica a la de Dart (`String.toLowerCase/trim`,
//! `RegExp` sin modo unicode).
//!
//! Dart y Rust discrepan en tres detalles que cambian los vectores, así que se
//! reproducen aquí a propósito:
//! - `toLowerCase` de Dart no aplica la sigma final contextual (Rust sí en
//!   `str::to_lowercase`): se pasa a minúsculas carácter a carácter.
//! - `\s` de Dart (sin `unicode: true`) es el de ECMAScript: incluye U+FEFF y
//!   excluye U+0085; el `\s` de Rust es el contrario.
//! - `\b` de Dart es ASCII.

use std::sync::LazyLock;

use regex::Regex;

/// Clase de caracteres equivalente al `\s` de Dart/ECMAScript.
macro_rules! ws {
    () => {
        r"[\t\n\x0B\x0C\r \x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]"
    };
}

fn compile(pattern: &str) -> Regex {
    Regex::new(pattern).expect("expresión regular válida")
}

pub(crate) static ARTIST_SPLIT: LazyLock<Regex> = LazyLock::new(|| {
    compile(concat!(
        ws!(),
        r"*(?:,|&|;|",
        ws!(),
        r"\+",
        ws!(),
        "|",
        ws!(),
        "/",
        ws!(),
        "|",
        ws!(),
        "+x",
        ws!(),
        r"+|(?-u:\b)feat\.?|(?-u:\b)ft\.?|(?-u:\b)featuring(?-u:\b))",
        ws!(),
        "*"
    ))
});

pub(crate) static FEAT_IN_TITLE: LazyLock<Regex> = LazyLock::new(|| {
    compile(concat!(
        r"[(\[](?:feat\.?|ft\.?|featuring)",
        ws!(),
        r"+([^)\]]+)[)\]]"
    ))
});

pub(crate) static FEAT_BLOCK: LazyLock<Regex> =
    LazyLock::new(|| compile(r"[(\[](?:feat|ft|featuring)[^)\]]*[)\]]"));

pub(crate) static NON_ALNUM: LazyLock<Regex> = LazyLock::new(|| compile(r"[^\p{L}\p{N}]+"));

pub(crate) static WHITESPACE_RUN: LazyLock<Regex> = LazyLock::new(|| compile(concat!(ws!(), "+")));

/// `String.toLowerCase` de Dart: asignación simple de minúsculas por carácter.
/// Rust usa además la asignación completa de SpecialCasing, cuya única entrada
/// incondicional es U+0130 (`İ` -> `i̇`); Dart devuelve `i`.
pub fn dart_lower(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        if c == '\u{130}' {
            out.push('i');
        } else {
            out.extend(c.to_lowercase());
        }
    }
    out
}

fn is_dart_trim_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n'
            | '\u{0B}'
            | '\u{0C}'
            | '\r'
            | ' '
            | '\u{85}'
            | '\u{A0}'
            | '\u{1680}'
            | '\u{2000}'
            ..='\u{200A}'
                | '\u{2028}'
                | '\u{2029}'
                | '\u{202F}'
                | '\u{205F}'
                | '\u{3000}'
                | '\u{FEFF}'
    )
}

/// `String.trim` de Dart (White_Space de Unicode más U+FEFF).
pub fn dart_trim(value: &str) -> &str {
    value.trim_matches(is_dart_trim_space)
}

/// Longitud en unidades UTF-16, como `String.length` de Dart.
pub fn utf16_len(value: &str) -> usize {
    value.encode_utf16().count()
}

/// Artistas de un campo «Artista» (colaboraciones, feat., etc.), en minúsculas,
/// sin vacíos ni repetidos y en orden de aparición.
pub fn dj_artists(artist: &str) -> Vec<String> {
    let lowered = dart_lower(artist);
    let mut out: Vec<String> = Vec::new();
    for part in ARTIST_SPLIT.split(&lowered) {
        let part = dart_trim(part);
        if !part.is_empty() && !out.iter().any(|seen| seen == part) {
            out.push(part.to_string());
        }
    }
    out
}

/// Artista principal (el primero) o cadena vacía.
pub fn primary_artist(artist: &str) -> String {
    dj_artists(artist).into_iter().next().unwrap_or_default()
}
