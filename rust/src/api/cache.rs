use aurora_cache::PruneRules;
use flutter_rust_bridge::frb;
use std::path::Path;

/// Resultado de una poda. Los tamaños son `i64` para que Dart reciba `int`
/// (un `u64` llegaría como `BigInt`).
pub struct PruneReport {
    pub deleted_files: u32,
    pub deleted_bytes: i64,
    pub remaining_bytes: i64,
    pub remaining_files: u32,
}

fn clamp_i64(value: u64) -> i64 {
    i64::try_from(value).unwrap_or(i64::MAX)
}

/// Poda `dir`: borra lo más antiguo hasta cumplir `max_bytes` y/o `max_files`.
/// Los límites negativos se tratan como 0.
#[frb(sync)]
pub fn prune_directory(
    dir: String,
    max_bytes: Option<i64>,
    max_files: Option<u32>,
    name_suffix: Option<String>,
    exclude_names: Vec<String>,
) -> anyhow::Result<PruneReport> {
    let rules = PruneRules {
        max_bytes: max_bytes.map(|v| v.max(0) as u64),
        max_files: max_files.map(|v| v as usize),
        name_suffix,
        exclude_names,
    };
    let report = aurora_cache::prune_directory(Path::new(&dir), &rules)?;
    Ok(PruneReport {
        deleted_files: report.deleted_files,
        deleted_bytes: clamp_i64(report.deleted_bytes),
        remaining_bytes: clamp_i64(report.remaining_bytes),
        remaining_files: report.remaining_files,
    })
}

/// Totales de la caché de audio de reproducción (`<id>.audio`).
pub struct AudioCacheInfo {
    pub bytes: i64,
    pub files: u32,
}

#[frb(sync)]
pub fn audio_cache_info(dir: String) -> anyhow::Result<AudioCacheInfo> {
    let info = aurora_cache::audio_cache_info(Path::new(&dir))?;
    Ok(AudioCacheInfo {
        bytes: clamp_i64(info.bytes),
        files: info.files,
    })
}

pub struct AudioPruneResult {
    pub deleted_files: u32,
    pub deleted_bytes: i64,
    /// Con reserva pedida, aun tras podar no cabe: el llamador debe fallar.
    pub no_space: bool,
}

/// Poda la caché hasta `max_bytes - reserve_bytes`, sin tocar `protected`.
#[frb(sync)]
pub fn prune_audio_cache(
    dir: String,
    max_bytes: i64,
    reserve_bytes: i64,
    protected: Vec<String>,
) -> anyhow::Result<AudioPruneResult> {
    let protected: Vec<std::path::PathBuf> = protected.into_iter().map(Into::into).collect();
    let report =
        aurora_cache::prune_audio_cache(Path::new(&dir), max_bytes, reserve_bytes, &protected)?;
    Ok(AudioPruneResult {
        deleted_files: report.deleted_files,
        deleted_bytes: clamp_i64(report.deleted_bytes),
        no_space: report.no_space,
    })
}

/// Vacía la caché de audio salvo `protected`; devuelve los bytes borrados.
#[frb(sync)]
pub fn clear_audio_cache(dir: String, protected: Option<String>) -> anyhow::Result<i64> {
    let protected = protected.map(std::path::PathBuf::from);
    Ok(clamp_i64(aurora_cache::clear_audio_cache(
        Path::new(&dir),
        protected.as_deref(),
    )?))
}
