//! Motor del DJ local de Aurora: vectores de pista por hashing de
//! características, perfil de gustos con decaimiento y ranking MMR.
//!
//! Port línea a línea de `lib/dj/ai_dj.dart` (v1.4.0); las pruebas de oro de
//! `tests/golden.rs` comparan bit a bit con la salida de esa versión Dart.

mod embed;
mod rank;
mod text;

pub use embed::{
    build_taste_profile, cosine, embed_track, hash_features, normalize, track_features,
    DjEventInput, DjProfile, DjTrack, VECTOR_DIMS,
};
pub use rank::{
    dj_want_heard, rank_candidates, Pick, RankCandidate, RankRequest, CONTINUITY_WEIGHT,
    PRIOR_WEIGHT, RECENT_PENALTY, SKIPPED_ARTIST_PENALTY, TASTE_WEIGHT,
};
pub use text::{dj_artists, primary_artist};
