import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/mini_player/blurred_cover_backdrop.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _track = Track(
  id: 'a',
  title: 'Una canción',
  artist: 'Un artista',
  artworkUrl: 'asset:assets/design_idea/descargas_locales_aurora_00.png',
  duration: Duration(minutes: 3),
);

void main() {
  late AppController controller;

  Future<void> mount(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: VinylPlayer(controller: controller)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // La carga real no avanza en el reloj falso: deja vencer su plazo (10 s).
    await tester.pump(const Duration(seconds: 11));
  }

  Future<void> setup(WidgetTester tester) async {
    controller = (await tester.runAsync(
      () => createTestController(tracks: [_track]),
    ))!;
    addTearDown(() => closeTestController(controller));
    controller.queue = [_track];
    controller.queueIndex = 0;
  }

  final themes = <String, ThemeData?>{
    'atelier': null,
    'modern': modernTheme(Brightness.light, Colors.teal),
    'brasa': brasaTheme(Brightness.dark, Colors.orange),
  };

  for (final entry in themes.entries) {
    testWidgets('${entry.key}: sin el ajuste no hay fondo de portada', (
      tester,
    ) async {
      await setup(tester);
      await mount(tester, theme: entry.value);
      expect(find.byType(BlurredCoverBackdrop), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${entry.key}: con el ajuste el fondo sube tras la cabecera', (
      tester,
    ) async {
      await setup(tester);
      controller.setBlurredCoverMode(true);
      for (final (size, scale) in [
        (const Size(390, 844), 1.0),
        (const Size(320, 640), 2.0),
        (const Size(1200, 800), 1.0),
      ]) {
        await mount(tester, theme: entry.value, size: size, scale: scale);
        expect(find.byType(BlurredCoverBackdrop), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('sin pista no se pinta el fondo aunque el ajuste esté activo', (
    tester,
  ) async {
    await setup(tester);
    controller.queue = [];
    controller.queueIndex = -1;
    controller.setBlurredCoverMode(true);
    await mount(tester);
    expect(find.byType(BlurredCoverBackdrop), findsNothing);
  });

  testWidgets('Slush: con el ajuste monta el fondo sin errores', (
    tester,
  ) async {
    await setup(tester);
    controller.setBlurredCoverMode(true);
    await mount(tester, theme: slushTheme(Brightness.light, Colors.teal));
    expect(find.byType(BlurredCoverBackdrop), findsOneWidget);
  });
}
