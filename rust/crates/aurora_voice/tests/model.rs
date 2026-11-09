//! Instalación del modelo desde un ZIP: raíz quitada, rutas peligrosas
//! rechazadas y nada a medias si falla.

use std::fs::File;
use std::io::Write;
use std::path::Path;

use aurora_voice::{install_model, model_is_installed};
use zip::write::SimpleFileOptions;

fn build(path: &Path, entries: &[(&str, &[u8])]) {
    let mut zip = zip::ZipWriter::new(File::create(path).unwrap());
    for (name, data) in entries {
        zip.start_file(*name, SimpleFileOptions::default()).unwrap();
        zip.write_all(data).unwrap();
    }
    zip.finish().unwrap();
}

#[test]
fn installs_a_vosk_layout_without_its_root_folder() {
    let dir = tempfile::tempdir().unwrap();
    let zip = dir.path().join("m.zip");
    build(
        &zip,
        &[
            ("vosk-model-x/am/final.mdl", b"mdl"),
            ("vosk-model-x/conf/model.conf", b"conf"),
            ("vosk-model-x/graph/Gr.fst", b"fst"),
        ],
    );
    let dest = dir.path().join("voice").join("model");
    install_model(&zip, &dest).unwrap();
    assert!(model_is_installed(&dest));
    assert_eq!(std::fs::read(dest.join("graph/Gr.fst")).unwrap(), b"fst");
    // Reinstalar reemplaza sin dejar restos.
    install_model(&zip, &dest).unwrap();
    let siblings: Vec<_> = std::fs::read_dir(dest.parent().unwrap()).unwrap().collect();
    assert_eq!(siblings.len(), 1);
}

#[test]
fn path_traversal_and_foreign_archives_are_rejected_and_leave_nothing() {
    let dir = tempfile::tempdir().unwrap();
    let dest = dir.path().join("model");
    let evil = dir.path().join("evil.zip");
    build(
        &evil,
        &[
            ("vosk-model-x/am/final.mdl", b"mdl"),
            ("vosk-model-x/conf/model.conf", b"conf"),
            ("vosk-model-x/../../escaped.txt", b"x"),
        ],
    );
    assert!(install_model(&evil, &dest).is_err());
    assert!(!dest.exists());
    assert!(!dir.path().join("escaped.txt").exists());
    assert!(!dir.path().parent().unwrap().join("escaped.txt").exists());

    let foreign = dir.path().join("foreign.zip");
    build(&foreign, &[("otra/cosa.txt", b"hola")]);
    assert!(install_model(&foreign, &dest).is_err());
    assert!(!dest.exists());
    let leftovers: Vec<_> = std::fs::read_dir(dir.path())
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.starts_with('.'))
        .collect();
    assert!(leftovers.is_empty(), "{leftovers:?}");

    let broken = dir.path().join("broken.zip");
    std::fs::write(&broken, b"no soy un zip").unwrap();
    assert!(install_model(&broken, &dest).is_err());
}
