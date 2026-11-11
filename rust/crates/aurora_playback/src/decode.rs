//! Decodificación a PCM `f32` estéreo entrelazado a la frecuencia de salida.
//!
//! Symphonia aporta los contenedores (MP3, FLAC, WAV, OGG, MP4/M4A, MKV/WebM) y
//! los códecs (MP3, FLAC, Vorbis, AAC-LC, ALAC, PCM). Opus, que Symphonia no
//! decodifica, va por libopus (`crate::opus`) con la sincronización de
//! `OpusHead` (pre-skip y ganancia). Lo que no se reconoce devuelve
//! [`OpenError::Unsupported`] para que el llamador use el motor anterior.

use std::io;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::opus::{OpusDec, MAX_FRAME};
use rubato::{FftFixedIn, Resampler};
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{
    Decoder, DecoderOptions, CODEC_TYPE_AAC, CODEC_TYPE_NULL, CODEC_TYPE_OPUS,
};
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo};
use symphonia::core::io::{MediaSource, MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;
use symphonia::core::units::Time;

const RESAMPLER_CHUNK: usize = 1024;
/// Opus necesita unos 80 ms de rodaje tras un salto para converger.
const OPUS_PREROLL_SECS: f64 = 0.080;

#[derive(Debug)]
pub enum OpenError {
    /// Formato, códec o transporte que este motor no maneja (usar el anterior).
    Unsupported(String),
    /// El origen existe pero falló (red, archivo corrupto).
    Failed(String),
}

impl std::fmt::Display for OpenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OpenError::Unsupported(m) => write!(f, "unsupported: {m}"),
            OpenError::Failed(m) => f.write_str(m),
        }
    }
}

impl std::error::Error for OpenError {}

enum Codec {
    Symphonia(Box<dyn Decoder>),
    Opus {
        decoder: Box<OpusDec>,
        channels: usize,
        /// Muestras (a 48 kHz) que hay que descartar al principio.
        pre_skip: usize,
        gain: f32,
    },
}

struct Converter {
    resampler: Option<FftFixedIn<f32>>,
    /// Entrada pendiente por canal hasta completar un trozo.
    pending: [Vec<f32>; 2],
    /// Muestras de retardo del remuestreador que aún hay que descartar.
    delay_left: usize,
}

impl Converter {
    fn new(from: u32, to: u32) -> Result<Self, OpenError> {
        let resampler = if from == to {
            None
        } else {
            Some(
                FftFixedIn::<f32>::new(from as usize, to as usize, RESAMPLER_CHUNK, 2, 2)
                    .map_err(|e| OpenError::Failed(format!("remuestreador: {e}")))?,
            )
        };
        let delay_left = resampler.as_ref().map_or(0, |r| r.output_delay());
        Ok(Self {
            resampler,
            pending: [Vec::new(), Vec::new()],
            delay_left,
        })
    }

    fn run_chunks(&mut self, out: &mut Vec<f32>, flush: bool) -> Result<(), OpenError> {
        let Some(resampler) = self.resampler.as_mut() else {
            return Ok(());
        };
        loop {
            let need = resampler.input_frames_next();
            let have = self.pending[0].len();
            let chunk: Vec<Vec<f32>> = if have >= need {
                self.pending
                    .iter_mut()
                    .map(|p| p.drain(..need).collect())
                    .collect()
            } else if flush && have > 0 {
                let result = resampler
                    .process_partial(
                        Some(&[self.pending[0].as_slice(), self.pending[1].as_slice()]),
                        None,
                    )
                    .map_err(|e| OpenError::Failed(format!("remuestreo: {e}")))?;
                self.pending.iter_mut().for_each(Vec::clear);
                push_planar(&result, &mut self.delay_left, out);
                return Ok(());
            } else {
                return Ok(());
            };
            let result = resampler
                .process(&chunk, None)
                .map_err(|e| OpenError::Failed(format!("remuestreo: {e}")))?;
            push_planar(&result, &mut self.delay_left, out);
        }
    }

    /// Entrada intercalada estéreo; salida intercalada estéreo.
    fn push(&mut self, stereo: &[f32], out: &mut Vec<f32>) -> Result<(), OpenError> {
        if self.resampler.is_none() {
            out.extend_from_slice(stereo);
            return Ok(());
        }
        for frame in stereo.chunks_exact(2) {
            self.pending[0].push(frame[0]);
            self.pending[1].push(frame[1]);
        }
        self.run_chunks(out, false)
    }

