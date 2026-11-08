//! Puente de las fuentes de música (`aurora_sources`). Funciones `sync`; ver
//! `database.rs`. Las respuestas de InnerTube llegan como texto JSON: Dart ya
//! las decodificó para la red y aquí se vuelven a analizar con el orden del
//! documento intacto.

use anyhow::{anyhow, Result};
use aurora_sources as src;
use flutter_rust_bridge::frb;

pub enum SourceSearchKind {
    Songs,
    Videos,
    Albums,
    Artists,
}

pub struct SourceTrack {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_ms: i64,
    pub artwork_url: Option<String>,
    pub page_url: String,
}

pub struct SourceSearchEntry {
    pub browse_id: String,
    pub title: String,
    pub subtitle: String,
    pub artwork_url: Option<String>,
}

pub struct SourceSearchPage {
    pub tracks: Vec<SourceTrack>,
    pub entries: Vec<SourceSearchEntry>,
    pub continuation: Option<String>,
}

pub struct SourceArtistRelease {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub year: Option<i32>,
    pub artwork_url: Option<String>,
}

pub struct SourceArtistPage {
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub releases: Vec<SourceArtistRelease>,
    pub related_artists: Vec<String>,
}

fn json(text: &str) -> Result<serde_json::Value> {
    serde_json::from_str(text).map_err(|e| anyhow!("Respuesta JSON no válida: {e}"))
}

fn track(t: src::Track) -> SourceTrack {
    SourceTrack {
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration_ms: t.duration_ms,
        artwork_url: t.artwork_url,
        page_url: t.page_url,
    }
}

#[frb(sync)]
pub fn innertube_parse_search_page(
    data_json: String,
    kind: SourceSearchKind,
) -> Result<SourceSearchPage> {
    let kind = match kind {
        SourceSearchKind::Songs => src::SearchKind::Songs,
        SourceSearchKind::Videos => src::SearchKind::Videos,
        SourceSearchKind::Albums => src::SearchKind::Albums,
        SourceSearchKind::Artists => src::SearchKind::Artists,
    };
    let page = src::parse_search_page(&json(&data_json)?, kind)?;
    Ok(SourceSearchPage {
        tracks: page.tracks.into_iter().map(track).collect(),
        entries: page
            .entries
            .into_iter()
            .map(|e| SourceSearchEntry {
                browse_id: e.browse_id,
                title: e.title,
                subtitle: e.subtitle,
                artwork_url: e.artwork_url,
            })
            .collect(),
        continuation: page.continuation,
    })
}

#[frb(sync)]
pub fn innertube_parse_browse_tracks(
    data_json: String,
    artist: Option<String>,
    album: Option<String>,
    artwork: Option<String>,
) -> Result<Vec<SourceTrack>> {
    let tracks = src::parse_browse_tracks(
        &json(&data_json)?,
        artist.as_deref(),
        album.as_deref(),
        artwork.as_deref(),
    )?;
    Ok(tracks.into_iter().map(track).collect())
}

#[frb(sync)]
pub fn innertube_parse_related(data_json: String) -> Result<Vec<SourceTrack>> {
    Ok(src::parse_related(&json(&data_json)?)?
        .into_iter()
        .map(track)
        .collect())
}

#[frb(sync)]
pub fn innertube_parse_artist_page(data_json: String) -> Result<SourceArtistPage> {
    let page = src::parse_artist_page(&json(&data_json)?)?;
    Ok(SourceArtistPage {
        name: page.name,
        image_url: page.image_url,
        releases: page
            .releases
            .into_iter()
            .map(|r| SourceArtistRelease {
                id: r.id,
                title: r.title,
                kind: r.kind,
                year: r.year,
                artwork_url: r.artwork_url,
            })
            .collect(),
        related_artists: page.related_artists,
    })
}
