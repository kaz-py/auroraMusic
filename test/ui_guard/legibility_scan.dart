import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Escáner de legibilidad compartido: recorre el árbol de render y devuelve los
// textos/iconos cuyo contraste contra el fondo resuelto es menor que
// [legibilityMin]. Lo usan `slush_legibility_test.dart` y `ui_guard_test.dart`.

/// Contraste mínimo bajo el cual un texto/icono se considera ilegible.
const legibilityMin = 3.0;

double contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
}

/// Corazón de Vinilo: icono decorativo de dos capas (contorno + relleno naranja).
const _decorativeHeart = 0xf738;

Color _over(Color top, Color under) => Color.alphaBlend(top, under);

String hexColor(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

class LegibilityHit {
  LegibilityHit(this.text, this.fg, this.bg, this.ratio);
  final String text;
  final Color fg, bg;
  final double ratio;
}

/// Recorre el árbol de render y devuelve los textos/iconos con poco contraste.
List<LegibilityHit> scanLegibility(
  RenderObject root,
  Color fallbackBg,
  Size screen,
) {
  final out = <LegibilityHit>[];
  void visit(RenderObject o) {
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderParagraph) _checkParagraph(o, fallbackBg, screen, out);
    o.visitChildren(visit);
  }

  visit(root);
  return out;
}

void _checkParagraph(
  RenderParagraph p,
  Color fallbackBg,
  Size screen,
  List<LegibilityHit> out,
) {
  if (!p.hasSize || !p.attached) return;
  final plain = p.text.toPlainText().trim();
  if (plain.isEmpty) return;
  if (plain.runes.length == 1 && plain.runes.first == _decorativeHeart) return;
  var fg = p.text.style?.color ?? const Color(0xff000000);
  if (fg.a == 0) return;
  final origin = p.localToGlobal(Offset.zero);
  final rect = origin & p.size;
  if (rect.isEmpty ||
      !(Offset.zero & screen).overlaps(rect) ||
      rect.width < 1 ||
      rect.height < 1) {
    return;
  }
  var opacity = 1.0;
  final layers = <Color>[]; // de dentro hacia fuera
  var opaque = false;
  var image = false;
  for (RenderObject? a = p.parent; a != null; a = a.parent) {
    if (a is RenderOffstage && a.offstage) return;
    if (a is RenderOpacity) opacity *= a.opacity;
    if (a is RenderAnimatedOpacity) opacity *= a.opacity.value;
    if (a is RenderBox && a.hasSize) {
      // Recortes de scroll/clip: fuera de la ventana visible no cuenta.
      if (a is RenderClipRect || a is RenderViewportBase) {
        final r = a.localToGlobal(Offset.zero) & a.size;
        if (!r.overlaps(rect)) return;
      }
    }
    if (opaque || image) continue;
    Color? c;
    if (a is RenderDecoratedBox &&
        a.position == DecorationPosition.background) {
      final d = a.decoration;
      if (d is BoxDecoration) {
        if (d.image != null) {
          image = true;
          continue;
        }
        c = d.color;
        final g = d.gradient;
        if (c == null && g is LinearGradient && g.colors.isNotEmpty) {
          c = g.colors.first;
        }
      } else if (d is ShapeDecoration) {
        if (d.image != null) {
          image = true;
          continue;
        }
        c = d.color;
        final g = d.gradient;
        if (c == null && g is LinearGradient && g.colors.isNotEmpty) {
          c = g.colors.first;
        }
      }
    } else if (a is RenderCustomPaint && a.painter != null) {
      image = true; // fondo pintado a mano: no medible
      continue;
    } else if (a.runtimeType.toString() == '_RenderChip') {
      final e = (p.debugCreator is DebugCreator)
          ? (p.debugCreator! as DebugCreator).element
          : null;
      RawChip? chip;
      e?.visitAncestorElements((x) {
        if (x.widget is RawChip) {
          chip = x.widget as RawChip;
          return false;
        }
        return true;
      });
      if (chip == null || e == null) {
        image = true;
        continue;
      }
      final t = ChipTheme.of(e);
      c = chip!.selected == true
          ? (chip!.selectedColor ?? t.selectedColor)
          : (chip!.backgroundColor ?? t.backgroundColor);
      if (c == null) {
        image = true;
        continue;
      }
    } else if (a.runtimeType.toString() == '_RenderColoredBox') {
      c = (a as dynamic).color as Color;
    } else if (a is RenderPhysicalModel) {
      c = a.color;
    } else if (a is RenderPhysicalShape) {
      c = a.color;
    }
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= .999) opaque = true;
    }
  }
  if (image || opacity < .05) return;
  var bg = opaque ? layers.removeLast() : fallbackBg;
  for (final l in layers.reversed) {
    bg = _over(l, bg);
  }
  fg = fg.withValues(alpha: fg.a * opacity);
  final shown = _over(fg, bg);
  final r = contrastRatio(shown, bg);
  if (r < legibilityMin) {
    final cp = plain.runes.first;
    final label = plain.length == 1 && cp >= 0xe000 && cp <= 0xf8ff
        ? 'icono U+${cp.toRadixString(16)}'
        : plain.replaceAll('\n', ' ');
    out.add(
      LegibilityHit(
        label.length > 32 ? label.substring(0, 32) : label,
        shown,
        bg,
        r,
      ),
    );
  }
}
