import 'package:aurora_music/ui/shell/shell_nav.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legibility_scan.dart';

/// Tipos de fallo que detecta la guarda de interfaz.
enum GuardKind { exception, contrast, hit, clip }

/// Un fallo concreto, ya sin duplicados dentro de su caso.
class GuardViolation {
  const GuardViolation(this.kind, this.detail);
  final GuardKind kind;
  final String detail;

  @override
  String toString() => '[${kind.name}] $detail';
}

/// Tamaño mínimo (px lógicos) de un objetivo táctil en móvil.
const minHitSize = 40.0;

/// Anchura bajo la cual rige el mínimo táctil (móvil).
const phoneMaxWidth = 600.0;

/// Recoge todas las excepciones del framework (desbordes incluidos) en vez de
/// quedarse solo con la primera. Devuelve el colector; se restaura solo al
/// acabar el test.
class ErrorCollector {
  ErrorCollector._(this._previous);
  final FlutterExceptionHandler? _previous;
  final _seen = <String>{};
  final violations = <GuardViolation>[];

  static ErrorCollector install(WidgetTester tester) {
    final collector = ErrorCollector._(FlutterError.onError);
    FlutterError.onError = collector._record;
    addTearDown(collector.restore);
    return collector;
  }

  /// Devuelve el manejador original. Hay que llamarlo antes de `fail`/`expect`
  /// fallidos: el binding exige su propio manejador para registrar el error.
  void restore() => FlutterError.onError = _previous;

  void _record(FlutterErrorDetails d) {
    final first = d.exceptionAsString().split('\n').first.trim();
    final deep = d.toString();
    final loc = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(deep)?.group(0);
    final detail = loc == null ? first : '$first @ $loc';
    if (_seen.add(detail)) {
      violations.add(GuardViolation(GuardKind.exception, detail));
    }
  }

  /// Devuelve y vacía lo recogido desde la última llamada.
  List<GuardViolation> drain() {
    final out = [...violations];
    violations.clear();
    _seen.clear();
    return out;
  }
}

List<GuardViolation> checkContrast(
  WidgetTester tester,
  Color fallbackBg,
  Size screen,
) {
  final seen = <String>{};
  final out = <GuardViolation>[];
  for (final h in scanLegibility(
    tester.binding.renderViews.first,
    fallbackBg,
    screen,
  )) {
    final d =
        '"${h.text}" fg ${hexColor(h.fg)} sobre ${hexColor(h.bg)} = '
        '${h.ratio.toStringAsFixed(2)} (mín ${legibilityMin.toStringAsFixed(0)})';
    if (seen.add(d)) out.add(GuardViolation(GuardKind.contrast, d));
  }
  return out;
}

bool _interactive(Widget w) {
  if (w is ButtonStyleButton) return w.enabled;
  if (w is ListTile) return w.enabled && (w.onTap != null);
  if (w is RawChip) {
    return w.isEnabled && (w.onPressed != null || w.onSelected != null);
  }
  if (w is InkResponse) return w.onTap != null;
  if (w is GestureDetector) return w.onTap != null;
  return false;
}

String _label(Element e) {
  String? text;
  String? tooltip;
  void walk(Element x) {
    final w = x.widget;
    if (text == null && w is Text && (w.data ?? '').trim().isNotEmpty) {
      text = w.data!.trim();
    } else if (text == null && w is Icon && w.icon != null) {
      text = 'icono U+${w.icon!.codePoint.toRadixString(16)}';
    } else if (w is Tooltip) {
      tooltip ??= w.message;
    }
    x.visitChildren(walk);
  }

  walk(e);
  e.visitAncestorElements((a) {
    if (a.widget is Tooltip) {
      tooltip ??= (a.widget as Tooltip).message;
      return false;
    }
    return a.widget is! Scaffold && a.widget is! Material;
  });
  final base = tooltip ?? text ?? '?';
  return base.length > 30 ? base.substring(0, 30) : base;
}

/// Objetivos táctiles visibles y activos menores de [minHitSize] en algún eje.
List<GuardViolation> checkHitTargets(WidgetTester tester) {
  final finder = find
      .byWidgetPredicate((w) => _interactive(w), description: 'interactivo')
      .hitTestable();
  final seen = <String>{};
  final out = <GuardViolation>[];
  for (final e in finder.evaluate()) {
    // La barra de título de escritorio (ventana, perfil) es de ratón, no táctil.
    if (e.findAncestorWidgetOfExactType<MouseOnlyRegion>() != null) continue;
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final s = ro.size;
    if (s.width >= minHitSize - .5 && s.height >= minHitSize - .5) continue;
    final rect = ro.localToGlobal(Offset.zero) & s;
    final key =
        '${rect.left.round()},${rect.top.round()},${s.width.round()},${s.height.round()}';
    if (!seen.add(key)) continue;
    out.add(
      GuardViolation(
        GuardKind.hit,
        '${e.widget.runtimeType} "${_label(e)}" mide '
        '${s.width.round()}x${s.height.round()} (mín ${minHitSize.round()}x${minHitSize.round()})',
      ),
    );
  }
  return out;
}

bool _fullyInside(Rect r, double w) => r.left >= -1 && r.right <= w + 1;

/// Texto/imagen visible que cruza el borde horizontal de la pantalla sin
/// estar dentro de un scroll horizontal ni recortado por un contenedor.
List<GuardViolation> checkClipping(WidgetTester tester, Size screen) {
  final out = <GuardViolation>[];
  final seen = <String>{};
  void visit(RenderObject o) {
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderParagraph || o is RenderImage) {
      _checkLeaf(o, screen, out, seen);
    }
    o.visitChildren(visit);
  }

  visit(tester.binding.renderViews.first);
  return out;
}

void _checkLeaf(
  RenderObject o,
  Size screen,
  List<GuardViolation> out,
  Set<String> seen,
) {
  final box = o as RenderBox;
  if (!box.hasSize || !box.attached || box.size.isEmpty) return;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final w = screen.width;
  if (_fullyInside(rect, w)) return;
  if (rect.left >= w || rect.right <= 0) return; // fuera por completo: oculto
  for (RenderObject? a = box.parent; a != null; a = a.parent) {
    if (a is RenderOffstage && a.offstage) return;
    if (a is RenderOpacity && a.opacity < .05) return;
    if (a is RenderViewportBase && a.axis == Axis.horizontal) return;
    if (a is RenderBox &&
        a.hasSize &&
        (a is RenderClipRect ||
            a is RenderClipRRect ||
            a is RenderClipPath ||
            a is RenderPhysicalModel ||
            a is RenderPhysicalShape)) {
      final r = a.localToGlobal(Offset.zero) & a.size;
      if (_fullyInside(r, w)) return;
    }
  }
  String label;
  if (box is RenderParagraph) {
    final t = box.text.toPlainText().trim();
    if (t.isEmpty) return;
    label = t.length == 1 && t.runes.first >= 0xe000
        ? 'icono U+${t.runes.first.toRadixString(16)}'
        : '"${t.replaceAll('\n', ' ')}"';
    if (label.length > 36) label = '${label.substring(0, 36)}…';
  } else {
    label = 'imagen';
  }
  final d =
      '$label sale de la pantalla: x ${rect.left.round()}..${rect.right.round()} '
      'de ${w.round()}';
  if (seen.add(d)) out.add(GuardViolation(GuardKind.clip, d));
}
