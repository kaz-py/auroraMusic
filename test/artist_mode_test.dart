import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(
    id: 'a',
    title: 'Ok Alright',
    artist: 'Travis Scott',
    duration: Duration(minutes: 3),
  ),
  Track(id: 'b', title: 'Segunda', artist: 'Aurora'),
];

class _FakeLyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration.zero, 'Primera línea'),
      LyricLine(Duration(seconds: 30), 'Segunda línea'),
    ],
  );
}

void main() {
  Future<AppController> mountPage(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1,
    VoidCallback? onClose,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(
      () => createTestController(tracks: _songs),
    ))!;
    c.queue = [..._songs];
    await tester.runAsync(() => c.playQueueAt(0));
    await c.audio.pause();
    addTearDown(() => tester.runAsync(() => closeTestController(c)));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ArtistModePage(
            controller: c,
            service: _FakeLyrics(),
            onClose: onClose ?? () {},
            onTogglePlay: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  testWidgets('muestra título, artista, letra sincronizada y controles', (
    tester,
  ) async {
    await mountPage(tester);
    expect(find.text('Ok Alright'), findsOneWidget);
    expect(find.text('Travis Scott'), findsOneWidget);
    expect(find.text('Primera línea'), findsOneWidget);
    for (final tip in [
      'Aleatorio',
      'Anterior',
      'Reproducir',
      'Siguiente',
      'Repetir',
      'Salir del modo artista',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('el botón de salir llama a onClose', (tester) async {
    var closed = 0;
    await mountPage(tester, onClose: () => closed++);
    await tester.tap(find.byTooltip('Salir del modo artista'));
    expect(closed, 1);
  });

  for (final (size, scale) in const [
    (Size(1440, 900), 1.0),
    (Size(900, 700), 2.0),
    (Size(412, 915), 1.0),
    (Size(360, 640), 2.0),
  ]) {
    testWidgets(
      'sin desbordes a ${size.width.toInt()}x${size.height.toInt()} ×$scale',
      (tester) async {
        await mountPage(tester, size: size, scale: scale);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final theme in const ['atelier', 'modern', 'brasa', 'slush']) {
    testWidgets('$theme: el botón de la barra abre el modo artista y oculta '
        'la barra', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: _songs,
          preferences: {'themeKind': theme, 'themeMode': 'dark'},
        ),
      ))!;
      c.queue = [..._songs];
      await tester.runAsync(() => c.playQueueAt(0));
      await c.audio.pause();
      final container = ProviderContainer(
        overrides: [controllerProvider.overrideWith((ref) => c)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(() => closeTestController(c));
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AuroraApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsNothing);
      expect(find.byType(MiniPlayerHost), findsWidgets);

      await tester.tap(find.byTooltip('Modo artista'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsOneWidget);
      // Se oculta toda la UI (menús, barra de abajo): solo queda esta página.
      expect(find.byType(MiniPlayerHost), findsNothing);
      expect(find.byTooltip('Modo artista'), findsNothing);
      expect(find.byTooltip('Minimizar'), findsOneWidget);
      expect(find.byTooltip('Salir del modo artista'), findsOneWidget);

      await tester.tap(find.byTooltip('Salir del modo artista'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsNothing);
      expect(find.byTooltip('Modo artista'), findsOneWidget);
    });
  }
}
