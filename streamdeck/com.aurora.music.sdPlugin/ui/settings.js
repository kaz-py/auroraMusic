'use strict';
// Inspector de propiedades. La conexión se guarda como ajuste GLOBAL del
// plugin (vale para todas las teclas); el modo de la Jam, por tecla.

const JAM_ACTION = 'com.aurora.music.jam';
let socket;
let pluginUuid;
let actionUuid;
let actionSettings = {};
let globalSettings = { mode: 'auto', url: '', token: '' };

const $ = (id) => document.getElementById(id);

function send(message) {
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
}

function readGlobal() {
  const mode = document.querySelector('input[name="mode"]:checked').value;
  globalSettings = { mode, url: $('url').value.trim(), token: $('token').value.trim() };
}

function saveGlobal() {
  readGlobal();
  $('manual').hidden = globalSettings.mode !== 'manual';
  send({ event: 'setGlobalSettings', context: pluginUuid, payload: globalSettings });
}

function showResult(ok, message) {
  const result = $('result');
  result.textContent = message;
  result.className = ok ? 'ok' : 'error';
  $('test').disabled = false;
}

function applyGlobal(settings) {
  globalSettings = { mode: 'auto', url: '', token: '', ...settings };
  document.querySelector(`input[name="mode"][value="${globalSettings.mode === 'manual' ? 'manual' : 'auto'}"]`).checked = true;
  $('url').value = globalSettings.url;
  $('token').value = globalSettings.token;
  $('manual').hidden = globalSettings.mode !== 'manual';
}

function connectElgatoStreamDeckSocket(port, uuid, registerEvent, _info, actionInfo) {
  pluginUuid = uuid;
  const action = JSON.parse(actionInfo);
  actionUuid = action.action;
  actionSettings = (action.payload && action.payload.settings) || {};
  $('jam-section').hidden = actionUuid !== JAM_ACTION;
  $('jam-mode').value = ['auto', 'online', 'lan'].includes(actionSettings.mode) ? actionSettings.mode : 'auto';

  socket = new WebSocket(`ws://127.0.0.1:${port}`);
  socket.onopen = () => {
    send({ event: registerEvent, uuid });
    send({ event: 'getGlobalSettings', context: uuid });
    send({ event: 'sendToPlugin', action: actionUuid, context: uuid, payload: { event: 'ready' } });
  };
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.event === 'didReceiveGlobalSettings') applyGlobal(message.payload.settings || {});
    if (message.event === 'sendToPropertyInspector' && message.payload && message.payload.event === 'testResult') {
      showResult(message.payload.ok, message.payload.message);
    }
  };
}
window.connectElgatoStreamDeckSocket = connectElgatoStreamDeckSocket;

document.querySelectorAll('input[name="mode"]').forEach((radio) => radio.addEventListener('change', saveGlobal));
$('url').addEventListener('change', saveGlobal);
$('token').addEventListener('change', saveGlobal);
$('jam-mode').addEventListener('change', () => {
  actionSettings = { ...actionSettings, mode: $('jam-mode').value };
  send({ event: 'setSettings', context: pluginUuid, payload: actionSettings });
});
$('test').addEventListener('click', () => {
  saveGlobal();
  $('test').disabled = true;
  $('result').textContent = 'Probando…';
  $('result').className = '';
  // El plugin lee los ajustes globales al recibirlos; se le da un instante.
  setTimeout(() => send({ event: 'sendToPlugin', action: actionUuid, context: pluginUuid, payload: { event: 'test' } }), 150);
});
