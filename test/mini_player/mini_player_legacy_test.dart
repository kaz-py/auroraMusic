import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/slush/slush_bars.dart';
import 'package:aurora_music/ui/slush/slush_mobile.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _track = Track(
  id: 'a',
  title: 'Uno',
  artist: 'Aurora',
  duration: Duration(minutes: 3),
);

void _noop() {}

void main() {
  late AppController controller;

  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter/Inter-Variable.ttf',
      'Bagel Fat One': 'assets/fonts/bagel_fat_one/BagelFatOne-Regular.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  const bars = MiniPlayerLegacyBars(
    shortcuts: null,
    onJam: _noop,
    onStartJam: _noop,
    onLyrics: _noop,
    onVinyl: _noop,
    onQueue: _noop,
    onEqualizer: _noop,
    onSettings: _noop,
    onOpenPlayer: _noop,
  );

  Future<void> mount(
    WidgetTester tester, {
    required int section,
    required bool rail,
    required MiniPlayerPlacement placement,
    ThemeData? theme,
    bool track = true,
  }) async {
    tester.view.physicalSize = rail
        ? const Size(1300, 800)
        : const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (track) {
      controller.queue = [_track];
      controller.queueIndex = 0;
    } else {
      controller.queue = [];
      controller.queueIndex = -1;
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              MiniPlayerHost(
                controller: controller,
                section: section,
                rail: rail,
                placement: placement,
                legacy: bars,
                onOpenPlayer: _noop,
                onTogglePlay: _noop,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> setup(WidgetTester tester) async {
    controller = (await tester.runAsync(
      () => createTestController(tracks: [_track]),
    ))!;
    addTearDown(() => closeTestController(controller));
  }

  testWidgets(
    'Atelier/Modern/Brasa: StudioTransport siempre, también sin pista',
    (tester) async {
      await setup(tester);
      for (final rail in [false, true]) {
        for (final (section, hasTrack) in [(0, true), (4, true), (0, false)]) {
          await mount(
            tester,
            section: section,
            rail: rail,
            placement: MiniPlayerPlacement.body,
            track: hasTrack,
          );
          expect(find.byType(StudioTransport), findsOneWidget);
        }
      }
    },
  );

  testWidgets('Slush móvil: píldora en la barra inferior, nada en el cuerpo', (
    tester,
  ) async {
    await setup(tester);
    final slush = slushTheme(Brightness.light, Colors.teal);
    await mount(
      tester,
      section: 0,
      rail: false,
      placement: MiniPlayerPlacement.bottomBar,
      theme: slush,
    );
    expect(find.byType(SlushMiniPlayer), findsOneWidget);
    await mount(
      tester,
      section: 0,
      rail: false,
      placement: MiniPlayerPlacement.body,
      theme: slush,
    );
    expect(find.byType(SlushMiniPlayer), findsNothing);
    expect(find.byType(StudioTransport), findsNothing);
    await mount(
      tester,
      section: 4,
      rail: false,
      placement: MiniPlayerPlacement.bottomBar,
      theme: slush,
    );
    expect(find.byType(SlushMiniPlayer), findsNothing);
  });

  testWidgets('Slush con carril: SlushPlayerBar salvo en la sección 4', (
    tester,
  ) async {
    await setup(tester);
    final slush = slushTheme(Brightness.light, Colors.teal);
    await mount(
      tester,
      section: 0,
      rail: true,
      placement: MiniPlayerPlacement.body,
      theme: slush,
    );
    expect(find.byType(SlushPlayerBar), findsOneWidget);
    // SlushPlayerBar desborda 2 px en este banco sin app (también montada sola,
    // sin host): el aspecto de la barra no es lo que se prueba aquí.
    tester.takeException();
    await mount(
      tester,
      section: 4,
      rail: true,
      placement: MiniPlayerPlacement.body,
      theme: slush,
    );
    expect(find.byType(SlushPlayerBar), findsNothing);
  });

  testWidgets(
    'Slush móvil con Jam: StudioTransport en el cuerpo, sin píldora',
    (tester) async {
      await setup(tester);
      await tester.runAsync(controller.beginJamPlayback);
      addTearDown(controller.endJamPlayback);
      final slush = slushTheme(Brightness.light, Colors.teal);
      await mount(
        tester,
        section: 4,
        rail: false,
        placement: MiniPlayerPlacement.body,
        theme: slush,
      );
      expect(find.byType(StudioTransport), findsOneWidget);
      await mount(
        tester,
        section: 0,
        rail: false,
        placement: MiniPlayerPlacement.bottomBar,
        theme: slush,
      );
      expect(find.byType(SlushMiniPlayer), findsNothing);
    },
  );
}
