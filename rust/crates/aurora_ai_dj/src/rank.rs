//! Ranking del DJ: gusto + continuidad + prior de la fuente, menos penalizaciones,
//! y elección voraz con MMR bajo enfriamiento de artista.
//! Transcripción de `rankDjCandidates` (`lib/dj/ai_dj.dart`, v1.4.0).

use std::collections::HashSet;

use crate::embed::{cosine, embed_track, DjTrack};
use crate::text::primary_artist;

pub const TASTE_WEIGHT: f64 = 0.55;
pub const PRIOR_WEIGHT: f64 = 0.25;
pub const CONTINUITY_WEIGHT: f64 = 0.20;
pub const RECENT_PENALTY: f64 = 0.35;
pub const SKIPPED_ARTIST_PENALTY: f64 = 0.30;

/// Candidato ya admitido por Dart (filtros, reproducible, sin pendiente de Spotify).
#[derive(Debug, Clone, PartialEq)]
pub struct RankCandidate {
    pub track: DjTrack,
    pub prior: f64,
    /// `recommendationTrackKeys(track)`.
    pub keys: Vec<String>,
    /// Sesgo de modo ya evaluado (`adjust?.call(track) ?? 0`).
    pub adjust: f64,
    /// `djCoherenceWeight * (coherencia - 0.5)`, o 0 sin contexto de coherencia.
    pub coherence_bonus: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RankRequest {
    pub candidates: Vec<RankCandidate>,
    pub profile: Vec<f64>,
    pub limit: usize,
    pub current: Option<DjTrack>,
    pub blocked_keys: Vec<String>,
    pub recent_keys: Vec<String>,
    pub skipped_artists: Vec<String>,
    /// Cadenas de artista sin tratar de la cola pendiente.
    pub queue_tail_artists: Vec<String>,
    pub lambda: f64,
    pub artist_cooldown: bool,
    pub heard_keys: Vec<String>,
    pub heard_share: Option<f64>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Pick {
    /// Posición en `RankRequest::candidates`.
    pub index: usize,
    pub affinity: f64,
}

/// Reparto determinista de la cuota: `true` cuando el siguiente puesto debe ser
/// una pista ya oída (la tanda empieza por una nueva y alterna hasta `share`).
pub fn dj_want_heard(heard_so_far: usize, chosen_so_far: usize, share: f64) -> bool {
    (heard_so_far as f64) < (share * (chosen_so_far + 1) as f64).round()
}

struct Pooled {
    index: usize,
    vector: Vec<f32>,
    relevance: f64,
    artist: String,
    heard: bool,
}

fn allowed(artists_so_far: &[String], cooldown: bool, artist: &str) -> bool {
    if artist.is_empty() || !cooldown {
        return true;
    }
    if artists_so_far.last().is_some_and(|last| last == artist) {
        return false;
    }
    let window = &artists_so_far[artists_so_far.len().saturating_sub(9)..];
    window.iter().filter(|a| *a == artist).count() < 2
}

pub fn rank_candidates(req: &RankRequest) -> Vec<Pick> {
    if req.limit == 0 {
        return Vec::new();
    }
    let current_vector = req.current.as_ref().map(embed_track);
    let recent: HashSet<&str> = req.recent_keys.iter().map(String::as_str).collect();
    let skipped: HashSet<&str> = req.skipped_artists.iter().map(String::as_str).collect();
    let heard_keys: HashSet<&str> = req.heard_keys.iter().map(String::as_str).collect();
    let mut seen: HashSet<&str> = req.blocked_keys.iter().map(String::as_str).collect();

    // Orden estable por prior descendente. (Dart usaba un sort inestable: solo
    // difiere con priors empatados, que no se dan con priors por posición.)
    let mut ordered: Vec<usize> = (0..req.candidates.len()).collect();
    ordered.sort_by(|&a, &b| req.candidates[b].prior.total_cmp(&req.candidates[a].prior));

    let mut pool: Vec<Pooled> = Vec::new();
    for index in ordered {
        let candidate = &req.candidates[index];
        if candidate.keys.iter().any(|k| seen.contains(k.as_str())) {
            continue;
        }
        seen.extend(candidate.keys.iter().map(String::as_str));
        let vector = embed_track(&candidate.track);
        let artist = primary_artist(&candidate.track.artist);
        let mut relevance = TASTE_WEIGHT * cosine(&req.profile, &vector);
        relevance += PRIOR_WEIGHT * candidate.prior;
        if let Some(current) = &current_vector {
            relevance += CONTINUITY_WEIGHT * cosine(current, &vector);
        }
        relevance -= -candidate.adjust;
        relevance -= if candidate.keys.iter().any(|k| recent.contains(k.as_str())) {
            RECENT_PENALTY
        } else {
            0.0
        };
        relevance -= if skipped.contains(artist.as_str()) {
            SKIPPED_ARTIST_PENALTY
        } else {
            0.0
        };
        // Coherencia con la semilla (puntuada en Dart): se suma al final, como en 1.5.x.
        relevance += candidate.coherence_bonus;
        let heard = candidate
            .keys
            .iter()
            .any(|k| heard_keys.contains(k.as_str()));
        pool.push(Pooled {
            index,
            vector,
            relevance,
            artist,
            heard,
        });
    }

    let mut artists_so_far: Vec<String> = Vec::new();
    if let (Some(current), true) = (&req.current, req.queue_tail_artists.is_empty()) {
        artists_so_far.push(primary_artist(&current.artist));
    }
    artists_so_far.extend(req.queue_tail_artists.iter().map(|a| primary_artist(a)));

    let mut heard_picked = 0usize;
    let mut picked: Vec<Pooled> = Vec::new();
    while picked.len() < req.limit && !pool.is_empty() {
        // Un puesto relajado por tanda cuando todos los artistas están en
        // enfriamiento, para que una biblioteca de un solo artista continúe.
        let relaxed = picked.is_empty()
            && !pool
                .iter()
                .any(|c| allowed(&artists_so_far, req.artist_cooldown, &c.artist));
        // Con cuota se busca primero en la clase que toca; si no hay, en cualquiera.
        let want_heard = req
            .heard_share
            .map(|share| dj_want_heard(heard_picked, picked.len(), share));
        let passes: Vec<Option<bool>> = match want_heard {
            Some(want) => vec![Some(want), None],
            None => vec![None],
        };
        let mut best: Option<usize> = None;
        for only in passes {
            let mut best_score = f64::NEG_INFINITY;
            for (i, item) in pool.iter().enumerate() {
                if !relaxed && !allowed(&artists_so_far, req.artist_cooldown, &item.artist) {
                    continue;
                }
                if only.is_some_and(|heard| item.heard != heard) {
                    continue;
                }
                let mut redundancy = 0.0f64;
                for chosen in &picked {
                    redundancy = redundancy.max(cosine(&item.vector, &chosen.vector));
                }
                let score = req.lambda * item.relevance - (1.0 - req.lambda) * redundancy;
                if score > best_score {
                    best_score = score;
                    best = Some(i);
                }
            }
            if best.is_some() {
                break;
            }
        }
        let Some(best) = best else { break };
        let chosen = pool.remove(best);
        if chosen.heard {
            heard_picked += 1;
        }
        artists_so_far.push(chosen.artist.clone());
        picked.push(chosen);
    }
    picked
        .into_iter()
        .map(|p| Pick {
            index: p.index,
            affinity: p.relevance.clamp(0.0, 1.0),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn track(artist: &str, title: &str) -> DjTrack {
        DjTrack {
            artist: artist.into(),
            title: title.into(),
            album: None,
            genres: vec![],
        }
    }

    fn candidate(artist: &str, title: &str, prior: f64, key: &str) -> RankCandidate {
        RankCandidate {
            track: track(artist, title),
            prior,
            keys: vec![key.into()],
            adjust: 0.0,
            coherence_bonus: 0.0,
        }
    }

    fn request(candidates: Vec<RankCandidate>, limit: usize) -> RankRequest {
        RankRequest {
            candidates,
            profile: vec![0.0; 256],
            limit,
            current: None,
            blocked_keys: vec![],
            recent_keys: vec![],
            skipped_artists: vec![],
            queue_tail_artists: vec![],
            lambda: 0.7,
            artist_cooldown: true,
            heard_keys: vec![],
            heard_share: None,
        }
    }

    #[test]
    fn want_heard_alternates_up_to_the_share() {
        // La tanda empieza por una nueva y alterna hasta la cuota.
        assert!(!dj_want_heard(0, 0, 0.4));
        assert!(dj_want_heard(0, 1, 0.4));
        assert!(!dj_want_heard(1, 2, 0.4));
        // `round` es mitad-lejos-de-cero: 0.5 -> 1 (como Dart).
        assert!(dj_want_heard(0, 0, 0.5));
        assert!(!dj_want_heard(1, 0, 0.5));
        assert!(!dj_want_heard(0, 5, 0.0));
    }

    #[test]
    fn equal_priors_keep_input_order() {
        // Con priors empatados la ordenación estable conserva el orden de entrada
        // y el desempate del argmax elige el primero del pool.
        let req = RankRequest {
            artist_cooldown: false,
            ..request(
                vec![
                    candidate("a", "x", 0.5, "k1"),
                    candidate("b", "y", 0.5, "k2"),
                    candidate("c", "z", 0.5, "k3"),
                ],
                1,
            )
        };
        let first = rank_candidates(&req);
        assert_eq!(first.len(), 1);
        let swapped = RankRequest {
            candidates: req.candidates.iter().rev().cloned().collect(),
            ..req.clone()
        };
        let second = rank_candidates(&swapped);
        assert_eq!(first[0].index, 0);
        assert_eq!(second[0].index, 0); // el mismo elemento del pool, ahora en la posición 0
    }

    #[test]
    fn duplicate_keys_keep_the_higher_prior_and_blocked_keys_drop() {
        let mut req = request(
            vec![
                candidate("a", "low", 0.2, "dup"),
                candidate("b", "high", 0.9, "dup"),
                candidate("c", "blocked", 0.8, "gone"),
            ],
            5,
        );
        req.blocked_keys = vec!["gone".into()];
        let picks = rank_candidates(&req);
        assert_eq!(picks.len(), 1);
        assert_eq!(picks[0].index, 1);
    }

    #[test]
    fn cooldown_blocks_back_to_back_artist_but_relaxes_when_only_one_artist() {
        let only_one = request(
            vec![
                candidate("solo", "a", 0.9, "1"),
                candidate("solo", "b", 0.8, "2"),
                candidate("solo", "c", 0.7, "3"),
            ],
            3,
        );
        // Sin artistas previos el primer puesto sale; luego el enfriamiento
        // bloquea al mismo artista seguido.
        let picks = rank_candidates(&only_one);
        assert_eq!(picks.len(), 1);
        let mut with_current = only_one.clone();
        with_current.current = Some(track("solo", "now"));
        let picks = rank_candidates(&with_current);
        assert_eq!(picks.len(), 1, "un solo puesto relajado por tanda");
    }

    #[test]
    fn zero_limit_is_empty() {
        assert!(rank_candidates(&request(vec![candidate("a", "x", 0.5, "k")], 0)).is_empty());
    }

    #[test]
    fn coherence_bonus_shifts_relevance_and_can_reorder_picks() {
        let mut req = request(
            vec![
                candidate("a", "x", 0.6, "k1"),
                candidate("b", "y", 0.5, "k2"),
            ],
            2,
        );
        req.lambda = 1.0;
        let plain = rank_candidates(&req);
        assert_eq!(plain[0].index, 0);
        req.candidates[1].coherence_bonus = 0.6;
        let boosted = rank_candidates(&req);
        assert_eq!(boosted[0].index, 1);
        let expected = PRIOR_WEIGHT * 0.5 + 0.6;
        assert!((boosted[0].affinity - expected).abs() < 1e-12);
    }
}
