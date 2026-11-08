//! Pruebas de oro: salida de `InnerTubeSource.parse*` (Dart, v1.5.2) sobre un
//! corpus escrito a mano más 350 documentos mutados al azar (tipos cambiados,
//! claves borradas). `error: true` = Dart lanzó; Rust debe devolver `Err`.

use std::fs;
use std::path::PathBuf;

use aurora_sources::{
    parse_artist_page, parse_browse_tracks, parse_related, parse_search_page, ArtistPage,
    SearchKind, SearchPage, Track,
};
use serde::Deserialize;
use serde_json::Value;

#[derive(Deserialize)]
struct Case {
    #[serde(rename = "fn")]
    function: String,
    kind: Option<String>,
    artist: Option<String>,
    album: Option<String>,
    artwork: Option<String>,
    data: Value,
    error: bool,
    expected: Option<Value>,
}

fn cases() -> Vec<Case> {
    let path =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/innertube_golden.json");
    serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap()
}

fn track(t: &Track) -> Value {
    serde_json::json!({
        "id": t.id, "title": t.title, "artist": t.artist, "album": t.album,
        "duration_ms": t.duration_ms, "artwork_url": t.artwork_url, "page_url": t.page_url,
    })
}

fn page(p: &SearchPage) -> Value {
    serde_json::json!({
        "tracks": p.tracks.iter().map(track).collect::<Vec<_>>(),
        "entries": p.entries.iter().map(|e| serde_json::json!({
            "browse_id": e.browse_id, "title": e.title, "subtitle": e.subtitle, "artwork_url": e.artwork_url,
        })).collect::<Vec<_>>(),
        "continuation": p.continuation,
    })
}

fn artist(p: &ArtistPage) -> Value {
    serde_json::json!({
        "name": p.name, "image_url": p.image_url,
        "releases": p.releases.iter().map(|r| serde_json::json!({
            "id": r.id, "title": r.title, "kind": r.kind, "year": r.year, "artwork_url": r.artwork_url,
        })).collect::<Vec<_>>(),
        "related_artists": p.related_artists,
    })
}

#[test]
fn innertube_parsers_match_the_dart_implementation() {
    let cases = cases();
    assert!(cases.len() >= 500);
    let (mut ok, mut errors) = (0, 0);
    let mut mismatches = Vec::new();
    for (n, case) in cases.iter().enumerate() {
        let result: Result<Value, _> = match case.function.as_str() {
            "search_page" => {
                let kind = match case.kind.as_deref() {
                    Some("songs") => SearchKind::Songs,
                    Some("videos") => SearchKind::Videos,
                    Some("albums") => SearchKind::Albums,
                    Some("artists") => SearchKind::Artists,
                    other => panic!("tipo {other:?}"),
                };
                parse_search_page(&case.data, kind).map(|p| page(&p))
            }
            "related" => {
                parse_related(&case.data).map(|t| Value::Array(t.iter().map(track).collect()))
            }
            "artist" => parse_artist_page(&case.data).map(|p| artist(&p)),
            "browse" => parse_browse_tracks(
                &case.data,
                case.artist.as_deref(),
                case.album.as_deref(),
                case.artwork.as_deref(),
            )
            .map(|t| Value::Array(t.iter().map(track).collect())),
            other => panic!("función {other}"),
        };
        match (&result, case.error) {
            (Err(_), true) => errors += 1,
            (Ok(got), false) if Some(got) == case.expected.as_ref() => ok += 1,
            (Ok(got), false) => mismatches.push(format!(
                "#{n} {} salida distinta\n  rust: {got}\n  dart: {}",
                case.function,
                case.expected
                    .as_ref()
                    .map_or("null".into(), |v| v.to_string())
            )),
            (Ok(got), true) => mismatches.push(format!(
                "#{n} {} Dart lanzó y Rust devolvió {got}",
                case.function
            )),
            (Err(e), false) => mismatches.push(format!(
                "#{n} {} Rust lanzó ({e}) y Dart devolvió {:?}",
                case.function, case.expected
            )),
        }
    }
    println!(
        "{ok} iguales, {errors} errores coincidentes, {} discrepancias",
        mismatches.len()
    );
    assert!(
        mismatches.is_empty(),
        "{} discrepancias; primeras:\n{}",
        mismatches.len(),
        mismatches
            .iter()
            .take(6)
            .cloned()
            .collect::<Vec<_>>()
            .join("\n")
    );
}
