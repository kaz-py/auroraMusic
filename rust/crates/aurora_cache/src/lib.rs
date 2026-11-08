//! Poda de directorios de caché por antigüedad (LRU por fecha de modificación).

mod audio_cache;

pub use audio_cache::{
    audio_cache_info, clear_audio_cache, is_audio_cache_name, prune_audio_cache, AudioCacheInfo,
    AudioPruneReport,
};

use std::fs;
use std::io;
use std::path::Path;
use std::time::SystemTime;

/// Límites de la poda. Si se dan los dos, se aplican ambos.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PruneRules {
    /// Borra los más antiguos hasta que el total sea `<= max_bytes`.
    pub max_bytes: Option<u64>,
    /// Borra los más antiguos hasta que haya `<= max_files` archivos.
    pub max_files: Option<usize>,
    /// Solo se gestionan los archivos cuyo nombre termina así.
    pub name_suffix: Option<String>,
    /// Nombres exactos que nunca se gestionan ni se borran.
    pub exclude_names: Vec<String>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PruneReport {
    pub deleted_files: u32,
    pub deleted_bytes: u64,
    pub remaining_bytes: u64,
    pub remaining_files: u32,
}

struct Entry {
    name: String,
    modified: SystemTime,
    len: u64,
}

/// Poda los archivos regulares directamente dentro de `dir`.
///
/// Ignora subdirectorios y enlaces simbólicos. Un archivo que no se puede
/// borrar se salta (cuenta como restante); nunca es un error. Un `dir`
/// inexistente devuelve un informe vacío.
pub fn prune_directory(dir: &Path, rules: &PruneRules) -> io::Result<PruneReport> {
    let listing = match fs::read_dir(dir) {
        Ok(listing) => listing,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(PruneReport::default()),
        Err(error) => return Err(error),
    };
    let mut entries = Vec::new();
    for item in listing {
        let Ok(item) = item else { continue };
        let Ok(meta) = fs::symlink_metadata(item.path()) else {
            continue;
        };
        if !meta.file_type().is_file() {
            continue;
        }
        let name = item.file_name().to_string_lossy().into_owned();
        if rules.exclude_names.contains(&name) {
            continue;
        }
        if let Some(suffix) = &rules.name_suffix {
            if !name.ends_with(suffix.as_str()) {
                continue;
            }
        }
        entries.push(Entry {
            name,
            modified: meta.modified().unwrap_or(SystemTime::UNIX_EPOCH),
            len: meta.len(),
        });
    }
    entries.sort_by(|a, b| {
        a.modified
            .cmp(&b.modified)
            .then_with(|| a.name.cmp(&b.name))
    });

    let mut report = PruneReport {
        remaining_bytes: entries.iter().map(|e| e.len).sum(),
        remaining_files: entries.len() as u32,
        ..PruneReport::default()
    };
    for entry in &entries {
        let over_bytes = rules
            .max_bytes
            .is_some_and(|max| report.remaining_bytes > max);
        let over_files = rules
            .max_files
            .is_some_and(|max| report.remaining_files as usize > max);
        if !over_bytes && !over_files {
            break;
        }
        if fs::remove_file(dir.join(&entry.name)).is_ok() {
            report.deleted_files += 1;
            report.deleted_bytes += entry.len;
            report.remaining_bytes -= entry.len;
            report.remaining_files -= 1;
        }
    }
    Ok(report)
}

#[cfg(test)]
mod tests {
    use super::*;
    use filetime::{set_file_mtime, FileTime};
    use tempfile::tempdir;

    fn put(dir: &Path, name: &str, len: usize, age_secs: i64) {
        let path = dir.join(name);
        fs::write(&path, vec![b'x'; len]).unwrap();
        set_file_mtime(&path, FileTime::from_unix_time(1_700_000_000 - age_secs, 0)).unwrap();
    }

    fn names(dir: &Path) -> Vec<String> {
        let mut found: Vec<String> = fs::read_dir(dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        found.sort();
        found
    }

    #[test]
    fn deletes_oldest_first_until_under_byte_limit() {
        let dir = tempdir().unwrap();
        put(dir.path(), "old", 100, 300);
        put(dir.path(), "mid", 100, 200);
        put(dir.path(), "new", 100, 100);
        let rules = PruneRules {
            max_bytes: Some(150),
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["new"]);
        assert_eq!(
            report,
            PruneReport {
                deleted_files: 2,
                deleted_bytes: 200,
                remaining_bytes: 100,
                remaining_files: 1
            }
        );
    }

    #[test]
    fn stops_as_soon_as_limit_is_met() {
        let dir = tempdir().unwrap();
        put(dir.path(), "a", 100, 300);
        put(dir.path(), "b", 100, 200);
        put(dir.path(), "c", 100, 100);
        let rules = PruneRules {
            max_bytes: Some(200),
            ..Default::default()
        };
        prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["b", "c"]);
    }

