//! Ecualizador paramétrico estéreo de 8 bandas peaking (RBJ, forma
//! transpuesta II) sobre PCM `f32` entrelazado. Port de `ParametricEqualizer`
//! (`lib/audio/eq_dsp.dart`): el orden de las operaciones en coma flotante es
//! parte del contrato.

pub const BAND_COUNT: usize = 8;
/// Muestras entre actualizaciones de la rampa de parámetros.
pub const BLOCK_FRAMES: usize = 32;
/// Limitador de codo suave: lineal hasta este nivel y asintótico a 1.
pub const LIMITER_KNEE: f64 = 0.95;
pub const DEFAULT_FREQUENCIES: [f64; BAND_COUNT] =
    [60.0, 170.0, 310.0, 600.0, 1000.0, 3000.0, 6000.0, 12000.0];

/// Una banda ya acotada por el llamador (frecuencia, ganancia en dB y Q).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EqBand {
    pub frequency: f64,
    pub gain_db: f64,
    pub q: f64,
}

impl EqBand {
    fn flat(index: usize) -> Self {
        Self {
            frequency: DEFAULT_FREQUENCIES[index],
            gain_db: 0.0,
            q: 1.0,
        }
    }
}

/// Coeficientes biquad normalizados (a0 = 1) de un filtro peaking RBJ.
/// Orden: b0, b1, b2, a1, a2.
pub fn peaking_coefficients(sample_rate: f64, frequency: f64, gain_db: f64, q: f64) -> [f64; 5] {
    let a = 10f64.powf(gain_db / 40.0);
    // Por debajo de Nyquist, o el seno/coseno degeneran.
    let f = frequency.clamp(1.0, sample_rate * 0.49);
    let w0 = 2.0 * std::f64::consts::PI * f / sample_rate;
    let alpha = w0.sin() / (2.0 * q);
    let cos_w = w0.cos();
    let a0 = 1.0 + alpha / a;
    [
        (1.0 + alpha * a) / a0,
        -2.0 * cos_w / a0,
        (1.0 - alpha * a) / a0,
        -2.0 * cos_w / a0,
        (1.0 - alpha / a) / a0,
    ]
}

fn tanh(x: f64) -> f64 {
    if x > 20.0 {
        return 1.0;
    }
    let e = (2.0 * x).exp();
    (e - 1.0) / (e + 1.0)
}

/// Limitador de codo suave: ningún pico supera la escala completa ni se
/// recorta en duro.
pub fn soft_limit(x: f64) -> f64 {
    let a = x.abs();
    if a <= LIMITER_KNEE {
        return x;
    }
    let room = 1.0 - LIMITER_KNEE;
    let y = LIMITER_KNEE + room * tanh((a - LIMITER_KNEE) / room);
    if x < 0.0 {
        -y
    } else {
        y
    }
}

struct Band {
    // Frecuencia y Q se interpolan en el dominio logarítmico, la ganancia en dB.
    f: f64,
    tf: f64,
    g: f64,
    tg: f64,
    q: f64,
    tq: f64,
    configured: bool,
    s1: Vec<f64>,
    s2: Vec<f64>,
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
    active: bool,
    dirty: bool,
}

impl Band {
    fn new(frequency: f64, channels: usize) -> Self {
        Self {
            f: frequency.ln(),
            tf: frequency.ln(),
            g: 0.0,
            tg: 0.0,
            q: 0.0,
            tq: 0.0,
            configured: false,
            s1: vec![0.0; channels],
            s2: vec![0.0; channels],
            b0: 1.0,
            b1: 0.0,
            b2: 0.0,
            a1: 0.0,
            a2: 0.0,
            active: false,
            dirty: false,
        }
    }

    fn set_target(&mut self, band: EqBand) {
        self.tf = band.frequency.ln();
        self.tg = band.gain_db;
        self.tq = band.q.ln();
        // La primera vez la Q parte directamente del objetivo.
        if !self.configured {
            self.q = self.tq;
        }
        self.configured = true;
    }

