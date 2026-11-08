use std::fs;
use std::path::PathBuf;
use std::thread::sleep;
use std::time::{Duration, Instant};

use aurora_database::{
    DatabaseError, Library, NewsRow, PlaylistRow, SyncMetaRow, VectorEntry, SCHEMA_VERSION,
};
use rusqlite::Connection;
use serde_json::Value;
use tempfile::{tempdir, TempDir};

fn fixtures() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn memory() -> Library {
    Library::open_memory(vec![]).unwrap()
}

fn tables(conn: &Connection) -> Vec<String> {
    let mut stmt = conn
        .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
        .unwrap();
    stmt.query_map([], |row| row.get(0))
        .unwrap()
        .map(Result::unwrap)
        .collect()
}

fn user_version(conn: &Connection) -> i64 {
    conn.query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap()
}

const V1: &[&str] = &[
    "CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
    "CREATE TABLE favorites (track_id TEXT PRIMARY KEY)",
    "CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, tracks TEXT NOT NULL)",
    "CREATE TABLE history (track_id TEXT PRIMARY KEY, played_at INTEGER NOT NULL)",
    "CREATE TABLE downloads (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
    "INSERT INTO tracks VALUES ('kept', '{\"id\":\"kept\"}')",
    "INSERT INTO favorites VALUES ('kept')",
];
const V2_EXTRA: &[&str] = &[
    "CREATE TABLE track_vectors (track_key TEXT PRIMARY KEY, track TEXT NOT NULL, dims INTEGER NOT NULL, vector BLOB NOT NULL, updated_at INTEGER NOT NULL)",
    "CREATE TABLE taste_profile (id INTEGER PRIMARY KEY CHECK (id = 1), dims INTEGER NOT NULL, vector BLOB NOT NULL, updated_at INTEGER NOT NULL)",
    "INSERT INTO track_vectors VALUES ('kept', '{\"id\":\"kept\"}', 2, x'0000803f00000000', 1)",
];
const V3_EXTRA: &[&str] = &[
    "CREATE TABLE followed_artists (browse_id TEXT PRIMARY KEY, name TEXT NOT NULL, image_url TEXT, followed_at INTEGER NOT NULL, last_release_id TEXT, last_release_title TEXT, known_releases TEXT NOT NULL DEFAULT '[]', checked_at INTEGER)",
    "CREATE TABLE new_releases (release_id TEXT PRIMARY KEY, artist_id TEXT NOT NULL, artist_name TEXT NOT NULL, title TEXT NOT NULL, subtitle TEXT NOT NULL, artwork_url TEXT, detected_at INTEGER NOT NULL)",
    "INSERT INTO followed_artists (browse_id,name,followed_at) VALUES ('UC1','Kept',5)",
];

fn legacy(version: i64) -> (TempDir, PathBuf) {
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    let conn = Connection::open(&path).unwrap();
    let mut statements: Vec<&str> = V1.to_vec();
    if version >= 2 {
        statements.extend_from_slice(V2_EXTRA);
    }
    if version >= 3 {
        statements.extend_from_slice(V3_EXTRA);
    }
    for statement in statements {
        conn.execute_batch(statement).unwrap();
    }
    conn.execute_batch(&format!("PRAGMA user_version = {version}"))
        .unwrap();
    (dir, path)
}

const ALL_TABLES: [&str; 10] = [
    "downloads",
    "favorites",
    "followed_artists",
    "history",
    "new_releases",
    "playlists",
    "sync_meta",
    "taste_profile",
    "track_vectors",
    "tracks",
];

