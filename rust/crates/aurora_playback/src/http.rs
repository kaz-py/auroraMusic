//! Lectura de audio por HTTP/HTTPS con `Range` para saltar. Sustituye las
//! opciones de FFmpeg que usaba el motor anterior: certificados verificados
//! (almacén del sistema), tiempo de espera de lectura de 15 s y reconexión
//! (hasta 3 intentos con espera creciente) cuando la conexión se corta.

use std::io::{self, Read, Seek, SeekFrom};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::sleep;
use std::time::Duration;

use symphonia::core::io::MediaSource;

const TIMEOUT: Duration = Duration::from_secs(15);
/// Un salto hacia delante menor que esto se resuelve leyendo y descartando.
const SKIP_FORWARD_LIMIT: u64 = 256 * 1024;
const RECONNECT_DELAYS_MS: [u64; 3] = [400, 1200, 3000];
/// Tras leer esto sin fallos, el contador de reconexiones vuelve a cero.
const HEALTHY_BYTES: u64 = 64 * 1024;

pub struct HttpSource {
    agent: ureq::Agent,
    url: String,
    headers: Vec<(String, String)>,
    body: Option<Box<dyn Read + Send + Sync>>,
    pos: u64,
    len: Option<u64>,
    ranges: bool,
    /// Se activa si la conexión se cortó a mitad y no se pudo recuperar.
    broken: Arc<AtomicBool>,
    reconnects: usize,
    healthy_since: u64,
}

fn http_error(e: ureq::Error) -> io::Error {
    match e {
        ureq::Error::Status(code, _) => io::Error::other(format!("HTTP {code}")),
        ureq::Error::Transport(t) => {
            io::Error::new(io::ErrorKind::ConnectionAborted, t.to_string())
        }
    }
}

impl HttpSource {
    /// Abre la URL (`http://` o `https://`).
    pub fn open(url: &str, headers: Vec<(String, String)>) -> io::Result<(Self, Arc<AtomicBool>)> {
        let lower = url.to_ascii_lowercase();
        if !(lower.starts_with("http://") || lower.starts_with("https://")) {
            return Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "solo se admite HTTP o HTTPS",
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
            .redirects(5)
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
            reconnects: 0,
            healthy_since: 0,
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
        let response = request.call().map_err(http_error)?;
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

    /// Reintenta desde `self.pos`; `false` si se agotaron los intentos o el
    /// servidor no permite reanudar.
    fn reconnect(&mut self) -> bool {
        self.body = None;
        if !self.ranges && self.pos > 0 {
            return false;
        }
        while self.reconnects < RECONNECT_DELAYS_MS.len() {
            sleep(Duration::from_millis(RECONNECT_DELAYS_MS[self.reconnects]));
            self.reconnects += 1;
            if self.connect(self.pos).is_ok() {
                self.healthy_since = self.pos;
                return true;
            }
        }
        false
    }

    fn give_up(&mut self, error: io::Error) -> io::Error {
        self.broken.store(true, Ordering::Relaxed);
        self.body = None;
        error
    }
}

impl Read for HttpSource {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        loop {
            if self.body.is_none() {
                match self.connect(self.pos) {
                    Ok(()) => {}
                    Err(_) if self.reconnect() => {}
                    Err(e) => return Err(self.give_up(e)),
                }
            }
            let Some(body) = self.body.as_mut() else {
                return Ok(0);
            };
            match body.read(buf) {
                Ok(0) => {
                    // Cierre limpio solo si llegamos al largo anunciado.
                    if self.len.is_some_and(|len| self.pos < len) {
                        if self.reconnect() {
                            continue;
                        }
                        return Err(self.give_up(io::Error::new(
                            io::ErrorKind::ConnectionAborted,
                            "la conexión se cortó antes de terminar",
                        )));
                    }
                    return Ok(0);
                }
                Ok(n) => {
                    self.pos += n as u64;
                    if self.reconnects > 0 && self.pos - self.healthy_since >= HEALTHY_BYTES {
                        self.reconnects = 0;
                    }
                    return Ok(n);
                }
                Err(e) => {
                    if self.reconnect() {
                        continue;
                    }
                    return Err(self.give_up(e));
                }
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
