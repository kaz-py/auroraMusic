//! Micrófono real. Ignorada por defecto: necesita un micrófono, `libvosk` y el
//! modelo. `AURORA_VOSK_LIB=… AURORA_VOSK_MODEL=… cargo test -p aurora_voice
//! --release --test device -- --ignored --nocapture`

use std::path::PathBuf;
use std::thread::sleep;
use std::time::Duration;

use aurora_voice::Listener;

#[test]
#[ignore = "necesita micrófono, libvosk y el modelo"]
fn the_real_microphone_opens_streams_audio_and_closes() {
    let lib = PathBuf::from(std::env::var_os("AURORA_VOSK_LIB").expect("AURORA_VOSK_LIB"));
    let model = PathBuf::from(std::env::var_os("AURORA_VOSK_MODEL").expect("AURORA_VOSK_MODEL"));
    let started = std::time::Instant::now();
    let mut listener = Listener::start(&lib, &model).expect("iniciar la escucha");
    println!("listo en {:?}", started.elapsed());
    let mut peak = 0.0f32;
    for _ in 0..30 {
        sleep(Duration::from_millis(100));
        peak = peak.max(listener.level());
    }
    println!(
        "nivel máximo en 3 s: {peak:.4}; eventos: {:?}",
        listener.poll()
    );
    assert!(listener.is_running());
    listener.stop();
    assert!(!listener.is_running());
}
