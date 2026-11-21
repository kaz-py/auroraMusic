pub const SPECTRUM_BARS: usize = 48;

/// Barras de frecuencia logarítmica a partir de los primeros 256 bins de la FFT
/// del mezclador. Con menos de 256 bins devuelve 48 ceros; los bins no finitos
/// se ignoran.
pub fn spectrum_bars(fft: &[f64]) -> Vec<f64> {
    if fft.len() < 256 {
        return vec![0.0; SPECTRUM_BARS];
    }
    (0..SPECTRUM_BARS)
        .map(|index| {
            let lo = (256f64.powf(index as f64 / 48.0).floor() as usize).min(255);
            let hi = (lo + 1)
                .max(256f64.powf((index + 1) as f64 / 48.0).floor() as usize)
                .clamp(1, 256);
            let mut peak = 0.0f64;
            for &value in &fft[lo..hi] {
                if value.is_finite() {
                    peak = peak.max(value);
                }
            }
            ((1.0 + peak * 30.0).ln() / 31f64.ln()).clamp(0.0, 1.0)
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_input_and_silence_are_zero() {
        assert_eq!(spectrum_bars(&[1.0; 255]), vec![0.0; 48]);
        assert_eq!(spectrum_bars(&[0.0; 256]), vec![0.0; 48]);
    }

    #[test]
    fn non_finite_bins_are_ignored_and_values_are_bounded() {
        let mut fft = vec![0.0; 256];
        fft[3] = f64::INFINITY;
        fft[10] = f64::NAN;
        fft[250] = 5.0;
        let bars = spectrum_bars(&fft);
        assert!(bars.iter().all(|b| (0.0..=1.0).contains(b)));
        assert_eq!(bars[0], 0.0);
        assert_eq!(bars[47], 1.0);
    }
}