#[test]
fn drift_written_database_opens_and_reads_back_every_value() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    fs::copy(fixtures().join("drift_v4.sqlite"), &path).unwrap();
    let expected: Value = serde_json::from_str(
        &fs::read_to_string(fixtures().join("drift_v4.expected.json")).unwrap(),
    )
    .unwrap();
    let lib = Library::open(&path).unwrap();

    let strings = |key: &str| -> Vec<String> {
        expected[key]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_str().unwrap().to_string())
            .collect()
    };

    assert_eq!(lib.read_tracks().unwrap(), strings("tracks"));
    let mut favorites = lib.read_favorites().unwrap();
    favorites.sort();
    assert_eq!(favorites, strings("favorites"));

    let playlists = lib.read_playlists().unwrap();
    let want = expected["playlists"].as_array().unwrap();
    assert_eq!(playlists.len(), want.len());
    for (got, want) in playlists.iter().zip(want) {
        assert_eq!(got.id, want["id"].as_str().unwrap());
        assert_eq!(got.name, want["name"].as_str().unwrap());
        assert_eq!(got.tracks_json, want["tracks_json"].as_str().unwrap());
    }

    assert_eq!(lib.read_history().unwrap(), strings("history_ids"));
    for row in expected["history_rows"].as_array().unwrap() {
        assert_eq!(
            lib.history_played_at(row["track_id"].as_str().unwrap())
                .unwrap(),
            Some(row["played_at"].as_i64().unwrap())
        );
    }

    let downloads = lib.read_downloads().unwrap();
    let want = expected["downloads"].as_array().unwrap();
    assert_eq!(downloads.len(), want.len());
    for (got, want) in downloads.iter().zip(want) {
        assert_eq!(got.id, want["id"].as_str().unwrap());
        assert_eq!(got.data, want["data"].as_str().unwrap());
    }

    assert_eq!(
        lib.count_track_vectors().unwrap(),
        expected["vector_count"].as_i64().unwrap()
    );
    let taste_row = lib.taste_row().unwrap().unwrap();
    assert_eq!(taste_row.dims, expected["taste_dims"].as_i64().unwrap());
    let taste = lib.read_taste_profile().unwrap().unwrap();
    let want: Vec<f32> = expected["taste_vector"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_f64().unwrap() as f32)
        .collect();
    assert_eq!(taste.len(), want.len());
    assert!(taste
        .iter()
        .zip(&want)
        .all(|(a, b)| a.to_bits() == b.to_bits()));

    let followed = lib.follow_list().unwrap();
    let want = expected["followed"].as_array().unwrap();
    assert_eq!(followed.len(), want.len());
    for (got, want) in followed.iter().zip(want) {
        assert_eq!(got.browse_id, want["browse_id"].as_str().unwrap());
        assert_eq!(got.name, want["name"].as_str().unwrap());
        assert_eq!(got.image_url.as_deref(), want["image_url"].as_str());
        assert_eq!(got.followed_at, want["followed_at"].as_i64().unwrap());
        assert_eq!(
            got.last_release_id.as_deref(),
            want["last_release_id"].as_str()
        );
        assert_eq!(
            got.last_release_title.as_deref(),
            want["last_release_title"].as_str()
        );
        assert_eq!(got.known_releases, want["known_releases"].as_str().unwrap());
        assert_eq!(got.checked_at, want["checked_at"].as_i64());
    }

    let news = lib.news_list().unwrap();
    let want = expected["news"].as_array().unwrap();
    assert_eq!(news.len(), want.len());
    for (got, want) in news.iter().zip(want) {
        assert_eq!(got.release_id, want["release_id"].as_str().unwrap());
        assert_eq!(got.artist_id, want["artist_id"].as_str().unwrap());
        assert_eq!(got.artist_name, want["artist_name"].as_str().unwrap());
        assert_eq!(got.title, want["title"].as_str().unwrap());
        assert_eq!(got.subtitle, want["subtitle"].as_str().unwrap());
        assert_eq!(got.artwork_url.as_deref(), want["artwork_url"].as_str());
        assert_eq!(got.detected_at, want["detected_at"].as_i64().unwrap());
    }

    let mut sync: Vec<(String, SyncMetaRow)> = Vec::new();
    for kind in ["favorites", "history", "playlists", "taste"] {
        for row in lib.read_sync_meta(kind).unwrap() {
            sync.push((kind.to_string(), row));
        }
    }
    sync.sort_by(|a, b| (&a.0, &a.1.key).cmp(&(&b.0, &b.1.key)));
    let want = expected["sync_meta"].as_array().unwrap();
    assert_eq!(sync.len(), want.len());
    for ((kind, got), want) in sync.iter().zip(want) {
        assert_eq!(kind, want["kind"].as_str().unwrap());
        assert_eq!(got.key, want["key"].as_str().unwrap());
        assert_eq!(got.updated_at, want["updated_at"].as_i64().unwrap());
        assert_eq!(got.deleted, want["deleted"].as_i64().unwrap() == 1);
        assert_eq!(got.dirty, want["dirty"].as_i64().unwrap() == 1);
    }
    // el favorito 'yt:bbb' se desmarcó: lápida pendiente
    assert!(sync
        .iter()
        .any(|(k, r)| k == "favorites" && r.key == "yt:bbb" && r.deleted && r.dirty));

    drop(lib);
    let side = Connection::open(&path).unwrap();
    assert_eq!(
        user_version(&side),
        expected["user_version"].as_i64().unwrap()
    );
    assert_eq!(user_version(&side), SCHEMA_VERSION);
}

