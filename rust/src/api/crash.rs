use aurora_cache::PruneRules;
use flutter_rust_bridge::frb;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::panic::PanicHookInfo;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

/// Registros que se conservan en `logs/` (Dart, Rust y nativos juntos).
const KEEP_LOGS: usize = 30;

static CRASH_LOG: OnceLock<(PathBuf, String)> = OnceLock::new();

/// Guarda los pánicos de Rust (de cualquier hilo: decodificador, salida de
/// audio, voz…) en `<dir>/rust-AAAA-MM-DD.log`, hora UTC, y deja la carpeta en
/// los 30 registros más recientes. Solo la primera llamada instala el gancho.
#[frb(sync)]
pub fn install_crash_log(dir: String, version: String) {
    let dir = PathBuf::from(dir);
    let _ = fs::create_dir_all(&dir);
    let rules = PruneRules {
        max_bytes: None,
        max_files: Some(KEEP_LOGS),
        name_suffix: None,
        exclude_names: Vec::new(),
    };
    let _ = aurora_cache::prune_directory(&dir, &rules);
    if CRASH_LOG.set((dir, version)).is_err() {
        return;
    }
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        if let Some((dir, version)) = CRASH_LOG.get() {
            write_panic(dir, version, info);
        }
        previous(info);
    }));
}

fn write_panic(dir: &Path, version: &str, info: &PanicHookInfo<'_>) {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());
    let (date, time) = utc(secs);
    let thread = std::thread::current();
    let entry = format!(
        "[{date}T{time}Z] Pánico en el hilo '{}' (Aurora {version})\n{info}\n{}\n\n",
        thread.name().unwrap_or("sin nombre"),
        std::backtrace::Backtrace::force_capture(),
    );
    // Sin disco no hay registro; el gancho nunca debe provocar otro pánico.
    if let Ok(mut file) = OpenOptions::new()
        .create(true)
        .append(true)
        .open(dir.join(format!("rust-{date}.log")))
    {
        let _ = file.write_all(entry.as_bytes());
    }
}

/// Fecha y hora UTC de un instante Unix (algoritmo civil de Howard Hinnant).
fn utc(secs: u64) -> (String, String) {
    let days = (secs / 86_400) as i64 + 719_468;
    let rem = secs % 86_400;
    let era = days / 146_097;
    let doe = days % 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);
    (
        format!("{year:04}-{month:02}-{day:02}"),
        format!("{:02}:{:02}:{:02}", rem / 3_600, rem / 60 % 60, rem % 60),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utc_dates() {
        assert_eq!(utc(0), ("1970-01-01".into(), "00:00:00".into()));
        assert_eq!(utc(951_825_599), ("2000-02-29".into(), "11:59:59".into()));
        assert_eq!(utc(1_709_251_199), ("2024-02-29".into(), "23:59:59".into()));
        assert_eq!(utc(1_709_251_200), ("2024-03-01".into(), "00:00:00".into()));
        assert_eq!(utc(1_798_761_599), ("2026-12-31".into(), "23:59:59".into()));
    }

    #[test]
    fn panic_in_any_thread_is_logged_and_folder_is_pruned() {
        let dir = std::env::temp_dir().join(format!("aurora_crash_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for i in 0..KEEP_LOGS + 5 {
            fs::write(dir.join(format!("viejo-{i:02}.log")), "x").unwrap();
        }
        install_crash_log(dir.to_string_lossy().into(), "9.9.9+1".into());
        assert_eq!(fs::read_dir(&dir).unwrap().count(), KEEP_LOGS);

        let worker = std::thread::Builder::new()
            .name("aurora-decoder".into())
            .spawn(|| panic!("flujo corrupto"))
            .unwrap();
        assert!(worker.join().is_err());

        let log = fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().path())
            .find(|p| {
                p.file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with("rust-")
            })
            .expect("registro de Rust");
        let text = fs::read_to_string(log).unwrap();
        assert!(
            text.contains("hilo 'aurora-decoder' (Aurora 9.9.9+1)"),
            "{text}"
        );
        assert!(text.contains("flujo corrupto"), "{text}");
        fs::remove_dir_all(&dir).unwrap();
    }
}
