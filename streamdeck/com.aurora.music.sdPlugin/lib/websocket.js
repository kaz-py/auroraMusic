'use strict';
// Cliente WebSocket mínimo (RFC 6455) sin dependencias: lo justo para hablar
// con el Stream Deck por ws://127.0.0.1. Solo texto; responde a ping y cierra
// con el cierre normal.

const crypto = require('node:crypto');
const http = require('node:http');
const { EventEmitter } = require('node:events');

const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
const MAX_MESSAGE = 4 * 1024 * 1024;

function frame(opcode, payload) {
  const length = payload.length;
  let header;
  if (length < 126) {
    header = Buffer.from([0x80 | opcode, 0x80 | length]);
  } else if (length < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 0x80 | 126;
    header.writeUInt16BE(length, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 0x80 | 127;
    header.writeBigUInt64BE(BigInt(length), 2);
  }
  const mask = crypto.randomBytes(4);
  const masked = Buffer.alloc(length);
  for (let i = 0; i < length; i++) masked[i] = payload[i] ^ mask[i % 4];
  return Buffer.concat([header, mask, masked]);
}

class WebSocketClient extends EventEmitter {
  /** Conecta a `ws://host:port/path`; emite `open`, `message`, `close`, `error`. */
  constructor(url) {
    super();
    this.closed = false;
    this._buffer = Buffer.alloc(0);
    this._parts = [];
    const target = new URL(url);
    if (target.protocol !== 'ws:') throw new Error('Solo ws://');
    const key = crypto.randomBytes(16).toString('base64');
    const request = http.request({
      host: target.hostname,
      port: target.port || 80,
      path: `${target.pathname}${target.search}` || '/',
      headers: {
        Connection: 'Upgrade',
        Upgrade: 'websocket',
        'Sec-WebSocket-Key': key,
        'Sec-WebSocket-Version': '13',
      },
    });
    request.on('upgrade', (response, socket, head) => {
      const expected = crypto
        .createHash('sha1')
        .update(key + GUID)
        .digest('base64');
      if (response.headers['sec-websocket-accept'] !== expected) {
        socket.destroy();
        this.emit('error', new Error('Respuesta de WebSocket inválida.'));
        return;
      }
      this._socket = socket;
      socket.on('data', (chunk) => this._onData(chunk));
      socket.on('close', () => this._finish());
      socket.on('error', (error) => this.emit('error', error));
      this.emit('open');
      if (head.length) this._onData(head);
    });
    request.on('response', (response) => {
      response.resume();
      this.emit('error', new Error(`El servidor rechazó el WebSocket (${response.statusCode}).`));
    });
    request.on('error', (error) => this.emit('error', error));
    request.end();
  }

  send(text) {
    if (!this._socket || this.closed) throw new Error('WebSocket cerrado.');
    this._socket.write(frame(0x1, Buffer.from(text, 'utf8')));
  }

  close() {
    if (this.closed || !this._socket) return;
    // El cierre se envía una sola vez (también al contestar al del servidor).
    if (!this._closeSent) {
      this._closeSent = true;
      try {
        this._socket.write(frame(0x8, Buffer.from([0x03, 0xe8])));
      } catch {
        // El socket ya cayó.
      }
    }
    this._socket.end();
  }

  _finish() {
    if (this.closed) return;
    this.closed = true;
    this.emit('close');
  }

  _fail() {
    this._socket?.destroy();
    this._finish();
  }

  _onData(chunk) {
    this._buffer = Buffer.concat([this._buffer, chunk]);
    for (;;) {
      if (this._buffer.length < 2) return;
      const first = this._buffer[0];
      const second = this._buffer[1];
      const fin = (first & 0x80) !== 0;
      const opcode = first & 0x0f;
      const masked = (second & 0x80) !== 0;
      let length = second & 0x7f;
      let offset = 2;
      if (length === 126) {
        if (this._buffer.length < 4) return;
        length = this._buffer.readUInt16BE(2);
        offset = 4;
      } else if (length === 127) {
        if (this._buffer.length < 10) return;
        const big = this._buffer.readBigUInt64BE(2);
        if (big > BigInt(MAX_MESSAGE)) return this._fail();
        length = Number(big);
        offset = 10;
      }
      if (length > MAX_MESSAGE) return this._fail();
      const maskLength = masked ? 4 : 0;
      if (this._buffer.length < offset + maskLength + length) return;
      let payload = this._buffer.subarray(offset + maskLength, offset + maskLength + length);
      if (masked) {
        const mask = this._buffer.subarray(offset, offset + 4);
        payload = Buffer.from(payload.map((byte, i) => byte ^ mask[i % 4]));
      } else {
        payload = Buffer.from(payload);
      }
      this._buffer = this._buffer.subarray(offset + maskLength + length);
      if (!this._onFrame(fin, opcode, payload)) return;
    }
  }

  /** Devuelve false si hay que dejar de leer (conexión cerrada). */
  _onFrame(fin, opcode, payload) {
    switch (opcode) {
      case 0x0: // continuación
      case 0x1: // texto
      case 0x2: // binario (no se usa; se trata como texto)
        if (opcode !== 0x0) this._parts = [];
        this._parts.push(payload);
        if (this._parts.reduce((total, part) => total + part.length, 0) > MAX_MESSAGE) {
          this._fail();
          return false;
        }
        if (fin) {
          const text = Buffer.concat(this._parts).toString('utf8');
          this._parts = [];
          this.emit('message', text);
        }
        return true;
      case 0x8:
        this.close();
        return false;
      case 0x9:
        this._socket.write(frame(0xa, payload));
        return true;
      default:
        return true;
    }
  }
}

module.exports = { WebSocketClient, frame };