#[test]
fn fresh_database_gets_every_table_and_schema_version() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    drop(Library::open(&path).unwrap());
    let conn = Connection::open(&path).unwrap();
    assert_eq!(tables(&conn), ALL_TABLES);
    assert_eq!(user_version(&conn), 4);
    // reabrir no repite la creación
    drop(Library::open(&path).unwrap());
}

#[test]
fn legacy_schemas_migrate_keeping_rows() {
    for version in 1..=3 {
        let (_dir, path) = legacy(version);
        let lib = Library::open(&path).unwrap();
        assert_eq!(
            lib.read_tracks().unwrap(),
            ["{\"id\":\"kept\"}"],
            "v{version}"
        );
        assert_eq!(lib.read_favorites().unwrap(), ["kept"], "v{version}");
        if version >= 2 {
            assert_eq!(lib.count_track_vectors().unwrap(), 1, "v{version}");
        }
        if version >= 3 {
            assert_eq!(lib.follow_list().unwrap()[0].name, "Kept", "v{version}");
        }
        // las tablas nuevas ya funcionan
        lib.upsert_track_vectors(vec![VectorEntry {
            track_key: "new".into(),
            track_json: "{}".into(),
            vector: vec![1.0, 0.0],
        }])
        .unwrap();
        lib.follow_add("UC9", "Nueva", None, 1).unwrap();
        lib.set_favorite("kept", false, true).unwrap();
        drop(lib);
        let conn = Connection::open(&path).unwrap();
        assert_eq!(tables(&conn), ALL_TABLES, "v{version}");
        assert_eq!(user_version(&conn), 4, "v{version}");
    }
}

#[test]
fn newer_schema_is_rejected() {
    let error = Library::open_memory(vec!["PRAGMA user_version = 5".into()])
        .err()
        .expect("must fail");
    assert!(matches!(error, DatabaseError::TooNew(5)));
    assert_eq!(
        error.to_string(),
        "La base de datos es de una versión más nueva (5) que esta aplicación."
    );
}

#[test]
fn vector_store_keeps_the_newest_5000() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    let lib = Library::open(&path).unwrap();
    let entry = |key: String| VectorEntry {
        track_key: key,
        track_json: "{}".into(),
        vector: vec![1.0, 2.0],
    };
    lib.upsert_track_vectors((0..3).map(|i| entry(format!("old{i}"))).collect())
        .unwrap();
    sleep(Duration::from_millis(5));
    lib.upsert_track_vectors((0..5000).map(|i| entry(format!("new{i}"))).collect())
        .unwrap();
    assert_eq!(lib.count_track_vectors().unwrap(), 5000);
    let conn = Connection::open(&path).unwrap();
    let old: i64 = conn
        .query_row(
            "SELECT COUNT(*) FROM track_vectors WHERE track_key LIKE 'old%'",
            [],
            |row| row.get(0),
        )
        .unwrap();
    assert_eq!(old, 0);
}