    fn reset(&mut self) {
        self.s1.fill(0.0);
        self.s2.fill(0.0);
    }

    fn step(current: f64, target: f64, k: f64, snap: f64) -> f64 {
        let next = current + (target - current) * k;
        if (next - target).abs() < snap {
            target
        } else {
            next
        }
    }

    fn advance(&mut self, k: f64, sample_rate: f64) {
        if self.f != self.tf || self.g != self.tg || self.q != self.tq || self.dirty {
            self.f = Self::step(self.f, self.tf, k, 1e-4);
            self.g = Self::step(self.g, self.tg, k, 1e-3);
            self.q = Self::step(self.q, self.tq, k, 1e-4);
            let c = peaking_coefficients(sample_rate, self.f.exp(), self.g, self.q.exp());
            self.b0 = c[0];
            self.b1 = c[1];
            self.b2 = c[2];
            self.a1 = c[3];
            self.a2 = c[4];
            self.dirty = self.f != self.tf || self.g != self.tg || self.q != self.tq;
            // Una banda a 0 dB es la identidad: se salta y su estado se descarta.
            let was_active = self.active;
            self.active = self.g != 0.0 || self.dirty;
            if was_active && !self.active {
                self.reset();
            }
        }
    }

    #[inline]
    fn run(&mut self, ch: usize, x: f64) -> f64 {
        let y = self.b0 * x + self.s1[ch];
        self.s1[ch] = self.b1 * x - self.a1 * y + self.s2[ch];
        self.s2[ch] = self.b2 * x - self.a2 * y;
        y
    }
}

/// Todo cambio (ganancia, frecuencia, Q, activación, preamp) se acerca al
/// objetivo con una rampa exponencial de unos `time_constant_ms`, actualizada
/// cada [`BLOCK_FRAMES`] tramas, para que mover un deslizador no produzca clics
/// ni saltos de volumen. Con el EQ apagado y la rampa terminada, `process` no
/// toca el audio.
pub struct ParametricEqualizer {
    sample_rate: f64,
    channels: usize,
    smoothing: f64,
    bands: Vec<Band>,
    target_enabled: bool,
    target_preamp: f64,
    mix: f64,
    preamp: f64,
}

impl ParametricEqualizer {
    pub fn new(sample_rate: f64, channels: usize, time_constant_ms: f64) -> Self {
        let channels = channels.max(1);
        Self {
            sample_rate,
            channels,
            smoothing: 1.0
                - (-(BLOCK_FRAMES as f64) / (sample_rate * time_constant_ms / 1000.0)).exp(),
            bands: DEFAULT_FREQUENCIES
                .iter()
                .map(|&f| Band::new(f, channels))
                .collect(),
            target_enabled: false,
            target_preamp: 1.0,
            mix: 0.0,
            preamp: 1.0,
        }
    }

    /// El EQ no modifica el audio y no hay rampa pendiente.
    pub fn is_idle(&self) -> bool {
        !self.target_enabled && self.mix == 0.0
    }

    /// `bands` puede traer menos de 8 (las que falten quedan planas).
    /// `target_preamp` es la ganancia lineal de compensación ya calculada por
    /// quien conoce la curva (1 si no hay compensación).
    pub fn configure(&mut self, enabled: bool, bands: &[EqBand], target_preamp: f64) {
        // Un EQ que estaba apagado no arrastra el estado de audio antiguo.
        if self.is_idle() && enabled {
            for band in &mut self.bands {
                band.reset();
            }
        }
        self.target_enabled = enabled;
        for (i, band) in self.bands.iter_mut().enumerate() {
            band.set_target(bands.get(i).copied().unwrap_or_else(|| EqBand::flat(i)));
        }
        self.target_preamp = target_preamp;
    }

