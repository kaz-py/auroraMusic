import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(
    id: 'a',
    title: 'Una canción con un título muy largo para el recorte',
    artist: 'Aurora',
  ),
  Track(id: 'b', title: 'Segunda', artist: 'Otro'),
];

void main() {
  for (final (size, scale) in const [
    (Size(1440, 900), 1.0),
    (Size(700, 640), 2.0),
  ]) {
    testWidgets(
      'la tarjeta de la canción ofrece las acciones y actúa (${size.width.toInt()} ×$scale)',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final c = (await tester.runAsync(
          () => createTestController(tracks: _songs),
        ))!;
        c.queue = [_songs.first];
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

        await tester.tap(find.textContaining('Una canción con').last);
        await tester.pump(const Duration(seconds: 1));
        for (final label in [
          'Reproducir a continuación',
          'Añadir a la cola',
          'Añadir a favoritos',
          'Compartir',
          'Abrir Modo Vinilo',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(tester.takeException(), isNull);

        // Una acción cierra la tarjeta y actúa.
        final before = c.queue.length;
        await tester.tap(find.text('Añadir a favoritos'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Compartir'), findsNothing);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect(c.favoriteIds, contains('a'));
        expect(c.queue.length, before);
      },
    );
  }
}