fn vector(key: &str, values: &[f32]) -> VectorEntry {
    VectorEntry {
        track_key: key.into(),
        track_json: format!("{{\"id\":\"{key}\"}}"),
        vector: values.to_vec(),
    }
}

#[test]
fn nearest_tracks_orders_by_cosine_and_honours_exclusions() {
    let lib = memory();
    lib.upsert_track_vectors(vec![
        vector("east", &[1.0, 0.0, 0.0]),
        vector("north-east", &[1.0, 1.0, 0.0]),
        vector("up", &[0.0, 0.0, 1.0]),
        vector("other-dims", &[1.0, 0.0]),
        vector("zero", &[0.0, 0.0, 0.0]),
    ])
    .unwrap();
    let ids = |rows: Vec<aurora_database::NearestRow>| -> Vec<String> {
        rows.into_iter().map(|r| r.track_json).collect()
    };
    let nearest = lib.nearest_tracks(&[1.0, 0.1, 0.0], 2, &[]).unwrap();
    assert_eq!(
        ids(nearest.clone()),
        ["{\"id\":\"east\"}", "{\"id\":\"north-east\"}"]
    );
    let expected = (1.0 * 1.0 + 0.1 * 0.0) / ((1.0f64 + 0.01) * 1.0).sqrt();
    assert!((nearest[0].score - expected).abs() < 1e-12);

    let excluded = lib
        .nearest_tracks(&[1.0, 0.1, 0.0], 2, &["east".to_string()])
        .unwrap();
    assert_eq!(
        ids(excluded),
        ["{\"id\":\"north-east\"}", "{\"id\":\"up\"}"]
    );
    assert!(lib
        .nearest_tracks(&[0.0, 0.0, 0.0], 5, &[])
        .unwrap()
        .is_empty());

    lib.upsert_track_vectors(vec![vector("east", &[0.0, 0.0, 1.0])])
        .unwrap();
    assert_eq!(lib.count_track_vectors().unwrap(), 5);
    let top = lib.nearest_tracks(&[0.0, 0.0, 1.0], 1, &[]).unwrap();
    assert!((top[0].score - 1.0).abs() < 1e-6);
}

#[test]
fn nearest_tracks_skips_blobs_with_the_wrong_length() {
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    let lib = Library::open(&path).unwrap();
    lib.upsert_track_vectors(vec![vector("good", &[1.0, 0.0])])
        .unwrap();
    Connection::open(&path)
        .unwrap()
        .execute(
            "INSERT INTO track_vectors VALUES ('bad', '{}', 2, x'0000803f', 1)",
            [],
        )
        .unwrap();
    let rows = lib.nearest_tracks(&[1.0, 0.0], 5, &[]).unwrap();
    assert_eq!(rows.len(), 1);
}

#[test]
fn taste_profile_round_trips_and_marks_on_request() {
    let lib = memory();
    assert_eq!(lib.read_taste_profile().unwrap(), None);
    let bytes: Vec<u8> = [0.5f32, 0.25]
        .iter()
        .flat_map(|v| v.to_le_bytes())
        .collect();
    lib.save_taste(2, &bytes, true).unwrap();
    assert_eq!(lib.read_taste_profile().unwrap(), Some(vec![0.5, 0.25]));
    let meta = lib.read_sync_meta("taste").unwrap();
    assert_eq!(meta.len(), 1);
    assert!(meta[0].dirty && !meta[0].deleted && meta[0].key == "1");
    let quiet = memory();
    quiet.save_taste(2, &bytes, false).unwrap();
    assert!(quiet.read_sync_meta("taste").unwrap().is_empty());
}