    #[test]
    fn deletes_oldest_first_by_count() {
        let dir = tempdir().unwrap();
        for (i, name) in ["a", "b", "c", "d"].iter().enumerate() {
            put(dir.path(), name, 1, 400 - i as i64 * 100);
        }
        let rules = PruneRules {
            max_files: Some(2),
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["c", "d"]);
        assert_eq!(report.deleted_files, 2);
        assert_eq!(report.remaining_files, 2);
    }

    #[test]
    fn applies_both_limits() {
        let dir = tempdir().unwrap();
        put(dir.path(), "a", 10, 400);
        put(dir.path(), "b", 500, 300);
        put(dir.path(), "c", 10, 200);
        put(dir.path(), "d", 10, 100);
        // count alone would keep b,c,d; bytes forces b out too.
        let rules = PruneRules {
            max_bytes: Some(100),
            max_files: Some(3),
            ..Default::default()
        };
        prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["c", "d"]);
    }

    #[test]
    fn equal_mtimes_break_ties_by_name() {
        let dir = tempdir().unwrap();
        put(dir.path(), "b", 1, 100);
        put(dir.path(), "a", 1, 100);
        put(dir.path(), "c", 1, 100);
        let rules = PruneRules {
            max_files: Some(1),
            ..Default::default()
        };
        prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["c"]);
    }

    #[test]
    fn suffix_filter_and_exclusions_leave_other_files_alone() {
        let dir = tempdir().unwrap();
        put(dir.path(), "offsets.json", 5, 900);
        put(dir.path(), "keep.txt", 5, 800);
        put(dir.path(), "a.json", 5, 300);
        put(dir.path(), "b.json", 5, 200);
        put(dir.path(), "c.json", 5, 100);
        let rules = PruneRules {
            max_files: Some(1),
            name_suffix: Some(".json".into()),
            exclude_names: vec!["offsets.json".into()],
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(names(dir.path()), ["c.json", "keep.txt", "offsets.json"]);
        assert_eq!(report.deleted_files, 2);
        assert_eq!(report.remaining_files, 1);
    }

    #[test]
    fn subdirectories_are_ignored() {
        let dir = tempdir().unwrap();
        fs::create_dir(dir.path().join("sub")).unwrap();
        fs::write(dir.path().join("sub").join("inner"), vec![0u8; 1000]).unwrap();
        put(dir.path(), "a", 10, 100);
        let rules = PruneRules {
            max_bytes: Some(0),
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(report.deleted_files, 1);
        assert!(dir.path().join("sub").join("inner").exists());
    }

    #[test]
    fn symlinks_are_ignored() {
        let dir = tempdir().unwrap();
        let outside = tempdir().unwrap();
        let target = outside.path().join("target");
        fs::write(&target, b"data").unwrap();
        let link = dir.path().join("link");
        #[cfg(unix)]
        let linked = std::os::unix::fs::symlink(&target, &link).is_ok();
        #[cfg(windows)]
        let linked = std::os::windows::fs::symlink_file(&target, &link).is_ok();
        if !linked {
            return; // sin privilegio para crear enlaces (Windows sin modo desarrollador)
        }
        let rules = PruneRules {
            max_files: Some(0),
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        assert_eq!(report, PruneReport::default());
        assert!(target.exists());
        assert!(fs::symlink_metadata(&link).is_ok());
    }

    #[test]
    fn empty_and_missing_directories_return_zeros() {
        let dir = tempdir().unwrap();
        let rules = PruneRules {
            max_bytes: Some(0),
            max_files: Some(0),
            ..Default::default()
        };
        assert_eq!(
            prune_directory(dir.path(), &rules).unwrap(),
            PruneReport::default()
        );
        let missing = dir.path().join("nope");
        assert_eq!(
            prune_directory(&missing, &rules).unwrap(),
            PruneReport::default()
        );
    }

    #[test]
    fn undeletable_file_is_skipped_and_counted_as_remaining() {
        let dir = tempdir().unwrap();
        put(dir.path(), "locked", 100, 300);
        put(dir.path(), "free", 100, 200);
        let locked = dir.path().join("locked");
        let mut perms = fs::metadata(&locked).unwrap().permissions();
        perms.set_readonly(true);
        fs::set_permissions(&locked, perms).unwrap();
        let rules = PruneRules {
            max_files: Some(0),
            ..Default::default()
        };
        let report = prune_directory(dir.path(), &rules).unwrap();
        let still_there = locked.exists();
        if still_there {
            // restaurar para que tempdir pueda limpiar
            let mut perms = fs::metadata(&locked).unwrap().permissions();
            #[allow(clippy::permissions_set_readonly_false)]
            perms.set_readonly(false);
            fs::set_permissions(&locked, perms).unwrap();
        }
        assert!(!dir.path().join("free").exists());
        if still_there {
            assert_eq!(report.deleted_files, 1);
            assert_eq!(report.remaining_files, 1);
            assert_eq!(report.remaining_bytes, 100);
        } // si el SO borra archivos de solo lectura, no hay nada que comprobar
    }
}
