import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/queue_panel.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/ui/follow_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _long =
    'Un título extremadamente largo para comprobar que se recorta con puntos suspensivos en móvil';
const _tracks = [
  Track(
    id: 'a',
    title: _long,
    artist: 'Artista con un nombre también bastante largo para el móvil',
    pageUrl: 'https://www.youtube.com/watch?v=a',
    artworkUrl: 'https://i.ytimg.com/vi/a/hq720.jpg',
    duration: Duration(minutes: 3),
  ),
  Track(
    id: 'b',
    title: 'Segunda pista',
    artist: 'Aurora',
    pageUrl: 'https://www.youtube.com/watch?v=b',
    artworkUrl: 'https://i.ytimg.com/vi/b/hq720.jpg',
    duration: Duration(minutes: 3),
  ),
];

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

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    for (final scale in const [1.0, 2.0]) {
      for (final mode in const ['dark', 'light']) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()} x$scale $mode';
        testWidgets('phone layout $label', (tester) async {
          final controller = (await tester.runAsync(
            () => createTestController(
              tracks: _tracks,
              audio: FakeAudio(),
              preferences: {'themeMode': mode},
            ),
          ))!;
          final container = ProviderContainer(
            overrides: [controllerProvider.overrideWith((ref) => controller)],
          );
          addTearDown(() async {
            container.dispose();
            await tester.runAsync(() async {
              await controller.closed;
              if (await controller.supportDirectory.exists()) {
                await controller.supportDirectory.delete(recursive: true);
              }
            });
          });
          controller.queue = [..._tracks];
          await tester.runAsync(() => controller.playQueueAt(0));
          await controller.audio.pause();

          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const AuroraApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'home');

          // Mini transport: ellipsized title, tappable controls with labels.
          final transport = find.byType(StudioTransport);
          expect(transport, findsOneWidget);
          final mini = find.descendant(
            of: transport,
            matching: find.text(_long),
          );
          expect(mini, findsOneWidget);
          expect(tester.widget<Text>(mini).overflow, TextOverflow.ellipsis);
          _expectTargets(
            tester,
            find.descendant(of: transport, matching: find.byType(IconButton)),
          );
          expect(find.byTooltip('Reproducir'), findsWidgets);

          // Full player.
          await tester.tap(mini);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'player');
          expect(find.text('AHORA SUENA'), findsOneWidget);
          expect(find.text(_long), findsWidgets);
          expect(find.byType(Slider), findsAtLeastNWidgets(3));
          for (final tip in const [
            'Aleatorio',
            'Anterior',
            'Siguiente',
            'Añadir a favoritos',
            'Cerrar reproductor',
          ]) {
            expect(find.byTooltip(tip), findsWidgets, reason: tip);
          }
          expect(find.byTooltip(RegExp('^Repetición')), findsOneWidget);
          final sheetButtons = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(IconButton),
          );
          for (var i = 0; i < sheetButtons.evaluate().length; i++) {
            await tester.ensureVisible(sheetButtons.at(i));
            _expectTargets(tester, sheetButtons.at(i));
          }
          expect(tester.takeException(), isNull, reason: 'player controls');

          // Queue sheet opened from the player.
          await tester.ensureVisible(find.byTooltip('Cola de reproducción'));
          await tester.tap(find.byTooltip('Cola de reproducción'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'queue sheet');
        });
      }
    }
  }

  testWidgets('queue panel fits narrow phones with large text', (tester) async {
    final controller = (await tester.runAsync(
      () => createTestController(tracks: _tracks, audio: FakeAudio()),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(controller)));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.queue = [..._tracks];
    await tester.runAsync(() => controller.playQueueAt(0));
    for (final size in const [Size(360, 640), Size(412, 915)]) {
      for (final scale in const [1.0, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: QueuePanel(controller: controller)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '$size $scale');
        expect(find.text('Segunda pista'), findsWidgets);
      }
    }
  });

  Future<AppController> pumpPhone(WidgetTester tester) async {
    final controller = (await tester.runAsync(
      () => createTestController(tracks: _tracks, audio: FakeAudio()),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(controller)));
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [controllerProvider.overrideWith((ref) => controller)],
        child: const AuroraApp(),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('artist detail header scrolls away on phones', (tester) async {
    final controller = await pumpPhone(tester);
    controller.searchDetail = const SearchEntry(
      kind: SearchKind.artists,
      browseId: 'UC1',
      title: 'Artista',
    );
    controller.searchDetailTracks = [
      for (var i = 0; i < 30; i++)
        Track(id: 't$i', title: 'Canción $i', artist: 'Artista'),
    ];
    await tester.tap(find.byTooltip('Buscar música'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowButton), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byType(FollowButton, skipOffstage: true), findsNothing);
  });

  testWidgets('system back from Buscar returns to Inicio', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byTooltip('Buscar música'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buscar música'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buscar música'), findsOneWidget);
  });
}

void _expectTargets(WidgetTester tester, Finder buttons) {
  for (var i = 0; i < buttons.evaluate().length; i++) {
    final size = tester.getSize(buttons.at(i));
    expect(
      size.shortestSide,
      greaterThanOrEqualTo(44),
      reason: 'tap target #$i $size',
    );
    final w = tester.widget<IconButton>(buttons.at(i));
    expect(w.tooltip, isNotEmpty, reason: 'tooltip #$i');
  }
}
