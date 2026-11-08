'use strict';
// Empaqueta el plugin como dist/com.aurora.music.streamDeckPlugin (un ZIP con
// la carpeta .sdPlugin en la raíz): doble clic y el Stream Deck lo instala.
// Usa `tar` (bsdtar, incluido en Windows 10+ y macOS), sin dependencias.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.join(__dirname, '..');
const folder = 'com.aurora.music.sdPlugin';
const dist = path.join(root, 'dist');
const zip = path.join(dist, 'com.aurora.music.zip');
const output = path.join(dist, 'com.aurora.music.streamDeckPlugin');

if (fs.existsSync(path.join(root, folder, 'node_modules'))) {
  throw new Error('El plugin no debe llevar node_modules (no tiene dependencias).');
}
fs.mkdirSync(dist, { recursive: true });
fs.rmSync(zip, { force: true });
fs.rmSync(output, { force: true });
const result = spawnSync('tar', ['-a', '-c', '-f', zip, folder], { cwd: root, stdio: 'inherit' });
if (result.status !== 0) throw new Error('Falló tar al crear el paquete.');
fs.renameSync(zip, output);
console.log(`${path.relative(root, output)} (${fs.statSync(output).size} bytes)`);