    /// Procesa `pcm` en el sitio. Las muestras no finitas se tratan como silencio.
    pub fn process(&mut self, pcm: &mut [f32]) {
        if self.is_idle() {
            return;
        }
        let channels = self.channels;
        let frames = pcm.len() / channels;
        let mut start = 0;
        while start < frames {
            let end = (start + BLOCK_FRAMES).min(frames);
            self.advance();
            if self.mix == 0.0 && !self.target_enabled {
                start += BLOCK_FRAMES;
                continue;
            }
            for ch in 0..channels {
                for n in start..end {
                    let index = n * channels + ch;
                    let sample = pcm[index] as f64;
                    let dry = if sample.is_finite() { sample } else { 0.0 };
                    let mut wet = dry;
                    for band in &mut self.bands {
                        if band.active {
                            wet = band.run(ch, wet);
                        }
                    }
                    if !wet.is_finite() {
                        for band in &mut self.bands {
                            band.reset();
                        }
                        wet = dry;
                    }
                    pcm[index] = soft_limit(dry + (wet * self.preamp - dry) * self.mix) as f32;
                }
            }
            start += BLOCK_FRAMES;
        }
    }

    fn advance(&mut self) {
        for band in &mut self.bands {
            band.advance(self.smoothing, self.sample_rate);
        }
        self.mix = self.approach(self.mix, if self.target_enabled { 1.0 } else { 0.0 });
        self.preamp = self.approach(self.preamp, self.target_preamp);
    }

    fn approach(&self, current: f64, target: f64) -> f64 {
        let next = current + (target - current) * self.smoothing;
        if (next - target).abs() < 1e-5 {
            target
        } else {
            next
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_db_peaking_filter_is_the_identity() {
        let c = peaking_coefficients(48000.0, 1000.0, 0.0, 1.0);
        assert!((c[0] - 1.0).abs() < 1e-12);
        assert!((c[1] - c[3]).abs() < 1e-12);
        assert!((c[2] - c[4]).abs() < 1e-12);
    }

    #[test]
    fn soft_limit_is_identity_below_the_knee_odd_and_bounded() {
        assert_eq!(soft_limit(0.5), 0.5);
        assert_eq!(soft_limit(-0.9), -0.9);
        let mut previous = soft_limit(0.95);
        let mut x = 0.96;
        while x < 30.0 {
            let y = soft_limit(x);
            assert!(y >= previous && y <= 1.0, "{x}");
            assert_eq!(soft_limit(-x), -y);
            previous = y;
            x += 0.37;
        }
        assert_eq!(soft_limit(1e9), 1.0);
    }

    #[test]
    fn idle_equalizer_leaves_audio_untouched_and_a_boost_changes_it() {
        let mut eq = ParametricEqualizer::new(48000.0, 2, 1.5);
        let mut pcm: Vec<f32> = (0..2000).map(|i| (i as f32 * 0.01).sin() * 0.5).collect();
        let original = pcm.clone();
        eq.process(&mut pcm);
        assert_eq!(pcm, original);
        assert!(eq.is_idle());
        let mut bands: Vec<EqBand> = (0..8).map(EqBand::flat).collect();
        bands[4].gain_db = 9.0;
        eq.configure(true, &bands, 0.35);
        assert!(!eq.is_idle());
        eq.process(&mut pcm);
        assert_ne!(pcm, original);
        assert!(pcm.iter().all(|v| v.abs() <= 1.0));
    }

    #[test]
    fn non_finite_input_never_poisons_the_output() {
        let mut eq = ParametricEqualizer::new(48000.0, 2, 1.5);
        let mut bands: Vec<EqBand> = (0..8).map(EqBand::flat).collect();
        bands[4].gain_db = 6.0;
        eq.configure(true, &bands, 1.0);
        let mut pcm = vec![0.1f32; 4000];
        pcm[10] = f32::NAN;
        pcm[501] = f32::INFINITY;
        eq.process(&mut pcm);
        assert!(pcm.iter().all(|v| v.is_finite()));
    }
}
