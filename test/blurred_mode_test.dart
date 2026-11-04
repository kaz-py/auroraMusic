import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/blurred_now_playing.dart';
import 'package:aurora_music/ui/lyrics_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
];

void main() {
  for (final theme in const ['atelier', 'modern', 'brasa', 'slush']) {
    testWidgets(
      '$theme: el botón de la barra abre el modo difuminado con letras',
      (tester) async {
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
        expect(find.byType(BlurredNowPlaying), findsNothing);

        await tester.tap(find.byTooltip('Modo difuminado'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BlurredNowPlaying), findsOneWidget);
        expect(find.byType(LyricsPanel), findsOneWidget);
        // La barra sigue ahí: se puede seguir controlando la pista.
        expect(find.byTooltip('Modo difuminado'), findsOneWidget);
      },
    );
  }
}
