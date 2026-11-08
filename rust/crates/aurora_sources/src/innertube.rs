//! Analizadores de respuestas de InnerTube (YouTube Music). Port de los
//! `static parse*` de `lib/sources/innertube_source.dart` (v1.5.2): mismo
//! recorrido en profundidad por el orden del documento, mismas deduplicaciones
//! y mismos puntos donde Dart lanza por un tipo inesperado.

use std::collections::HashSet;
use std::sync::LazyLock;

use regex::Regex;
use serde_json::{Map, Value};

use crate::dart::{
    as_list, as_map, as_num, as_str, dart_string, lower, must_map, nn, path, trim,
    uri_scheme_userinfo, ParseError, R,
};

static VIDEO_ID: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Za-z0-9_-]{11}$").unwrap());
static CLOCK: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?:([0-9]+):)?([0-9]{1,2}):([0-9]{2})$").unwrap());
static YEAR: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^(?:19|20)[0-9]{2}$").unwrap());
static THUMB_SIZE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"=w[0-9]+-h[0-9]+").unwrap());

const PAGE_TYPE: [&str; 3] = [
    "browseEndpointContextSupportedConfigs",
    "browseEndpointContextMusicConfig",
    "pageType",
];
const ALBUM: &str = "MUSIC_PAGE_TYPE_ALBUM";
const ARTIST: &str = "MUSIC_PAGE_TYPE_ARTIST";
const USER_CHANNEL: &str = "MUSIC_PAGE_TYPE_USER_CHANNEL";
const FALLBACK_ARTIST: &str = "YouTube Music";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Track {
    pub id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub duration_ms: i64,
    pub artwork_url: Option<String>,
    pub page_url: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchKind {
    Songs,
    Videos,
    Albums,
    Artists,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SearchEntry {
    pub browse_id: String,
    pub title: String,
    pub subtitle: String,
    pub artwork_url: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SearchPage {
    pub tracks: Vec<Track>,
    pub entries: Vec<SearchEntry>,
    pub continuation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ArtistRelease {
    pub id: String,
    pub title: String,
    pub kind: String,
    pub year: Option<i32>,
    pub artwork_url: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ArtistPage {
    pub name: Option<String>,
    pub image_url: Option<String>,
    pub releases: Vec<ArtistRelease>,
    pub related_artists: Vec<String>,
}

pub fn is_valid_video_id(id: &str) -> bool {
    VIDEO_ID.is_match(id)
}

fn clock_of(text: &str) -> R<Option<i64>> {
    let Some(c) = CLOCK.captures(trim(text)) else {
        return Ok(None);
    };
    let part = |i: usize| -> R<i64> {
        match c.get(i) {
            None => Ok(0),
            Some(m) => m
                .as_str()
                .parse::<i64>()
                .map_err(|_| ParseError("reloj fuera de rango".into())),
        }
    };
    let (h, m, s) = (part(1)?, part(2)?, part(3)?);
    let total = h
        .checked_mul(3600)
        .and_then(|v| v.checked_add(m * 60 + s))
        .and_then(|v| v.checked_mul(1000))
        .ok_or_else(|| ParseError("reloj fuera de rango".into()))?;
    Ok(Some(total))
}

fn artwork(thumbnail: Option<&Value>) -> R<Option<String>> {
    let inner = as_map(path(thumbnail, &["musicThumbnailRenderer", "thumbnail"])?)?;
    let list = match inner {
        Some(m) => as_list(m.get("thumbnails"))?,
        None => None,
    };
    let mut best: Option<&Map<String, Value>> = None;
    for image in list.into_iter().flatten() {
        let Value::Object(image) = image else {
            continue;
        };
        let url = as_str(image.get("url"))?.unwrap_or("");
        match uri_scheme_userinfo(url) {
            Some((scheme, false)) if scheme == "https" => {}
            _ => continue,
        }
        let better = match best {
            None => true,
            Some(b) => {
                as_num(image.get("width"))?.unwrap_or(0.0) > as_num(b.get("width"))?.unwrap_or(0.0)
            }
        };
        if better {
            best = Some(image);
        }
    }
    let url = match best {
        Some(b) => as_str(b.get("url"))?,
        None => None,
    };
    Ok(url.map(|u| THUMB_SIZE.replace(u, "=w544-h544").into_owned()))
}

fn rows(root: &Value) -> Vec<&Map<String, Value>> {
    fn walk<'a>(node: &'a Value, out: &mut Vec<&'a Map<String, Value>>) {
        match node {
            Value::Object(m) => {
                if let Some(Value::Object(row)) = m.get("musicResponsiveListItemRenderer") {
                    out.push(row);
                    return;
                }
                for v in m.values() {
                    walk(v, out);
                }
            }
            Value::Array(a) => {
                for v in a {
                    walk(v, out);
                }
            }
            _ => {}
        }
    }
    let mut out = Vec::new();
    walk(root, &mut out);
    out
}

/// Columnas de texto (`runs`) de una fila `musicResponsiveListItemRenderer`.
fn columns(row: &Map<String, Value>) -> R<Vec<Vec<&Value>>> {
    let mut out = Vec::new();
    for column in as_list(row.get("flexColumns"))?.into_iter().flatten() {
        let renderer = match nn(Some(column)) {
            None => None,
            Some(c) => as_map(nn(
                must_map(c)?.get("musicResponsiveListItemFlexColumnRenderer")
            ))?,
        };
        let runs = match renderer {
            None => None,
            Some(r) => as_list(path(r.get("text"), &["runs"])?)?,
        };
        out.push(runs.map(|r| r.iter().collect()).unwrap_or_default());
    }
    Ok(out)
}

fn row_to_track(
    row: &Map<String, Value>,
    fb_artist: Option<&str>,
    fb_album: Option<&str>,
    fb_art: Option<&str>,
) -> R<Option<Track>> {
    let cols = columns(row)?;
    if cols.is_empty() || cols[0].is_empty() {
        return Ok(None);
    }
    let title_run = must_map(cols[0][0])?;
    let id = match as_str(path(row.get("playlistItemData"), &["videoId"])?)? {
        Some(id) => Some(id),
        None => as_str(path(
            title_run.get("navigationEndpoint"),
            &["watchEndpoint", "videoId"],
        )?)?,
    };
    let title = as_str(title_run.get("text"))?;
    let (Some(id), Some(title)) = (id, title) else {
        return Ok(None);
    };
    if !VIDEO_ID.is_match(id) {
        return Ok(None);
    }
    let mut artists: Vec<String> = Vec::new();
    let mut album: Option<String> = None;
    let mut duration: Option<i64> = None;
    let details: &[&Value] = if cols.len() > 1 { &cols[1] } else { &[] };
    for run in details {
        let Value::Object(run) = run else { continue };
        let text = trim(as_str(run.get("text"))?.unwrap_or("")).to_string();
        let mut page_path = vec!["browseEndpoint"];
        page_path.extend(PAGE_TYPE);
        let page = path(run.get("navigationEndpoint"), &page_path)?;
        let page = page.and_then(Value::as_str);
        if page == Some(ALBUM) {
            album = Some(text);
        } else if page == Some(ARTIST) || page == Some(USER_CHANNEL) {
            artists.push(text);
        } else if duration.is_none() {
            duration = clock_of(&text)?;
        }
    }
    if artists.is_empty() {
        if let Some(fb) = fb_artist {
            artists.push(fb.to_string());
        }
    }
    if artists.is_empty() && !details.is_empty() {
        let first = trim(as_str(must_map(details[0])?.get("text"))?.unwrap_or("")).to_string();
        if !first.is_empty() && clock_of(&first)?.is_none() {
            artists.push(first);
        }
    }
    let fixed_first = match as_list(row.get("fixedColumns"))?.and_then(|l| l.first()) {
        None => None,
        Some(v) => as_map(Some(v))?,
    };
    let fixed = match fixed_first {
        None => None,
        Some(m) => {
            let renderer = as_map(m.get("musicResponsiveListItemFixedColumnRenderer"))?;
            match renderer {
                None => None,
                Some(r) => as_list(path(r.get("text"), &["runs"])?)?,
            }
        }
    };
    if duration.is_none() {
        let fixed_text = match fixed.and_then(|l| l.first()) {
            None => None,
            Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("text")))?,
        };
        duration = clock_of(fixed_text.unwrap_or(""))?;
    }
    let art = artwork(row.get("thumbnail"))?.or_else(|| fb_art.map(str::to_string));
    Ok(Some(Track {
        id: format!("yt:{id}"),
        title: title.to_string(),
        artist: if artists.is_empty() {
            FALLBACK_ARTIST.to_string()
        } else {
            artists.join(", ")
        },
        album: album.or_else(|| fb_album.map(str::to_string)),
        duration_ms: duration.unwrap_or(0),
        artwork_url: art,
        page_url: format!("https://music.youtube.com/watch?v={id}"),
    }))
}

/// Filas de pista de una búsqueda, página de álbum o estante de canciones. La
/// cabecera de la página aporta artista/álbum/portada por defecto.
pub fn parse_browse_tracks(
    data: &Value,
    artist: Option<&str>,
    album: Option<&str>,
    artwork_url: Option<&str>,
) -> R<Vec<Track>> {
    let mut seen = HashSet::new();
    let mut tracks = Vec::new();
    for row in rows(data) {
        if let Some(track) = row_to_track(row, artist, album, artwork_url)? {
            if seen.insert(track.id.clone()) {
                tracks.push(track);
            }
        }
    }
    Ok(tracks)
}

pub fn parse_search(data: &Value) -> R<Vec<Track>> {
    parse_browse_tracks(data, None, None, None)
}

fn find_continuation(node: &Value, token: &mut Option<String>) -> R<()> {
    if token.is_some() {
        return Ok(());
    }
    match node {
        Value::Object(m) => {
            let direct = as_str(path(Some(node), &["nextContinuationData", "continuation"])?)?;
            *token = match direct {
                Some(t) => Some(t.to_string()),
                None => as_str(path(
                    Some(node),
                    &[
                        "continuationItemRenderer",
                        "continuationEndpoint",
                        "continuationCommand",
                        "token",
                    ],
                )?)?
                .map(str::to_string),
            };
            for v in m.values() {
                find_continuation(v, token)?;
            }
        }
        Value::Array(a) => {
            for v in a {
                find_continuation(v, token)?;
            }
        }
        _ => {}
    }
    Ok(())
}

pub fn parse_search_page(data: &Value, kind: SearchKind) -> R<SearchPage> {
    let mut token = None;
    find_continuation(data, &mut token)?;
    if matches!(kind, SearchKind::Songs | SearchKind::Videos) {
        return Ok(SearchPage {
            tracks: parse_search(data)?,
            entries: Vec::new(),
            continuation: token,
        });
    }
    let wanted = if kind == SearchKind::Albums {
        ALBUM
    } else {
        ARTIST
    };
    let mut seen = HashSet::new();
    let mut entries = Vec::new();
    for row in rows(data) {
        let browse = as_map(path(row.get("navigationEndpoint"), &["browseEndpoint"])?)?;
        let id = match browse {
            Some(b) => as_str(b.get("browseId"))?,
            None => None,
        };
        let page = match browse {
            Some(b) => path(
                b.get("browseEndpointContextSupportedConfigs"),
                &PAGE_TYPE[1..],
            )?,
            None => None,
        };
        let cols = columns(row)?;
        let Some(id) = id else { continue };
        if page.and_then(Value::as_str) != Some(wanted)
            || cols.is_empty()
            || cols[0].is_empty()
            || !seen.insert(id.to_string())
        {
            continue;
        }
        let title = as_str(must_map(cols[0][0])?.get("text"))?
            .unwrap_or("")
            .to_string();
        let subtitle = if cols.len() > 1 {
            let mut out = String::new();
            for run in &cols[1] {
                let text = must_map(run)?.get("text");
                out.push_str(&match nn(text) {
                    Some(v) => dart_string(v),
                    None => String::new(),
                });
            }
            out
        } else {
            String::new()
        };
        entries.push(SearchEntry {
            browse_id: id.to_string(),
            title,
            subtitle,
            artwork_url: artwork(row.get("thumbnail"))?,
        });
    }
    Ok(SearchPage {
        tracks: Vec::new(),
        entries,
        continuation: token,
    })
}

pub fn parse_related(data: &Value) -> R<Vec<Track>> {
    fn walk(node: &Value, seen: &mut HashSet<String>, tracks: &mut Vec<Track>) -> R<()> {
        match node {
            Value::Object(m) => {
                if let Some(Value::Object(row)) = m.get("playlistPanelVideoRenderer") {
                    let id = nn(row.get("videoId"));
                    let first_run = |key: &str| -> R<Option<&Value>> {
                        Ok(as_list(path(row.get(key), &["runs"])?)?.and_then(|l| l.first()))
                    };
                    let title = first_run("title")?;
                    let artist = first_run("longBylineText")?;
                    let length = match first_run("lengthText")? {
                        None => None,
                        Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("text")))?,
                    };
                    let thumbs = as_list(path(row.get("thumbnail"), &["thumbnails"])?)?;
                    let art = match thumbs.and_then(|l| l.last()) {
                        None => None,
                        Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("url")))?,
                    };
                    let title_text = match title {
                        None => None,
                        Some(v) => nn(as_map(Some(v))?.and_then(|m| m.get("text"))),
                    };
                    if let (Some(Value::String(id)), Some(Value::String(title_text))) =
                        (id, title_text)
                    {
                        if VIDEO_ID.is_match(id)
                            && !trim(title_text).is_empty()
                            && seen.insert(id.clone())
                        {
                            let artist_text = match artist {
                                None => None,
                                Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("text")))?,
                            };
                            let artwork_url = match uri_scheme_userinfo(art.unwrap_or("")) {
                                Some((scheme, _)) if scheme == "https" => art.map(str::to_string),
                                _ => None,
                            };
                            tracks.push(Track {
                                id: format!("yt:{id}"),
                                title: title_text.clone(),
                                artist: artist_text.unwrap_or(FALLBACK_ARTIST).to_string(),
                                album: None,
                                duration_ms: match length {
                                    None => 0,
                                    Some(l) => clock_of(l)?.unwrap_or(0),
                                },
                                artwork_url,
                                page_url: format!("https://music.youtube.com/watch?v={id}"),
                            });
                        }
                    }
                    return Ok(());
                }
                for v in m.values() {
                    walk(v, seen, tracks)?;
                }
            }
            Value::Array(a) => {
                for v in a {
                    walk(v, seen, tracks)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
    let mut seen = HashSet::new();
    let mut tracks = Vec::new();
    walk(data, &mut seen, &mut tracks)?;
    Ok(tracks)
}

pub fn parse_artist_page(data: &Value) -> R<ArtistPage> {
    let header = as_map(data.get("header"))?;
    let head_value = header.and_then(|h| {
        [
            "musicImmersiveHeaderRenderer",
            "musicVisualHeaderRenderer",
            "musicHeaderRenderer",
        ]
        .iter()
        .find_map(|k| nn(h.get(*k)))
    });
    let head = as_map(head_value)?;
    let name = match as_list(path(head.and_then(|h| h.get("title")), &["runs"])?)?
        .and_then(|l| l.first())
    {
        None => None,
        Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("text")))?.map(str::to_string),
    };

    struct State {
        seen: HashSet<String>,
        releases: Vec<ArtistRelease>,
        related: Vec<String>,
        related_keys: HashSet<String>,
    }
    fn walk(node: &Value, st: &mut State) -> R<()> {
        match node {
            Value::Object(m) => {
                if let Some(Value::Object(row)) = m.get("musicTwoRowItemRenderer") {
                    let browse = as_map(path(row.get("navigationEndpoint"), &["browseEndpoint"])?)?;
                    let id = match browse {
                        Some(b) => as_str(b.get("browseId"))?,
                        None => None,
                    };
                    let page = match browse {
                        Some(b) => path(
                            b.get("browseEndpointContextSupportedConfigs"),
                            &PAGE_TYPE[1..],
                        )?,
                        None => None,
                    };
                    let page = page.and_then(Value::as_str);
                    let title = match as_list(path(row.get("title"), &["runs"])?)?
                        .and_then(|l| l.first())
                    {
                        None => None,
                        Some(v) => as_str(as_map(Some(v))?.and_then(|m| m.get("text")))?,
                    };
                    if let Some(title) = title {
                        if page == Some(ARTIST)
                            && !trim(title).is_empty()
                            && st.related_keys.insert(lower(trim(title)))
                        {
                            st.related.push(trim(title).to_string());
                        }
                    }
                    if let (Some(id), Some(title)) = (id, title) {
                        if page == Some(ALBUM)
                            && !trim(title).is_empty()
                            && st.seen.insert(id.to_string())
                        {
                            let mut parts: Vec<String> = Vec::new();
                            for r in as_list(path(row.get("subtitle"), &["runs"])?)?
                                .into_iter()
                                .flatten()
                            {
                                let text = trim(as_str(must_map(r)?.get("text"))?.unwrap_or(""))
                                    .to_string();
                                if !text.is_empty() && text != "\u{2022}" {
                                    parts.push(text);
                                }
                            }
                            let year = parts.iter().find(|t| YEAR.is_match(t)).cloned();
                            let kind = parts
                                .iter()
                                .find(|t| Some(*t) != year.as_ref())
                                .cloned()
                                .unwrap_or_default();
                            st.releases.push(ArtistRelease {
                                id: id.to_string(),
                                title: trim(title).to_string(),
                                kind,
                                year: year.and_then(|y| y.parse().ok()),
                                artwork_url: artwork(row.get("thumbnailRenderer"))?,
                            });
                        }
                    }
                    return Ok(());
                }
                for v in m.values() {
                    walk(v, st)?;
                }
            }
            Value::Array(a) => {
                for v in a {
                    walk(v, st)?;
                }
            }
            _ => {}
        }
        Ok(())
    }
    let mut st = State {
        seen: HashSet::new(),
        releases: Vec::new(),
        related: Vec::new(),
        related_keys: HashSet::new(),
    };
    if let Some(contents) = data.get("contents") {
        walk(contents, &mut st)?;
    }
    Ok(ArtistPage {
        name,
        image_url: artwork(head.and_then(|h| h.get("thumbnail")))?,
        releases: st.releases,
        related_artists: st.related,
    })
}
