import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_player.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

double _ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
}

void main() {
  testWidgets('Slush vinilo se pinta en escritorio y móvil sin errores', (
    tester,
  ) async {
    final controller = (await tester.runAsync(createTestController))!;
    try {
      for (final size in [const Size(1280, 800), const Size(390, 800)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: slushTheme(Brightness.light, const Color(0xffe86927)),
            home: Scaffold(
              body: VinylPlayer(controller: controller, onSection: (_) {}),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.text('VINILO'), findsOneWidget);
        expect(find.byKey(const ValueKey('cassette-toggle')), findsOneWidget);
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => closeTestController(controller));
      await tester.binding.setSurfaceSize(null);
    }
  });

  testWidgets(
    'Slush vinilo: sin desborde 360-1920 px, texto x2, claro y oscuro; '
    'controles táctiles >= 44 bajo 900',
    (tester) async {
      final controller = (await tester.runAsync(createTestController))!;
      try {
        for (final brightness in Brightness.values) {
          for (final scale in const [1.0, 2.0]) {
            for (final width in const [
              360.0,
              412.0,
              600.0,
              900.0,
              1440.0,
              1920.0,
            ]) {
              await tester.binding.setSurfaceSize(Size(width, 900));
              await tester.pumpWidget(
                MaterialApp(
                  theme: slushTheme(brightness, const Color(0xffe86927)),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: Scaffold(
                    body: VinylPlayer(
                      controller: controller,
                      onSection: (_) {},
                    ),
                  ),
                ),
              );
              await tester.pump();
              final reason = '$brightness ${width}px x$scale';
              expect(tester.takeException(), isNull, reason: reason);
              if (width < Breakpoints.medium) {
                for (final tip in const [
                  'Anterior',
                  'Siguiente',
                  'Reproducir',
                ]) {
                  final size = tester.getSize(find.byTooltip(tip).first);
                  expect(
                    size.shortestSide,
                    greaterThanOrEqualTo(SlushControl.touch),
                    reason: '$tip $reason',
                  );
                }
              }
            }
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => closeTestController(controller));
        await tester.binding.setSurfaceSize(null);
      }
    },
  );

  test(
    'slushScreenColor oscuro cae en la capa screen y mantiene contraste',
    () {
      for (final accent in const [
        Color(0xffe86927),
        Color(0xff3b8bf2),
        Color(0xff5fe0a0),
        Color(0xffffd62e),
        Color(0xff5b3fe0),
        Color(0xfff2f2f2),
      ]) {
        final c = slushScreenColor(accent, dark: true);
        expect(
          _ratio(c, SlushPalette.dark.screen),
          lessThan(1.25),
          reason: 'tinte leve $accent',
        );
        expect(
          _ratio(SlushPalette.dark.ink3, c),
          greaterThanOrEqualTo(4.5),
          reason: 'ink3 sobre $accent',
        );
        expect(
          _ratio(SlushPalette.dark.ink, c),
          greaterThanOrEqualTo(12),
          reason: 'ink sobre $accent',
        );
        final light = slushScreenColor(accent);
        expect(_ratio(Slush.ink, light), greaterThanOrEqualTo(4.5));
      }
    },
  );
}
