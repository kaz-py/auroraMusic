'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { afterEach, beforeEach, test } = require('node:test');
const { resolveConnection } = require('../com.aurora.music.sdPlugin/lib/aurora');
const { AuroraPlugin, UUID } = require('../com.aurora.music.sdPlugin/lib/plugin');
const { fakeAurora, fakeStreamDeck } = require('./helpers');

let deck, aurora, plugin, directory;

async function start({ global, pollMs = 60000, paths } = {}) {
  deck = await fakeStreamDeck();
  aurora = await fakeAurora();
  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'aurora-sd-'));
  plugin = new AuroraPlugin({
    port: deck.port,
    uuid: 'plugin-uuid',
    registerEvent: 'registerPlugin',
    pollMs,
    resolve: (settings) => resolveConnection(settings, { paths: paths || [path.join(directory, 'remote_control.json')] }),
  });
  await deck.waitFor((m) => m.event === 'getGlobalSettings');
  deck.send({
    event: 'didReceiveGlobalSettings',
    payload: { settings: global ?? { mode: 'manual', url: aurora.baseUrl, token: aurora.token } },
  });
  await new Promise((r) => setTimeout(r, 30));
}

afterEach(async () => {
  plugin?.socket.close();
  plugin?.stop();
  await deck?.close();
  await aurora?.close();
  if (directory) fs.rmSync(directory, { recursive: true, force: true });
  plugin = deck = aurora = directory = undefined;
});

const key = (action, settings = {}) =>
  deck.send({ event: 'keyDown', action, context: `ctx-${action}`, payload: { settings } });

test('registers with the Stream Deck and asks for the global settings', async () => {
  await start();
  assert.deepEqual(deck.received[0], { event: 'registerPlugin', uuid: 'plugin-uuid' });
});

test('each key calls its Aurora route with the token and confirms with showOk', async () => {
  await start();
  for (const [action, route] of [['toggle', 'toggle'], ['next', 'next'], ['previous', 'previous']]) {
    key(`${UUID}.${action}`);
    await deck.waitFor((m) => m.event === 'showOk' && m.context === `ctx-${UUID}.${action}`);
    assert.ok(aurora.calls.some((c) => c.method === 'POST' && c.path === `/v1/${route}`), route);
  }
});

test('the Jam key sends the mode chosen on that key (default auto)', async () => {
  await start();
  key(`${UUID}.jam`, { mode: 'lan' });
  await deck.waitFor((m) => m.event === 'showOk');
  assert.deepEqual(aurora.calls.at(-1), { method: 'POST', path: '/v1/jam/start', body: { mode: 'lan' } });
  deck.received.length = 0;
  key(`${UUID}.jam`, { mode: 'otra-cosa' });
  await deck.waitFor((m) => m.event === 'showOk');
  assert.deepEqual(aurora.calls.at(-1).body, { mode: 'auto' });
});

test('failures show the alert: wrong token, API error, Aurora closed', async () => {
  await start({ global: { mode: 'manual', url: 'http://127.0.0.1:47890/v1', token: 'x' } });
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'showAlert');
  await deck.waitFor((m) => m.event === 'logMessage' && /no está abierta/.test(m.payload.message));

  deck.received.length = 0;
  deck.send({
    event: 'didReceiveGlobalSettings',
    payload: { settings: { mode: 'manual', url: aurora.baseUrl, token: 'incorrecto' } },
  });
  await new Promise((r) => setTimeout(r, 30));
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'logMessage' && /Token incorrecto/.test(m.payload.message));
  assert.ok(deck.received.some((m) => m.event === 'showAlert'));

  deck.received.length = 0;
  deck.send({
    event: 'didReceiveGlobalSettings',
    payload: { settings: { mode: 'manual', url: aurora.baseUrl, token: aurora.token } },
  });
  await new Promise((r) => setTimeout(r, 30));
  aurora.state.failure = { status: 409, error: 'Lo controla Ana.' };
  key(`${UUID}.toggle`);
  await deck.waitFor((m) => m.event === 'logMessage' && /Lo controla Ana/.test(m.payload.message));
  assert.ok(deck.received.some((m) => m.event === 'showAlert'));
});

test('automatic mode reads the file Aurora publishes and follows token changes', async () => {
  const file = (dir) => path.join(dir, 'remote_control.json');
  await start({ global: { mode: 'auto' } });
  // Sin archivo: Aurora no está abierta.
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'logMessage' && /No encuentro Aurora/.test(m.payload.message));

  fs.writeFileSync(file(directory), JSON.stringify({ baseUrl: aurora.baseUrl, port: aurora.port, token: aurora.token }));
  deck.received.length = 0;
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'showOk');

  // Aurora regeneró el token: con el archivo viejo falla; con el nuevo, no.
  aurora.state.token = 'otro-token';
  deck.received.length = 0;
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'logMessage' && /Token incorrecto/.test(m.payload.message));
  fs.writeFileSync(file(directory), JSON.stringify({ baseUrl: aurora.baseUrl, token: 'otro-token' }));
  deck.received.length = 0;
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'showOk');
});

test('manual mode never sends the token to a non-local URL', async () => {
  await start({ global: { mode: 'manual', url: 'http://example.com/v1', token: 'secreto' } });
  key(`${UUID}.next`);
  await deck.waitFor((m) => m.event === 'logMessage' && /127\.0\.0\.1/.test(m.payload.message));
  assert.equal(aurora.calls.length, 0);
  assert.ok(deck.received.some((m) => m.event === 'showAlert'));
});

test('the inspector test button reports the connection or the reason', async () => {
  await start();
  deck.send({ event: 'sendToPlugin', action: `${UUID}.next`, context: 'pi', payload: { event: 'test' } });
  const ok = await deck.waitFor((m) => m.event === 'sendToPropertyInspector');
  assert.equal(ok.context, 'pi');
  assert.equal(ok.payload.event, 'testResult');
  assert.equal(ok.payload.ok, true);
  assert.match(ok.payload.message, /Conectado \(manual\): Tema — Ana/);

  deck.received.length = 0;
  deck.send({
    event: 'didReceiveGlobalSettings',
    payload: { settings: { mode: 'manual', url: aurora.baseUrl, token: '' } },
  });
  await new Promise((r) => setTimeout(r, 30));
  deck.send({ event: 'sendToPlugin', action: `${UUID}.next`, context: 'pi', payload: { event: 'test' } });
  const bad = await deck.waitFor((m) => m.event === 'sendToPropertyInspector');
  assert.equal(bad.payload.ok, false);
  assert.match(bad.payload.message, /Falta el token/);
});

test('the play/pause key follows the real state of Aurora', async () => {
  await start({ pollMs: 40 });
  deck.send({ event: 'willAppear', action: `${UUID}.toggle`, context: 'k1', payload: { settings: {} } });
  // Pausado al aparecer: el estado 0 es el de partida, no se reenvía.
  aurora.state.playing = true;
  const playing = await deck.waitFor((m) => m.event === 'setState' && m.payload.state === 1);
  assert.equal(playing.context, 'k1');
  aurora.state.playing = false;
  await deck.waitFor((m) => m.event === 'setState' && m.payload.state === 0 && m.context === 'k1');

  // Sin teclas visibles no se consulta.
  deck.send({ event: 'willDisappear', action: `${UUID}.toggle`, context: 'k1', payload: {} });
  await new Promise((r) => setTimeout(r, 30));
  const before = aurora.calls.length;
  await new Promise((r) => setTimeout(r, 150));
  assert.equal(aurora.calls.length, before);
});
