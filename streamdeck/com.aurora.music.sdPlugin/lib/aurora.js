'use strict';
// Conexión con la API local de Aurora (ver docs/stream_deck.md).

const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');

const LOOPBACK = new Set(['127.0.0.1', 'localhost']);
const DEFAULT_TIMEOUT_MS = 6000;
// Iniciar una Jam en línea puede tardar: el servidor de Aurora espera hasta 30 s.
const JAM_TIMEOUT_MS = 35000;

class AuroraError extends Error {
  constructor(message, { status, code } = {}) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

/** Rutas donde Aurora deja `remote_control.json` mientras la API está activa. */
function discoveryPaths(env = process.env, home = os.homedir()) {
  const paths = [];
  if (env.APPDATA) paths.push(path.join(env.APPDATA, 'com.aurora', 'Aurora', 'remote_control.json'));
  paths.push(path.join(home, '.local', 'share', 'com.aurora', 'Aurora', 'remote_control.json'));
  return paths;
}

/** Acepta solo `http://127.0.0.1|localhost[:puerto]`: el token nunca sale del equipo. */
function normalizeBaseUrl(raw) {
  let url;
  try {
    url = new URL(String(raw || '').trim());
  } catch {
    throw new AuroraError('La URL no es válida.');
  }
  if (url.protocol !== 'http:' || !LOOPBACK.has(url.hostname)) {
    throw new AuroraError('La URL debe ser http://127.0.0.1 (solo este equipo).');
  }
  const base = `http://${url.hostname}:${url.port || 80}`;
  return `${base}${url.pathname.replace(/\/+$/, '') || '/v1'}`;
}

/**
 * Datos de conexión: `auto` lee el archivo que publica Aurora; `manual` usa la
 * URL y el token escritos en el Stream Deck.
 */
function resolveConnection(settings = {}, { readFile = fs.readFileSync, paths = discoveryPaths() } = {}) {
  if (settings.mode === 'manual') {
    const token = String(settings.token || '').trim();
    if (!token) throw new AuroraError('Falta el token. Cópialo desde Ajustes de Aurora.');
    return { baseUrl: normalizeBaseUrl(settings.url || 'http://127.0.0.1:47890/v1'), token, source: 'manual' };
  }
  for (const file of paths) {
    let info;
    try {
      info = JSON.parse(readFile(file, 'utf8'));
    } catch {
      continue;
    }
    if (info && typeof info.token === 'string' && info.token && info.baseUrl) {
      return { baseUrl: normalizeBaseUrl(info.baseUrl), token: info.token, source: 'auto' };
    }
  }
  throw new AuroraError(
    'No encuentro Aurora. Ábrela y activa «Control remoto (Stream Deck)» en Ajustes.',
    { code: 'NOT_FOUND' },
  );
}

/** Petición a la API; devuelve el JSON de la respuesta o lanza [AuroraError]. */
function request(connection, route, { method = 'POST', body, timeout = DEFAULT_TIMEOUT_MS } = {}) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${connection.baseUrl}/${route}`);
    const payload = body === undefined ? undefined : Buffer.from(JSON.stringify(body));
    const req = http.request(
      {
        host: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method,
        timeout,
        headers: {
          Authorization: `Bearer ${connection.token}`,
          ...(payload ? { 'Content-Type': 'application/json', 'Content-Length': payload.length } : {}),
        },
      },
      (response) => {
        const chunks = [];
        response.on('data', (chunk) => chunks.push(chunk));
        response.on('end', () => {
          let json = {};
          try {
            json = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          } catch {
            // Respuesta que no es de Aurora.
          }
          if (response.statusCode === 200 && json.ok) return resolve(json);
          if (response.statusCode === 401) {
            return reject(new AuroraError('Token incorrecto.', { status: 401, code: 'UNAUTHORIZED' }));
          }
          reject(
            new AuroraError(json.error || `Aurora respondió ${response.statusCode}.`, {
              status: response.statusCode,
              code: 'SERVER',
            }),
          );
        });
      },
    );
    req.on('timeout', () => {
      req.destroy();
      reject(new AuroraError('Aurora no respondió a tiempo.', { code: 'TIMEOUT' }));
    });
    req.on('error', (error) => {
      if (error instanceof AuroraError) return reject(error);
      reject(
        error.code === 'ECONNREFUSED'
          ? new AuroraError('Aurora no está abierta o la API está desactivada.', { code: 'REFUSED' })
          : new AuroraError(`No se pudo conectar: ${error.message}`, { code: 'NETWORK' }),
      );
    });
    if (payload) req.write(payload);
    req.end();
  });
}

module.exports = { AuroraError, JAM_TIMEOUT_MS, discoveryPaths, normalizeBaseUrl, request, resolveConnection };
