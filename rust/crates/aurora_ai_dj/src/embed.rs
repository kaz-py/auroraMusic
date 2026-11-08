//! Vectores de pista por hashing de características y perfil de gustos.
//! Transcripción de `lib/dj/ai_dj.dart` (hasta la v1.4.0): el orden de las
//! operaciones en coma flotante es parte del contrato.

use std::collections::HashMap;

use crate::text::{
    dart_lower, dart_trim, dj_artists, utf16_len, FEAT_BLOCK, FEAT_IN_TITLE, NON_ALNUM,
    WHITESPACE_RUN,
};

pub const VECTOR_DIMS: usize = 256;

/// Los datos de una pista que usa el DJ.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DjTrack {
    pub artist: String,
    pub title: String,
    pub album: Option<String>,
    pub genres: Vec<String>,
}

const NOISE_TOKENS: [&str; 38] = [
    "official",
    "oficial",
    "video",
    "videoclip",
    "audio",
    "lyrics",
    "lyric",
    "letra",
    "letras",
    "hd",
    "hq",
    "4k",
    "remastered",
    "remaster",
    "visualizer",
    "mv",
    "clip",
    "full",
    "version",
    "feat",
    "ft",
    "featuring",
    "prod",
    "the",
    "el",
    "la",
    "los",
    "las",
    "de",
    "del",
    "y",
    "and",
    "of",
    "en",
    "con",
    "with",
    "music",
    "topic",
];

/// Mapa ordenado con actualización en sitio: el orden de inserción fija el
/// orden de acumulación (y por tanto el redondeo a `f32`).
#[derive(Default)]
struct OrderedWeights {
    entries: Vec<(String, f64)>,
    index: HashMap<String, usize>,
}

impl OrderedWeights {
    fn add(&mut self, key: String, weight: f64) {
        match self.index.get(&key) {
            Some(&i) => self.entries[i].1 += weight,
            None => {
                self.index.insert(key.clone(), self.entries.len());
                self.entries.push((key, weight));
            }
        }
    }
}

/// Características ponderadas y dispersas de una pista, antes del hashing.
pub fn track_features(track: &DjTrack) -> Vec<(String, f64)> {
    let mut features = OrderedWeights::default();
    let artists = dj_artists(&track.artist);
    for (i, artist) in artists.iter().enumerate() {
        features.add(format!("a:{artist}"), if i == 0 { 1.0 } else { 0.7 });
    }
    let title = dart_lower(&track.title);
    for captures in FEAT_IN_TITLE.captures_iter(&title) {
        for artist in dj_artists(&captures[1]) {
            if !artists.contains(&artist) {
                features.add(format!("a:{artist}"), 0.7);
            }
        }
    }
    let album = track
        .album
        .as_deref()
        .map(|a| dart_lower(dart_trim(a)))
        .unwrap_or_default();
    if !album.is_empty() && album != title {
        features.add(format!("al:{album}"), 0.5);
    }
    for genre in &track.genres {
        let value = dart_lower(dart_trim(genre));
        if !value.is_empty() {
            features.add(format!("g:{value}"), 0.8);
        }
    }
    let mut artist_tokens: Vec<&str> = Vec::new();
    for artist in &artists {
        artist_tokens.extend(WHITESPACE_RUN.split(artist));
    }
    let cleaned = FEAT_BLOCK.replace_all(&title, " ");
    let mut seen: Vec<&str> = Vec::new();
    for token in NON_ALNUM.split(&cleaned) {
        if utf16_len(token) >= 2
            && !NOISE_TOKENS.contains(&token)
            && !artist_tokens.contains(&token)
            && !seen.contains(&token)
        {
            seen.push(token);
        }
    }
    for token in seen {
        features.add(format!("t:{token}"), 0.25);
    }
    features.entries
}

/// FNV-1a de 32 bits sobre unidades UTF-16 (estable entre ejecuciones).
fn fnv1a(value: &str) -> u32 {
    let mut hash: u32 = 0x811c9dc5;
    for unit in value.encode_utf16() {
        hash ^= unit as u32;
        hash = hash.wrapping_mul(0x01000193);
    }
    hash
}