    fn finish(&mut self, out: &mut Vec<f32>) -> Result<(), OpenError> {
        if self.resampler.is_some() {
            self.run_chunks(out, true)?;
            // Rellena con silencio para expulsar la cola del filtro.
            if let Some(r) = self.resampler.as_mut() {
                let silence = vec![vec![0.0f32; RESAMPLER_CHUNK]; 2];
                let tail = r.output_delay();
                let mut produced = Vec::new();
                let result = r
                    .process(&silence, None)
                    .map_err(|e| OpenError::Failed(format!("remuestreo: {e}")))?;
                push_planar(&result, &mut 0, &mut produced);
                produced.truncate(tail * 2);
                out.extend_from_slice(&produced);
            }
        }
        Ok(())
    }

    fn reset(&mut self) {
        if let Some(r) = self.resampler.as_mut() {
            r.reset();
            self.delay_left = r.output_delay();
        }
        self.pending.iter_mut().for_each(Vec::clear);
    }
}

fn push_planar(planar: &[Vec<f32>], delay_left: &mut usize, out: &mut Vec<f32>) {
    let frames = planar[0].len();
    let skip = (*delay_left).min(frames);
    *delay_left -= skip;
    for (left, right) in planar[0][skip..frames].iter().zip(&planar[1][skip..frames]) {
        out.push(*left);
        out.push(*right);
    }
}

/// Origen ya decodificado a estéreo `f32` a `out_rate`.
pub struct PcmStream {
    format: Box<dyn FormatReader>,
    codec: Codec,
    track_id: u32,
    src_rate: u32,
    out_rate: u32,
    time_base: Option<symphonia::core::units::TimeBase>,
    converter: Converter,
    scratch: Option<SampleBuffer<f32>>,
    /// Descartar el audio anterior a este instante (tras un salto).
    skip_until: Option<f64>,
    broken: Option<Arc<AtomicBool>>,
    duration_secs: Option<f64>,
    strict: bool,
    finished: bool,
}

fn to_stereo(interleaved: &[f32], channels: usize, out: &mut Vec<f32>) {
    match channels {
        0 => {}
        1 => out.extend(interleaved.iter().flat_map(|&s| [s, s])),
        2 => out.extend_from_slice(interleaved),
        n => {
            // Mezcla simple: frontales L/R más el centro (si hay) a -3 dB.
            for frame in interleaved.chunks_exact(n) {
                let center = if n >= 3 { frame[2] * 0.707 } else { 0.0 };
                out.push(frame[0] + center);
                out.push(frame[1] + center);
            }
        }
    }
}

fn opus_head(extra: &[u8]) -> Option<(usize, usize, f32)> {
    if extra.len() < 19 || &extra[..8] != b"OpusHead" {
        return None;
    }
    let channels = extra[9] as usize;
    let pre_skip = u16::from_le_bytes([extra[10], extra[11]]) as usize;
    let gain_q8 = i16::from_le_bytes([extra[16], extra[17]]) as f32;
    if extra[18] != 0 && channels > 2 {
        return None;
    }
    Some((channels, pre_skip, 10f32.powf(gain_q8 / (20.0 * 256.0))))
}

impl PcmStream {
    pub fn open(
        source: Box<dyn MediaSource>,
        extension: Option<&str>,
        out_rate: u32,
        start_secs: f64,
        broken: Option<Arc<AtomicBool>>,
    ) -> Result<Self, OpenError> {
        Self::open_inner(source, extension, Some(out_rate), start_secs, broken, false)
    }

    /// Sin remuestrear y con decodificación estricta (cualquier paquete que no
    /// se decodifique es un error): para validar archivos descargados.
    pub fn open_strict(
        source: Box<dyn MediaSource>,
        extension: Option<&str>,
    ) -> Result<Self, OpenError> {
        Self::open_inner(source, extension, None, 0.0, None, true)
    }

