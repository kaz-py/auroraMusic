//! Esquema y migraciones. Es byte a byte el SQL que escribía drift
//! (`LibraryDatabase` en Dart hasta la v1.4.0): una base creada por la versión
//! anterior se abre sin cambios.

use rusqlite::Connection;

use crate::error::{DatabaseError, Result};

pub const SCHEMA_VERSION: i64 = 4;

const BASE_TABLES: [&str; 5] = [
    "CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
    "CREATE TABLE favorites (track_id TEXT PRIMARY KEY)",
    "CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, tracks TEXT NOT NULL)",
    "CREATE TABLE history (track_id TEXT PRIMARY KEY, played_at INTEGER NOT NULL)",
    "CREATE TABLE downloads (id TEXT PRIMARY KEY, data TEXT NOT NULL)",
];

const VECTOR_TABLES: [&str; 2] = [
    "CREATE TABLE IF NOT EXISTS track_vectors (track_key TEXT PRIMARY KEY, \
     track TEXT NOT NULL, dims INTEGER NOT NULL, vector BLOB NOT NULL, \
     updated_at INTEGER NOT NULL)",
    "CREATE TABLE IF NOT EXISTS taste_profile (id INTEGER PRIMARY KEY \
     CHECK (id = 1), dims INTEGER NOT NULL, vector BLOB NOT NULL, \
     updated_at INTEGER NOT NULL)",
];

const FOLLOW_TABLES: [&str; 2] = [
    "CREATE TABLE IF NOT EXISTS followed_artists (browse_id TEXT PRIMARY KEY, \
     name TEXT NOT NULL, image_url TEXT, followed_at INTEGER NOT NULL, \
     last_release_id TEXT, last_release_title TEXT, \
     known_releases TEXT NOT NULL DEFAULT '[]', checked_at INTEGER)",
    "CREATE TABLE IF NOT EXISTS new_releases (release_id TEXT PRIMARY KEY, \
     artist_id TEXT NOT NULL, artist_name TEXT NOT NULL, title TEXT NOT NULL, \
     subtitle TEXT NOT NULL, artwork_url TEXT, detected_at INTEGER NOT NULL)",
];

const SYNC_TABLES: [&str; 1] = [
    "CREATE TABLE IF NOT EXISTS sync_meta (kind TEXT NOT NULL, key TEXT NOT NULL, \
     updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0, \
     dirty INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (kind, key))",
];

fn run(conn: &Connection, statements: &[&str]) -> Result<()> {
    for statement in statements {
        conn.execute(statement, [])?;
    }
    Ok(())
}

/// Lleva la base a [`SCHEMA_VERSION`]. Cada migración va en una transacción.
pub fn migrate(conn: &mut Connection) -> Result<()> {
    let version: i64 = conn.query_row("PRAGMA user_version", [], |row| row.get(0))?;
    if version > SCHEMA_VERSION {
        return Err(DatabaseError::TooNew(version));
    }
    if version == SCHEMA_VERSION {
        return Ok(());
    }
    let tx = conn.transaction()?;
    if version == 0 {
        run(&tx, &BASE_TABLES)?;
        run(&tx, &VECTOR_TABLES)?;
        run(&tx, &FOLLOW_TABLES)?;
        run(&tx, &SYNC_TABLES)?;
    } else {
        if version < 2 {
            run(&tx, &VECTOR_TABLES)?;
        }
        if version < 3 {
            run(&tx, &FOLLOW_TABLES)?;
        }
        if version < 4 {
            run(&tx, &SYNC_TABLES)?;
        }
    }
    tx.execute_batch(&format!("PRAGMA user_version = {SCHEMA_VERSION}"))?;
    tx.commit()?;
    Ok(())
}
