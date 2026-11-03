import 'dart:math' as math;

import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

const _accents = [
  Color(0xffff0000),
  Color(0xff2255cc),
  Color(0xff22aa66),
  Color(0xffffcc00),
  Color(0xff8844cc),
  Color(0xff111111),
  Color(0xffffffff),
];

void main() {
  void text(String what, Color fg, Color bg) =>
      expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
  void ctrl(String what, Color fg, Color bg) =>
      expect(ratio(fg, bg), greaterThanOrEqualTo(3), reason: what);

  test('Slush: texto 4.5:1 y controles 3:1 con varios acentos', () {
    for (final a in _accents) {
      final t = slushTheme(Brightness.light, a);
      final s = t.colorScheme;
      final tag = 'acento $a';
      for (final f in [
        Colors.white,
        Slush.mint,
        Slush.yellow,
        Slush.lilac,
        s.surface,
      ]) {
        text('tinta sobre $f ($tag)', Slush.ink, f);
        ctrl('contorno sobre $f ($tag)', Slush.ink, f);
      }
      final chipSide = (t.chipTheme.side! as WidgetStateProperty<BorderSide?>)
          .resolve({});
      expect(chipSide?.color, Slush.ink);
      expect(chipSide?.width, greaterThanOrEqualTo(2));
      expect(t.chipTheme.color!.resolve({WidgetState.selected}), Slush.mint);
      expect(t.chipTheme.color!.resolve({}), SlushPalette.light.paper);
      final track = t.switchTheme.trackColor!;
      final on = track.resolve({WidgetState.selected})!;
      final off = track.resolve({})!;
      expect(on, isNot(off));
      ctrl('pulgar sobre pista on ($tag)', Slush.ink, on);
      ctrl('pulgar sobre pista off ($tag)', Slush.ink, off);
      ctrl(
        'pulgar del deslizador ($tag)',
        t.sliderTheme.thumbColor!,
        s.surface,
      );
      ctrl(
        'tramo inactivo ($tag)',
        t.sliderTheme.inactiveTrackColor!,
        s.surface,
      );
      text(
        'fila seleccionada ($tag)',
        t.listTileTheme.selectedColor!,
        t.listTileTheme.selectedTileColor!,
      );
    }
  });

  test('Modern: texto 4.5:1 y controles 3:1 en claro y oscuro', () {
    for (final b in Brightness.values) {
      for (final a in _accents) {
        final t = modernTheme(b, a);
        final s = t.colorScheme;
        final tag = '$b $a';
        text('chip off ($tag)', s.onSurface, s.surfaceContainerHighest);
        text('chip on ($tag)', s.onPrimary, s.primary);
        final side = t.chipTheme.side!.color;
        ctrl('borde chip / tarjeta ($tag)', side, s.surfaceContainerLow);
        ctrl('borde chip / relleno ($tag)', side, s.surfaceContainerHighest);
        ctrl('borde / fondo ($tag)', s.outline, s.surface);
        ctrl('pista on ($tag)', s.primary, s.surfaceContainerLow);
        text('botón secundario ($tag)', s.primary, s.surfaceContainerLow);
        text(
          'fila seleccionada ($tag)',
          t.listTileTheme.selectedColor!,
          t.listTileTheme.selectedTileColor!,
        );
        expect(
          ratio(s.outlineVariant, s.surface),
          greaterThanOrEqualTo(2.5),
          reason: tag,
        );
      }
    }
  });
}
