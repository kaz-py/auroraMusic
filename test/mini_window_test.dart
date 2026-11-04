import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/mini_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(
    id: 'a',
    title: 'Una canción con un título larguísimo para comprobar el recorte',
    artist: 'Un artista con un nombre igual de largo que el título anterior',
    duration: Duration(minutes: 3),
  ),
  Track(id: 'b', title: 'Segunda', artist: 'Aurora'),
];

/// Canal nativo falso: anota las llamadas y responde que todo salió bien.
List<MethodCall> _mockWindow(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('aurora/window'),
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('aurora/window'),
      null,
    ),
  );
  return calls;
}

void main() {
  group('MiniWindowView', () {
    Future<AppController> mount(
      WidgetTester tester, {
      Size size = const Size(380, 150),
      double scale = 1,
      VoidCallback? onExit,
      VoidCallback? onTogglePlay,
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
          home: MiniWindowView(
            controller: c,
            onExit: onExit ?? () {},
            onTogglePlay: onTogglePlay ?? () {},
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('muestra título, artista y los controles de la pista', (
      tester,
    ) async {
      await mount(tester);
      expect(find.textContaining('Una canción con un título'), findsOneWidget);
      expect(find.textContaining('Un artista con un nombre'), findsOneWidget);
      for (final tip in [
        'Añadir a favoritos',
        'Anterior',
        'Siguiente',
        'Salir del mini reproductor',
      ]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('play y salir llaman a sus acciones', (tester) async {
      var plays = 0, exits = 0;
      await mount(tester, onTogglePlay: () => plays++, onExit: () => exits++);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.tap(find.byTooltip('Salir del mini reproductor'));
      expect((plays, exits), (1, 1));
    });

    for (final (size, scale) in const [
      (Size(380, 150), 1.0),
      (Size(380, 150), 2.0),
      (Size(300, 120), 1.0),
      (Size(300, 120), 2.0),
    ]) {
      testWidgets(
        'sin desbordes a ${size.width.toInt()}x${size.height.toInt()} ×$scale',
        (tester) async {
          await mount(tester, size: size, scale: scale);
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  testWidgets(
    'el menú de la canción abre el mini reproductor y su botón vuelve',
    (tester) async {
      final calls = _mockWindow(tester);
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(tracks: _songs),
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
      expect(find.byType(MiniWindowView), findsNothing);

      // Clic en la portada/título de la barra → menú de la canción.
      await tester.tap(find.textContaining('Una canción con un título').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir el mini reproductor'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MiniWindowView), findsOneWidget);
      expect(calls.last.method, 'setMini');
      expect((calls.last.arguments as Map)['enabled'], isTrue);

      await tester.tap(find.byTooltip('Salir del mini reproductor'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(MiniWindowView), findsNothing);
      expect((calls.last.arguments as Map)['enabled'], isFalse);
    },
    skip: !Platform.isWindows,
  );
}
