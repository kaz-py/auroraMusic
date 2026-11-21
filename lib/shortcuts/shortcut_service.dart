import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acciones configurables. `label` es el texto mostrado en Ajustes.
enum ShortcutId {
  playPause('Reproducir / pausar'),
  next('Siguiente'),
  previous('Anterior'),
  shuffle('Aleatorio'),
  repeat('Repetir'),
  mute('Silenciar'),
  volumeUp('Subir volumen'),
  volumeDown('Bajar volumen'),
  seekForward('Avanzar 5 s'),
  seekBack('Retroceder 5 s'),
  favorite('Favorito'),
  jam('Abrir JAM'),
  queue('Abrir cola'),
  home('Ir a Inicio'),
  search('Ir a Búsqueda'),
  library('Ir a Biblioteca'),
  downloads('Ir a Descargas'),
  searchFocus('Enfocar búsqueda'),
  vinyl('Modo Vinilo'),
  lyrics('Letras'),
  equalizer('Ecualizador'),
  sleep('Temporizador de sueño'),
  addToQueue('Añadir a la cola (fila enfocada)'),
  addToJam('Añadir a la Jam (fila enfocada)'),
  toggleSidebar('Plegar o desplegar el panel izquierdo'),
  toggleAside('Ocultar o mostrar el panel derecho');

  const ShortcutId(this.label);
  final String label;
}

class ShortcutIntent extends Intent {
  const ShortcutIntent(this.id);
  final ShortcutId id;
}

class ShortcutService extends ChangeNotifier {
  ShortcutService(this._prefs) {
    _load();
  }

  static const prefsKey = 'shortcuts';
  final SharedPreferences _prefs;

  static const defaults = <ShortcutId, SingleActivator>{
    ShortcutId.playPause: SingleActivator(LogicalKeyboardKey.space),
    ShortcutId.next: SingleActivator(
      LogicalKeyboardKey.arrowRight,
      control: true,
    ),
    ShortcutId.previous: SingleActivator(
      LogicalKeyboardKey.arrowLeft,
      control: true,
    ),
    ShortcutId.shuffle: SingleActivator(
      LogicalKeyboardKey.keyS,
      control: true,
      shift: true,
    ),
    ShortcutId.repeat: SingleActivator(
      LogicalKeyboardKey.keyR,
      control: true,
      shift: true,
    ),
    ShortcutId.mute: SingleActivator(LogicalKeyboardKey.keyM),
    ShortcutId.volumeUp: SingleActivator(
      LogicalKeyboardKey.arrowUp,
      control: true,
    ),
    ShortcutId.volumeDown: SingleActivator(
      LogicalKeyboardKey.arrowDown,
      control: true,
    ),
    ShortcutId.seekForward: SingleActivator(LogicalKeyboardKey.arrowRight),
    ShortcutId.seekBack: SingleActivator(LogicalKeyboardKey.arrowLeft),
    ShortcutId.favorite: SingleActivator(
      LogicalKeyboardKey.keyD,
      control: true,
    ),
    ShortcutId.jam: SingleActivator(LogicalKeyboardKey.keyJ, control: true),
    ShortcutId.queue: SingleActivator(
      LogicalKeyboardKey.keyQ,
      control: true,
      shift: true,
    ),
    ShortcutId.home: SingleActivator(LogicalKeyboardKey.digit1, control: true),
    ShortcutId.search: SingleActivator(
      LogicalKeyboardKey.digit2,
      control: true,
    ),
    ShortcutId.library: SingleActivator(
      LogicalKeyboardKey.digit3,
      control: true,
    ),
    ShortcutId.downloads: SingleActivator(
      LogicalKeyboardKey.digit4,
      control: true,
    ),
    ShortcutId.searchFocus: SingleActivator(
      LogicalKeyboardKey.keyK,
      control: true,
    ),
    ShortcutId.vinyl: SingleActivator(LogicalKeyboardKey.keyI, control: true),
    // Ctrl+L no choca con EditableText (no es atajo de edición de Flutter);
    // se mantiene. Alternativa si molesta: Ctrl+Shift+L.
    ShortcutId.lyrics: SingleActivator(LogicalKeyboardKey.keyL, control: true),
    ShortcutId.equalizer: SingleActivator(
      LogicalKeyboardKey.keyE,
      control: true,
    ),
    ShortcutId.sleep: SingleActivator(
      LogicalKeyboardKey.keyT,
      control: true,
      shift: true,
    ),
    ShortcutId.addToQueue: SingleActivator(
      LogicalKeyboardKey.keyA,
      control: true,
      shift: true,
    ),
    ShortcutId.addToJam: SingleActivator(
      LogicalKeyboardKey.keyJ,
      control: true,
      shift: true,
    ),
    ShortcutId.toggleSidebar: SingleActivator(
      LogicalKeyboardKey.keyB,
      control: true,
    ),
    ShortcutId.toggleAside: SingleActivator(
      LogicalKeyboardKey.keyB,
      control: true,
      alt: true,
    ),
  };

  final Map<ShortcutId, SingleActivator> _custom = {};

  SingleActivator activatorOf(ShortcutId id) => _custom[id] ?? defaults[id]!;
  bool isCustom(ShortcutId id) => _custom.containsKey(id);
  String labelOf(ShortcutId id) => describe(activatorOf(id));

