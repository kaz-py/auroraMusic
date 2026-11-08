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
