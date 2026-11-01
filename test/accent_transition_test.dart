import 'dart:math';

import 'package:aurora_music/main.dart';
import 'package:aurora_music/theme/accent_transition.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + .05) / (min(x, y) + .05);
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

double _step(Color a, Color b) =>
    (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();

const orange = Color(0xffe86927);
const blue = Color(0xff3478c8);
const green = Color(0xff28734a);

class _Frame {
  _Frame(this.accent, this.theme, this.moving, this.scope);
  final Color accent;
  final ThemeData theme;
  final bool moving;
  final Color scope;
}

typedef _Build = ThemeData Function(Brightness, Color);

/// Pinta una app mínima con el mismo `AccentTransition` de `AuroraApp` y anota
/// lo que recibe el tema en cada fotograma.
Widget _app(
  Color accent,
  _Build build,
  Brightness brightness,
  List<_Frame> frames, {
  bool instant = false,
}) => AccentTransition(
  accent: accent,
  instant: instant,
  builder: (context, a, moving) {
    final theme = build(brightness, a);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AccentScope(
        accent: a,
        child: Builder(
          builder: (context) {
            frames.add(_Frame(a, theme, moving, AccentScope.of(context, a)));
            return const SizedBox();
          },
        ),
      ),
    );
  },
);

/// Pasos de 16 ms hasta pasar `ms`; devuelve cuántos fotogramas se anotaron.
Future<void> _run(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  final kinds = <String, _Build>{
    'atelier': auroraTheme,
    'modern': modernTheme,
    'brasa': brasaTheme,
    'slush': slushTheme,
  };
  final cases = [
    for (final e in kinds.entries)
      for (final b in Brightness.values)
        if (!(e.key == 'brasa' && b == Brightness.light)) (e.key, e.value, b),
  ];

  group('lerpAccent', () {
    test('extremos exactos y camino corto del tono sin pasar por gris', () {
      expect(lerpAccent(orange, blue, 0), orange);
      expect(lerpAccent(orange, blue, 1), blue);
      final opposite = [
        HSLColor.fromAHSL(1, 7.5, .65, .65).toColor(),
        HSLColor.fromAHSL(1, 187.5, .65, .65).toColor(),
      ];
      for (final pair in [
        (orange, blue),
        (blue, orange),
        (opposite[0], opposite[1]),
        (green, orange),
      ]) {
        var minSat = 1.0;
        var maxStep = 0.0;
        Color? prev;
        for (var i = 0; i <= 100; i++) {
          final c = lerpAccent(pair.$1, pair.$2, i / 100);
          minSat = min(minSat, HSLColor.fromColor(c).saturation);
          if (prev != null) maxStep = max(maxStep, _step(prev, c));
          prev = c;
        }
        expect(minSat, greaterThan(.4), reason: '${pair.$1} -> ${pair.$2}');
        expect(maxStep, lessThan(.12), reason: 'sin saltos');
      }
    });

    test('un extremo gris toma el tono del otro', () {
      const grey = Color(0xff808080);
      final mid = HSLColor.fromColor(lerpAccent(grey, orange, .5));
      expect(mid.hue, closeTo(HSLColor.fromColor(orange).hue, 1));
    });
  });

  group('AccentTransition', () {
    for (final (name, build, brightness) in cases) {
      testWidgets('$name $brightness: suave, continua y legible', (
        tester,
      ) async {
        final frames = <_Frame>[];
        await tester.pumpWidget(_app(orange, build, brightness, frames));
        // Primera carga: sin animación.
        expect(frames.single.accent, orange);
        expect(frames.single.moving, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);

        // Cambio de canción: naranja -> azul.
        frames.clear();
        await tester.pumpWidget(_app(blue, build, brightness, frames));
        await _run(tester, 400);
        final mid = frames.last;
        await _run(tester, 520);
        final end = frames.last;
        expect(frames.first.accent, orange, reason: 'arranca del color viejo');
        expect(end.accent, blue);
        expect(end.moving, isFalse);
        expect(end.scope, blue, reason: 'AccentScope sigue al acento animado');
        for (final f in frames) {
          expect(f.scope, f.accent);
        }
        // Mitad: ni extremo, y igual a la mezcla HSL a t=.5 (±1 fotograma).
        final expectedMid = lerpAccent(orange, blue, .5);
        for (final ch in [
          (mid.accent.r, expectedMid.r),
          (mid.accent.g, expectedMid.g),
          (mid.accent.b, expectedMid.b),
        ]) {
          expect((ch.$1 - ch.$2).abs(), lessThan(.06));
        }

        var minText = 99.0, minAction = 99.0, minBgSat = 1.0, maxBgStep = 0.0;
        Color? prevBg;
        for (final f in frames) {
          final s = f.theme.colorScheme;
          final bg = f.theme.scaffoldBackgroundColor;
          minText = min(minText, _contrast(s.onSurface, bg));
          minText = min(minText, _contrast(s.onSurface, s.surface));
          minAction = min(minAction, _contrast(s.onPrimary, s.primary));
          minBgSat = min(minBgSat, HSLColor.fromColor(bg).saturation);
          if (prevBg != null) maxBgStep = max(maxBgStep, _step(prevBg, bg));
          prevBg = bg;
        }
        expect(minText, greaterThanOrEqualTo(3), reason: 'texto en todo frame');
        expect(minAction, greaterThanOrEqualTo(3));
        final es = end.theme.colorScheme;
        expect(
          _contrast(es.onSurface, end.theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(es.onPrimary, es.primary), greaterThanOrEqualTo(4.5));
        expect(maxBgStep, lessThan(.05), reason: 'fondo sin saltos por frame');
        // El fondo de Slush ya no cruza por gris (RGB directo bajaba a ~.1).
        if (name == 'slush') expect(minBgSat, greaterThan(.25));

        // ignore: avoid_print
        print(
          'TABLA $name ${brightness.name.padRight(5)} '
          'acento ${_hex(frames.first.accent)} ${_hex(mid.accent)} ${_hex(end.accent)} | '
          'fondo ${_hex(frames.first.theme.scaffoldBackgroundColor)} '
          '${_hex(mid.theme.scaffoldBackgroundColor)} '
          '${_hex(end.theme.scaffoldBackgroundColor)} | '
          'primary ${_hex(frames.first.theme.colorScheme.primary)} '
          '${_hex(mid.theme.colorScheme.primary)} '
          '${_hex(end.theme.colorScheme.primary)} | '
          'minTexto ${minText.toStringAsFixed(2)} minAccion ${minAction.toStringAsFixed(2)} '
          'maxPasoFondo ${maxBgStep.toStringAsFixed(4)} minSatFondo ${minBgSat.toStringAsFixed(2)} '
          'fotogramas ${frames.length}',
        );
      });
    }

    testWidgets('interrupción a mitad: continúa desde el color mostrado', (
      tester,
    ) async {
      final frames = <_Frame>[];
      await tester.pumpWidget(
        _app(orange, slushTheme, Brightness.light, frames),
      );
      await tester.pumpWidget(_app(blue, slushTheme, Brightness.light, frames));
      await _run(tester, 304);
      final before = frames.last;
      expect(before.accent, isNot(orange));
      expect(before.accent, isNot(blue));
      frames.clear();
      await tester.pumpWidget(
        _app(green, slushTheme, Brightness.light, frames),
      );
      expect(
        _step(frames.first.accent, before.accent),
        lessThan(.001),
        reason: 'el primer fotograma nuevo es el color que se veía',
      );
      expect(frames.first.moving, isTrue);
      await _run(tester, 400);
      var maxStep = 0.0;
      for (var i = 1; i < frames.length; i++) {
        maxStep = max(maxStep, _step(frames[i - 1].accent, frames[i].accent));
      }
      expect(maxStep, lessThan(.1));
      await _run(tester, 520);
      expect(frames.last.accent, green);
      expect(frames.last.moving, isFalse);
    });

    testWidgets('movimiento reducido (sistema o ajuste): cambio instantáneo', (
      tester,
    ) async {
      for (final viaSystem in [true, false]) {
        final frames = <_Frame>[];
        if (viaSystem) {
          tester.platformDispatcher.accessibilityFeaturesTestValue =
              const FakeAccessibilityFeatures(disableAnimations: true);
          addTearDown(
            tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
          );
        } else {
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
        }
        await tester.pumpWidget(
          _app(
            orange,
            auroraTheme,
            Brightness.light,
            frames,
            instant: !viaSystem,
          ),
        );
        frames.clear();
        await tester.pumpWidget(
          _app(
            blue,
            auroraTheme,
            Brightness.light,
            frames,
            instant: !viaSystem,
          ),
        );
        expect(frames.last.accent, blue, reason: 'viaSystem=$viaSystem');
        expect(frames.last.moving, isFalse);
        expect(tester.binding.hasScheduledFrame, isFalse);
      }
    });

    testWidgets('reducir movimiento a mitad de transición salta al final', (
      tester,
    ) async {
      final frames = <_Frame>[];
      await tester.pumpWidget(
        _app(orange, auroraTheme, Brightness.light, frames),
      );
      await tester.pumpWidget(
        _app(blue, auroraTheme, Brightness.light, frames),
      );
      await _run(tester, 200);
      await tester.pumpWidget(
        _app(blue, auroraTheme, Brightness.light, frames, instant: true),
      );
      expect(frames.last.accent, blue);
      expect(frames.last.moving, isFalse);
    });
  });
}
