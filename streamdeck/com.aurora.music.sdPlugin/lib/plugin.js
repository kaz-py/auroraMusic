'use strict';
// Plugin de Stream Deck para Aurora: conecta con el Stream Deck por WebSocket
// y traduce cada tecla a una llamada de la API local de Aurora.

const { AuroraError, JAM_TIMEOUT_MS, request, resolveConnection } = require('./aurora');
const { WebSocketClient } = require('./websocket');

const UUID = 'com.aurora.music';
const POLL_MS = 2000;
const ACTIONS = {
  [`${UUID}.toggle`]: { route: 'toggle' },
  [`${UUID}.next`]: { route: 'next' },
  [`${UUID}.previous`]: { route: 'previous' },
  [`${UUID}.jam`]: {
    route: 'jam/start',
    body: (settings) => ({ mode: ['auto', 'online', 'lan'].includes(settings.mode) ? settings.mode : 'auto' }),
    timeout: JAM_TIMEOUT_MS,
  },
};

class AuroraPlugin {
  /**
   * @param {{port: number|string, uuid: string, registerEvent: string,
   *   resolve?: Function, pollMs?: number}} options
   */
  constructor({ port, uuid, registerEvent, resolve = resolveConnection, pollMs = POLL_MS }) {
    this.uuid = uuid;
    this.registerEvent = registerEvent;
    this.resolve = resolve;
    this.pollMs = pollMs;
    this.global = {};
    this.contexts = new Map(); // context -> { action, settings }
    this.timer = null;
    this.polling = false;
    this.socket = new WebSocketClient(`ws://127.0.0.1:${port}`);
    this.socket.on('open', () => {
      this._send({ event: this.registerEvent, uuid: this.uuid });
      this._send({ event: 'getGlobalSettings', context: this.uuid });
    });
    this.socket.on('message', (text) => this._onMessage(text));
    this.socket.on('close', () => this.stop());
    this.socket.on('error', () => this.stop());
    this.onClose = () => {};
  }

  stop() {
    clearInterval(this.timer);
    this.timer = null;
    this.onClose();
  }

  _send(message) {
    try {
      this.socket.send(JSON.stringify(message));
    } catch {
      // El Stream Deck se cerró; `close` ya lo gestiona.
    }
  }

  _onMessage(text) {
    let message;
    try {
      message = JSON.parse(text);
    } catch {
      return;
    }
    switch (message.event) {
      case 'didReceiveGlobalSettings':
        this.global = message.payload?.settings || {};
        break;
      case 'willAppear':
        this.contexts.set(message.context, {
          action: message.action,
          settings: message.payload?.settings || {},
        });
        this._startPolling();
        void this._poll();
        break;
      case 'willDisappear':
        this.contexts.delete(message.context);
        break;
      case 'didReceiveSettings': {
        const entry = this.contexts.get(message.context);
        if (entry) entry.settings = message.payload?.settings || {};
        break;
      }
      case 'keyDown':
        void this._keyDown(message);
        break;
      case 'sendToPlugin':
        void this._fromInspector(message);
        break;
      default:
        break;
    }
  }

  _connection() {
    return this.resolve(this.global);
  }

  async _keyDown(message) {
    const spec = ACTIONS[message.action];
    if (!spec) return;
    const settings = message.payload?.settings || this.contexts.get(message.context)?.settings || {};
    try {
      await request(this._connection(), spec.route, {
        body: spec.body ? spec.body(settings) : undefined,
        timeout: spec.timeout,
      });
      this._send({ event: 'showOk', context: message.context });
      if (message.action === `${UUID}.toggle`) setTimeout(() => void this._poll(), 250);
    } catch (error) {
      this._send({ event: 'showAlert', context: message.context });
      this._send({
        event: 'logMessage',
        payload: { message: `Aurora ${spec.route}: ${error instanceof AuroraError ? error.message : error}` },
      });
    }
  }

  async _fromInspector(message) {
    const event = message.payload?.event;
    if (event !== 'test' && event !== 'ready') return;
    let result;
    try {
      const connection = this._connection();
      const status = await request(connection, 'status', { method: 'GET' });
      const track = status.track ? `${status.track.title} — ${status.track.artist}` : 'sin canción';
      result = { ok: true, message: `Conectado (${connection.source === 'auto' ? 'automático' : 'manual'}): ${track}.` };
    } catch (error) {
      result = { ok: false, message: error instanceof AuroraError ? error.message : String(error) };
    }
    this._send({
      event: 'sendToPropertyInspector',
      action: message.action,
      context: message.context,
      payload: { event: 'testResult', ...result },
    });
  }

  _startPolling() {
    if (this.timer) return;
    this.timer = setInterval(() => void this._poll(), this.pollMs);
    this.timer.unref?.();
  }

  /** Mantiene el icono de reproducir/pausar al día mientras haya una tecla visible. */
  async _poll() {
    if (this.polling) return;
    const toggles = [...this.contexts].filter(([, entry]) => entry.action === `${UUID}.toggle`);
    if (!toggles.length) return;
    this.polling = true;
    try {
      const status = await request(this._connection(), 'status', { method: 'GET', timeout: 1500 });
      const state = status.playing ? 1 : 0;
      for (const [context, entry] of toggles) {
        if (entry.state !== state) {
          entry.state = state;
          this._send({ event: 'setState', context, payload: { state } });
        }
      }
    } catch {
      // Aurora cerrada: la tecla se queda como estaba.
    } finally {
      this.polling = false;
    }
  }
}

module.exports = { ACTIONS, AuroraPlugin, UUID };
