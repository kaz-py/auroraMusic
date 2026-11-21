import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/follow/follow_models.dart';
import 'package:aurora_music/follow/follow_repository.dart';
import 'package:aurora_music/follow/follow_service.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/ui/artists_page.dart';
import 'package:aurora_music/ui/follow_widgets.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _sizes = [Size(320, 700), Size(500, 800), Size(1400, 900)];

void main() {
  late LibraryDatabase db;
  late FollowService service;
  late List<SearchEntry> hits;

  setUp(() {
    db = LibraryDatabase.memory();
    hits = const [
      SearchEntry(
        kind: SearchKind.artists,
        browseId: 'UCana',
        title: 'Ana Núñez',
      ),
    ];
    service = FollowService(
      repository: FollowRepository(db),
      fetchArtist: (_) async => const ArtistPage(),
      findArtist: (_) async => hits,
    );
  });
  tearDown(() async {
    service.dispose();
    await db.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(500, 800),
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: app!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => pumpEventQueue());
    await tester.pump();
  }

  group('FollowButton', () {
    testWidgets('alterna Seguir / Siguiendo con tooltip y semántica', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, FollowButton(service: service, name: 'Ana Núñez'));
      expect(find.text('Seguir'), findsOneWidget);
      expect(
        find.byTooltip('Seguir a Ana Núñez y ver sus novedades'),
        findsOneWidget,
      );
      await tester.tap(find.text('Seguir'));
      await settle(tester);
      expect(find.text('Siguiendo'), findsOneWidget);
      expect(find.byTooltip('Dejar de seguir a Ana Núñez'), findsOneWidget);
      expect(service.artists.single.browseId, 'UCana');
      expect(find.bySemanticsLabel('Siguiendo a Ana Núñez'), findsOneWidget);

      await tester.tap(find.text('Siguiendo'));
      await settle(tester);
      expect(find.text('Seguir'), findsOneWidget);
      expect(service.artists, isEmpty);
      semantics.dispose();
    });

    testWidgets('si no encuentra al artista avisa y no sigue', (tester) async {
      hits = const [];
      await mount(tester, FollowButton(service: service, name: 'Nadie'));
      await tester.tap(find.text('Seguir'));
      await settle(tester);
      expect(find.textContaining('No se encontró a «Nadie»'), findsOneWidget);
      expect(find.text('Seguir'), findsOneWidget);
      expect(service.artists, isEmpty);
      // El aviso se cierra solo (no queda un SnackBar persistente).
      await tester.pump(const Duration(seconds: 1)); // termina la entrada
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se encontró'), findsNothing);
    });

    for (final size in _sizes) {
      testWidgets('cabe en ${size.width.toInt()} px con texto al 200 %', (
        tester,
      ) async {
        await mount(
          tester,
          FollowButton(
            service: service,
            name: 'Un artista con un nombre bastante largo de verdad',
            browseId: 'UCx',
          ),
          size: size,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => service.follow('Un artista', browseId: 'UCx'),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('FollowedArtistsSection', () {
    Future<void> seed(WidgetTester tester) async {
      await tester.runAsync(() async {
        await service.repository.follow('UC1', 'Ana Núñez');
        await service.repository.follow(
          'UC2',
          'Un artista con un nombre muy largo que debe envolver sin desbordar',
        );
        await service.repository.addNews([
          NewRelease(
            id: 'MPREb_1',
            artistId: 'UC1',
            artistName: 'Ana Núñez',
            title: 'Un título de sencillo bastante largo para probar',
            subtitle: 'Sencillo • Ana Núñez • 2026',
            detectedAt: DateTime(2026, 10),
          ),
        ]);
        await service.load();
      });
    }

    testWidgets('lista novedades y seguidos, abre, descarta y deja de seguir', (
      tester,
    ) async {
      await seed(tester);
      FollowedArtist? openedArtist;
      NewRelease? openedRelease;
      await mount(
        tester,
        FollowedArtistsSection(
          service: service,
          onOpenArtist: (a) => openedArtist = a,
          onOpenRelease: (r) => openedRelease = r,
        ),
      );
      expect(find.text('Novedades de tus artistas'), findsOneWidget);
      expect(find.text('Artistas que sigues'), findsOneWidget);
      expect(find.text('Sencillo • Ana Núñez • 2026'), findsOneWidget);

      await tester.tap(
        find.byTooltip(
          'Abrir Un título de sencillo bastante largo para probar',
        ),
      );
      expect(openedRelease?.id, 'MPREb_1');
      expect(openedRelease?.entry.kind, SearchKind.albums);
      await tester.tap(find.text('Ana Núñez').first);
      expect(openedArtist?.browseId, 'UC1');

      await tester.tap(find.byTooltip('Dejar de seguir a Ana Núñez'));
      await settle(tester);
      expect(service.artists.map((a) => a.browseId), ['UC2']);
      expect(find.text('Novedades de tus artistas'), findsNothing);
    });

    testWidgets('marcar como vistas oculta la sección de novedades', (
      tester,
    ) async {
      await seed(tester);
      await mount(
        tester,
        FollowedArtistsSection(
          service: service,
          onOpenArtist: (_) {},
          onOpenRelease: (_) {},
        ),
      );
      await tester.tap(find.text('Marcar como vistas'));
      await settle(tester);
      expect(find.text('Novedades de tus artistas'), findsNothing);
      expect(find.text('Artistas que sigues'), findsOneWidget);
    });

    testWidgets('sin seguidos explica cómo seguir', (tester) async {
      await mount(
        tester,
        FollowedArtistsSection(
          service: service,
          onOpenArtist: (_) {},
          onOpenRelease: (_) {},
        ),
      );
      expect(find.textContaining('Sigue a un artista'), findsOneWidget);
    });

    for (final size in _sizes) {
      testWidgets('sin desbordes en ${size.width.toInt()} px y texto 200 %', (
        tester,
      ) async {
        await seed(tester);
        await mount(
          tester,
          FollowedArtistsSection(
            service: service,
            onOpenArtist: (_) {},
            onOpenRelease: (_) {},
          ),
          size: size,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('integración en pantallas existentes', () {
    testWidgets('la lista de artistas muestra solo los seguidos', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await service.repository.follow('UC1', 'Ana Núñez');
        await service.load();
      });
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: ArtistsPage(
                tracks: const [
                  Track(id: 'one', title: 'First', artist: 'Ana Núñez'),
                  Track(id: 'two', title: 'Other', artist: 'No seguido'),
                ],
                follow: service,
                onPlay: (_) {},
                onSearch: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('1 artista que sigues'), findsOneWidget);
      expect(find.text('No seguido'), findsNothing);
      await tester.tap(find.text('Ana Núñez').first);
      await tester.pumpAndSettle();
      expect(find.text('Siguiendo'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    for (final size in _sizes) {
      testWidgets('el reproductor muestra Seguir junto al artista a '
          '${size.width.toInt()} px y 200 %', (tester) async {
        final controller = (await tester.runAsync(
          () => createTestController(
            tracks: const [
              Track(
                id: 'yt:abc',
                title: 'Canción',
                artist: 'Ana Núñez feat. Otro artista con nombre largo',
                pageUrl: 'https://music.youtube.com/watch?v=abc',
              ),
            ],
          ),
        ))!;
        await tester.runAsync(
          () => controller.playTrack(controller.tracks.first),
        );
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: VinylPlayer(controller: controller, follow: service),
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Seguir'), findsOneWidget);
        expect(
          find.byTooltip('Seguir a Ana Núñez y ver sus novedades'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() => closeTestController(controller));
        await tester.binding.setSurfaceSize(null);
      });
    }
  });
}
