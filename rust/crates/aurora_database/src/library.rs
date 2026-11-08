use std::path::Path;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::{params, Connection, OptionalExtension};

use crate::error::Result;
use crate::schema::migrate;

/// Máximo de vectores de pista que se conservan (los más recientes).
pub const MAX_TRACK_VECTORS: i64 = 5000;

pub struct Library(Mutex<Connection>);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlaylistRow {
    pub id: String,
    pub name: String,
    pub tracks_json: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DownloadRow {
    pub id: String,
    pub data: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VectorEntry {
    pub track_key: String,
    pub track_json: String,
    pub vector: Vec<f32>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NearestRow {
    pub track_json: String,
    pub score: f64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TasteRow {
    pub dims: i64,
    pub vector: Vec<u8>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SyncMetaRow {
    pub key: String,
    pub updated_at: i64,
    pub deleted: bool,
    pub dirty: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FollowedRow {
    pub browse_id: String,
    pub name: String,
    pub image_url: Option<String>,
    pub followed_at: i64,
    pub last_release_id: Option<String>,
    pub last_release_title: Option<String>,
    pub known_releases: String,
    pub checked_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewsRow {
    pub release_id: String,
    pub artist_id: String,
    pub artist_name: String,
    pub title: String,
    pub subtitle: String,
    pub artwork_url: Option<String>,
    pub detected_at: i64,
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn f32s(bytes: &[u8]) -> Vec<f32> {
    bytes
        .chunks_exact(4)
        .map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]]))
        .collect()
}

/// Marca de sincronización, en la misma transacción que el cambio local.
fn mark(conn: &Connection, kind: &str, key: &str, deleted: bool) -> Result<()> {
    conn.execute(
        "INSERT INTO sync_meta VALUES (?,?,?,?,1) ON CONFLICT(kind,key) DO UPDATE SET \
         updated_at=excluded.updated_at, deleted=excluded.deleted, dirty=1",
        params![kind, key, now_ms(), deleted as i64],
    )?;
    Ok(())
}

impl Library {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        Self::from_connection(Connection::open(path)?)
    }

    /// Base en memoria. `setup_sql` se ejecuta ANTES de las migraciones, así
    /// las pruebas pueden construir esquemas antiguos (`PRAGMA user_version = N`).
    pub fn open_memory(setup_sql: Vec<String>) -> Result<Self> {
        let conn = Connection::open_in_memory()?;
        for statement in &setup_sql {
            conn.execute_batch(statement)?;
        }
        Self::from_connection(conn)
    }

    fn from_connection(mut conn: Connection) -> Result<Self> {
        conn.busy_timeout(Duration::from_millis(5000))?;
        migrate(&mut conn)?;
        Ok(Self(Mutex::new(conn)))
    }

    fn conn(&self) -> Result<MutexGuard<'_, Connection>> {
        Ok(self.0.lock()?)
    }

    // ---- pistas -------------------------------------------------------

    pub fn read_tracks(&self) -> Result<Vec<String>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached("SELECT data FROM tracks ORDER BY rowid DESC")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn save_track(&self, id: &str, data: &str) -> Result<()> {
        self.conn()?.execute(
            "INSERT INTO tracks (id,data) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",
            params![id, data],
        )?;
        Ok(())
    }

    pub fn save_track_if_absent(&self, id: &str, data: &str) -> Result<()> {
        self.conn()?.execute(
            "INSERT OR IGNORE INTO tracks (id,data) VALUES (?,?)",
            params![id, data],
        )?;
        Ok(())
    }

    pub fn track_json(&self, id: &str) -> Result<Option<String>> {
        Ok(self
            .conn()?
            .query_row("SELECT data FROM tracks WHERE id=?", [id], |row| row.get(0))
            .optional()?)
    }

    // ---- favoritos ----------------------------------------------------

    pub fn read_favorites(&self) -> Result<Vec<String>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached("SELECT track_id FROM favorites")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn set_favorite(&self, id: &str, selected: bool, mark_change: bool) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        if selected {
            tx.execute("INSERT OR IGNORE INTO favorites VALUES (?)", [id])?;
        } else {
            tx.execute("DELETE FROM favorites WHERE track_id=?", [id])?;
        }
        if mark_change {
            mark(&tx, "favorites", id, !selected)?;
        }
        tx.commit()?;
        Ok(())
    }

    // ---- listas -------------------------------------------------------

    pub fn read_playlists(&self) -> Result<Vec<PlaylistRow>> {
        let conn = self.conn()?;
        let mut stmt =
            conn.prepare_cached("SELECT id, name, tracks FROM playlists ORDER BY rowid")?;
        let rows = stmt.query_map([], |row| {
            Ok(PlaylistRow {
                id: row.get(0)?,
                name: row.get(1)?,
                tracks_json: row.get(2)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn playlist_row(&self, id: &str) -> Result<Option<PlaylistRow>> {
        Ok(self
            .conn()?
            .query_row(
                "SELECT id, name, tracks FROM playlists WHERE id=?",
                [id],
                |row| {
                    Ok(PlaylistRow {
                        id: row.get(0)?,
                        name: row.get(1)?,
                        tracks_json: row.get(2)?,
                    })
                },
            )
            .optional()?)
    }

    pub fn save_playlist(
        &self,
        id: &str,
        name: &str,
        tracks_json: &str,
        mark_change: bool,
    ) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO playlists (id,name,tracks) VALUES (?,?,?) ON CONFLICT(id) \
             DO UPDATE SET name=excluded.name,tracks=excluded.tracks",
            params![id, name, tracks_json],
        )?;
        if mark_change {
            mark(&tx, "playlists", id, false)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn delete_playlist(&self, id: &str, mark_change: bool) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        tx.execute("DELETE FROM playlists WHERE id=?", [id])?;
        if mark_change {
            mark(&tx, "playlists", id, true)?;
        }
        tx.commit()?;
        Ok(())
    }

    /// Guarda pistas y listas (marcadas para sincronizar) en una sola
    /// transacción: o entra todo o nada (importación de listas de Spotify).
    pub fn save_tracks_and_playlists(
        &self,
        tracks: &[(String, String)],
        playlists: &[PlaylistRow],
    ) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        for (id, data) in tracks {
            tx.execute(
                "INSERT INTO tracks (id,data) VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",
                params![id, data],
            )?;
        }
        for playlist in playlists {
            tx.execute(
                "INSERT INTO playlists (id,name,tracks) VALUES (?,?,?) ON CONFLICT(id) \
                 DO UPDATE SET name=excluded.name,tracks=excluded.tracks",
                params![playlist.id, playlist.name, playlist.tracks_json],
            )?;
            mark(&tx, "playlists", &playlist.id, false)?;
        }
        tx.commit()?;
        Ok(())
    }

    // ---- historial ----------------------------------------------------

    /// `played_at_ms = None` usa la hora actual.
    pub fn record_play(
        &self,
        id: &str,
        played_at_ms: Option<i64>,
        mark_change: bool,
    ) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO history VALUES (?,?) ON CONFLICT(track_id) DO UPDATE SET \
             played_at=excluded.played_at",
            params![id, played_at_ms.unwrap_or_else(now_ms)],
        )?;
        if mark_change {
            mark(&tx, "history", id, false)?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn read_history(&self) -> Result<Vec<String>> {
        let conn = self.conn()?;
        let mut stmt =
            conn.prepare_cached("SELECT track_id FROM history ORDER BY played_at DESC LIMIT 100")?;
        let rows = stmt.query_map([], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn history_played_at(&self, id: &str) -> Result<Option<i64>> {
        Ok(self
            .conn()?
            .query_row(
                "SELECT played_at FROM history WHERE track_id=?",
                [id],
                |row| row.get(0),
            )
            .optional()?)
    }

    // ---- descargas ----------------------------------------------------

    pub fn save_download(&self, id: &str, data: &str) -> Result<()> {
        self.conn()?.execute(
            "INSERT INTO downloads VALUES (?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data",
            params![id, data],
        )?;
        Ok(())
    }

    pub fn read_downloads(&self) -> Result<Vec<DownloadRow>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached("SELECT id,data FROM downloads ORDER BY rowid DESC")?;
        let rows = stmt.query_map([], |row| {
            Ok(DownloadRow {
                id: row.get(0)?,
                data: row.get(1)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn delete_download(&self, id: &str) -> Result<()> {
        self.conn()?
            .execute("DELETE FROM downloads WHERE id=?", [id])?;
        Ok(())
    }

    // ---- vectores y perfil de gustos ---------------------------------

    /// Guarda embeddings por clave de pista y conserva los
    /// [`MAX_TRACK_VECTORS`] más recientes.
    pub fn upsert_track_vectors(&self, entries: Vec<VectorEntry>) -> Result<()> {
        if entries.is_empty() {
            return Ok(());
        }
        let now = now_ms();
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        {
            let mut stmt = tx.prepare_cached(
                "INSERT INTO track_vectors VALUES (?,?,?,?,?) ON CONFLICT(track_key) \
                 DO UPDATE SET track=excluded.track, dims=excluded.dims, \
                 vector=excluded.vector, updated_at=excluded.updated_at",
            )?;
            for entry in &entries {
                let mut blob = Vec::with_capacity(entry.vector.len() * 4);
                for value in &entry.vector {
                    blob.extend_from_slice(&value.to_le_bytes());
                }
                stmt.execute(params![
                    entry.track_key,
                    entry.track_json,
                    entry.vector.len() as i64,
                    blob,
                    now
                ])?;
            }
        }
        tx.execute(
            &format!(
                "DELETE FROM track_vectors WHERE track_key NOT IN (SELECT track_key \
                 FROM track_vectors ORDER BY updated_at DESC LIMIT {MAX_TRACK_VECTORS})"
            ),
            [],
        )?;
        tx.commit()?;
        Ok(())
    }

    pub fn count_track_vectors(&self) -> Result<i64> {
        Ok(self
            .conn()?
            .query_row("SELECT COUNT(*) AS c FROM track_vectors", [], |row| {
                row.get(0)
            })?)
    }

    /// Vecinos por coseno de `query`, el mejor primero. Búsqueda exhaustiva.
    // shortcut: recorre todas las filas; basta para unos miles de pistas,
    // pasar a un índice ANN (o sqlite-vec) si el almacén crece mucho más.
    pub fn nearest_tracks(
        &self,
        query: &[f64],
        k: usize,
        exclude: &[String],
    ) -> Result<Vec<NearestRow>> {
        let query_norm: f64 = query.iter().map(|q| q * q).sum();
        if query_norm == 0.0 {
            return Ok(Vec::new());
        }
        let conn = self.conn()?;
        let mut scored: Vec<(f64, i64)> = Vec::new();
        {
            let mut stmt = conn.prepare_cached(
                "SELECT rowid, track_key, vector FROM track_vectors WHERE dims=? ORDER BY rowid",
            )?;
            let mut rows = stmt.query([query.len() as i64])?;
            while let Some(row) = rows.next()? {
                let key = row.get_ref(1)?.as_str()?;
                if exclude.iter().any(|e| e == key) {
                    continue;
                }
                let blob = row.get_ref(2)?.as_blob()?;
                if blob.len() != query.len() * 4 {
                    continue;
                }
                let (mut dot, mut norm) = (0.0f64, 0.0f64);
                for (q, chunk) in query.iter().zip(blob.chunks_exact(4)) {
                    let v = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f64;
                    dot += q * v;
                    norm += v * v;
                }
                if norm == 0.0 {
                    continue;
                }
                scored.push((dot / (query_norm * norm).sqrt(), row.get(0)?));
            }
        }
        scored.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
        let mut result = Vec::with_capacity(k.min(scored.len()));
        for (score, rowid) in scored.into_iter().take(k) {
            let track_json: String = conn.query_row(
                "SELECT track FROM track_vectors WHERE rowid=?",
                [rowid],
                |row| row.get(0),
            )?;
            result.push(NearestRow { track_json, score });
        }
        Ok(result)
    }

    pub fn read_taste_profile(&self) -> Result<Option<Vec<f32>>> {
        Ok(self.taste_row()?.map(|row| f32s(&row.vector)))
    }

    pub fn taste_row(&self) -> Result<Option<TasteRow>> {
        Ok(self
            .conn()?
            .query_row(
                "SELECT dims, vector FROM taste_profile WHERE id=1",
                [],
                |row| {
                    Ok(TasteRow {
                        dims: row.get(0)?,
                        vector: row.get(1)?,
                    })
                },
            )
            .optional()?)
    }

    pub fn save_taste(&self, dims: i64, vector: &[u8], mark_change: bool) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO taste_profile VALUES (1,?,?,?) ON CONFLICT(id) DO UPDATE SET \
             dims=excluded.dims, vector=excluded.vector, updated_at=excluded.updated_at",
            params![dims, vector, now_ms()],
        )?;
        if mark_change {
            mark(&tx, "taste", "1", false)?;
        }
        tx.commit()?;
        Ok(())
    }

    // ---- sincronización ----------------------------------------------

    /// Elementos locales anteriores a la cuenta: ts 0 para que, ante conflicto,
    /// gane el servidor, y el resto se suba (unión).
    pub fn seed_sync_meta(&self) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        for query in [
            "SELECT 'favorites', track_id FROM favorites",
            "SELECT 'playlists', id FROM playlists",
            "SELECT 'history', track_id FROM history",
            "SELECT 'taste', '1' FROM taste_profile",
        ] {
            tx.execute(
                &format!(
                    "INSERT OR IGNORE INTO sync_meta (kind,key,updated_at,deleted,dirty) \
                     SELECT *, 0, 0, 1 FROM ({query})"
                ),
                [],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn mark_all_sync_dirty(&self) -> Result<()> {
        self.conn()?.execute("UPDATE sync_meta SET dirty=1", [])?;
        Ok(())
    }

    pub fn read_sync_meta(&self, kind: &str) -> Result<Vec<SyncMetaRow>> {
        let conn = self.conn()?;
        let mut stmt =
            conn.prepare_cached("SELECT key,updated_at,deleted,dirty FROM sync_meta WHERE kind=?")?;
        let rows = stmt.query_map([kind], |row| {
            Ok(SyncMetaRow {
                key: row.get(0)?,
                updated_at: row.get(1)?,
                deleted: row.get::<_, i64>(2)? == 1,
                dirty: row.get::<_, i64>(3)? == 1,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    /// Claves pendientes de subir (el historial se limita a las 500 más nuevas).
    pub fn dirty_sync_keys(&self, kind: &str) -> Result<Vec<String>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached(
            "SELECT key FROM sync_meta WHERE kind=? AND dirty=1 \
             ORDER BY updated_at DESC LIMIT 500",
        )?;
        let rows = stmt.query_map([kind], |row| row.get(0))?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn set_sync_meta(&self, kind: &str, key: &str, ts: i64, deleted: bool) -> Result<()> {
        self.conn()?.execute(
            "INSERT INTO sync_meta VALUES (?,?,?,?,0) ON CONFLICT(kind,key) DO UPDATE \
             SET updated_at=?, deleted=?, dirty=0",
            params![kind, key, ts, deleted as i64, ts, deleted as i64],
        )?;
        Ok(())
    }

    /// Quita «pendiente» solo si nadie lo cambió mientras se subía.
    pub fn clear_sync_dirty(
        &self,
        kind: &str,
        key: &str,
        sent_ts: i64,
        server_ts: i64,
    ) -> Result<()> {
        self.conn()?.execute(
            "UPDATE sync_meta SET dirty=0, updated_at=? WHERE kind=? AND key=? AND updated_at=?",
            params![server_ts, kind, key, sent_ts],
        )?;
        Ok(())
    }

    // ---- artistas seguidos y novedades -------------------------------

    pub fn follow_list(&self) -> Result<Vec<FollowedRow>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached(
            "SELECT browse_id, name, image_url, followed_at, last_release_id, \
             last_release_title, known_releases, checked_at \
             FROM followed_artists ORDER BY followed_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(FollowedRow {
                browse_id: row.get(0)?,
                name: row.get(1)?,
                image_url: row.get(2)?,
                followed_at: row.get(3)?,
                last_release_id: row.get(4)?,
                last_release_title: row.get(5)?,
                known_releases: row.get(6)?,
                checked_at: row.get(7)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn follow_add(
        &self,
        browse_id: &str,
        name: &str,
        image_url: Option<&str>,
        followed_at: i64,
    ) -> Result<()> {
        self.conn()?.execute(
            "INSERT OR IGNORE INTO followed_artists \
             (browse_id,name,image_url,followed_at) VALUES (?,?,?,?)",
            params![browse_id, name, image_url, followed_at],
        )?;
        Ok(())
    }

    /// Deja de seguir y borra las novedades de ese artista, en una transacción.
    pub fn follow_remove(&self, browse_id: &str) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        tx.execute(
            "DELETE FROM followed_artists WHERE browse_id=?",
            [browse_id],
        )?;
        tx.execute("DELETE FROM new_releases WHERE artist_id=?", [browse_id])?;
        tx.commit()?;
        Ok(())
    }

    pub fn follow_save_check(
        &self,
        browse_id: &str,
        last_release_id: Option<&str>,
        last_release_title: Option<&str>,
        known_releases_json: &str,
        checked_at: Option<i64>,
    ) -> Result<()> {
        self.conn()?.execute(
            "UPDATE followed_artists SET last_release_id=?, last_release_title=?, \
             known_releases=?, checked_at=? WHERE browse_id=?",
            params![
                last_release_id,
                last_release_title,
                known_releases_json,
                checked_at,
                browse_id
            ],
        )?;
        Ok(())
    }

    pub fn news_list(&self) -> Result<Vec<NewsRow>> {
        let conn = self.conn()?;
        let mut stmt = conn.prepare_cached(
            "SELECT release_id, artist_id, artist_name, title, subtitle, artwork_url, \
             detected_at FROM new_releases ORDER BY detected_at DESC",
        )?;
        let rows = stmt.query_map([], |row| {
            Ok(NewsRow {
                release_id: row.get(0)?,
                artist_id: row.get(1)?,
                artist_name: row.get(2)?,
                title: row.get(3)?,
                subtitle: row.get(4)?,
                artwork_url: row.get(5)?,
                detected_at: row.get(6)?,
            })
        })?;
        Ok(rows.collect::<rusqlite::Result<_>>()?)
    }

    pub fn news_add(&self, rows: &[NewsRow]) -> Result<()> {
        let mut conn = self.conn()?;
        let tx = conn.transaction()?;
        {
            let mut stmt =
                tx.prepare_cached("INSERT OR IGNORE INTO new_releases VALUES (?,?,?,?,?,?,?)")?;
            for r in rows {
                stmt.execute(params![
                    r.release_id,
                    r.artist_id,
                    r.artist_name,
                    r.title,
                    r.subtitle,
                    r.artwork_url,
                    r.detected_at
                ])?;
            }
        }
        tx.commit()?;
        Ok(())
    }

    /// Sin `release_id` descarta todas («marcar como vistas»).
    pub fn news_dismiss(&self, release_id: Option<&str>) -> Result<()> {
        let conn = self.conn()?;
        match release_id {
            None => conn.execute("DELETE FROM new_releases", [])?,
            Some(id) => conn.execute("DELETE FROM new_releases WHERE release_id=?", [id])?,
        };
        Ok(())
    }

    pub fn news_prune(&self, older_than_ms: i64) -> Result<()> {
        self.conn()?.execute(
            "DELETE FROM new_releases WHERE detected_at<?",
            [older_than_ms],
        )?;
        Ok(())
    }
}