    fn open_inner(
        source: Box<dyn MediaSource>,
        extension: Option<&str>,
        out_rate: Option<u32>,
        start_secs: f64,
        broken: Option<Arc<AtomicBool>>,
        strict: bool,
    ) -> Result<Self, OpenError> {
        let mss = MediaSourceStream::new(source, MediaSourceStreamOptions::default());
        let mut hint = Hint::new();
        if let Some(ext) = extension {
            hint.with_extension(ext);
        }
        let probed = symphonia::default::get_probe()
            .format(
                &hint,
                mss,
                &FormatOptions {
                    enable_gapless: true,
                    ..Default::default()
                },
                &MetadataOptions::default(),
            )
            .map_err(|e| match e {
                SymError::Unsupported(m) => OpenError::Unsupported(m.to_string()),
                SymError::IoError(io) => OpenError::Failed(io.to_string()),
                other => OpenError::Unsupported(other.to_string()),
            })?;
        let format = probed.format;
        let track = format
            .tracks()
            .iter()
            .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
            .ok_or_else(|| OpenError::Unsupported("sin pista de audio".into()))?;
        let track_id = track.id;
        let params = track.codec_params.clone();
        let time_base = params.time_base;
        let duration_secs = match (params.n_frames, time_base) {
            (Some(n), Some(tb)) => {
                let t = tb.calc_time(n);
                Some(t.seconds as f64 + t.frac)
            }
            _ => None,
        };
        let (codec, src_rate) = if params.codec == CODEC_TYPE_OPUS {
            let extra = params
                .extra_data
                .as_deref()
                .ok_or_else(|| OpenError::Unsupported("Opus sin OpusHead".into()))?;
            let (channels, pre_skip, gain) = opus_head(extra)
                .ok_or_else(|| OpenError::Unsupported("OpusHead no admitido".into()))?;
            let decoder = OpusDec::new(channels.clamp(1, 2))
                .map_err(|e| OpenError::Unsupported(format!("Opus: {e:?}")))?;
            (
                Codec::Opus {
                    decoder: Box::new(decoder),
                    channels: channels.clamp(1, 2),
                    pre_skip,
                    gain,
                },
                48_000,
            )
        } else {
            // HE-AAC (SBR/PS): Symphonia solo decodifica AAC-LC y sonaría a la mitad de frecuencia.
            if params.codec == CODEC_TYPE_AAC {
                let object_type = params
                    .extra_data
                    .as_deref()
                    .and_then(|e| e.first())
                    .map(|b| b >> 3);
                if matches!(object_type, Some(5 | 29)) {
                    return Err(OpenError::Unsupported("HE-AAC".into()));
                }
            }
            let decoder = symphonia::default::get_codecs()
                .make(&params, &DecoderOptions::default())
                .map_err(|e| OpenError::Unsupported(e.to_string()))?;
            let rate = params
                .sample_rate
                .ok_or_else(|| OpenError::Unsupported("frecuencia desconocida".into()))?;
            (Codec::Symphonia(decoder), rate)
        };
        let out_rate = out_rate.unwrap_or(src_rate);
        let converter = Converter::new(src_rate, out_rate)?;
        let mut stream = Self {
            format,
            codec,
            track_id,
            src_rate,
            out_rate,
            time_base,
            converter,
            scratch: None,
            skip_until: None,
            broken,
            duration_secs,
            strict,
            finished: false,
        };
        if start_secs > 0.0 {
            stream.seek(start_secs)?;
        }
        Ok(stream)
    }

    pub fn duration_secs(&self) -> Option<f64> {
        self.duration_secs
    }

    /// Duración sumando la de los paquetes (sin decodificar), para contenedores
    /// que no la declaran. `None` si no hay base de tiempo o no suman nada.
    pub fn scan_duration(&mut self) -> Option<f64> {
        let time_base = self.time_base?;
        let mut total = 0u64;
        while let Ok(packet) = self.format.next_packet() {
            if packet.track_id() == self.track_id {
                total += packet.dur;
            }
        }
        if total == 0 {
            return None;
        }
        let time = time_base.calc_time(total);
        Some(time.seconds as f64 + time.frac)
    }

    pub fn out_rate(&self) -> u32 {
        self.out_rate
    }

    fn seek(&mut self, secs: f64) -> Result<(), OpenError> {
        let preroll = if matches!(self.codec, Codec::Opus { .. }) {
            OPUS_PREROLL_SECS
        } else {
            0.0
        };
        let landing = (secs - preroll).max(0.0);
        let to = SeekTo::Time {
            time: Time::from(landing),
            track_id: Some(self.track_id),
        };
        match self.format.seek(SeekMode::Accurate, to) {
            Ok(seeked) => {
                let _ = seeked;
                self.after_seek(secs);
                Ok(())
            }
            Err(e) => Err(OpenError::Failed(format!("no se pudo saltar: {e}"))),
        }
    }

