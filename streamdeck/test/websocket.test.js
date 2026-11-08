'use strict';
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { WebSocketServer } = require('ws');
const { WebSocketClient } = require('../com.aurora.music.sdPlugin/lib/websocket');

function listen() {
  return new Promise((resolve) => {
    const server = new WebSocketServer({ port: 0, host: '127.0.0.1' }, () => resolve(server));
  });
}
const once = (emitter, event) => new Promise((resolve) => emitter.once(event, resolve));

test('handshake and text in both directions, including long payloads', async () => {
  const server = await listen();
  const received = [];
  server.on('connection', (socket) => {
    socket.on('message', (data) => {
      received.push(data.toString());
      socket.send(`eco:${data.length}`);
    });
  });
  const client = new WebSocketClient(`ws://127.0.0.1:${server.address().port}`);
  await once(client, 'open');
  const replies = [];
  client.on('message', (text) => replies.push(text));
  const sizes = [5, 125, 126, 300, 65535, 65536, 200000];
  for (const size of sizes) client.send('é'.repeat(1) + 'x'.repeat(size - 1));
  while (replies.length < sizes.length) await new Promise((r) => setTimeout(r, 10));
  assert.deepEqual(
    received.map((text) => Buffer.byteLength(text)),
    sizes.map((size) => size + 1),
  );
  assert.deepEqual(replies, sizes.map((size) => `eco:${size + 1}`));
  client.close();
  server.close();
});

test('reassembles fragmented messages and answers pings', async () => {
  const server = await listen();
  let pongs = 0;
  server.on('connection', (socket) => {
    socket.on('pong', () => pongs++);
    socket.ping();
    socket.send('par', { fin: false });
    socket.send('tido', { fin: true });
  });
  const client = new WebSocketClient(`ws://127.0.0.1:${server.address().port}`);
  const text = await once(client, 'message');
  assert.equal(text, 'partido');
  while (pongs === 0) await new Promise((r) => setTimeout(r, 10));
  assert.equal(pongs, 1);
  client.close();
  server.close();
});

test('close from either side ends the client and sending afterwards throws', async () => {
  const server = await listen();
  let serverSocket;
  server.on('connection', (socket) => (serverSocket = socket));
  const client = new WebSocketClient(`ws://127.0.0.1:${server.address().port}`);
  await once(client, 'open');
  while (!serverSocket) await new Promise((r) => setTimeout(r, 10));
  const closed = once(client, 'close');
  serverSocket.close();
  await closed;
  assert.throws(() => client.send('x'), /cerrado/);
  server.close();
});

test('a server that is not a WebSocket is reported as an error', async () => {
  const http = require('node:http');
  const plain = http.createServer((_, response) => response.end('hola'));
  await new Promise((resolve) => plain.listen(0, '127.0.0.1', resolve));
  const client = new WebSocketClient(`ws://127.0.0.1:${plain.address().port}`);
  const error = await once(client, 'error');
  assert.match(error.message, /rechaz/);
  plain.close();
});
