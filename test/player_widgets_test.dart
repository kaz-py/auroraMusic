import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/queue_panel.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _TrackingAudio extends FakeAudio {
  final seeks = <Duration>[];

  @override
  Future<void> seek(Duration value) async {
    seeks.add(value);
    await super.seek(value);
  }
}

void main() {
  const previous = Track(
    id: 'previous',
    title: 'Earlier record',
    artist: 'Artist',
    pageUrl: 'https://example.test/previous',
  );
  const current = Track(
    id: 'current',
    title: 'Current record',
    artist: 'Artist',
    pageUrl: 'https://example.test/current',
  );
  const duplicateA = Track(
    id: 'duplicate',
    title: 'Duplicate one',
    artist: 'Artist',
    pageUrl: 'https://example.test/duplicate-one',
  );
  const duplicateB = Track(
    id: 'duplicate',
    title: 'Duplicate two',
    artist: 'Artist',
    pageUrl: 'https://example.test/duplicate-two',
  );

  group('player widgets', () {
    late AppController controller;
    late _TrackingAudio audio;

    setUp(() async {
      audio = _TrackingAudio();
      controller = await createTestController(audio: audio);
      controller.queue = [previous, current, duplicateA, duplicateB];
      controller.queueIndex = 1;
      await controller.playQueueAt(1);
      await audio.pause();
      expect(controller.error, isNull);
      expect(audio.loaded, isNotNull);
      // Registrado en setUp: corre después de los addTearDown de `mount`.
      addTearDown(() => closeTestController(controller));
    });

    Future<void> mount(
      WidgetTester tester,
      Widget screen, {
      Size size = const Size(320, 600),
      double scale = 1,
      ThemeData? theme,
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: screen),
        ),
      );
      // El reproductor pide letras al montarse: se deja acabar su E/S de caché
      // y se desmonta antes de borrar el directorio de soporte.
      addTearDown(() async {
        await settleLyricsIo(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    /// Atelier (el tema por defecto) pinta solo la portada: el disco que
    /// gira y busca por posición es la vista vinilo de Modern (escritorio).
    Future<void> mountVinyl(WidgetTester tester) async {
      await controller.preferences.setBool('modernPhoto', false);
      await mount(
        tester,
        VinylPlayer(controller: controller),
        size: const Size(1280, 800),
        theme: modernTheme(Brightness.dark, const Color(0xff6ea8ff)),
      );
    }

    testWidgets('slider seeks the real playback backend', (tester) async {
      await mount(tester, VinylPlayer(controller: controller));
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
      slider.onChanged!(90000);
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      expect(audio.position, const Duration(seconds: 90));
      expect(tester.takeException(), isNull);
    });

    testWidgets('vinyl click seeks by position without changing playback', (
      tester,
    ) async {
      await mountVinyl(tester);
      final disc = find.byKey(const ValueKey('vinyl-disc'));
      final rect = tester.getRect(disc);
      await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );

      expect(audio.position, const Duration(seconds: 135));
      expect(audio.isPlaying, isFalse);
      expect(controller.queue.map((track) => track.id), [
        'previous',
        'current',
        'duplicate',
        'duplicate',
      ]);
      expect(controller.queueIndex, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('vinyl drag coalesces movement and seeks backward', (
      tester,
    ) async {
      audio.position = const Duration(seconds: 90);
      await mountVinyl(tester);
      final disc = find.byKey(const ValueKey('vinyl-disc'));
      final rect = tester.getRect(disc);
      final gesture = await tester.startGesture(rect.center);
      await gesture.moveBy(const Offset(-20, 0));
      await gesture.moveBy(const Offset(-20, 0));
      expect(audio.position, const Duration(seconds: 90));
      expect(audio.seeks, isEmpty);
      await gesture.up();
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );

      final expectedTarget = Duration(
        milliseconds: (90000 - 40 * audio.duration.inMilliseconds / rect.width)
            .round(),
      );
      expect(audio.seeks, hasLength(1));
      expect(audio.position, expectedTarget);
      expect(audio.position, lessThan(const Duration(seconds: 90)));
      expect(audio.seeks, [expectedTarget]);
      expect(audio.isPlaying, isFalse);
      expect(controller.queue.map((track) => track.id), [
        'previous',
        'current',
        'duplicate',
        'duplicate',
      ]);
      expect(controller.queueIndex, 1);

      await audio.play();
      final playingStart = audio.position;
      final playingGesture = await tester.startGesture(rect.center);
      await playingGesture.moveBy(const Offset(-20, 0));
      await playingGesture.moveBy(const Offset(-20, 0));
      await playingGesture.up();
      await tester.pump();
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      final playingTarget = Duration(
        milliseconds:
            (playingStart.inMilliseconds -
                    40 * audio.duration.inMilliseconds / rect.width)
                .round(),
      );
      expect(audio.position, playingTarget);
      expect(audio.seeks, [expectedTarget, playingTarget]);
      expect(audio.isPlaying, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'vinyl stays safe while paused by reduced motion and background',
      (tester) async {
        await mountVinyl(tester);
        await audio.play();
        controller.reducedMotion = true;
        controller.notifyListeners();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('queue handles duplicate IDs on narrow enlarged text', (
      tester,
    ) async {
      await mount(tester, QueuePanel(controller: controller), scale: 2);
      expect(find.text('Current record'), findsOneWidget);
      expect(find.text('Duplicate one'), findsOneWidget);
      expect(find.text('Duplicate two'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('queue fits a short desktop viewport', (tester) async {
      await mount(
        tester,
        QueuePanel(controller: controller),
        size: const Size(900, 600),
      );
      expect(find.text('Current record'), findsOneWidget);
      expect(find.byType(ReorderableListView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
