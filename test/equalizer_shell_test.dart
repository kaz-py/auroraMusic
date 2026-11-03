import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/studio/equalizer_panel.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(
  id: 'song',
  title: 'Canción base',
  artist: 'Artista',
  duration: Duration(minutes: 3),
);

void main() {
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  late AppController app;
  late ProviderContainer container;

  setUp(() async {
    app = await createTestController(tracks: [_song], audio: FakeAudio());
    await app.playTrack(_song);
    await app.pausePlayback();
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => app)],
    );
  });

  tearDown(() async {
    container.dispose();
    await app.closed;
    if (await app.supportDirectory.exists()) {
      await app.supportDirectory.delete(recursive: true);
    }
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuroraApp()),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Las pantallas con animación continua (vinilo) no "se asientan".
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 500));
  }

  // Botón de EQ del mini (carril ancho): tooltip «Ecualizador…».
  final miniEqButton = find.descendant(
    of: find.byType(MiniPlayerGestures),
    matching: find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message?.startsWith('Ecualizador') ?? false),
    ),
  );

  testWidgets('the mini EQ button is on home, queue, lyrics and Jam', (
    tester,
  ) async {
    await mount(tester, const Size(1400, 900));
    for (final (key, shift) in [
      (LogicalKeyboardKey.digit1, false), // inicio
      (LogicalKeyboardKey.keyQ, true), // cola
      (LogicalKeyboardKey.keyL, false), // letras (página)
      (LogicalKeyboardKey.keyJ, false), // Jam
    ]) {
      await chord(tester, key, shift: shift);
      expect(miniEqButton, findsOneWidget, reason: 'section for $key');
      expect(tester.takeException(), isNull);
    }
    // Vinilo: el mini se oculta por contrato; Ctrl+E sigue abriendo la hoja.
    await chord(tester, LogicalKeyboardKey.keyI);
    expect(find.byType(VinylPlayer), findsOneWidget);
    expect(find.byType(MiniPlayerGestures), findsNothing);
    await chord(tester, LogicalKeyboardKey.keyE);
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ctrl+E opens the EQ sheet over the current screen', (
    tester,
  ) async {
    await mount(tester, const Size(1400, 900));
    await chord(tester, LogicalKeyboardKey.keyQ, shift: true);
    await chord(tester, LogicalKeyboardKey.keyE);
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.byType(MiniPlayerGestures), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the mini EQ button opens the same EQ sheet', (tester) async {
    await mount(tester, const Size(1400, 900));
    await chord(tester, LogicalKeyboardKey.keyQ, shift: true);
    expect(find.byType(EqualizerPanel), findsNothing);
    await tester.tap(miniEqButton);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping the mini on a phone opens the vinyl player', (
    tester,
  ) async {
    await mount(tester, const Size(500, 900));
    await tester.tap(find.text(_song.title).last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(VinylPlayer), findsOneWidget);
    expect(find.byType(MiniPlayerGestures), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
