'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { test } = require('node:test');
const { ACTIONS } = require('../com.aurora.music.sdPlugin/lib/plugin');

const root = path.join(__dirname, '..', 'com.aurora.music.sdPlugin');
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json'), 'utf8'));

const exists = (relative) =>
  ['.svg', '.png'].some((extension) => fs.existsSync(path.join(root, relative + extension)));

test('every manifest action has a handler and every handler is declared', () => {
  assert.deepEqual(manifest.Actions.map((a) => a.UUID).sort(), Object.keys(ACTIONS).sort());
  for (const action of manifest.Actions) assert.ok(action.UUID.startsWith(`${manifest.UUID}.`));
});

test('every file the manifest points to exists', () => {
  assert.ok(fs.existsSync(path.join(root, manifest.CodePath)), 'CodePath');
  assert.ok(fs.existsSync(path.join(root, manifest.PropertyInspectorPath)), 'PropertyInspectorPath');
  assert.ok(exists(manifest.Icon) && exists(manifest.CategoryIcon), 'iconos del plugin');
  for (const action of manifest.Actions) {
    assert.ok(exists(action.Icon), action.UUID);
    for (const state of action.States) assert.ok(exists(state.Image), state.Image);
  }
});

test('the plugin has no runtime dependencies to ship', () => {
  assert.ok(!fs.existsSync(path.join(root, 'node_modules')));
  const sources = ['bin/plugin.js', 'lib/aurora.js', 'lib/plugin.js', 'lib/websocket.js'];
  for (const file of sources) {
    const text = fs.readFileSync(path.join(root, file), 'utf8');
    for (const [, name] of text.matchAll(/require\('([^']+)'\)/g)) {
      assert.ok(name.startsWith('node:') || name.startsWith('.'), `${file} requiere ${name}`);
    }
  }
});
