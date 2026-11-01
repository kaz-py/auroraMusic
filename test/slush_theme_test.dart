import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'dart:math' as math;

void main() {
  test('Modern y Brasa tiñen el fondo con el color de portada', () {
    const a = Color(0xffff0000), b = Color(0xff0000ff);
    for (final f in [modernTheme, brasaTheme, slushTheme]) {
      final x = f(Brightness.dark, a).colorScheme.surface;
      final y = f(Brightness.dark, b).colorScheme.surface;
      expect(x, isNot(y));
    }
  });

  double ratio(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  const accents = [
    Color(0xffff0000),
    Color(0xff2255cc),
    Color(0xff22aa66),
    Color(0xffffcc00),
    Color(0xff8844cc),
  ];

  test('Slush claro: tinta negra, papel blanco y marca propia', () {
    final t = slushTheme(Brightness.light, const Color(0xff2255cc));
    expect(t.brightness, Brightness.light);
    expect(t.colorScheme.onSurface, Slush.ink);
    expect(t.extension<SlushMarker>(), isNotNull);
    expect(t.extension<SlushPalette>(), SlushPalette.light);
    expect(t.colorScheme.surface.computeLuminance(), greaterThan(.6));
  });

  test('Slush oscuro: paleta crema sobre papel oscuro con contraste AA', () {
    final t = slushTheme(Brightness.dark, const Color(0xffe86927));
    final p = t.extension<SlushPalette>()!;
    expect(t.brightness, Brightness.dark);
    expect(p, SlushPalette.dark);
    expect(t.extension<SlushMarker>(), isNotNull);
    expect(ratio(p.ink, p.paper), greaterThanOrEqualTo(4.5));
    expect(ratio(p.ink, t.colorScheme.surface), greaterThanOrEqualTo(4.5));
    for (final a in accents) {
      final s = slushTheme(Brightness.dark, a).colorScheme;
      expect(ratio(s.onSurface, s.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(s.surface.computeLuminance(), lessThan(.2));
    }
  });

  test('Slush: contraste AA en texto y controles', () {
    for (final a in accents) {
      final s = slushTheme(Brightness.light, a).colorScheme;
      for (final bg in [s.surface, Colors.white, Slush.mint, Slush.yellow]) {
        expect(ratio(Slush.ink, bg), greaterThanOrEqualTo(4.5));
      }
      expect(ratio(s.onSurfaceVariant, s.surface), greaterThanOrEqualTo(4.5));
      expect(ratio(s.outline, s.surface), greaterThanOrEqualTo(3));
      expect(ratio(Slush.mint, Slush.ink), greaterThanOrEqualTo(3));
    }
  });

  test('Modern: contraste AA en claro y oscuro con varios acentos', () {
    for (final b in Brightness.values) {
      for (final a in accents) {
        final s = modernTheme(b, a).colorScheme;
        void text(Color fg, Color bg) =>
            expect(ratio(fg, bg), greaterThanOrEqualTo(4.5), reason: '$b $a');
        void ctrl(Color fg, Color bg) =>
            expect(ratio(fg, bg), greaterThanOrEqualTo(3), reason: '$b $a');
        text(s.onSurface, s.surface);
        text(s.onSurface, s.surfaceContainerHigh);
        text(s.onSurfaceVariant, s.surfaceContainerHigh);
        text(s.onPrimary, s.primary);
        text(s.onSecondaryContainer, s.secondaryContainer);
        ctrl(s.outline, s.surface);
        ctrl(s.outline, s.surfaceContainerHigh);
        ctrl(s.primary, s.surface);
        ctrl(s.tertiary, s.surface);
      }
    }
  });
}
