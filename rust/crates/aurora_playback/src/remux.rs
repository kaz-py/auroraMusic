//! Copia sin pérdida del Opus que descarga yt-dlp (WebM) a un archivo Ogg
//! `.opus`: los paquetes se pasan tal cual, sin decodificar ni volver a
//! codificar, así que el archivo guardado conserva exactamente la calidad que
//! sirve YouTube (un MP3 la degradaría). Sustituye al `-x --audio-format mp3`
//! de FFmpeg.

use std::fs::File;
use std::io::BufWriter;
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};

use ogg::writing::{PacketWriteEndInfo, PacketWriter};
use symphonia::core::codecs::CODEC_TYPE_OPUS;
use symphonia::core::errors::Error as SymError;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::{MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

use crate::decode::OpenError;

const SERIAL: u32 = 0x4155_5241;
/// Un página Ogg por segundo de audio aproximadamente.
const PACKETS_PER_PAGE: u32 = 50;

fn failed(message: impl Into<String>) -> OpenError {
    OpenError::Failed(message.into())
}

/// Muestras a 48 kHz que dura un paquete Opus (RFC 6716, §3.1), leídas de su
/// primer byte (TOC) y, con el código 3, del número de tramas.
fn packet_samples(packet: &[u8]) -> Option<u64> {
    let toc = *packet.first()?;
    let config = toc >> 3;
    let frame = match config {
        0..=11 => [480u64, 960, 1920, 2880][(config % 4) as usize],
        12..=15 => [480u64, 960][(config % 2) as usize],
        _ => [120u64, 240, 480, 960][(config % 4) as usize],
    };
    let frames = match toc & 3 {
        0 => 1,
        1 | 2 => 2,
        _ => (*packet.get(1)? & 0x3F) as u64,
    };
    Some(frame * frames)
}

fn tags() -> Vec<u8> {
    let vendor = b"Aurora";
    let mut out = b"OpusTags".to_vec();
    out.extend_from_slice(&(vendor.len() as u32).to_le_bytes());
    out.extend_from_slice(vendor);
    out.extend_from_slice(&0u32.to_le_bytes());
    out
}

/// Pasa el audio Opus de `src` (WebM/Matroska u Ogg) a `dst` como Ogg Opus.
/// Devuelve la duración en segundos. `progress` recibe milésimas.
pub fn remux_opus_to_ogg(
    src: &Path,
    dst: &Path,
    cancel: &AtomicBool,
    progress: &AtomicU32,
) -> Result<f64, OpenError> {
    let file = File::open(src).map_err(|e| failed(e.to_string()))?;
    let mss = MediaSourceStream::new(Box::new(file), MediaSourceStreamOptions::default());
    let mut hint = Hint::new();
    if let Some(ext) = src.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|e| match e {
            SymError::IoError(io) => failed(io.to_string()),
            other => OpenError::Unsupported(other.to_string()),
        })?;
    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec == CODEC_TYPE_OPUS)
        .ok_or_else(|| OpenError::Unsupported("el archivo no contiene audio Opus".into()))?;
    let track_id = track.id;
    let head = track
        .codec_params
        .extra_data
        .as_deref()
        .filter(|h| h.len() >= 19 && &h[..8] == b"OpusHead" && h[9] <= 2 && h[18] == 0)
        .ok_or_else(|| OpenError::Unsupported("OpusHead no admitido".into()))?
        .to_vec();
    let total_secs = match (track.codec_params.n_frames, track.codec_params.time_base) {
        (Some(n), Some(tb)) => {
            let t = tb.calc_time(n);
            Some(t.seconds as f64 + t.frac)
        }
        _ => None,
    };
    let pre_skip = u16::from_le_bytes([head[10], head[11]]) as u64;

    let out = BufWriter::new(File::create(dst).map_err(|e| failed(e.to_string()))?);
    let mut writer = PacketWriter::new(out);
    let io = |e: std::io::Error| failed(e.to_string());
    writer
        .write_packet(head, SERIAL, PacketWriteEndInfo::EndPage, 0)
        .map_err(io)?;
    writer
        .write_packet(tags(), SERIAL, PacketWriteEndInfo::EndPage, 0)
        .map_err(io)?;

    // Se escribe con un paquete de retraso para marcar el último como fin de flujo.
    let mut pending: Option<(Vec<u8>, u64)> = None;
    let mut granule = pre_skip;
    let mut in_page = 0u32;
    let mut samples = 0u64;
    loop {
        if cancel.load(Ordering::Relaxed) {
            return Err(failed("conversión cancelada"));
        }
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(SymError::IoError(_)) | Err(SymError::ResetRequired) => break,
            Err(e) => return Err(failed(e.to_string())),
        };
        if packet.track_id() != track_id {
            continue;
        }
        let data = packet.data.to_vec();
        let n = packet_samples(&data).ok_or_else(|| failed("paquete Opus inválido"))?;
        if let Some((prev, prev_granule)) = pending.take() {
            in_page += 1;
            let end = if in_page >= PACKETS_PER_PAGE {
                in_page = 0;
                PacketWriteEndInfo::EndPage
            } else {
                PacketWriteEndInfo::NormalPacket
            };
            writer
                .write_packet(prev, SERIAL, end, prev_granule)
                .map_err(io)?;
        }
        granule += n;
        samples += n;
        pending = Some((data, granule));
        if let Some(total) = total_secs.filter(|t| *t > 0.0) {
            let done = (samples as f64 / 48_000.0 / total).clamp(0.0, 1.0);
            progress.store((done * 1000.0) as u32, Ordering::Relaxed);
        }
    }
    let Some((last, last_granule)) = pending else {
        return Err(failed("el archivo no contiene audio"));
    };
    writer
        .write_packet(last, SERIAL, PacketWriteEndInfo::EndStream, last_granule)
        .map_err(io)?;
    progress.store(1000, Ordering::Relaxed);
    Ok(samples as f64 / 48_000.0)
}
