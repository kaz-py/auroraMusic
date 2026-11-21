//! Pruebas de oro: entradas y salidas volcadas desde `lib/audio/eq_dsp.dart` y
//! `lib/audio/audio_math.dart` (v1.4.0) con `test/zz_gen_audio_golden_test.dart`
//! (generador ya eliminado).

use std::fs;
use std::path::PathBuf;

use aurora_audio::{
    is_complete_audio_stream, spectrum_bars, EqBand, ParametricEqualizer, StreamState,
};
use serde::Deserialize;

#[derive(Deserialize)]
struct Golden {
    eq: Vec<EqScenario>,
    spectrum: Vec<SpectrumCase>,
    complete: Vec<CompleteCase>,
}

#[derive(Deserialize)]
struct EqScenario {
    name: String,
    channels: usize,
    time_constant_ms: f64,
    steps: Vec<Step>,
}

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case")]
enum Step {
    Configure {
        enabled: bool,
        bands: Vec<[f64; 3]>,
        preamp: f64,
        idle: bool,
    },
    Process {
        input: Vec<f64>,
        specials: Vec<(usize, String)>,
        output: Vec<f64>,
        idle: bool,
    },
}

#[derive(Deserialize)]
struct SpectrumCase {
    input: Vec<f64>,
    specials: Vec<(usize, String)>,
    output: Vec<f64>,
}

#[derive(Deserialize)]
struct CompleteCase {
    is_playing: bool,
    is_buffering: bool,
    clean_eof: bool,
    decoded_us: i64,
    consumed_us: i64,
    expected_us: i64,
    result: bool,
}

fn golden() -> Golden {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/golden.json");
    serde_json::from_str(&fs::read_to_string(path).unwrap()).unwrap()
}

fn apply_specials(values: &mut [f64], specials: &[(usize, String)]) {
    for (index, kind) in specials {
        values[*index] = match kind.as_str() {
            "nan" => f64::NAN,
            "inf" => f64::INFINITY,
            "-inf" => f64::NEG_INFINITY,
            other => panic!("especial desconocido {other}"),
        };
    }
}

#[test]
fn equalizer_matches_the_dart_implementation() {
    let golden = golden();
    assert!(golden.eq.len() >= 9);
    for scenario in &golden.eq {
        let mut eq =
            ParametricEqualizer::new(48000.0, scenario.channels, scenario.time_constant_ms);
        let (mut samples, mut exact, mut worst) = (0usize, 0usize, 0.0f64);
        for (n, step) in scenario.steps.iter().enumerate() {
            let label = format!("{} paso {n}", scenario.name);
            match step {
                Step::Configure {
                    enabled,
                    bands,
                    preamp,
                    idle,
                } => {
                    let bands: Vec<EqBand> = bands
                        .iter()
                        .map(|b| EqBand {
                            frequency: b[0],
                            gain_db: b[1],
                            q: b[2],
                        })
                        .collect();
                    eq.configure(*enabled, &bands, *preamp);
                    assert_eq!(eq.is_idle(), *idle, "{label}: idle");
                }
                Step::Process {
                    input,
                    specials,
                    output,
                    idle,
                } => {
                    let mut values = input.clone();
                    apply_specials(&mut values, specials);
                    let mut pcm: Vec<f32> = values.iter().map(|&v| v as f32).collect();
                    eq.process(&mut pcm);
                    assert_eq!(eq.is_idle(), *idle, "{label}: idle");
                    assert_eq!(pcm.len(), output.len(), "{label}: length");
                    for (i, (got, want)) in pcm.iter().zip(output).enumerate() {
                        let want32 = *want as f32;
                        samples += 1;
                        exact += (got.to_bits() == want32.to_bits()) as usize;
                        let diff = (*got as f64 - *want).abs();
                        worst = worst.max(diff);
                        assert!(diff <= 2e-6, "{label}[{i}]: {got} vs {want}");
                    }
                }
            }
        }
        println!(
            "{}: {samples} muestras, {:.4}% idénticas bit a bit, error máximo {worst:.3e}",
            scenario.name,
            100.0 * exact as f64 / samples.max(1) as f64
        );
    }
}

#[test]
fn spectrum_bars_match_the_dart_implementation() {
    let golden = golden();
    assert!(golden.spectrum.len() >= 9);
    for (n, case) in golden.spectrum.iter().enumerate() {
        let mut input = case.input.clone();
        apply_specials(&mut input, &case.specials);
        let bars = spectrum_bars(&input);
        assert_eq!(bars.len(), case.output.len(), "caso {n}");
        for (i, (got, want)) in bars.iter().zip(&case.output).enumerate() {
            assert!(
                (got - want).abs() < 1e-12,
                "caso {n} barra {i}: {got} vs {want}"
            );
        }
    }
}

#[test]
fn stream_completion_matches_the_dart_implementation() {
    let golden = golden();
    assert!(golden.complete.len() >= 1000);
    for case in &golden.complete {
        let state = StreamState {
            is_playing: case.is_playing,
            is_buffering: case.is_buffering,
            clean_eof: case.clean_eof,
            decoded_us: case.decoded_us,
            consumed_us: case.consumed_us,
            expected_us: case.expected_us,
        };
        assert_eq!(is_complete_audio_stream(&state), case.result, "{state:?}");
    }
}
