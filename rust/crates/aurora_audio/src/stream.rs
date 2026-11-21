/// Un mezclador nativo informa del tiempo consumido en `float32`: se permite un
/// bloque de mezcla de 1024 tramas a 48 kHz (unos 21,34 ms) de redondeo.
const MIX_BLOCK_US: i64 = 21_334;
const ONE_SECOND_US: i64 = 1_000_000;

/// Estado observado de un flujo de audio; todas las duraciones en microsegundos.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StreamState {
    pub is_playing: bool,
    pub is_buffering: bool,
    pub clean_eof: bool,
    pub decoded_us: i64,
    pub consumed_us: i64,
    /// Duración esperada; `<= 0` si se desconoce.
    pub expected_us: i64,
}

/// `true` si el flujo terminó de verdad: se oyó todo lo decodificado y lo
/// decodificado cubre la duración esperada (con un segundo de margen).
pub fn is_complete_audio_stream(state: &StreamState) -> bool {
    state.is_playing
        && !state.is_buffering
        && state.clean_eof
        && state.decoded_us > 0
        && state.consumed_us.saturating_add(MIX_BLOCK_US) >= state.decoded_us
        && (state.expected_us <= 0
            || state.decoded_us.saturating_add(ONE_SECOND_US) >= state.expected_us)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn done() -> StreamState {
        StreamState {
            is_playing: true,
            is_buffering: false,
            clean_eof: true,
            decoded_us: 10_000_000,
            consumed_us: 10_000_000,
            expected_us: 10_000_000,
        }
    }

    #[test]
    fn complete_stream_is_accepted_and_each_condition_matters() {
        assert!(is_complete_audio_stream(&done()));
        assert!(!is_complete_audio_stream(&StreamState {
            is_playing: false,
            ..done()
        }));
        assert!(!is_complete_audio_stream(&StreamState {
            is_buffering: true,
            ..done()
        }));
        assert!(!is_complete_audio_stream(&StreamState {
            clean_eof: false,
            ..done()
        }));
        assert!(!is_complete_audio_stream(&StreamState {
            decoded_us: 0,
            consumed_us: 0,
            ..done()
        }));
    }

    #[test]
    fn consumption_tolerance_is_one_mix_block() {
        let at = |gap: i64| StreamState {
            consumed_us: 10_000_000 - gap,
            ..done()
        };
        assert!(is_complete_audio_stream(&at(21_334)));
        assert!(!is_complete_audio_stream(&at(21_335)));
    }

    #[test]
    fn short_streams_are_rejected_unless_duration_is_unknown() {
        let short = |expected: i64| StreamState {
            expected_us: expected,
            ..done()
        };
        assert!(is_complete_audio_stream(&short(11_000_000)));
        assert!(!is_complete_audio_stream(&short(11_000_001)));
        assert!(is_complete_audio_stream(&short(0)));
        assert!(is_complete_audio_stream(&short(-5)));
    }
}