    fn after_seek(&mut self, target_secs: f64) {
        match &mut self.codec {
            Codec::Symphonia(d) => d.reset(),
            Codec::Opus {
                decoder, pre_skip, ..
            } => {
                decoder.reset();
                *pre_skip = 0;
            }
        }
        self.converter.reset();
        self.skip_until = Some(target_secs);
    }

    /// Añade a `out` el siguiente trozo (estéreo intercalado a `out_rate`).
    /// `Ok(false)` = fin del flujo (`finished` queda activado).
    pub fn next_chunk(&mut self, out: &mut Vec<f32>) -> Result<bool, OpenError> {
        if self.finished {
            return Ok(false);
        }
        loop {
            let packet = match self.format.next_packet() {
                Ok(p) => p,
                Err(SymError::IoError(e)) if e.kind() == io::ErrorKind::UnexpectedEof => {
                    if self
                        .broken
                        .as_ref()
                        .is_some_and(|b| b.load(Ordering::Relaxed))
                    {
                        return Err(OpenError::Failed(
                            "la conexión se cortó antes de terminar".into(),
                        ));
                    }
                    self.finished = true;
                    self.converter.finish(out)?;
                    return Ok(!out.is_empty());
                }
                Err(SymError::ResetRequired) => {
                    self.finished = true;
                    return Ok(false);
                }
                Err(SymError::IoError(e)) => return Err(OpenError::Failed(e.to_string())),
                Err(e) => return Err(OpenError::Failed(e.to_string())),
            };
            if packet.track_id() != self.track_id {
                continue;
            }
            let packet_secs = self.time_base.map(|tb| {
                let t = tb.calc_time(packet.ts());
                t.seconds as f64 + t.frac
            });
            let strict = self.strict;
            let mut stereo = Vec::new();
            let frames_start_secs = packet_secs;
            match &mut self.codec {
                Codec::Symphonia(decoder) => match decoder.decode(&packet) {
                    Ok(buffer) => {
                        let spec = *buffer.spec();
                        let scratch = self.scratch.get_or_insert_with(|| {
                            SampleBuffer::<f32>::new(buffer.capacity() as u64, spec)
                        });
                        if (scratch.capacity() as u64)
                            < buffer.capacity() as u64 * spec.channels.count() as u64
                        {
                            *scratch = SampleBuffer::<f32>::new(buffer.capacity() as u64, spec);
                        }
                        scratch.copy_interleaved_ref(buffer);
                        to_stereo(scratch.samples(), spec.channels.count(), &mut stereo);
                    }
                    Err(SymError::DecodeError(message)) => {
                        if strict {
                            return Err(OpenError::Failed(format!("paquete dañado: {message}")));
                        }
                        continue;
                    }
                    Err(e) => return Err(OpenError::Failed(e.to_string())),
                },
                Codec::Opus {
                    decoder,
                    channels,
                    pre_skip,
                    gain,
                } => {
                    let mut pcm = vec![0f32; MAX_FRAME * *channels];
                    let frames = match decoder.decode_float(&packet.data, &mut pcm) {
                        Ok(n) => n,
                        Err(e) => {
                            if strict {
                                return Err(OpenError::Failed(format!(
                                    "paquete Opus dañado: {e:?}"
                                )));
                            }
                            continue;
                        }
                    };
                    let mut samples = &mut pcm[..frames * *channels];
                    if (*gain - 1.0).abs() > 1e-6 {
                        samples.iter_mut().for_each(|s| *s *= *gain);
                    }
                    if *pre_skip > 0 {
                        let drop = (*pre_skip).min(frames);
                        *pre_skip -= drop;
                        samples = &mut samples[drop * *channels..];
                    }
                    to_stereo(samples, *channels, &mut stereo);
                }
            }
            // Descarta lo anterior al punto pedido tras un salto.
            if let Some(target) = self.skip_until {
                let frames = stereo.len() / 2;
                let start = frames_start_secs.unwrap_or(target);
                let end = start + frames as f64 / self.src_rate as f64;
                if end <= target {
                    continue;
                }
                let drop =
                    (((target - start) * self.src_rate as f64).max(0.0) as usize).min(frames);
                stereo.drain(..drop * 2);
                self.skip_until = None;
            }
            if stereo.is_empty() {
                continue;
            }
            self.converter.push(&stereo, out)?;
            if !out.is_empty() {
                return Ok(true);
            }
        }
    }
}