#[test]
fn marking_writes_a_dirty_sync_row_only_when_asked() {
    let lib = memory();
    lib.set_favorite("a", true, true).unwrap();
    let meta = lib.read_sync_meta("favorites").unwrap();
    assert_eq!(meta.len(), 1);
    assert!(meta[0].dirty && !meta[0].deleted);
    lib.set_favorite("a", false, true).unwrap();
    let meta = lib.read_sync_meta("favorites").unwrap();
    assert!(meta[0].dirty && meta[0].deleted);
    assert!(lib.read_favorites().unwrap().is_empty());

    lib.set_favorite("quiet", true, false).unwrap();
    assert!(lib
        .read_sync_meta("favorites")
        .unwrap()
        .iter()
        .all(|r| r.key != "quiet"));
    assert_eq!(lib.read_favorites().unwrap(), ["quiet"]);

    lib.save_playlist("p", "Nombre", "[]", true).unwrap();
    lib.record_play("t", Some(42), true).unwrap();
    assert_eq!(lib.read_sync_meta("playlists").unwrap().len(), 1);
    assert_eq!(lib.read_sync_meta("history").unwrap().len(), 1);
    assert_eq!(lib.history_played_at("t").unwrap(), Some(42));
    lib.delete_playlist("p", true).unwrap();
    assert!(lib.read_sync_meta("playlists").unwrap()[0].deleted);
    assert!(lib.playlist_row("p").unwrap().is_none());
}

#[test]
fn sync_metadata_primitives() {
    let lib = memory();
    lib.set_favorite("a", true, false).unwrap();
    lib.save_playlist("p", "P", "[]", false).unwrap();
    lib.record_play("h", Some(7), false).unwrap();
    lib.seed_sync_meta().unwrap();
    for kind in ["favorites", "playlists", "history"] {
        let rows = lib.read_sync_meta(kind).unwrap();
        assert_eq!(rows.len(), 1, "{kind}");
        assert_eq!(
            (rows[0].updated_at, rows[0].deleted, rows[0].dirty),
            (0, false, true)
        );
    }
    lib.set_sync_meta("favorites", "a", 100, false).unwrap();
    assert!(lib.dirty_sync_keys("favorites").unwrap().is_empty());
    lib.mark_all_sync_dirty().unwrap();
    assert_eq!(lib.dirty_sync_keys("favorites").unwrap(), ["a"]);
    // otro cambio mientras se subía: no se limpia
    lib.clear_sync_dirty("favorites", "a", 99, 150).unwrap();
    assert_eq!(lib.dirty_sync_keys("favorites").unwrap(), ["a"]);
    lib.clear_sync_dirty("favorites", "a", 100, 150).unwrap();
    let row = &lib.read_sync_meta("favorites").unwrap()[0];
    assert_eq!((row.updated_at, row.dirty), (150, false));
}

#[test]
fn history_is_newest_first_and_capped() {
    let lib = memory();
    for i in 0..120 {
        lib.record_play(&format!("t{i}"), Some(1000 + i), false)
            .unwrap();
    }
    let history = lib.read_history().unwrap();
    assert_eq!(history.len(), 100);
    assert_eq!(history[0], "t119");
    lib.record_play("t0", Some(5000), false).unwrap();
    assert_eq!(lib.read_history().unwrap()[0], "t0");
}

