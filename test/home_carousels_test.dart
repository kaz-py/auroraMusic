import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/follow/follow_models.dart';
import 'package:aurora_music/follow/follow_repository.dart';
import 'package:aurora_music/follow/follow_service.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/ui/home_music_page.dart';
import 'package:aurora_music/ui/horizontal_music_row.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController controller;
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });
  setUp(() async {
    controller = await createTestController(
      tracks: List.generate(
        12,
        (i) => Track(
          id: 'song-$i',
          title: 'Canción $i con un nombre largo de la biblioteca',
          artist: 'Artista ${i % 4}',
          pageUrl: 'https://www.youtube.com/watch?v=fixture-$i',
        ),
      ),
      playlists: List.generate(
        5,
        (i) => MusicPlaylist(
          id: 'list-$i',
          name: 'Mi playlist $i para escuchar',
          trackIds: ['song-$i'],
        ),
      ),
    );
  });
  tearDown(() => closeTestController(controller));

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(320, 800),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('row supports touch, mouse drag, arrows and keyboard endpoints', (
    tester,
  ) async {
    const key = ValueKey('row');
    await mount(
      tester,
      HorizontalMusicRow(
        key: key,
        title: 'Fila de prueba',
        itemCount: 8,
        itemWidth: 180,
        itemHeight: 160,
        itemBuilder: (_, index) => ColoredBox(
          color: Colors.blueGrey,
          child: Center(child: Text('Tema $index')),
        ),
      ),
    );
    final list = find.descendant(
      of: find.byKey(key),
      matching: find.byType(ListView),
    );
    final scroll = tester.widget<ListView>(list).controller!;
    expect(find.text('Desliza para ver más'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find
                .ancestor(
                  of: find.byTooltip('Anterior en Fila de prueba'),
                  matching: find.byType(IconButton),
                )
                .first,
          )
          .onPressed,
      isNull,
    );
    await tester.drag(list, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    scroll.jumpTo(0);
    await tester.pumpAndSettle();
    final mouse = await tester.startGesture(
      tester.getCenter(list),
      kind: PointerDeviceKind.mouse,
    );
    await mouse.moveBy(const Offset(-140, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Siguiente en Fila de prueba'));
    await tester.pumpAndSettle();
    final afterArrow = scroll.offset;
    Focus.of(tester.element(find.text('Fila de prueba'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(afterArrow));
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'vertical wheel stays with page, horizontal and Shift wheel move row',
    (tester) async {
      final page = ScrollController();
      addTearDown(page.dispose);
      await mount(
        tester,
        ListView(
          controller: page,
          children: [
            HorizontalMusicRow(
              title: 'Rueda',
              itemCount: 8,
              itemHeight: 160,
              itemBuilder: (_, i) => Text('Tema $i'),
            ),
            const SizedBox(height: 1500),
          ],
        ),
      );
      final list = find.byType(ListView).last;
      final scroll = tester.widget<ListView>(list).controller!;
      Future<void> wheel(Offset delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: tester.getCenter(list),
            scrollDelta: delta,
            kind: PointerDeviceKind.mouse,
          ),
        );
        await tester.pumpAndSettle();
      }

      await wheel(const Offset(0, 80));
      expect(scroll.offset, 0);
      expect(page.offset, greaterThan(0));
      page.jumpTo(0);
      await tester.pumpAndSettle();
      await wheel(const Offset(100, 0));
      expect(scroll.offset, greaterThan(0));
      expect(page.offset, 0);
      final beforeShift = scroll.offset;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await wheel(const Offset(0, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(scroll.offset, greaterThan(beforeShift));
      expect(page.offset, 0);
    },
  );

  testWidgets(
    'a short shelf hides overflow controls and an empty home has a working search action',
    (tester) async {
      await mount(
        tester,
        HorizontalMusicRow(
          title: 'Una canción',
          itemCount: 1,
          itemHeight: 120,
          itemBuilder: (_, _) => const Text('Única canción'),
        ),
      );
      expect(find.text('Desliza para ver más'), findsNothing);
      expect(find.byTooltip('Siguiente en Una canción'), findsNothing);
      controller.tracks.clear();
      controller.playlists.clear();
      var searched = false;
      await mount(
        tester,
        HomeMusicPage(
          controller: controller,
          onSearch: () => searched = true,
          onDownloads: () {},
          onLikes: () {},
          onOpenPlaylist: (_) {},
        ),
      );
      expect(find.byType(HorizontalMusicRow), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Encontrar música'),
        240,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encontrar música'));
      expect(searched, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home rows use real data and playlist action at 320 dp with 200 percent text',
    (tester) async {
      MusicPlaylist? opened;
      await mount(
        tester,
        HomeMusicPage(
          controller: controller,
          onSearch: () {},
          onDownloads: () {},
          onLikes: () {},
          onOpenPlaylist: (p) => opened = p,
        ),
        scale: 2,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-recommendations')),
        240,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-recommendations')),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-playlists')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.scrollUntilVisible(
        find.text('Mi playlist 4 para escuchar'),
        150,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('home-playlists')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.ensureVisible(find.text('Mi playlist 4 para escuchar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi playlist 4 para escuchar'));
      expect(opened?.id, 'list-4');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-library')),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(const ValueKey('home-library')), findsOneWidget);
      final track = controller.tracks.first;
      await tester.ensureVisible(find.byTooltip('Escuchar ${track.title}'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Escuchar ${track.title}'));
      await tester.pumpAndSettle();
      expect(controller.currentTrack?.id, track.id);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home desktop and narrow review captures use real fonts and library fixtures',
    (tester) async {
      await tester.runAsync(
        () => controller.playTrack(controller.tracks.first),
      );
      for (final size in [const Size(1440, 900), const Size(320, 800)]) {
        await mount(
          tester,
          RepaintBoundary(
            key: const ValueKey('home-review'),
            child: HomeMusicPage(
              controller: controller,
              onSearch: () {},
              onDownloads: () {},
              onLikes: () {},
              onOpenPlaylist: (_) {},
            ),
          ),
          size: size,
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('home-review')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui-review').create(recursive: true);
          await File(
            'build/ui-review/home-carousels-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'home shows only followed artists (no derived albums) at enlarged narrow size',
    (tester) async {
      const artistA = 'Artista A con un nombre largo';
      const artistB = 'Artista B con un nombre largo';
      const album = 'Un álbum homónimo de la biblioteca';
      controller.tracks
        ..clear()
        ..addAll(const [
          Track(
            id: 'a-one',
            title: 'Primera de A',
            artist: artistA,
            album: album,
            pageUrl: 'https://youtu.be/a-one',
          ),
          Track(
            id: 'a-two',
            title: 'Segunda de A',
            artist: artistA,
            album: album,
            pageUrl: 'https://youtu.be/a-two',
          ),
          Track(
            id: 'b-one',
            title: 'Primera de B',
            artist: artistB,
            album: album,
            pageUrl: 'https://youtu.be/b-one',
          ),
          Track(
            id: 'b-two',
            title: 'Segunda de B',
            artist: artistB,
            album: album,
            pageUrl: 'https://youtu.be/b-two',
          ),
          Track(
            id: 'missing',
            title: 'Sin metadatos',
            artist: ' ',
            pageUrl: 'https://youtu.be/missing',
          ),
        ]);
      controller.playlists.clear();
      final db = LibraryDatabase.memory();
      final follow = FollowService(
        repository: FollowRepository(db),
        fetchArtist: (_) async => const ArtistPage(),
        findArtist: (_) async => const [],
      );
      addTearDown(() async {
        follow.dispose();
        await db.close();
      });
      await mount(
        tester,
        HomeMusicPage(
          controller: controller,
          follow: follow,
          onSearch: () {},
          onDownloads: () {},
          onLikes: () {},
          onOpenPlaylist: (_) {},
        ),
        scale: 2,
      );
      // Sin seguidos no hay carril de artistas, ni de álbumes deducidos.
      expect(find.byKey(const ValueKey('home-artists')), findsNothing);
      expect(find.byKey(const ValueKey('home-albums')), findsNothing);
      await tester.runAsync(() async {
        await follow.follow('Seguido uno', browseId: 'UC1');
        await follow.follow(artistB, browseId: 'UC2');
        await pumpEventQueue();
      });
      await tester.pump();
      final outer = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('home-artists')),
        300,
        scrollable: outer,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-artists')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-albums')), findsNothing);
      await tester.ensureVisible(find.byTooltip('Abrir artista $artistB'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Abrir artista $artistB'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
