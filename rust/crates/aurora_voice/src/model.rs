//! Instalación del modelo de voz desde el ZIP descargado.

use std::fs::{self, File};
use std::io;
use std::path::{Component, Path, PathBuf};

use crate::VoiceError;

/// Tope de lo que se descomprime: el modelo pequeño ronda los 50 MB.
const MAX_TOTAL_BYTES: u64 = 400 * 1024 * 1024;

fn fail(message: impl Into<String>) -> VoiceError {
    VoiceError::Model(message.into())
}

/// ¿Hay un modelo utilizable en `dir`?
pub fn model_is_installed(dir: &Path) -> bool {
    dir.join("am").join("final.mdl").is_file() && dir.join("conf").join("model.conf").is_file()
}

/// Descomprime `archive` (con una carpeta raíz, como los de Vosk) en `dest`.
/// Rechaza rutas que salgan de la carpeta y archivos desproporcionados; trabaja
/// en una carpeta temporal y solo la mueve al final, así un fallo no deja un
/// modelo a medias.
pub fn install_model(archive: &Path, dest: &Path) -> Result<(), VoiceError> {
    let file = File::open(archive).map_err(|e| fail(format!("No se pudo abrir el modelo: {e}")))?;
    let mut zip = zip::ZipArchive::new(file)
        .map_err(|e| fail(format!("El modelo no es un ZIP válido: {e}")))?;
    let parent = dest
        .parent()
        .ok_or_else(|| fail("Carpeta de destino inválida."))?;
    fs::create_dir_all(parent).map_err(|e| fail(e.to_string()))?;
    let staging = parent.join(format!(
        ".{}.tmp",
        dest.file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("modelo")
    ));
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging).map_err(|e| fail(e.to_string()))?;
    let result = extract(&mut zip, &staging);
    if let Err(e) = result {
        let _ = fs::remove_dir_all(&staging);
        return Err(e);
    }
    if !model_is_installed(&staging) {
        let _ = fs::remove_dir_all(&staging);
        return Err(fail("El archivo no contiene un modelo de voz de Vosk."));
    }
    let _ = fs::remove_dir_all(dest);
    fs::rename(&staging, dest).map_err(|e| fail(format!("No se pudo instalar el modelo: {e}")))
}

fn extract(zip: &mut zip::ZipArchive<File>, into: &Path) -> Result<(), VoiceError> {
    let mut total = 0u64;
    for index in 0..zip.len() {
        let mut entry = zip
            .by_index(index)
            .map_err(|e| fail(format!("Modelo dañado: {e}")))?;
        // `enclosed_name` descarta `..` y rutas absolutas.
        let relative = entry
            .enclosed_name()
            .ok_or_else(|| fail("El modelo contiene una ruta no permitida."))?;
        // Se quita la carpeta raíz del archivo.
        let stripped: PathBuf = relative
            .components()
            .skip(1)
            .filter(|c| matches!(c, Component::Normal(_)))
            .collect();
        if stripped.as_os_str().is_empty() {
            continue;
        }
        let target = into.join(&stripped);
        if entry.is_dir() {
            fs::create_dir_all(&target).map_err(|e| fail(e.to_string()))?;
            continue;
        }
        total = total.saturating_add(entry.size());
        if total > MAX_TOTAL_BYTES {
            return Err(fail("El modelo descomprimido es demasiado grande."));
        }
        if let Some(dir) = target.parent() {
            fs::create_dir_all(dir).map_err(|e| fail(e.to_string()))?;
        }
        let mut out = File::create(&target).map_err(|e| fail(e.to_string()))?;
        // `take` por si el tamaño declarado miente.
        io::copy(&mut io::Read::take(&mut entry, MAX_TOTAL_BYTES), &mut out)
            .map_err(|e| fail(format!("Modelo dañado: {e}")))?;
    }
    Ok(())
}
