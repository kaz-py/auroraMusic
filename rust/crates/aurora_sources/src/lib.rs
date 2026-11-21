//! Fuentes de música de Aurora. Por ahora: analizadores de las respuestas de
//! InnerTube (YouTube Music). Las partes con red y reloj (cola de solicitudes,
//! proxy local, orquestador de streams) siguen en Dart.

mod dart;
mod innertube;

pub use dart::ParseError;
pub use innertube::{
    is_valid_video_id, parse_artist_page, parse_browse_tracks, parse_related, parse_search,
    parse_search_page, ArtistPage, ArtistRelease, SearchEntry, SearchKind, SearchPage, Track,
};
