import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/studio/home_introduction.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/jam/jam_page.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/vinyl_player.dart';

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
  late AppController controller;
  late ProviderContainer container;
  late _TrackingAudio audio;
  late _ProgressiveSource source;

  setUp(() async {
    studioClock = () => DateTime(2026, 10, 18, 2, 30);
    audio = _TrackingAudio();
    source = _ProgressiveSource();
    controller = await createTestController(
      audio: audio,
      source: source,
      tracks: const [
        Track(
          id: 'one',
          title:
              'Una canción con un título muy largo para comprobar la interfaz',
          artist: 'Un artista con un nombre largo',
          pageUrl: 'https://www.youtube.com/watch?v=test-one',
          duration: Duration(minutes: 4),
        ),
        Track(
          id: 'two',
          title: 'Otra canción',
          artist: 'Aurora',
          pageUrl: 'https://www.youtube.com/watch?v=test-two',
          duration: Duration(minutes: 3),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => controller)],
    );
  });

  tearDown(() async {
    container.dispose();
    await controller.database.close();
    if (await controller.supportDirectory.exists()) {
      await controller.supportDirectory.delete(recursive: true);
    }
  });

  // [animated]: deja las animaciones del sistema activas (el análisis del
  // espectro las exige); el vinilo gira sin fin, así que no se "asienta".
  Future<void> mount(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    bool animated = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            // El vinilo del mini gira sin fin al sonar: sin animaciones el
            // giro se detiene y pumpAndSettle termina.
            disableAnimations: !animated,
          ),
          child: const RepaintBoundary(
            key: ValueKey('ui-review'),
            child: AuroraApp(),
          ),
        ),
      ),
    );
    animated
        ? await tester.pump(const Duration(milliseconds: 500))
        : await tester.pumpAndSettle();
  }

  // Móvil sin carril: cola, letras y EQ salen del menú «Más vistas».
  Future<void> openFromMoreViews(WidgetTester tester, String view) async {
    await tester.tap(find.byTooltip('Más vistas'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text(view).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final outer = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(target, 240, scrollable: outer);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review screenshots use test library data at desktop and mobile sizes',
    (tester) async {
      for (final font in {
        'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
        'Plus Jakarta Sans':
            'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
        'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
      }.entries) {
        await (FontLoader(
          font.key,
        )..addFont(rootBundle.load(font.value))).load();
      }
      await tester.runAsync(
        () => controller.playTrack(controller.tracks.first),
      );
      controller.playlists.add(
        const MusicPlaylist(
          id: 'review',
          name: 'Mi colección',
          trackIds: ['one', 'two'],
        ),
      );
      for (final size in [const Size(1440, 900), const Size(320, 800)]) {
        await mount(tester, size);
        expect(tester.takeException(), isNull);
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('ui-review')),
        );
        await tester.runAsync(() async {
          final snapshot = await boundary.toImage();
          final bytes = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          final directory = Directory('build/ui-review');
          await directory.create(recursive: true);
          await File(
            '${directory.path}/home-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          snapshot.dispose();
        });
        await tester.dragUntilVisible(
          find.text('Personalizar el DJ'),
          find.byType(ListView).first,
          const Offset(0, -250),
        );
        await tester.ensureVisible(find.text('Personalizar el DJ'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Personalizar el DJ'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          final snapshot = await boundary.toImage();
          final bytes = await snapshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File(
            'build/ui-review/dj-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          snapshot.dispose();
        });
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'typing never searches; a newer submission supersedes the pending one',
    (tester) async {
      await mount(tester, const Size(800, 900));
      await tester.tap(find.byTooltip('Buscar música'));
      await tester.pumpAndSettle();
      final source = controller.source as FakeSource;
      source.pendingSearch = Completer<List<Track>>();
      await tester.enterText(find.byType(TextField), 'Me at the zoo');
      await tester.pump(const Duration(seconds: 1));
      expect(source.searchQueries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(source.searchQueries, ['Me at the zoo']);
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump(const Duration(seconds: 1));
      expect(controller.searching, isTrue);
      expect(source.searchQueries, ['Me at the zoo', 'ab']);
      source.pendingSearch!.complete([controller.tracks.first]);
      await tester.pumpAndSettle();
      expect(controller.searching, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final size in [
    const Size(320, 700),
    const Size(800, 900),
    const Size(1440, 900),
  ]) {
    testWidgets('Navigation works without overflow at ${size.width} dp', (
      tester,
    ) async {
      await mount(tester, size);
      expect(find.text('Inicio').first, findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width >= 1200) {
        await tester.tap(find.byTooltip('Buscar').first);
      } else if (size.width >= 600) {
        await tester.tap(find.byTooltip('Buscar música'));
      } else {
        await tester.tap(find.byTooltip('Buscar').last);
      }
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (size.width == 320) {
        await tester.enterText(find.byType(TextField), 'sin coincidencias');
        await tester.pump(const Duration(milliseconds: 600));
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(find.text('Sin resultados'), findsOneWidget);
        controller.searchResults = [controller.tracks.first];
        controller.clearError();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'ab');
        await tester.pumpAndSettle();
        expect(controller.searchResults, [controller.tracks.first]);
        expect(find.text(controller.tracks.first.title), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Inicio shows honest cold-start recommendations that play', (
    tester,
  ) async {
    await mount(tester, const Size(800, 900));

    await reveal(tester, find.byKey(const ValueKey('home-recommendations')));
    expect(find.text('Para ti'), findsOneWidget);
    expect(
      find.text('Aún no hay señales personales; elegimos de tu biblioteca'),
      findsOneWidget,
    );
    expect(find.textContaining('De tu biblioteca'), findsWidgets);
    final recommended = controller.recommendations.first.track;
    await tester.tap(find.byTooltip('Reproducir ${recommended.title}'));
    await tester.pumpAndSettle();

    expect(controller.currentTrack?.id, recommended.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('liked-only library can still discover by its strongest artist', (
    tester,
  ) async {
    await controller.toggleFavorite(controller.tracks[0]);
    await controller.toggleFavorite(controller.tracks[1]);
    final source = controller.source as FakeSource;
    source.searchMatches = const [
      Track(
        id: 'liked-discovery',
        title: 'New pick',
        artist: 'Aurora',
        pageUrl: 'https://youtu.be/liked-discovery',
      ),
    ];
    await mount(tester, const Size(800, 900));

    expect(controller.recommendations, isEmpty);
    expect(controller.canDiscoverRecommendations, isTrue);
    await reveal(tester, find.text('Descubrir en YouTube'));
    await tester.tap(find.text('Descubrir en YouTube'));
    await tester.pumpAndSettle();

    expect(source.searchQueries, ['Aurora songs']);
    expect(find.text('New pick'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('experimental playback setting is visible and responds', (
    tester,
  ) async {
    await mount(tester, const Size(800, 900));
    await tester.tap(find.byIcon(Icons.tune).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reproducción').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reproducción').first);
    await tester.pumpAndSettle();
    final switchFinder = find.ancestor(
      of: find.text('Descargar mientras se reproduce').last,
      matching: find.byType(SwitchListTile),
    );
    expect(tester.widget<SwitchListTile>(switchFinder).value, isFalse);
    expect(tester.widget<SwitchListTile>(switchFinder).onChanged, isNotNull);
    await tester.ensureVisible(
      find.text('Descargar mientras se reproduce').last,
    );
    await tester.tap(find.text('Descargar mientras se reproduce').last);
    await tester.pumpAndSettle();

    expect(controller.experimentalProgressivePlayback, isTrue);
    expect(source.applied, isTrue);
    expect(
      controller.preferences.getBool('experimentalProgressivePlayback'),
      isTrue,
    );
    expect(tester.widget<SwitchListTile>(switchFinder).value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('experimental playback setting explains unsupported sources', (
    tester,
  ) async {
    source.supported = false;
    await mount(tester, const Size(800, 900));
    await tester.tap(find.byIcon(Icons.tune).last);
    await tester.pumpAndSettle();
    expect(find.text('Descargar mientras se reproduce'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'DJ controls start and stop recommendation without pausing audio',
    (tester) async {
      await controller.playTrack(controller.tracks.first);
      final currentId = controller.currentTrack?.id;
      final audioLoads = audio.loadCount;
      await mount(tester, const Size(800, 900));
      await reveal(tester, find.text('Iniciar DJ'));
      await tester.tap(find.text('Iniciar DJ'));
      await tester.pumpAndSettle();

      expect(controller.personalDjActive, isTrue);
      expect(controller.audio.isPlaying, isTrue);
      expect(controller.currentTrack?.id, currentId);
      expect(audio.loadCount, audioLoads);
      await tester.tap(find.text('Detener DJ'));
      await tester.pumpAndSettle();

      expect(controller.personalDjActive, isFalse);
      expect(controller.audio.isPlaying, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'YouTube discovery runs only on request and stays outside library',
    (tester) async {
      await mount(tester, const Size(800, 900));
      final source = controller.source as FakeSource;
      source.searchMatches = const [
        Track(
          id: 'discovered',
          title: 'Una sugerencia nueva',
          artist: 'Aurora',
          pageUrl: 'https://youtu.be/discovered',
        ),
      ];
      expect(source.searchQueries, isEmpty);
      await reveal(tester, find.text('Personalizar el DJ'));
      await reveal(tester, find.text('Descubrir en YouTube'));
      await tester.tap(find.text('Descubrir en YouTube'));
      await tester.pumpAndSettle();

      expect(source.searchQueries, ['Aurora songs']);
      expect(find.text('Una sugerencia nueva'), findsOneWidget);
      expect(find.text('Encontradas en YouTube'), findsOneWidget);
      expect(controller.tracks.map((track) => track.id).toSet(), {
        'one',
        'two',
      });
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('600px-high desktop navigation stays scroll-safe and routes', (
    tester,
  ) async {
    await mount(tester, const Size(1100, 600));
    expect(tester.takeException(), isNull);
    for (final destination in [
      'Buscar',
      'Biblioteca',
      'Descargas locales',
      'Modo Vinilo',
      'Cola de reproducción',
      'Ajustes',
    ]) {
      await tester.ensureVisible(find.byTooltip(destination).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(destination).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: destination);
    }
    await tester.ensureVisible(find.byTooltip('Letras').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Letras').first);
    await tester.pumpAndSettle();
    expect(find.byType(ArtistModePage), findsOneWidget);
    await tester.tap(find.byTooltip('Salir del modo letra'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistModePage), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('desktop places DJ immediately after Search and exposes Jam', (
    tester,
  ) async {
    await mount(tester, const Size(1000, 900));
    final search = tester.getCenter(find.byTooltip('Buscar'));
    final dj = tester.getCenter(find.byTooltip('DJ'));
    final library = tester.getCenter(find.byTooltip('Biblioteca'));
    expect(dj.dy, greaterThan(search.dy));
    expect(dj.dy, lessThan(library.dy));
    expect(find.byTooltip('Jam'), findsOneWidget);
    await tester.tap(find.byTooltip('DJ'));
    await tester.pumpAndSettle();
    expect(find.text('Descubre tu próxima canción'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Jam mounts lazily and keeps its State across navigation', (
    tester,
  ) async {
    await mount(tester, const Size(1000, 900));
    expect(find.byType(JamPage, skipOffstage: false), findsNothing);
    expect(source.searchQueries, isEmpty);
    await tester.tap(find.byTooltip('Jam'));
    await tester.pumpAndSettle();
    final firstState = tester.state(find.byType(JamPage));
    await tester.tap(find.byTooltip('Inicio'));
    await tester.pumpAndSettle();
    expect(find.byType(JamPage), findsNothing);
    expect(
      tester.state(find.byType(JamPage, skipOffstage: false)),
      same(firstState),
    );
    await tester.tap(find.byTooltip('Jam'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(JamPage)), same(firstState));
    expect(source.searchQueries, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mobile navigation has five destinations and settings shortcut', (
    tester,
  ) async {
    await mount(tester, const Size(320, 700), scale: 2);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      ['Inicio', 'Buscar', 'DJ', 'Biblioteca', 'Descargas'],
    );
    await tester.tap(find.byTooltip('DJ').last);
    await tester.pumpAndSettle();
    expect(find.text('Descubre tu próxima canción'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Modo Vinilo'), findsOneWidget);
    expect(find.text('Jam'), findsOneWidget);
    expect(find.text('Cola de reproducción'), findsOneWidget);
    expect(find.text('Letras'), findsOneWidget);
    await tester.tap(find.text('Modo Vinilo'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cola de reproducción'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('No hay canciones en la cola'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    expect(find.text('No hay canciones en la cola'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letras'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistModePage), findsOneWidget);
    await tester.tap(find.byTooltip('Salir del modo letra'));
    await tester.pumpAndSettle();
    expect(find.byType(ArtistModePage), findsNothing);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cuenta y servicios').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuenta y servicios').first);
    await tester.pumpAndSettle();
    expect(find.text('Perfil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('200 percent text remains usable on a narrow screen', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.toggleFavorite(
        controller.tracks.firstWhere((track) => track.id == 'one'),
      ),
    );
    await mount(tester, const Size(320, 800), scale: 2);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byIcon(Icons.library_music_outlined).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Me gusta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Me gusta'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Una canción con un título muy largo para comprobar la interfaz',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Descargas locales').last);
    await tester.pumpAndSettle();
    expect(find.text('Carpeta de descargas'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Cambiar carpeta'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cambiar carpeta'), findsOneWidget);
    final openLabel = controller.canConfigureDownloadDirectory
        ? 'Explorador Windows'
        : 'Abrir carpeta';
    await tester.scrollUntilVisible(
      find.text(openLabel),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text(openLabel), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text(openLabel),
              matching: find.byWidgetPredicate(
                (widget) => widget is FilledButton,
              ),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.text(controller.downloadsDirectoryPath), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Deleting a completed download requires confirmation and keeps collections',
    (tester) async {
      late File file;
      late DownloadJob job;
      await tester.runAsync(() async {
        final directory = Directory(
          p.join(controller.supportDirectory.path, 'downloads'),
        );
        await directory.create(recursive: true);
        file = File(p.join(directory.path, 'one.mp3'));
        await file.writeAsBytes([1, 2, 3]);
        final track = controller.tracks
            .firstWhere((track) => track.id == 'one')
            .copyWith(localPath: file.path);
        job = DownloadJob(
          id: 'download-one',
          track: track,
          status: DownloadStatus.completed,
          progress: 1,
          localPath: file.path,
        );
        await controller.database.saveDownload(job);
        controller.downloads.add(job);
        await controller.toggleFavorite(track);
        await controller.createPlaylist('Mi lista');
        await controller.addToPlaylist(controller.playlists.single, track);
      });
      await mount(tester, const Size(320, 800), scale: 2);
      await tester.tap(find.byTooltip('Descargas locales').last);
      await tester.pumpAndSettle();
      final deleteDownload = find.byTooltip('Eliminar archivo descargado');
      await tester.dragUntilVisible(
        deleteDownload,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(deleteDownload);
      await tester.pumpAndSettle();
      await tester.tap(deleteDownload);
      await tester.pumpAndSettle();
      expect(find.text('Eliminar descarga'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(file.exists), isTrue);
      expect(controller.downloads, hasLength(1));
      await tester.dragUntilVisible(
        deleteDownload,
        find.byType(ListView).first,
        const Offset(0, -300),
      );
      await tester.ensureVisible(deleteDownload);
      await tester.pumpAndSettle();
      await tester.tap(deleteDownload);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Eliminar archivo'));
      await tester.runAsync(() => tester.tap(find.text('Eliminar archivo')));
      await tester.pumpAndSettle();
      await tester.runAsync(() => controller.removeDownload(job));
      await tester.pumpAndSettle();
      expect(controller.error, isNull);
      expect(await tester.runAsync(file.exists), isFalse);
      expect(controller.downloads, isEmpty);
      expect(controller.favoriteIds, contains('one'));
      expect(controller.playlists.single.trackIds, contains('one'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('profile menu opens from the photo and jumps to a category', (
    tester,
  ) async {
    await mount(tester, const Size(1200, 800));
    await tester.tap(find.byTooltip('Perfil y ajustes').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-menu-header')), findsOneWidget);
    for (final label in ['Perfil', 'Ajustes', 'Apariencia', 'Acerca de']) {
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.text('Cuenta y servicios').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-menu-header')), findsNothing);
    // La sección «Cuenta» llega desplegada con su contenido.
    expect(find.textContaining('Las cuentas no están configuradas'), findsOne);
    await tester.tap(find.byTooltip('Perfil y ajustes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Acerca de').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Tu biblioteca permanece'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings sections are collapsible, lazy and searchable', (
    tester,
  ) async {
    await mount(tester, const Size(1200, 800));
    await tester.tap(find.byTooltip('Perfil y ajustes').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apariencia').last);
    await tester.pumpAndSettle();
    // Solo la primera sección de la categoría está desplegada.
    expect(find.text('Temas'), findsOneWidget);
    expect(find.text('Reducir movimiento'), findsNothing);
    await tester.tap(find.text('Movimiento').first);
    await tester.pumpAndSettle();
    expect(find.text('Reducir movimiento'), findsOneWidget);
    // Plegar de nuevo la quita del árbol.
    await tester.tap(find.text('Movimiento').first);
    await tester.pumpAndSettle();
    expect(find.text('Reducir movimiento'), findsNothing);
    // Búsqueda sin tildes entre todas las categorías.
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'sueno',
    );
    await tester.pumpAndSettle();
    expect(find.text('Sueño'), findsOneWidget);
    expect(find.text('Movimiento'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'zzzz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-no-results')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings fit a narrow screen at 200 percent text', (
    tester,
  ) async {
    await mount(tester, const Size(360, 740), scale: 2);
    await tester.tap(find.byIcon(Icons.tune).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-search')), findsOneWidget);
    await tester.tap(find.text('Reproducción').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'YouTube session settings explain local import and disable controls while busy',
    (tester) async {
      await mount(tester, const Size(320, 800), scale: 2);
      await tester.tap(find.byIcon(Icons.tune).last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Avanzado').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Avanzado').first);
      await tester.pumpAndSettle();
      // Las secciones de Ajustes son plegables: abre la de herramientas.
      final settingsScroll = find.byType(ListView).first;
      await tester.dragUntilVisible(
        find.text('Herramientas, sesión y diagnóstico'),
        settingsScroll,
        const Offset(0, -300),
      );
      await tester.ensureVisible(
        find.text('Herramientas, sesión y diagnóstico'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Herramientas, sesión y diagnóstico'));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.text('Sesión de YouTube opcional sin importar'),
        settingsScroll,
        const Offset(0, -300),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Sesión de YouTube opcional sin importar'),
        findsOneWidget,
      );
      await tester.dragUntilVisible(
        find.textContaining('cookies.txt en formato Netscape'),
        settingsScroll,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar sesión'), findsNothing);
      expect(
        find.textContaining('cookies.txt en formato Netscape'),
        findsOneWidget,
      );
      expect(find.textContaining('ni errores 429.'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Importar sesión'),
        settingsScroll,
        const Offset(0, -350),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      controller.sessionBusy = true;
      controller.clearError();
      await tester.pumpAndSettle();
      final busyButton = find.ancestor(
        of: find.text('Procesando sesión…'),
        matching: find.byWidgetPredicate((widget) => widget is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(busyButton).onPressed, isNull);
      expect(tester.takeException(), isNull);
      controller.sessionBusy = false;
      late File exported;
      await tester.runAsync(() async {
        exported = File(
          p.join(controller.supportDirectory.path, 'exported-cookies.txt'),
        );
        await exported.writeAsString(
          '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t2147483647\tTEST\texample\n',
        );
        await controller.configureYouTubeSession(exported);
      });
      await tester.pumpAndSettle();
      final localCopy = File(controller.source.cookieFile!);
      await tester.dragUntilVisible(
        find.text('Sesión de YouTube configurada'),
        settingsScroll,
        const Offset(0, 200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sesión de YouTube configurada'), findsOneWidget);
      await tester.dragUntilVisible(
        find.text('Reemplazar sesión'),
        settingsScroll,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Eliminar sesión'), findsOneWidget);
      expect(find.textContaining(localCopy.path), findsNothing);
      controller.sessionBusy = true;
      controller.clearError();
      await tester.pumpAndSettle();
      final deleteButton = find.ancestor(
        of: find.text('Eliminar sesión'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      expect(tester.widget<TextButton>(deleteButton).onPressed, isNull);
      controller.sessionBusy = false;
      controller.clearError();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Eliminar sesión'));
        for (
          var attempt = 0;
          attempt < 200 && controller.sessionBusy;
          attempt++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.hasYouTubeSession, isFalse);
      expect(await tester.runAsync(localCopy.exists), isFalse);
      expect(await tester.runAsync(exported.exists), isTrue);
      expect(find.text('Eliminar sesión'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Biblioteca shows only Likes and user playlists with their own members',
    (tester) async {
      final extraTracks = List.generate(
        24,
        (index) => Track(
          id: 'catalog-$index',
          title: 'Catálogo $index',
          artist: 'Aurora',
          pageUrl: 'https://www.youtube.com/watch?v=catalog$index',
          duration: const Duration(minutes: 3),
        ),
      );
      controller.tracks.addAll(extraTracks);
      await tester.runAsync(() async {
        await controller.toggleFavorite(controller.tracks.first);
        await controller.createPlaylist('Mi lista');
        await controller.addToPlaylist(
          controller.playlists.single,
          controller.tracks[1],
        );
      });
      await mount(tester, const Size(320, 800));
      await tester.tap(find.byIcon(Icons.library_music_outlined).last);
      await tester.pumpAndSettle();

      expect(find.text('Me gusta'), findsOneWidget);
      expect(find.text('Mi lista'), findsOneWidget);
      expect(find.text('Catálogo 0'), findsNothing);
      expect(find.text('Catálogo 23'), findsNothing);

      await tester.tap(find.text('Me gusta'));
      await tester.pumpAndSettle();
      expect(find.text(controller.tracks.first.title), findsOneWidget);
      expect(find.text(controller.tracks[1].title), findsNothing);
      expect(find.text('Catálogo 0'), findsNothing);

      await tester.tap(find.text('Todas las listas'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Mi lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mi lista'));
      await tester.pumpAndSettle();
      expect(find.text(controller.tracks[1].title), findsOneWidget);
      expect(find.text(controller.tracks.first.title), findsNothing);
      expect(find.text('Catálogo 0'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Selected playlist header follows renames', (tester) async {
    await tester.runAsync(() => controller.createPlaylist('Nombre anterior'));
    final selected = controller.playlists.single;
    await mount(tester, const Size(320, 800), scale: 2);
    await tester.tap(find.byIcon(Icons.library_music_outlined).last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nombre anterior'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nombre anterior'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => controller.renamePlaylist(selected, 'Nombre actualizado'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nombre actualizado'), findsOneWidget);
    expect(find.text('Nombre anterior'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Queue deduplicates playback context and selects the tapped song',
    (tester) async {
      final one = controller.tracks.firstWhere((track) => track.id == 'one');
      final two = controller.tracks.firstWhere((track) => track.id == 'two');
      await tester.runAsync(
        () => controller.playTrack(one, context: [one, two, one]),
      );
      await mount(tester, const Size(320, 800));
      await openFromMoreViews(tester, 'Cola de reproducción');
      final rows = find.descendant(
        of: find.byType(ReorderableListView),
        matching: find.byType(ListTile),
      );
      // El panel muestra la actual aparte y solo «A continuación» en la lista:
      // con la cola deduplicada [one, two] queda una fila (sin dedupe, dos).
      expect(controller.queue.map((track) => track.id), ['one', 'two']);
      expect(find.text('1 canciones'), findsOneWidget);
      expect(rows, findsNWidgets(1));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(rows.at(0));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(rows.at(0));
        for (var attempt = 0; attempt < 200 && controller.busy; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      expect(controller.busy, isFalse);
      await tester.pumpAndSettle();
      expect(controller.queueIndex, 1);
      expect(controller.queue.map((track) => track.id), ['one', 'two']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Full player, queue and real EQ bands fit a narrow screen', (
    tester,
  ) async {
    await tester.runAsync(
      () => controller.playTrack(
        controller.tracks.first,
        context: controller.tracks,
      ),
    );
    await mount(tester, const Size(320, 800), scale: 2, animated: true);
    expect(audio.analysisEnabled, isFalse);
    // Tocar el mini abre el reproductor (sección 4, Vinilo).
    await tester.tap(
      find.descendant(
        of: find.byType(MiniPlayerGestures),
        matching: find.byType(Artwork),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(VinylPlayer), findsOneWidget);
    expect(find.byType(MiniPlayerGestures), findsNothing);
    expect(audio.analysisEnabled, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(audio.analysisEnabled, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(audio.analysisEnabled, isTrue);
    controller.setReducedMotion(true);
    await tester.pump(const Duration(milliseconds: 500));
    expect(audio.analysisEnabled, isFalse);
    controller.setReducedMotion(false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(audio.analysisEnabled, isTrue);
    expect(tester.takeException(), isNull);
    // Letras: modo artista (sección 6) y salida con «Salir del modo letra».
    await openFromMoreViews(tester, 'Letras');
    expect(audio.analysisEnabled, isFalse);
    expect(find.byType(ArtistModePage), findsOneWidget);
    final closeLyrics = find.byTooltip('Salir del modo letra');
    expect(closeLyrics, findsOneWidget);
    await tester.tap(closeLyrics);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    // Ecualizador: sus bandas reales caben en 320 dp a 200 % de texto.
    await openFromMoreViews(tester, 'Ecualizador');
    expect(audio.analysisEnabled, isTrue);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('12k'), findsOneWidget);
    expect(find.text('Almacenamiento y biblioteca'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar ecualizador'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(audio.analysisEnabled, isFalse);
    await openFromMoreViews(tester, 'Cola de reproducción');
    expect(find.text('A continuación'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _TrackingAudio extends FakeAudio {
  bool analysisEnabled = true;
  @override
  void setVisualizationEnabled(bool enabled) => analysisEnabled = enabled;
}

class _ProgressiveSource extends FakeSource {
  bool supported = true;
  bool? applied;

  @override
  bool get supportsExperimentalProgressivePlayback => supported;

  @override
  void setExperimentalProgressivePlayback(bool enabled) => applied = enabled;
}
