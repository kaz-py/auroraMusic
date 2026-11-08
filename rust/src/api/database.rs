//! Puente de la base de datos de la biblioteca (`aurora_database`).
//!
//! Todas las funciones son `sync`: los widget tests corren bajo `FakeAsync` y
//! las llamadas asíncronas de FRB terminan por puertos nativos que no avanzan
//! allí. Los envoltorios Dart siguen devolviendo `Future` donde ya lo hacían.

use anyhow::Result;
use aurora_database as db;
use flutter_rust_bridge::frb;

#[frb(opaque)]
pub struct LibraryDb(db::Library);

pub struct TrackRow {
    pub id: String,
    pub data: String,
}

pub struct PlaylistRow {
    pub id: String,
    pub name: String,
    pub tracks_json: String,
}

pub struct DownloadRow {
    pub id: String,
    pub data: String,
}

pub struct VectorEntry {
    pub track_key: String,
    pub track_json: String,
    pub vector: Vec<f32>,
}

pub struct NearestRow {
    pub track_json: String,
    pub score: f64,
}

pub struct TasteRow {
    pub dims: i64,
    pub vector: Vec<u8>,
}

pub struct SyncMetaRow {
    pub key: String,
    pub updated_at: i64,
    pub deleted: bool,
    pub dirty: bool,
}

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

pub struct NewsRow {
    pub release_id: String,
    pub artist_id: String,
    pub artist_name: String,
    pub title: String,
    pub subtitle: String,
    pub artwork_url: Option<String>,
    pub detected_at: i64,
}

impl From<db::PlaylistRow> for PlaylistRow {
    fn from(r: db::PlaylistRow) -> Self {
        Self {
            id: r.id,
            name: r.name,
            tracks_json: r.tracks_json,
        }
    }
}

impl From<db::DownloadRow> for DownloadRow {
    fn from(r: db::DownloadRow) -> Self {
        Self {
            id: r.id,
            data: r.data,
        }
    }
}

impl From<db::NearestRow> for NearestRow {
    fn from(r: db::NearestRow) -> Self {
        Self {
            track_json: r.track_json,
            score: r.score,
        }
    }
}

impl From<db::TasteRow> for TasteRow {
    fn from(r: db::TasteRow) -> Self {
        Self {
            dims: r.dims,
            vector: r.vector,
        }
    }
}

impl From<db::SyncMetaRow> for SyncMetaRow {
    fn from(r: db::SyncMetaRow) -> Self {
        Self {
            key: r.key,
            updated_at: r.updated_at,
            deleted: r.deleted,
            dirty: r.dirty,
        }
    }
}

impl From<db::FollowedRow> for FollowedRow {
    fn from(r: db::FollowedRow) -> Self {
        Self {
            browse_id: r.browse_id,
            name: r.name,
            image_url: r.image_url,
            followed_at: r.followed_at,
            last_release_id: r.last_release_id,
            last_release_title: r.last_release_title,
            known_releases: r.known_releases,
            checked_at: r.checked_at,
        }
    }
}

impl From<db::NewsRow> for NewsRow {
    fn from(r: db::NewsRow) -> Self {
        Self {
            release_id: r.release_id,
            artist_id: r.artist_id,
            artist_name: r.artist_name,
            title: r.title,
            subtitle: r.subtitle,
            artwork_url: r.artwork_url,
            detected_at: r.detected_at,
        }
    }
}

impl From<NewsRow> for db::NewsRow {
    fn from(r: NewsRow) -> Self {
        Self {
            release_id: r.release_id,
            artist_id: r.artist_id,
            artist_name: r.artist_name,
            title: r.title,
            subtitle: r.subtitle,
            artwork_url: r.artwork_url,
            detected_at: r.detected_at,
        }
    }
}

fn collect<T, U: From<T>>(rows: Vec<T>) -> Vec<U> {
    rows.into_iter().map(U::from).collect()
}

impl LibraryDb {
    #[frb(sync)]
    pub fn open(path: String) -> Result<LibraryDb> {
        Ok(LibraryDb(db::Library::open(path)?))
    }

    /// Base en memoria; `setup_sql` corre antes de las migraciones (pruebas).
    #[frb(sync)]
    pub fn open_memory(setup_sql: Vec<String>) -> Result<LibraryDb> {
        Ok(LibraryDb(db::Library::open_memory(setup_sql)?))
    }

