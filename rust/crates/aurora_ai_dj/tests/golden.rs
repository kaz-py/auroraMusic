//! Pruebas de oro: entradas y salidas volcadas desde `lib/dj/ai_dj.dart`
//! (v1.4.0) con `test/zz_gen_dj_golden_test.dart` (generador ya eliminado).

use std::fs;
use std::path::PathBuf;

use aurora_ai_dj::{
    build_taste_profile, dj_artists, embed_track, rank_candidates, track_features, DjEventInput,
    DjTrack, RankCandidate, RankRequest,
};
use serde::Deserialize;

#[derive(Deserialize)]
struct Golden {
    embeddings: Vec<EmbeddingCase>,
    profiles: Vec<ProfileCase>,
    ranks: Vec<RankCase>,
}

#[derive(Deserialize, Clone)]
struct TrackIn {
    artist: String,
    title: String,
    album: Option<String>,
    genres: Vec<String>,
}

impl From<TrackIn> for DjTrack {
    fn from(t: TrackIn) -> Self {
        DjTrack {
            artist: t.artist,
            title: t.title,
            album: t.album,
            genres: t.genres,
        }
    }
}

#[derive(Deserialize)]
struct EmbeddingCase {
    track: TrackIn,
    artists: Vec<String>,
    features: Vec<(String, f64)>,
    vector: Vec<f64>,
}

#[derive(Deserialize)]
struct EventIn {
    track: TrackIn,
    skip: bool,
    at_ms: i64,
}

#[derive(Deserialize)]
struct ProfileCase {
    favorites: Vec<TrackIn>,
    playlist_tracks: Vec<TrackIn>,
    history: Vec<TrackIn>,
    events: Vec<EventIn>,
    now_ms: i64,
    half_life_minutes: i64,
    vector: Vec<f64>,
    features: Vec<(String, f64)>,
}

#[derive(Deserialize)]
struct CandidateIn {
    track: TrackIn,
    prior: f64,
    keys: Vec<String>,
    adjust: f64,
    #[serde(default)]
    coherence_bonus: f64,
}

#[derive(Deserialize)]
struct ExpectedPick {
    index: usize,
    affinity: f64,
}

#[derive(Deserialize)]
struct RankCase {
    name: String,
    candidates: Vec<CandidateIn>,
    profile: Vec<f64>,
    limit: usize,
    current: Option<TrackIn>,
    blocked_keys: Vec<String>,
    recent_keys: Vec<String>,
    skipped_artists: Vec<String>,
    queue_tail_artists: Vec<String>,
    lambda: f64,
    artist_cooldown: bool,
    heard_keys: Vec<String>,
    heard_share: Option<f64>,
    expected: Vec<ExpectedPick>,
}

fn golden() -> Golden {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/golden.json");
    serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap()
}

fn assert_bits_equal(label: &str, got: &[f32], want: &[f64]) {
    assert_eq!(got.len(), want.len(), "{label}: length");
    for (i, (g, w)) in got.iter().zip(want).enumerate() {
        assert_eq!(
            g.to_bits(),
            (*w as f32).to_bits(),
            "{label}[{i}]: {g} vs {w}"
        );
    }
}

fn assert_features_equal(label: &str, got: &[(String, f64)], want: &[(String, f64)]) {
    assert_eq!(got.len(), want.len(), "{label}: feature count");
    for (g, w) in got.iter().zip(want) {
        assert_eq!(g.0, w.0, "{label}: key order");
        assert_eq!(g.1.to_bits(), w.1.to_bits(), "{label}: weight of {}", g.0);
    }
}

#[test]
fn artists_features_and_embeddings_match_dart() {
    let golden = golden();
    assert!(golden.embeddings.len() >= 60);
    for case in &golden.embeddings {
        let label = format!("{:?} / {:?}", case.track.artist, case.track.title);
        let track: DjTrack = case.track.clone().into();
        assert_eq!(dj_artists(&track.artist), case.artists, "{label}: artists");
        assert_features_equal(&label, &track_features(&track), &case.features);
        assert_bits_equal(&label, &embed_track(&track), &case.vector);
    }
}

#[test]
fn taste_profiles_match_dart() {
    let golden = golden();
    assert!(golden.profiles.len() >= 2);
    for (n, case) in golden.profiles.iter().enumerate() {
        let tracks =
            |list: &[TrackIn]| -> Vec<DjTrack> { list.iter().cloned().map(Into::into).collect() };
        let events: Vec<DjEventInput> = case
            .events
            .iter()
            .map(|e| DjEventInput {
                track: e.track.clone().into(),
                skip: e.skip,
                at_ms: e.at_ms,
            })
            .collect();
        let profile = build_taste_profile(
            &tracks(&case.favorites),
            &tracks(&case.playlist_tracks),
            &tracks(&case.history),
            &events,
            case.now_ms,
            case.half_life_minutes,
        );
        let label = format!("profile {n}");
        assert_bits_equal(&label, &profile.vector, &case.vector);
        assert_features_equal(&label, &profile.features, &case.features);
    }
}

#[test]
fn rankings_match_dart() {
    let golden = golden();
    assert!(golden.ranks.len() >= 5);
    for case in golden.ranks {
        let request = RankRequest {
            candidates: case
                .candidates
                .into_iter()
                .map(|c| RankCandidate {
                    track: c.track.into(),
                    prior: c.prior,
                    keys: c.keys,
                    adjust: c.adjust,
                    coherence_bonus: c.coherence_bonus,
                })
                .collect(),
            profile: case.profile,
            limit: case.limit,
            current: case.current.map(Into::into),
            blocked_keys: case.blocked_keys,
            recent_keys: case.recent_keys,
            skipped_artists: case.skipped_artists,
            queue_tail_artists: case.queue_tail_artists,
            lambda: case.lambda,
            artist_cooldown: case.artist_cooldown,
            heard_keys: case.heard_keys,
            heard_share: case.heard_share,
        };
        let picks = rank_candidates(&request);
        let got: Vec<usize> = picks.iter().map(|p| p.index).collect();
        let want: Vec<usize> = case.expected.iter().map(|p| p.index).collect();
        assert_eq!(got, want, "{}: pick order", case.name);
        for (pick, expected) in picks.iter().zip(&case.expected) {
            assert!(
                (pick.affinity - expected.affinity).abs() < 1e-12,
                "{}: affinity {} vs {}",
                case.name,
                pick.affinity,
                expected.affinity
            );
        }
    }
}
