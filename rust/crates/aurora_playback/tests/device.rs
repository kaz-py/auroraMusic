//! Prueba con el dispositivo de salida real, en silencio (volumen 0): comprueba
//! que la devolución de llamada corre en tiempo real y avanza la posición.
//! `cargo test -p aurora_playback --release --test device -- --ignored --nocapture`

use std::path::PathBuf;
use std::thread::sleep;
use std::time::{Duration, Instant};

use aurora_playback::{Engine, LoadSpec};

#[test]
#[ignore]
fn real_output_runs_in_real_time_while_muted() {
    let engine = Engine::new().expect("dispositivo de salida");
    println!("frecuencia de salida: {} Hz", engine.sample_rate());
    engine.set_volume(0.0);
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../aurora_audio/tests/fixtures/media/tone-opus.webm");
    engine
        .load(&LoadSpec {
            input: path.to_string_lossy().into_owned(),
            headers: vec![],
            start_secs: 0.0,
        })
        .unwrap();
    engine.play();
    let started = Instant::now();
    sleep(Duration::from_millis(1000));
    let state = engine.state();
    let wall = started.elapsed().as_secs_f64();
    let played = state.consumed_us as f64 / 1e6;
    println!("tiempo real {wall:.3} s, reproducido {played:.3} s, estado {state:?}");
    assert!(
        (played - wall).abs() < 0.25,
        "la salida no va en tiempo real"
    );
    // Termina solo y avisa.
    let deadline = Instant::now() + Duration::from_secs(5);
    while !engine.state().ended && Instant::now() < deadline {
        sleep(Duration::from_millis(20));
    }
    assert!(engine.state().ended, "{:?}", engine.state());
    let total = engine.state().consumed_us as f64 / 1e6;
    println!("duración reproducida {total:.3} s");
    assert!((total - 2.0).abs() < 0.1);
}
