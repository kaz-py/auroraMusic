import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  const track = Track(
    id: 'current',
    title: 'Current record',
    artist: 'Artist',
    pageUrl: 'https://example.test/current',
  );

  late FakeAudio audio;
  late AppController controller;

  setUp(() async {
    audio = FakeAudio();
    controller = await createTestController(audio: audio);
    controller.queue = [track];
    controller.queueIndex = 0;
    await controller.playQueueAt(0);
    await audio.pause();
  });

  tearDown(() => closeTestController(controller));

  testWidgets('toggle switches to cassette, remembers it and skips 10 s', (
    tester,
  ) async {
    // Slush es el tema que conserva el interruptor vinilo/casete a pantalla completa.
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.light, const Color(0xffe86927)),
        home: Scaffold(body: VinylPlayer(controller: controller)),
      ),
    );
    expect(find.byKey(const ValueKey('vinyl-disc')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('cassette-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cassette-body')), findsOneWidget);
    expect(find.byKey(const ValueKey('vinyl-disc')), findsNothing);
    expect(controller.preferences.getBool('cassetteMode'), isTrue);

    await tester.tap(find.byTooltip('Adelantar 10 s'));
    await tester.runAsync(
      () async => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    expect(audio.position, const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
    // Slush pide letras al montarse: se deja acabar su E/S antes de cerrar.
    await settleLyricsIo(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