    // ---- pistas
    #[frb(sync)]
    pub fn read_tracks(&self) -> Result<Vec<String>> {
        Ok(self.0.read_tracks()?)
    }
    #[frb(sync)]
    pub fn save_track(&self, id: String, data: String) -> Result<()> {
        Ok(self.0.save_track(&id, &data)?)
    }
    #[frb(sync)]
    pub fn save_track_if_absent(&self, id: String, data: String) -> Result<()> {
        Ok(self.0.save_track_if_absent(&id, &data)?)
    }
    #[frb(sync)]
    pub fn track_json(&self, id: String) -> Result<Option<String>> {
        Ok(self.0.track_json(&id)?)
    }

    // ---- favoritos
    #[frb(sync)]
    pub fn read_favorites(&self) -> Result<Vec<String>> {
        Ok(self.0.read_favorites()?)
    }
    #[frb(sync)]
    pub fn set_favorite(&self, id: String, selected: bool, mark: bool) -> Result<()> {
        Ok(self.0.set_favorite(&id, selected, mark)?)
    }

    // ---- listas
    #[frb(sync)]
    pub fn read_playlists(&self) -> Result<Vec<PlaylistRow>> {
        Ok(collect(self.0.read_playlists()?))
    }
    #[frb(sync)]
    pub fn playlist_row(&self, id: String) -> Result<Option<PlaylistRow>> {
        Ok(self.0.playlist_row(&id)?.map(Into::into))
    }
    #[frb(sync)]
    pub fn save_playlist(
        &self,
        id: String,
        name: String,
        tracks_json: String,
        mark: bool,
    ) -> Result<()> {
        Ok(self.0.save_playlist(&id, &name, &tracks_json, mark)?)
    }
    #[frb(sync)]
    pub fn delete_playlist(&self, id: String, mark: bool) -> Result<()> {
        Ok(self.0.delete_playlist(&id, mark)?)
    }
    /// Pistas y listas en una sola transacción (las listas se marcan para sincronizar).
    #[frb(sync)]
    pub fn save_tracks_and_playlists(
        &self,
        tracks: Vec<TrackRow>,
        playlists: Vec<PlaylistRow>,
    ) -> Result<()> {
        let tracks: Vec<(String, String)> = tracks.into_iter().map(|t| (t.id, t.data)).collect();
        let playlists: Vec<db::PlaylistRow> = playlists
            .into_iter()
            .map(|p| db::PlaylistRow {
                id: p.id,
                name: p.name,
                tracks_json: p.tracks_json,
            })
            .collect();
        Ok(self.0.save_tracks_and_playlists(&tracks, &playlists)?)
    }

    // ---- historial
    #[frb(sync)]
    pub fn record_play(&self, id: String, played_at_ms: Option<i64>, mark: bool) -> Result<()> {
        Ok(self.0.record_play(&id, played_at_ms, mark)?)
    }
    #[frb(sync)]
    pub fn read_history(&self) -> Result<Vec<String>> {
        Ok(self.0.read_history()?)
    }
    #[frb(sync)]
    pub fn history_played_at(&self, id: String) -> Result<Option<i64>> {
        Ok(self.0.history_played_at(&id)?)
    }

    // ---- descargas
    #[frb(sync)]
    pub fn save_download(&self, id: String, data: String) -> Result<()> {
        Ok(self.0.save_download(&id, &data)?)
    }
    #[frb(sync)]
    pub fn read_downloads(&self) -> Result<Vec<DownloadRow>> {
        Ok(collect(self.0.read_downloads()?))
    }
    #[frb(sync)]
    pub fn delete_download(&self, id: String) -> Result<()> {
        Ok(self.0.delete_download(&id)?)
    }

