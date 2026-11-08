//! Puente del DJ local (`aurora_ai_dj`). Funciones `sync`; ver `database.rs`.

use aurora_ai_dj as dj;
use flutter_rust_bridge::frb;

pub struct DjTrack {
    pub artist: String,
    pub title: String,
    pub album: Option<String>,
    pub genres: Vec<String>,
}

pub struct DjFeature {
    pub key: String,
    pub weight: f64,
}

pub struct DjEventInput {
    pub track: DjTrack,
    pub skip: bool,
    pub at_ms: i64,
}

pub struct DjProfile {
    pub vector: Vec<f32>,
    pub features: Vec<DjFeature>,
}

pub struct DjRankCandidate {
    pub track: DjTrack,
    pub prior: f64,
    pub keys: Vec<String>,
    pub adjust: f64,
    pub coherence_bonus: f64,
}

pub struct DjRankRequest {
    pub candidates: Vec<DjRankCandidate>,
    pub profile: Vec<f64>,
    pub limit: u32,
    pub current: Option<DjTrack>,
    pub blocked_keys: Vec<String>,
    pub recent_keys: Vec<String>,
    pub skipped_artists: Vec<String>,
    pub queue_tail_artists: Vec<String>,
    pub lambda: f64,
    pub artist_cooldown: bool,
    pub heard_keys: Vec<String>,
    pub heard_share: Option<f64>,
}

pub struct DjPick {
    /// Posición del candidato en `DjRankRequest::candidates`.
    pub index: u32,
    pub affinity: f64,
}

impl From<DjTrack> for dj::DjTrack {
    fn from(t: DjTrack) -> Self {
        Self {
            artist: t.artist,
            title: t.title,
            album: t.album,
            genres: t.genres,
        }
    }
}

fn features_out(features: Vec<(String, f64)>) -> Vec<DjFeature> {
    features
        .into_iter()
        .map(|(key, weight)| DjFeature { key, weight })
        .collect()
}

#[frb(sync)]
pub fn dj_artists(artist: String) -> Vec<String> {
    dj::dj_artists(&artist)
}

#[frb(sync)]
pub fn dj_track_features(track: DjTrack) -> Vec<DjFeature> {
    features_out(dj::track_features(&track.into()))
}

#[frb(sync)]
pub fn dj_hash_features(features: Vec<DjFeature>) -> Vec<f32> {
    let features: Vec<(String, f64)> = features.into_iter().map(|f| (f.key, f.weight)).collect();
    dj::hash_features(&features)
}

#[frb(sync)]
pub fn dj_embed_track(track: DjTrack) -> Vec<f32> {
    dj::embed_track(&track.into())
}

#[frb(sync)]
pub fn dj_build_taste_profile(
    favorites: Vec<DjTrack>,
    playlist_tracks: Vec<DjTrack>,
    history: Vec<DjTrack>,
    events: Vec<DjEventInput>,
    now_ms: i64,
    half_life_minutes: i64,
) -> DjProfile {
    let tracks =
        |list: Vec<DjTrack>| -> Vec<dj::DjTrack> { list.into_iter().map(Into::into).collect() };
    let events: Vec<dj::DjEventInput> = events
        .into_iter()
        .map(|e| dj::DjEventInput {
            track: e.track.into(),
            skip: e.skip,
            at_ms: e.at_ms,
        })
        .collect();
    let profile = dj::build_taste_profile(
        &tracks(favorites),
        &tracks(playlist_tracks),
        &tracks(history),
        &events,
        now_ms,
        half_life_minutes,
    );
    DjProfile {
        vector: profile.vector,
        features: features_out(profile.features),
    }
}

#[frb(sync)]
pub fn dj_rank_candidates(request: DjRankRequest) -> Vec<DjPick> {
    let request = dj::RankRequest {
        candidates: request
            .candidates
            .into_iter()
            .map(|c| dj::RankCandidate {
                track: c.track.into(),
                prior: c.prior,
                keys: c.keys,
                adjust: c.adjust,
                coherence_bonus: c.coherence_bonus,
            })
            .collect(),
        profile: request.profile,
        limit: request.limit as usize,
        current: request.current.map(Into::into),
        blocked_keys: request.blocked_keys,
        recent_keys: request.recent_keys,
        skipped_artists: request.skipped_artists,
        queue_tail_artists: request.queue_tail_artists,
        lambda: request.lambda,
        artist_cooldown: request.artist_cooldown,
        heard_keys: request.heard_keys,
        heard_share: request.heard_share,
    };
    dj::rank_candidates(&request)
        .into_iter()
        .map(|p| DjPick {
            index: p.index as u32,
            affinity: p.affinity,
        })
        .collect()
}
