//! Lectura de audio por HTTP (solo bucle local: el proxy de Aurora), con
//! `Range` para saltar. Equivale a las opciones de FFmpeg que usaba el motor
//! anterior: tiempo de espera de lectura de 15 s y reintento de la conexión.

use std::io::{self, Read, Seek, SeekFrom};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use symphonia::core::io::MediaSource;

const TIMEOUT: Duration = Duration::from_secs(15);
/// Un salto hacia delante menor que esto se resuelve leyendo y descartando.
const SKIP_FORWARD_LIMIT: u64 = 256 * 1024;

pub struct HttpSource {
    agent: ureq::Agent,
    url: String,
    headers: Vec<(String, String)>,
    body: Option<Box<dyn Read + Send + Sync>>,
    pos: u64,
    len: Option<u64>,
    ranges: bool,
    /// Se activa si la conexión se cortó a mitad (para no confundirlo con el final).
    broken: Arc<AtomicBool>,
}

impl HttpSource {
    /// Abre la URL. Solo `http://127.0.0.1` / `localhost`: el audio remoto sigue
    /// el camino anterior (Dart + FFmpeg) hasta que haya TLS verificado aquí.
    pub fn open(url: &str, headers: Vec<(String, String)>) -> io::Result<(Self, Arc<AtomicBool>)> {
        let lower = url.to_ascii_lowercase();
        let local = lower.starts_with("http://127.0.0.1:")
            || lower.starts_with("http://127.0.0.1/")
            || lower.starts_with("http://localhost:")
            || lower.starts_with("http://localhost/");
        if !local {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "solo se admite HTTP de bucle local",
            ));
        }
        for (name, value) in &headers {
            if name.contains(['\r', '\n']) || value.contains(['\r', '\n']) {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidInput,
                    "cabecera inválida",
                ));
            }
        }
        let agent = ureq::AgentBuilder::new()
            .timeout_connect(TIMEOUT)
            .timeout_read(TIMEOUT)
            .redirects(0)
            .build();
        let broken = Arc::new(AtomicBool::new(false));
        let mut source = Self {
            agent,
            url: url.to_string(),
            headers,
            body: None,
            pos: 0,
            len: None,
            ranges: false,
            broken: broken.clone(),
        };
        source.connect(0)?;
        Ok((source, broken))
    }

    fn connect(&mut self, start: u64) -> io::Result<()> {
        let mut request = self.agent.get(&self.url);
        for (name, value) in &self.headers {
            request = request.set(name, value);
        }
        if start > 0 {
            request = request.set("Range", &format!("bytes={start}-"));
        }
        let response = request.call().map_err(|e| match e {
            ureq::Error::Status(code, _) => io::Error::other(format!("HTTP {code}")),
            ureq::Error::Transport(t) => {
                io::Error::new(io::ErrorKind::ConnectionAborted, t.to_string())
            }
        })?;
        let status = response.status();
        let total = response
            .header("Content-Range")
            .and_then(|v| v.rsplit('/').next())
            .and_then(|v| v.trim().parse::<u64>().ok())
            .or_else(|| {
                if status == 200 {
                    response
                        .header("Content-Length")
                        .and_then(|v| v.trim().parse().ok())
                } else {
                    None
                }
            });
        if total.is_some() {
            self.len = total;
        }
        self.ranges = status == 206
            || response
                .header("Accept-Ranges")
                .is_some_and(|v| v.eq_ignore_ascii_case("bytes"));
        // Un servidor sin Range responde 200 desde el principio: hay que saltar leyendo.
        let mut body: Box<dyn Read + Send + Sync> = Box::new(response.into_reader());
        let mut actual = if start > 0 && status != 206 { 0 } else { start };
        while actual < start {
            let mut sink = [0u8; 16 * 1024];
            let want = ((start - actual) as usize).min(sink.len());
            let n = body.read(&mut sink[..want])?;
            if n == 0 {
                return Err(io::Error::new(
                    io::ErrorKind::UnexpectedEof,
                    "fin antes del punto pedido",
                ));
            }
            actual += n as u64;
        }
        self.body = Some(body);
        self.pos = start;
        Ok(())
    }
}

impl Read for HttpSource {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        if self.body.is_none() {
            self.connect(self.pos)?;
        }
        let Some(body) = self.body.as_mut() else {
            return Ok(0);
        };
        match body.read(buf) {
            Ok(0) => {
                // Cierre limpio solo si llegamos al largo anunciado.
                if self.len.is_some_and(|len| self.pos < len) {
                    self.broken.store(true, Ordering::Relaxed);
                    self.body = None;
                    return Err(io::Error::new(
                        io::ErrorKind::ConnectionAborted,
                        "la conexión se cortó antes de terminar",
                    ));
                }
                Ok(0)
            }
            Ok(n) => {
                self.pos += n as u64;
                Ok(n)
            }
            Err(e) => {
                self.broken.store(true, Ordering::Relaxed);
                self.body = None;
                Err(e)
            }
        }
    }
}

impl Seek for HttpSource {
    fn seek(&mut self, from: SeekFrom) -> io::Result<u64> {
        let target = match from {
            SeekFrom::Start(p) => p as i64,
            SeekFrom::Current(d) => self.pos as i64 + d,
            SeekFrom::End(d) => match self.len {
                Some(len) => len as i64 + d,
                None => {
                    return Err(io::Error::new(
                        io::ErrorKind::Unsupported,
                        "largo desconocido",
                    ))
                }
            },
        };
        if target < 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "posición negativa",
            ));
        }
        let target = target as u64;
        if target == self.pos && self.body.is_some() {
            return Ok(target);
        }
        // Salto corto hacia delante: leer y descartar evita una conexión nueva.
        if self.body.is_some() && target > self.pos && target - self.pos <= SKIP_FORWARD_LIMIT {
            let mut remaining = target - self.pos;
            let mut sink = [0u8; 16 * 1024];
            while remaining > 0 {
                let want = (remaining as usize).min(sink.len());
                let n = self.read(&mut sink[..want])?;
                if n == 0 {
                    break;
                }
                remaining -= n as u64;
            }
            return Ok(self.pos);
        }
        if !self.ranges && target != 0 {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "el servidor no admite Range",
            ));
        }
        self.body = None;
        self.pos = target;
        Ok(target)
    }
}

impl MediaSource for HttpSource {
    fn is_seekable(&self) -> bool {
        self.ranges && self.len.is_some()
    }

    fn byte_len(&self) -> Option<u64> {
        self.len
    }
}
