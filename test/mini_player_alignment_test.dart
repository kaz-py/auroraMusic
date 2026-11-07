import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';

import 'support/fakes.dart';

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
  testWidgets('mini-player centers desktop transport and fits mobile metadata', (
    tester,
  ) async {
    const track = Track(
      id: 'alignment',
      title: 'Una pista larga para comprobar el recorte del mini reproductor',
      artist: 'Aurora',
      pageUrl: 'https://www.youtube.com/watch?v=alignment',
      duration: Duration(minutes: 3),
    );
    final controller = (await tester.runAsync(
      () => createTestController(tracks: const [track], audio: FakeAudio()),
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
    await tester.runAsync(() => controller.playTrack(track));
    await controller.audio.pause();

    for (final (size, scale) in [
      (const Size(360, 800), 1.0),
      (const Size(412, 800), 1.0),
      (const Size(600, 900), 1.0),
      (const Size(900, 900), 1.0),
      (const Size(1440, 900), 1.0),
      (const Size(360, 800), 2.0),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: const AuroraApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mini = find.byType(MiniPlayerHost);
      final playButton = find.descendant(
        of: mini,
        matching: find.byTooltip('Reproducir'),
      );
      expect(playButton, findsOneWidget);
      final metadata = find.descendant(
        of: mini,
        matching: find.text(track.title),
      );
      expect(metadata, findsOneWidget);
      final miniRect = tester.getRect(mini);
      final metadataRect = tester.getRect(metadata);
      final playRect = tester.getRect(playButton);
      // The title never runs under the play button, and both sit inside the bar.
      expect(metadataRect.right, lessThanOrEqualTo(playRect.left));
      expect(playRect.left, greaterThanOrEqualTo(miniRect.left));
      expect(playRect.right, lessThanOrEqualTo(miniRect.right));
      expect(playRect.height, greaterThanOrEqualTo(44));
      expect(
        metadataRect.center.dy,
        closeTo(playRect.center.dy, miniRect.height / 2),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'layout $size at scale $scale',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  });
}