#[test]
fn follow_remove_deletes_only_that_artists_news() {
    let lib = memory();
    lib.follow_add("UC1", "Uno", Some("https://img"), 10)
        .unwrap();
    lib.follow_add("UC2", "Dos", None, 20).unwrap();
    lib.follow_add("UC1", "Otro nombre", None, 99).unwrap(); // idempotente
    let followed = lib.follow_list().unwrap();
    assert_eq!(
        followed
            .iter()
            .map(|f| f.browse_id.as_str())
            .collect::<Vec<_>>(),
        ["UC2", "UC1"]
    );
    assert_eq!(followed[1].name, "Uno");
    assert_eq!(followed[1].known_releases, "[]");
    let news = |release: &str, artist: &str, at: i64| NewsRow {
        release_id: release.into(),
        artist_id: artist.into(),
        artist_name: artist.into(),
        title: "t".into(),
        subtitle: "s".into(),
        artwork_url: None,
        detected_at: at,
    };
    lib.news_add(&[
        news("r1", "UC1", 1),
        news("r2", "UC2", 2),
        news("r1", "UC1", 3),
    ])
    .unwrap();
    assert_eq!(lib.news_list().unwrap().len(), 2);
    lib.follow_save_check("UC2", Some("r2"), Some("T"), "[\"r2\"]", Some(500))
        .unwrap();
    let uc2 = &lib.follow_list().unwrap()[0];
    assert_eq!(uc2.last_release_id.as_deref(), Some("r2"));
    assert_eq!(uc2.checked_at, Some(500));

    lib.follow_remove("UC1").unwrap();
    let remaining = lib.news_list().unwrap();
    assert_eq!(remaining.len(), 1);
    assert_eq!(remaining[0].artist_id, "UC2");
    assert_eq!(lib.follow_list().unwrap().len(), 1);

    lib.news_add(&[news("r3", "UC2", 10)]).unwrap();
    lib.news_prune(5).unwrap();
    assert_eq!(lib.news_list().unwrap().len(), 1);
    lib.news_dismiss(Some("r3")).unwrap();
    assert!(lib.news_list().unwrap().is_empty());
    lib.news_add(&[news("r4", "UC2", 10), news("r5", "UC2", 11)])
        .unwrap();
    lib.news_dismiss(None).unwrap();
    assert!(lib.news_list().unwrap().is_empty());
}

#[test]
fn downloads_are_listed_newest_first() {
    let lib = memory();
    lib.save_download("a", "1").unwrap();
    lib.save_download("b", "2").unwrap();
    lib.save_download("a", "3").unwrap(); // upsert conserva la posición
    let ids: Vec<_> = lib
        .read_downloads()
        .unwrap()
        .into_iter()
        .map(|d| (d.id, d.data))
        .collect();
    assert_eq!(ids, [("b".into(), "2".into()), ("a".into(), "3".into())]);
    lib.delete_download("b").unwrap();
    assert_eq!(lib.read_downloads().unwrap().len(), 1);
}

#[test]
fn tracks_are_newest_first_and_upsert_keeps_position() {
    let lib = memory();
    lib.save_track("a", "A1").unwrap();
    lib.save_track("b", "B").unwrap();
    lib.save_track("a", "A2").unwrap();
    lib.save_track_if_absent("b", "ignored").unwrap();
    lib.save_track_if_absent("c", "C").unwrap();
    assert_eq!(lib.read_tracks().unwrap(), ["C", "B", "A2"]);
    assert_eq!(lib.track_json("b").unwrap().as_deref(), Some("B"));
    assert_eq!(lib.track_json("zz").unwrap(), None);
}

/// Abre una COPIA de la base real y muestra solo recuentos.
/// `AURORA_DB_COPY=<ruta> cargo test -p aurora_database open_user_copy -- --ignored --nocapture`
#[test]
#[ignore]
fn open_user_copy() {
    let path = std::env::var("AURORA_DB_COPY").expect("AURORA_DB_COPY");
    let lib = Library::open(&path).unwrap();
    let conn = Connection::open(&path).unwrap();
    println!("user_version={}", user_version(&conn));
    println!("tracks={}", lib.read_tracks().unwrap().len());
    println!("favorites={}", lib.read_favorites().unwrap().len());
    println!("playlists={}", lib.read_playlists().unwrap().len());
    println!("history={}", lib.read_history().unwrap().len());
    println!("downloads={}", lib.read_downloads().unwrap().len());
    println!("track_vectors={}", lib.count_track_vectors().unwrap());
    println!(
        "taste={}",
        lib.read_taste_profile().unwrap().map_or(0, |v| v.len())
    );
    println!("followed={}", lib.follow_list().unwrap().len());
    println!("news={}", lib.news_list().unwrap().len());
    for kind in ["favorites", "playlists", "history", "taste"] {
        println!(
            "sync_meta[{kind}]={}",
            lib.read_sync_meta(kind).unwrap().len()
        );
    }
}

