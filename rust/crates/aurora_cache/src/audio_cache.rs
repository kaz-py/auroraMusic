//! Caché de audio de reproducción (`yt-dlp-audio/`): archivos `<id de 11
//! caracteres>.audio`. Port de `playbackCacheInfo`, `clearPlaybackCache` y
//! `_pruneAudioCache` de `lib/sources/yt_dlp_source.dart` (v1.5.2).
//!
//! Solo cuentan los archivos regulares con ese nombre exacto; los enlaces
//! simbólicos y todo lo demás se ignoran. Un archivo que no se puede borrar
//! (el reproductor lo tiene abierto) se salta sin error.

use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::time::SystemTime;

/// `^[A-Za-z0-9_-]{11}\.audio$`
pub fn is_audio_cache_name(name: &str) -> bool {
    match name.strip_suffix(".audio") {
        Some(id) => {
            id.len() == 11
                && id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
        }
        None => false,
    }
}

struct CachedFile {
    path: PathBuf,
    modified: SystemTime,
    len: u64,
}

fn cached_files(dir: &Path) -> io::Result<Vec<CachedFile>> {
    let mut files = Vec::new();
    for entry in fs::read_dir(dir)? {
        let Ok(entry) = entry else { continue };
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if !is_audio_cache_name(&name) {
            continue;
        }
        let Ok(meta) = fs::symlink_metadata(entry.path()) else {
            continue;
        };
        if !meta.file_type().is_file() {
            continue;
        }
        files.push(CachedFile {
            path: entry.path(),
            modified: meta.modified().unwrap_or(SystemTime::UNIX_EPOCH),
            len: meta.len(),
        });
    }
    Ok(files)
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AudioCacheInfo {
    pub bytes: u64,
    pub files: u32,
}

pub fn audio_cache_info(dir: &Path) -> io::Result<AudioCacheInfo> {
    let files = cached_files(dir)?;
    Ok(AudioCacheInfo {
        bytes: files.iter().map(|f| f.len).sum(),
        files: files.len() as u32,
    })
}

/// Igualdad de rutas como `p.equals` de Dart: normalizada y, en Windows, sin
/// distinguir mayúsculas.
fn same_path(a: &Path, b: &Path) -> bool {
    fn norm(p: &Path) -> Vec<String> {
        p.components()
            .filter(|c| !matches!(c, Component::CurDir))
            .map(|c| {
                let s = c.as_os_str().to_string_lossy().into_owned();
                if cfg!(windows) {
                    s.to_lowercase()
                } else {
                    s
                }
            })
            .collect()
    }
    norm(a) == norm(b)
}

/// Resultado de [`prune_audio_cache`].
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct AudioPruneReport {
    pub deleted_files: u32,
    pub deleted_bytes: u64,
    /// Con `reserve_bytes > 0`, aun tras podar no cabe la reserva.
    pub no_space: bool,
}

/// Borra lo más antiguo hasta que el total sea `<= max_bytes - reserve_bytes`,
/// sin tocar `protected`. No hay error por falta de espacio: se indica en el
/// informe para que el llamador lance el suyo.
pub fn prune_audio_cache(
    dir: &Path,
    max_bytes: i64,
    reserve_bytes: i64,
    protected: &[PathBuf],
) -> io::Result<AudioPruneReport> {
    let mut files = cached_files(dir)?;
    files.sort_by(|a, b| {
        a.modified
            .cmp(&b.modified)
            .then_with(|| a.path.cmp(&b.path))
    });
    let limit = max_bytes.saturating_sub(reserve_bytes);
    let mut total: i64 = files.iter().map(|f| f.len as i64).sum();
    let mut report = AudioPruneReport::default();
    for file in &files {
        if total <= limit {
            break;
        }
        if protected.iter().any(|p| same_path(p, &file.path)) {
            continue;
        }
        if fs::remove_file(&file.path).is_ok() {
            total -= file.len as i64;
            report.deleted_files += 1;
            report.deleted_bytes += file.len;
        }
    }
    report.no_space = reserve_bytes > 0 && total > limit;
    Ok(report)
}

/// `File.resolveSymbolicLinks` con el respaldo de `_canonicalFilePath`: si el
/// archivo no existe, la carpeta canónica más el nombre.
fn canonical_file_path(path: &Path) -> io::Result<PathBuf> {
    match fs::canonicalize(path) {
        Ok(p) => Ok(p),
        Err(_) => {
            let absolute = std::path::absolute(path)?;
            let parent = fs::canonicalize(absolute.parent().unwrap_or(Path::new(".")))?;
            Ok(parent.join(absolute.file_name().unwrap_or_default()))
        }
    }
}

/// Vacía la caché salvo `protected` y devuelve los bytes borrados. Un archivo
/// cuya ruta canónica salga de la caché (enlace) se ignora.
pub fn clear_audio_cache(dir: &Path, protected: Option<&Path>) -> io::Result<u64> {
    let cache = fs::canonicalize(dir)?;
    let protected = match protected {
        Some(p) => Some(canonical_file_path(p)?),
        None => None,
    };
    let mut removed = 0;
    for file in cached_files(dir)? {
        let Ok(canonical) = fs::canonicalize(&file.path) else {
            continue;
        };
        if !canonical.starts_with(&cache)
            || protected.as_ref().is_some_and(|p| same_path(p, &canonical))
        {
            continue;
        }
        if fs::remove_file(&file.path).is_ok() {
            removed += file.len;
        }
    }
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;
    use filetime::{set_file_mtime, FileTime};
    use tempfile::tempdir;

    const A: &str = "AAAAAAAAAAA.audio";
    const B: &str = "BBBBBBBBBBB.audio";
    const C: &str = "CCCCCCCCCCC.audio";

    fn put(dir: &Path, name: &str, len: usize, age: i64) -> PathBuf {
        let path = dir.join(name);
        fs::write(&path, vec![1u8; len]).unwrap();
        set_file_mtime(&path, FileTime::from_unix_time(1_700_000_000 - age, 0)).unwrap();
        path
    }

    fn exists(dir: &Path, name: &str) -> bool {
        dir.join(name).exists()
    }

    #[test]
    fn only_exact_cache_names_are_recognised() {
        assert!(is_audio_cache_name("abcDEF_-123.audio"));
        assert!(!is_audio_cache_name("short.audio"));
        assert!(!is_audio_cache_name("abcDEF_-1234.audio"));
        assert!(!is_audio_cache_name("abcDEF_-123.audio.tmp"));
        assert!(!is_audio_cache_name("abcDEF 1234.audio"));
        assert!(!is_audio_cache_name("abcDEF_-123.AUDIO"));
        assert!(!is_audio_cache_name("ábcDEF_-123.audio"));
    }

    #[test]
    fn info_counts_only_matching_regular_files() {
        let dir = tempdir().unwrap();
        put(dir.path(), A, 3, 10);
        put(dir.path(), B, 4, 20);
        put(dir.path(), "notes.txt", 100, 30);
        put(dir.path(), "AAAAAAAAAAA.audio.part", 100, 30);
        fs::create_dir(dir.path().join("DDDDDDDDDDD.audio")).unwrap();
        assert_eq!(
            audio_cache_info(dir.path()).unwrap(),
            AudioCacheInfo { bytes: 7, files: 2 }
        );
    }

    #[test]
    fn prune_deletes_oldest_first_and_skips_protected_files() {
        let dir = tempdir().unwrap();
        let a = put(dir.path(), A, 10, 300);
        put(dir.path(), B, 10, 200);
        put(dir.path(), C, 10, 100);
        let report = prune_audio_cache(dir.path(), 15, 0, &[a]).unwrap();
        assert!(exists(dir.path(), A), "protegido");
        assert!(!exists(dir.path(), B));
        assert!(!exists(dir.path(), C));
        assert_eq!((report.deleted_files, report.deleted_bytes), (2, 20));
        assert!(!report.no_space);
    }

    #[test]
    fn prune_without_reserve_never_reports_no_space() {
        let dir = tempdir().unwrap();
        let a = put(dir.path(), A, 10, 300);
        let report = prune_audio_cache(dir.path(), 0, 0, &[a]).unwrap();
        assert!(!report.no_space);
        assert!(exists(dir.path(), A));
    }

    #[test]
    fn prune_reserves_room_and_reports_when_it_cannot() {
        let dir = tempdir().unwrap();
        put(dir.path(), A, 10, 300);
        let b = put(dir.path(), B, 10, 200);
        // limite = 25 - 20 = 5: hay que borrarlo todo salvo lo protegido.
        let report = prune_audio_cache(dir.path(), 25, 20, &[b]).unwrap();
        assert!(!exists(dir.path(), A));
        assert!(exists(dir.path(), B));
        assert!(report.no_space);
        // Una reserva mayor que el máximo vacía lo que se pueda.
        let report = prune_audio_cache(dir.path(), 5, 100, &[]).unwrap();
        assert!(!exists(dir.path(), B));
        assert!(report.no_space, "total 0 > limite negativo");
    }

    #[test]
    fn prune_ignores_foreign_files() {
        let dir = tempdir().unwrap();
        put(dir.path(), "keep.txt", 1000, 500);
        put(dir.path(), A, 10, 100);
        prune_audio_cache(dir.path(), 0, 0, &[]).unwrap();
        assert!(exists(dir.path(), "keep.txt"));
        assert!(!exists(dir.path(), A));
    }

    #[test]
    fn clear_removes_everything_except_the_protected_file() {
        let dir = tempdir().unwrap();
        let a = put(dir.path(), A, 3, 10);
        put(dir.path(), B, 4, 20);
        put(dir.path(), "other.bin", 50, 30);
        let removed = clear_audio_cache(dir.path(), Some(&a)).unwrap();
        assert_eq!(removed, 4);
        assert!(exists(dir.path(), A));
        assert!(!exists(dir.path(), B));
        assert!(exists(dir.path(), "other.bin"));
        assert_eq!(clear_audio_cache(dir.path(), None).unwrap(), 3);
    }

    #[test]
    fn clear_protects_a_missing_file_by_its_canonical_path() {
        let dir = tempdir().unwrap();
        put(dir.path(), A, 3, 10);
        let ghost = dir.path().join("ZZZZZZZZZZZ.audio");
        assert_eq!(clear_audio_cache(dir.path(), Some(&ghost)).unwrap(), 3);
    }

    #[test]
    fn clear_ignores_symlinks() {
        let dir = tempdir().unwrap();
        let outside = tempdir().unwrap();
        let target = outside.path().join("target");
        fs::write(&target, b"data").unwrap();
        let link = dir.path().join(A);
        #[cfg(unix)]
        let linked = std::os::unix::fs::symlink(&target, &link).is_ok();
        #[cfg(windows)]
        let linked = std::os::windows::fs::symlink_file(&target, &link).is_ok();
        if !linked {
            return;
        }
        assert_eq!(clear_audio_cache(dir.path(), None).unwrap(), 0);
        assert!(target.exists());
        assert_eq!(
            audio_cache_info(dir.path()).unwrap(),
            AudioCacheInfo::default()
        );
    }

    #[test]
    fn missing_directory_is_an_error_for_info_and_clear() {
        let dir = tempdir().unwrap();
        let missing = dir.path().join("nope");
        assert!(audio_cache_info(&missing).is_err());
        assert!(clear_audio_cache(&missing, None).is_err());
    }
}
