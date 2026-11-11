//! Diagnóstico opcional: guarda cada frase que se entrega a Whisper (audio ya
//! normalizado) con lo que entendió y lo que Aurora hizo con ello, para ver por
//! qué una orden no se reconoció. Solo en una carpeta local que elige el
//! usuario al activarlo; se conservan las últimas [`KEEP`] frases.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Frases (audio + línea del registro) que se conservan.
pub(crate) const KEEP: usize = 40;
const LOG: &str = "diagnostico.jsonl";

pub(crate) struct Diagnostics {
    dir: PathBuf,
}

impl Diagnostics {
    pub(crate) fn open(dir: &Path) -> Option<Self> {
        fs::create_dir_all(dir).ok()?;
        Some(Self {
            dir: dir.to_path_buf(),
        })
    }

    pub(crate) fn record(
        &self,
        pcm: &[f32],
        text: &str,
        no_speech: f32,
        decision: &str,
        decode_ms: u128,
    ) {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_or(0, |d| d.as_millis());
        let name = format!("frase_{stamp}.wav");
        if write_wav(&self.dir.join(&name), pcm).is_err() {
            return;
        }
        let peak = pcm.iter().fold(0.0f32, |m, s| m.max(s.abs()));
        let line = format!(
            "{{\"archivo\":\"{name}\",\"texto\":{},\"no_speech\":{no_speech:.2},\
             \"decision\":{},\"segundos\":{:.2},\"pico\":{peak:.3},\"ms\":{decode_ms}}}\n",
            json_string(text),
            json_string(decision),
            pcm.len() as f32 / 16_000.0,
        );
        if let Ok(mut log) = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(self.dir.join(LOG))
        {
            let _ = log.write_all(line.as_bytes());
        }
        self.prune();
    }

    fn prune(&self) {
        let Ok(entries) = fs::read_dir(&self.dir) else {
            return;
        };
        let mut audio: Vec<PathBuf> = entries
            .flatten()
            .map(|e| e.path())
            .filter(|p| {
                p.file_name()
                    .and_then(|n| n.to_str())
                    .is_some_and(|n| n.starts_with("frase_") && n.ends_with(".wav"))
            })
            .collect();
        audio.sort();
        let extra = audio.len().saturating_sub(KEEP);
        for old in audio.into_iter().take(extra) {
            let _ = fs::remove_file(old);
        }
    }
}

fn json_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// WAV de 16 bits, mono, 16 kHz.
fn write_wav(path: &Path, pcm: &[f32]) -> std::io::Result<()> {
    let data_len = (pcm.len() * 2) as u32;
    let mut file = std::io::BufWriter::new(fs::File::create(path)?);
    file.write_all(b"RIFF")?;
    file.write_all(&(36 + data_len).to_le_bytes())?;
    file.write_all(b"WAVEfmt ")?;
    file.write_all(&16u32.to_le_bytes())?;
    file.write_all(&1u16.to_le_bytes())?; // PCM
    file.write_all(&1u16.to_le_bytes())?; // mono
    file.write_all(&16_000u32.to_le_bytes())?;
    file.write_all(&32_000u32.to_le_bytes())?; // bytes por segundo
    file.write_all(&2u16.to_le_bytes())?;
    file.write_all(&16u16.to_le_bytes())?;
    file.write_all(b"data")?;
    file.write_all(&data_len.to_le_bytes())?;
    for sample in pcm {
        let value = (sample.clamp(-1.0, 1.0) * 32767.0) as i16;
        file.write_all(&value.to_le_bytes())?;
    }
    file.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_phrase_is_saved_with_its_log_line_and_old_ones_are_pruned() {
        let dir = tempfile::tempdir().unwrap();
        let diagnostics = Diagnostics::open(&dir.path().join("diag")).unwrap();
        for i in 0..KEEP + 5 {
            std::thread::sleep(std::time::Duration::from_millis(2));
            diagnostics.record(&[0.5; 1600], &format!("Aurora \"{i}\""), 0.1, "Ignored", 12);
        }
        let wavs = fs::read_dir(dir.path().join("diag"))
            .unwrap()
            .flatten()
            .filter(|e| e.path().extension().is_some_and(|x| x == "wav"))
            .count();
        assert_eq!(wavs, KEEP);
        let log = fs::read_to_string(dir.path().join("diag").join(LOG)).unwrap();
        assert_eq!(log.lines().count(), KEEP + 5);
        assert!(log.lines().next().unwrap().contains("\\\"0\\\""));
        let first = fs::read_dir(dir.path().join("diag"))
            .unwrap()
            .flatten()
            .find(|e| e.path().extension().is_some_and(|x| x == "wav"))
            .unwrap();
        let bytes = fs::read(first.path()).unwrap();
        assert_eq!(&bytes[..4], b"RIFF");
        assert_eq!(bytes.len(), 44 + 3200);
    }
}