/// Normaliza a norma 1 (en `f64`); un vector nulo se devuelve igual.
pub fn normalize(vector: &mut [f32]) {
    let mut norm = 0.0f64;
    for &value in vector.iter() {
        let value = value as f64;
        norm += value * value;
    }
    if norm == 0.0 {
        return;
    }
    let norm = norm.sqrt();
    for value in vector.iter_mut() {
        *value = (*value as f64 / norm) as f32;
    }
}

pub fn hash_features(features: &[(String, f64)]) -> Vec<f32> {
    let mut vector = vec![0.0f32; VECTOR_DIMS];
    for (key, weight) in features {
        let hash = fnv1a(key);
        let sign = if hash & 0x8000_0000 == 0 { 1.0 } else { -1.0 };
        let slot = hash as usize % VECTOR_DIMS;
        vector[slot] = (vector[slot] as f64 + sign * weight) as f32;
    }
    normalize(&mut vector);
    vector
}

pub fn embed_track(track: &DjTrack) -> Vec<f32> {
    hash_features(&track_features(track))
}

/// Coseno con la aritmética de `djCosine` (`f64` sobre elementos ensanchados).
pub fn cosine<A: Copy + Into<f64>, B: Copy + Into<f64>>(a: &[A], b: &[B]) -> f64 {
    if a.len() != b.len() {
        return 0.0;
    }
    let (mut dot, mut na, mut nb) = (0.0f64, 0.0f64, 0.0f64);
    for (&x, &y) in a.iter().zip(b) {
        let (x, y): (f64, f64) = (x.into(), y.into());
        dot += x * y;
        na += x * x;
        nb += y * y;
    }
    if na == 0.0 || nb == 0.0 {
        0.0
    } else {
        dot / (na * nb).sqrt()
    }
}

/// Un resultado de reproducción observado, ya asociado a su pista.
#[derive(Debug, Clone, PartialEq)]
pub struct DjEventInput {
    pub track: DjTrack,
    pub skip: bool,
    pub at_ms: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct DjProfile {
    pub vector: Vec<f32>,
    /// Pesos sin hashear, en orden de inserción (para las consultas de descubrimiento).
    pub features: Vec<(String, f64)>,
}

/// Suma ponderada con decaimiento temporal de señales reales. Favoritos y
/// listas no tienen fecha y no decaen; los eventos decaen con `half_life_minutes`.
pub fn build_taste_profile(
    favorites: &[DjTrack],
    playlist_tracks: &[DjTrack],
    history: &[DjTrack],
    events: &[DjEventInput],
    now_ms: i64,
    half_life_minutes: i64,
) -> DjProfile {
    let mut vector = vec![0.0f32; VECTOR_DIMS];
    let mut features = OrderedWeights::default();
    let mut add = |track: &DjTrack, weight: f64| {
        let track_features = track_features(track);
        let embedding = hash_features(&track_features);
        for (slot, value) in vector.iter_mut().zip(&embedding) {
            *slot = (*slot as f64 + weight * *value as f64) as f32;
        }
        for (key, value) in track_features {
            match features.index.get(&key) {
                Some(&i) => features.entries[i].1 += weight * value,
                None => {
                    features.index.insert(key.clone(), features.entries.len());
                    features.entries.push((key, weight * value));
                }
            }
        }
    };
    for track in favorites {
        add(track, 3.0);
    }
    for track in playlist_tracks {
        add(track, 1.5);
    }
    for (i, track) in history.iter().enumerate() {
        add(track, 0.8 / (1.0 + i as f64 / 4.0));
    }
    for event in events {
        // Minutos enteros truncados hacia cero, como `Duration.inMinutes`.
        let age = ((now_ms - event.at_ms) / 60_000).clamp(0, 1 << 30);
        let decay = 0.5f64.powf(age as f64 / half_life_minutes as f64);
        add(&event.track, if event.skip { -1.5 } else { 1.0 } * decay);
    }
    normalize(&mut vector);
    DjProfile {
        vector,
        features: features.entries,
    }
}
