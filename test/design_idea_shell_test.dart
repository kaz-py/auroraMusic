import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/studio/home_introduction.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/jam/jam_page.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

// Metadata is an offline test fixture; artwork comes from committed references.
final fixture = [
  for (var i = 0; i < 8; i++)
    Track(
      id: 'studio-$i',
      title: [
        'Midnight in Paris Sessions',
        'Wind & Rain Whispers',
        'Rust & Soil',
        'Chamber Reverb',
        'Goldberg In The Dark',
        'Madrugada en Cádiz',
        'Naima (Take 42)',
        'Says',
      ][i],
      artist: [
        'Arthur & The Ink',
        'Sato & Takada Ensemble',
        'Clara Vance',
        'Hildur Guðnadóttir Trio',
        'Vikingur Ólafsson',
        'Manuel Molina',
        'John Coltrane',
        'Nils Frahm',
      ][i],
      album: [
        'Midnight in Paris Sessions',
        'Wind Whisperer',
        'Rust & Soil',
        'Chamber Reverb Sessions',
        'Goldberg In The Dark',
        'Madrugada en Cádiz',
        null,
        null,
      ][i],
      genres: const [],
      duration: Duration(minutes: 3 + i % 4, seconds: 12 + i * 3),
      artworkUrl:
          'asset:assets/design_idea/inicio_aurora_music_player_${(i + 1).toString().padLeft(2, '0')}.png',
      pageUrl: 'https://youtu.be/studio-$i',
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  late ProviderContainer container;

  setUpAll(() async {
    final editorial = FontLoader('Newsreader')
      ..addFont(
        rootBundle.load('assets/fonts/newsreader/Newsreader-Variable.ttf'),
      )
      ..addFont(
        rootBundle.load(
          'assets/fonts/newsreader/Newsreader-Italic-Variable.ttf',
        ),
      );
    await editorial.load();
    for (final font in {
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      // Widget tests use Ahem for system fallback fonts. This test-only alias
      // keeps stamps readable; runtime still uses the platform monospace font.
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  setUp(() async {
    studioClock = () => DateTime(2026, 10, 18, 2, 30);
    controller = await createTestController(
      tracks: fixture,
      playlists: const [
        MusicPlaylist(
          id: 'late',
          name: 'Jazz de madrugada',
          trackIds: ['studio-0', 'studio-1', 'studio-2'],
        ),
        MusicPlaylist(
          id: 'slow',
          name: 'Amanecer sin prisa',
          trackIds: ['studio-3', 'studio-4'],
        ),
      ],
    );
    controller.recentTracks = fixture.take(5).toList();
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => controller)],
    );
  });

  tearDown(() async {
    container.dispose();
    await controller.closed;
    if (await controller.supportDirectory.exists()) {
      await controller.supportDirectory.delete(recursive: true);
    }
  });

  Future<void> mount(WidgetTester tester, Size size, {double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const RepaintBoundary(
          key: ValueKey('studio-shell-capture'),
          child: AuroraApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AuroraShell));
    final artwork = tester.widgetList<Artwork>(find.byType(Artwork)).toList();
    await tester.runAsync(() async {
      for (final item in artwork) {
        final url = item.track.artworkUrl;
        if (url == null || !url.startsWith('asset:')) continue;
        await precacheImage(
          ResizeImage.resizeIfNeeded(
            item.size.ceil().clamp(48, 1024),
            null,
            AssetImage(url.substring(6)),
          ),
          context,
        );
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String filename) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('studio-shell-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory('build/ui-review/design_idea_shell');
      await output.create(recursive: true);
      await File(
        '${output.path}/$filename',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'studio home shell captures exact reference width and full height offline',
    (tester) async {
      await tester.runAsync(() => controller.playTrack(fixture.first));
      await controller.pausePlayback();
      controller.recentTracks = fixture.take(5).toList();
      for (final size in [
        const Size(1286, 1029),
        const Size(1300, 1029),
        const Size(1286, 1600),
      ]) {
        await mount(tester, size);
        expect(find.text('Madrugada acústica'), findsOneWidget);
        expect(find.byType(MiniPlayerGestures), findsOneWidget);
        expect(find.byType(JamPage, skipOffstage: false), findsNothing);
        expect((controller.source as FakeSource).searchQueries, isEmpty);
        expect(tester.takeException(), isNull, reason: 'shell $size');
        await capture(
          tester,
          'inicio-${size.width.toInt()}x${size.height.toInt()}.png',
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'studio mobile shell routes at 200 percent text without overflow or automatic network',
    (tester) async {
      await mount(tester, const Size(320, 800), scale: 2);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await capture(tester, 'inicio-320x800-text200.png');
      await tester.tap(find.byTooltip('DJ').last);
      await tester.pumpAndSettle();
      expect(find.text('Descubre tu próxima canción'), findsOneWidget);
      expect((controller.source as FakeSource).searchQueries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Buscar').last);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