    // ---- vectores y perfil de gustos
    #[frb(sync)]
    pub fn upsert_track_vectors(&self, entries: Vec<VectorEntry>) -> Result<()> {
        let entries = entries
            .into_iter()
            .map(|e| db::VectorEntry {
                track_key: e.track_key,
                track_json: e.track_json,
                vector: e.vector,
            })
            .collect();
        Ok(self.0.upsert_track_vectors(entries)?)
    }
    #[frb(sync)]
    pub fn count_track_vectors(&self) -> Result<i64> {
        Ok(self.0.count_track_vectors()?)
    }
    #[frb(sync)]
    pub fn nearest_tracks(
        &self,
        query: Vec<f64>,
        k: u32,
        exclude: Vec<String>,
    ) -> Result<Vec<NearestRow>> {
        Ok(collect(
            self.0.nearest_tracks(&query, k as usize, &exclude)?,
        ))
    }
    #[frb(sync)]
    pub fn read_taste_profile(&self) -> Result<Option<Vec<f32>>> {
        Ok(self.0.read_taste_profile()?)
    }
    #[frb(sync)]
    pub fn taste_row(&self) -> Result<Option<TasteRow>> {
        Ok(self.0.taste_row()?.map(Into::into))
    }
    #[frb(sync)]
    pub fn save_taste(&self, dims: i64, vector: Vec<u8>, mark: bool) -> Result<()> {
        Ok(self.0.save_taste(dims, &vector, mark)?)
    }

    // ---- sincronización
    #[frb(sync)]
    pub fn seed_sync_meta(&self) -> Result<()> {
        Ok(self.0.seed_sync_meta()?)
    }
    #[frb(sync)]
    pub fn mark_all_sync_dirty(&self) -> Result<()> {
        Ok(self.0.mark_all_sync_dirty()?)
    }
    #[frb(sync)]
    pub fn read_sync_meta(&self, kind: String) -> Result<Vec<SyncMetaRow>> {
        Ok(collect(self.0.read_sync_meta(&kind)?))
    }
    #[frb(sync)]
    pub fn dirty_sync_keys(&self, kind: String) -> Result<Vec<String>> {
        Ok(self.0.dirty_sync_keys(&kind)?)
    }
    #[frb(sync)]
    pub fn set_sync_meta(&self, kind: String, key: String, ts: i64, deleted: bool) -> Result<()> {
        Ok(self.0.set_sync_meta(&kind, &key, ts, deleted)?)
    }
    #[frb(sync)]
    pub fn clear_sync_dirty(
        &self,
        kind: String,
        key: String,
        sent_ts: i64,
        server_ts: i64,
    ) -> Result<()> {
        Ok(self.0.clear_sync_dirty(&kind, &key, sent_ts, server_ts)?)
    }

    // ---- artistas seguidos y novedades
    #[frb(sync)]
    pub fn follow_list(&self) -> Result<Vec<FollowedRow>> {
        Ok(collect(self.0.follow_list()?))
    }
    #[frb(sync)]
    pub fn follow_add(
        &self,
        browse_id: String,
        name: String,
        image_url: Option<String>,
        followed_at: i64,
    ) -> Result<()> {
        Ok(self
            .0
            .follow_add(&browse_id, &name, image_url.as_deref(), followed_at)?)
    }
    #[frb(sync)]
    pub fn follow_remove(&self, browse_id: String) -> Result<()> {
        Ok(self.0.follow_remove(&browse_id)?)
    }
    #[frb(sync)]
    pub fn follow_save_check(
        &self,
        browse_id: String,
        last_release_id: Option<String>,
        last_release_title: Option<String>,
        known_releases_json: String,
        checked_at: Option<i64>,
    ) -> Result<()> {
        Ok(self.0.follow_save_check(
            &browse_id,
            last_release_id.as_deref(),
            last_release_title.as_deref(),
            &known_releases_json,
            checked_at,
        )?)
    }
    #[frb(sync)]
    pub fn news_list(&self) -> Result<Vec<NewsRow>> {
        Ok(collect(self.0.news_list()?))
    }
    #[frb(sync)]
    pub fn news_add(&self, rows: Vec<NewsRow>) -> Result<()> {
        let rows: Vec<db::NewsRow> = collect(rows);
        Ok(self.0.news_add(&rows)?)
    }
    #[frb(sync)]
    pub fn news_dismiss(&self, release_id: Option<String>) -> Result<()> {
        Ok(self.0.news_dismiss(release_id.as_deref())?)
    }
    #[frb(sync)]
    pub fn news_prune(&self, older_than_ms: i64) -> Result<()> {
        Ok(self.0.news_prune(older_than_ms)?)
    }
}
