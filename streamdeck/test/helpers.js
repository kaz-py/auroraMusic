'use strict';
const http = require('node:http');
const { WebSocketServer } = require('ws');

/** Stream Deck simulado: guarda lo que el plugin le manda y permite enviarle eventos. */
async function fakeStreamDeck() {
  const server = await new Promise((resolve) => {
    const wss = new WebSocketServer({ port: 0, host: '127.0.0.1' }, () => resolve(wss));
  });
  const received = [];
  let socket;
  server.on('connection', (s) => {
    socket = s;
    s.on('message', (data) => received.push(JSON.parse(data.toString())));
  });
  return {
    port: server.address().port,
    received,
    send: (message) => socket.send(JSON.stringify(message)),
    async waitFor(predicate, ms = 3000) {
      const end = Date.now() + ms;
      for (;;) {
        const hit = received.find(predicate);
        if (hit) return hit;
        if (Date.now() > end) throw new Error(`No llegó el mensaje esperado. Recibidos: ${JSON.stringify(received)}`);
        await new Promise((r) => setTimeout(r, 10));
      }
    },
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

/** API de Aurora simulada con las mismas reglas de token que la real. */
async function fakeAurora({ token = 'tok-de-prueba', playing = false } = {}) {
  const calls = [];
  const state = { playing, failure: null, token };
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on('data', (c) => chunks.push(c));
    request.on('end', () => {
      const body = Buffer.concat(chunks).toString();
      const done = (status, json) => {
        response.writeHead(status, { 'Content-Type': 'application/json' });
        response.end(JSON.stringify(json));
      };
      if (request.headers.authorization !== `Bearer ${state.token}`) {
        return done(401, { ok: false, error: 'Token inválido o ausente.' });
      }
      calls.push({ method: request.method, path: request.url, body: body ? JSON.parse(body) : null });
      if (state.failure) return done(state.failure.status, { ok: false, error: state.failure.error });
      if (request.url === '/v1/status') {
        return done(200, { ok: true, playing: state.playing, track: { title: 'Tema', artist: 'Ana' } });
      }
      done(200, { ok: true });
    });
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  return {
    get token() {
      return state.token;
    },
    port,
    calls,
    state,
    baseUrl: `http://127.0.0.1:${port}/v1`,
    close: () => new Promise((resolve) => (server.closeAllConnections(), server.close(resolve))),
  };
}

module.exports = { fakeAurora, fakeStreamDeck };