  Map<ShortcutActivator, Intent> get bindings => {
    for (final id in ShortcutId.values) activatorOf(id): ShortcutIntent(id),
  };

  /// Combinaciones del sistema o de edición de texto: no asignables.
  static bool isReserved(SingleActivator a) {
    final k = a.trigger;
    if (a.meta) return true; // Win+…
    if (a.alt &&
        (k == LogicalKeyboardKey.f4 ||
            k == LogicalKeyboardKey.tab ||
            k == LogicalKeyboardKey.escape ||
            k == LogicalKeyboardKey.space)) {
      return true;
    }
    if (a.control && a.alt && k == LogicalKeyboardKey.delete) return true;
    if (a.control &&
        (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.tab)) {
      return true;
    }
    if (a.control && !a.alt && !a.shift) {
      final edit = {
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyZ,
        LogicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyN,
      };
      if (edit.contains(k)) return true;
    }
    if (a.control && a.shift && k == LogicalKeyboardKey.keyZ) return true;
    final bare = {
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.backspace,
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.printScreen,
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.f10,
      LogicalKeyboardKey.f11,
      LogicalKeyboardKey.f12,
    };
    return bare.contains(k);
  }

  /// Otra acción que ya usa esa combinación (distinta de [except]).
  ShortcutId? conflictOf(SingleActivator a, {ShortcutId? except}) {
    for (final id in ShortcutId.values) {
      if (id != except && _same(activatorOf(id), a)) return id;
    }
    return null;
  }

  static bool _same(SingleActivator a, SingleActivator b) =>
      a.trigger == b.trigger &&
      a.control == b.control &&
      a.shift == b.shift &&
      a.alt == b.alt &&
      a.meta == b.meta;

  /// Devuelve null si se aplicó, o el motivo del rechazo.
  String? assign(ShortcutId id, SingleActivator a) {
    if (isReserved(a)) return '${describe(a)} está reservado por el sistema.';
    final other = conflictOf(a, except: id);
    if (other != null) return '${describe(a)} ya es «${other.label}».';
    if (_same(defaults[id]!, a)) {
      _custom.remove(id);
    } else {
      _custom[id] = a;
    }
    _save();
    return null;
  }

  void reset(ShortcutId id) {
    if (_custom.remove(id) != null) _save();
  }

  void resetAll() {
    _custom.clear();
    _save();
  }

  String exportJson() => jsonEncode({
    for (final e in _custom.entries) e.key.name: _encode(e.value),
  });

  /// Importa un JSON, todo o nada. Devuelve null si va bien, o el error.
  String? importJson(String text) {
    try {
      final data = jsonDecode(text);
      if (data is! Map) return 'Formato no válido.';
      final next = <ShortcutId, SingleActivator>{};
      for (final id in ShortcutId.values) {
        final raw = data[id.name];
        if (raw == null) continue;
        final a = _decode(raw);
        if (a == null) return 'Entrada no válida para «${id.label}».';
        if (isReserved(a)) {
          return '«${id.label}» usa una combinación reservada.';
        }
        next[id] = a;
      }
      final seen = <ShortcutId>[];
      for (final id in ShortcutId.values) {
        final a = next[id] ?? defaults[id]!;
        for (final p in seen) {
          if (_same(next[p] ?? defaults[p]!, a)) {
            return '«${id.label}» choca con «${p.label}».';
          }
        }
        seen.add(id);
      }
      _custom
        ..clear()
        ..addAll(next);
      _save();
      return null;
    } catch (_) {
      return 'JSON no válido.';
    }
  }

  void _load() {
    final text = _prefs.getString(prefsKey);
    if (text == null) return;
    try {
      final data = jsonDecode(text) as Map;
      for (final id in ShortcutId.values) {
        final a = data[id.name] == null ? null : _decode(data[id.name]);
        if (a != null && !isReserved(a)) _custom[id] = a;
      }
    } catch (_) {}
  }

  void _save() {
    _prefs.setString(prefsKey, exportJson());
    notifyListeners();
  }

  static Map<String, Object> _encode(SingleActivator a) => {
    'key': a.trigger.keyId,
    if (a.control) 'ctrl': true,
    if (a.shift) 'shift': true,
    if (a.alt) 'alt': true,
  };

  static SingleActivator? _decode(Object? raw) {
    if (raw is! Map || raw['key'] is! int) return null;
    final key = LogicalKeyboardKey.findKeyByKeyId(raw['key'] as int);
    if (key == null) return null;
    return SingleActivator(
      key,
      control: raw['ctrl'] == true,
      shift: raw['shift'] == true,
      alt: raw['alt'] == true,
    );
  }

  static String describe(SingleActivator a) {
    final k = a.trigger;
    final names = {
      LogicalKeyboardKey.space: 'Espacio',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
    };
    final name =
        names[k] ??
        (k.keyLabel.length == 1 ? k.keyLabel.toUpperCase() : k.keyLabel);
    return [
      if (a.control) 'Ctrl',
      if (a.alt) 'Alt',
      if (a.shift) 'Mayús',
      name,
    ].join('+');
  }

  /// ¿Debe ceder la tecla al campo de texto enfocado? Teclas sin Ctrl/Alt y
  /// las de navegación (incluso con Ctrl) son del editor.
  static bool yieldsToTextField(SingleActivator a) {
    if (!a.control && !a.alt) return true;
    final edit = {
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.end,
    };
    return edit.contains(a.trigger);
  }
}