#[test]
#[ignore]
fn bench_read_tracks() {
    let lib = memory();
    let json = "{\"id\":\"yt:XXXXXXXXXXX\",\"title\":\"Una canción con un título largo\",\"artist\":\"Artista\",\"durationMs\":200000,\"artworkUrl\":\"https://i.ytimg.com/vi/XXXXXXXXXXX/hqdefault.jpg\",\"pageUrl\":\"https://music.youtube.com/watch?v=XXXXXXXXXXX\",\"localPath\":null,\"album\":\"Álbum\",\"genres\":[\"rock\"],\"spotifyUri\":null,\"spotifyMatchPending\":false}";
    for i in 0..10_000 {
        lib.save_track(&format!("yt:{i}"), json).unwrap();
    }
    let start = Instant::now();
    let tracks = lib.read_tracks().unwrap();
    let elapsed = start.elapsed();
    println!("bench_read_tracks: {} tracks in {elapsed:?}", tracks.len());
    assert!(elapsed < Duration::from_millis(50), "{elapsed:?}");
}

#[test]
#[ignore]
fn bench_nearest_tracks() {
    let lib = memory();
    let mut seed = 12345u64;
    let mut next = || {
        seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        ((seed >> 33) as f32 / (1u64 << 31) as f32) - 0.5
    };
    let entries: Vec<VectorEntry> = (0..5000)
        .map(|i| VectorEntry {
            track_key: format!("yt:{i}"),
            track_json: format!("{{\"id\":\"yt:{i}\"}}"),
            vector: (0..256).map(|_| next()).collect(),
        })
        .collect();
    lib.upsert_track_vectors(entries).unwrap();
    let query: Vec<f64> = (0..256).map(|_| next() as f64).collect();
    let start = Instant::now();
    let rows = lib.nearest_tracks(&query, 20, &[]).unwrap();
    let elapsed = start.elapsed();
    println!("bench_nearest_tracks: {} rows in {elapsed:?}", rows.len());
    assert_eq!(rows.len(), 20);
    assert!(elapsed < Duration::from_millis(50), "{elapsed:?}");
}

#[test]
fn saving_tracks_and_playlists_is_atomic_and_marks_playlists() {
    let lib = memory();
    let playlist = |id: &str| PlaylistRow {
        id: id.into(),
        name: format!("Lista {id}"),
        tracks_json: "[\"a\"]".into(),
    };
    lib.save_tracks_and_playlists(
        &[("a".into(), "A".into()), ("b".into(), "B".into())],
        &[playlist("p1"), playlist("p2")],
    )
    .unwrap();
    assert_eq!(lib.read_tracks().unwrap(), ["B", "A"]);
    assert_eq!(lib.read_playlists().unwrap().len(), 2);
    let meta = lib.read_sync_meta("playlists").unwrap();
    assert_eq!(meta.len(), 2);
    assert!(meta.iter().all(|m| m.dirty && !m.deleted));

    // Una fila inválida revierte todo el lote.
    let dir = tempdir().unwrap();
    let path = dir.path().join("aurora.sqlite");
    let lib = Library::open(&path).unwrap();
    Connection::open(&path)
        .unwrap()
        .execute_batch("CREATE TRIGGER no_boom BEFORE INSERT ON playlists WHEN NEW.id='boom' BEGIN SELECT RAISE(ABORT, 'no'); END")
        .unwrap();
    let result = lib.save_tracks_and_playlists(
        &[("a".into(), "A".into())],
        &[playlist("ok"), playlist("boom")],
    );
    assert!(result.is_err());
    assert!(lib.read_tracks().unwrap().is_empty());
    assert!(lib.read_playlists().unwrap().is_empty());
    assert!(lib.read_sync_meta("playlists").unwrap().is_empty());
}
