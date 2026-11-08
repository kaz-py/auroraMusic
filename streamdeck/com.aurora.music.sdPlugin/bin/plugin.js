'use strict';
// Punto de entrada: el Stream Deck lo lanza con
//   -port <puerto> -pluginUUID <uuid> -registerEvent <evento> -info <json>

const { AuroraPlugin } = require('../lib/plugin');

function argument(name) {
  const index = process.argv.indexOf(`-${name}`);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

const port = argument('port');
const uuid = argument('pluginUUID');
const registerEvent = argument('registerEvent');
if (!port || !uuid || !registerEvent) {
  console.error('Faltan los argumentos del Stream Deck (-port, -pluginUUID, -registerEvent).');
  process.exit(1);
}

const plugin = new AuroraPlugin({ port, uuid, registerEvent });
plugin.onClose = () => process.exit(0);
