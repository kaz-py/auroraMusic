import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/import/spotify_import.dart';
import 'package:aurora_music/ui/spotify_import_dialog.dart';
import 'package:aurora_music/theme/atelier_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/fakes.dart';

class _FixtureSource extends FakeSource {
  @override
  bool get supportsPlaybackCache => true;
}

class _FixtureLyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration.zero, 'Una luz sobre el camino'),
      LyricLine(Duration(seconds: 2), 'La música nos acompaña'),
      LyricLine(Duration(seconds: 4), 'Y seguimos escuchando'),
    ],
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native redesigned interface and lyrics', (tester) async {
    // Original artwork fixtures served locally; no external image service.
    final coverBytes = <List<int>>[];
    for (var i = 0; i < 8; i++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final tone = HSLColor.fromAHSL(1, 22 + i * 30.0, .35, .25).toColor();
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 320),
        Paint()..color = tone,
      );
      canvas.drawCircle(
        const Offset(160, 160),
        94,
        Paint()..color = const Color(0xffddbe89),
      );
      canvas.drawRect(
        const Rect.fromLTWH(24, 272, 272, 36),
        Paint()..color = const Color(0xff211b17),
      );
      final paragraph =
          (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 18))
                ..pushStyle(ui.TextStyle(color: const Color(0xfff4eee7)))
                ..addText('SESIÓN AURORA · ${i + 1}'))
              .build()
            ..layout(const ui.ParagraphConstraints(width: 256));
      canvas.drawParagraph(paragraph, const Offset(32, 280));
      final picture = recorder.endRecording();
      final cover = await picture.toImage(320, 320);
      final bytes = await cover.toByteData(format: ui.ImageByteFormat.png);
      coverBytes.add(bytes!.buffer.asUint8List());
      cover.dispose();
      picture.dispose();
      paragraph.dispose();
    }
    final server = await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server!.listen((request) async {
      final index = int.tryParse(request.uri.path.substring(1)) ?? 0;
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.add(coverBytes[index.clamp(0, 7)]);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final controller = await tester.runAsync(
      () => createTestController(
        source: _FixtureSource(),
        tracks: [
          Track(
            id: 'fixture-a',
            title: 'Luz de octubre',
            artist: 'Sesión Aurora',
            duration: Duration(minutes: 3),
            pageUrl: 'https://example.test/fixture-a',
            artworkUrl: 'http://127.0.0.1:${server.port}/0',
          ),
          Track(
            id: 'fixture-b',
            title: 'Otra orilla',
            artist: 'Estudio de prueba',
            duration: Duration(minutes: 4),
            artworkUrl: 'http://127.0.0.1:${server.port}/1',
          ),
          Track(
            id: 'fixture-c',
            title: 'Por el camino',
            artist: 'Sesión Aurora',
            duration: Duration(minutes: 2),
            artworkUrl: 'http://127.0.0.1:${server.port}/2',
          ),
          for (var i = 3; i < 8; i++)
            Track(
              id: 'fixture-$i',
              title: 'Estudio de octubre ${i + 1}',
              artist: 'Colección de prueba',
              duration: const Duration(minutes: 3),
              artworkUrl: 'http://127.0.0.1:${server.port}/$i',
            ),
        ],
      ),
    );
    final c = controller!;
    await tester.runAsync(() async {
      await c.createPlaylist('Noches de octubre');
      await c.addToPlaylist(c.playlists.first, c.tracks.first);
      await c.createPlaylist('Para caminar');
      await c.addToPlaylist(c.playlists.first, c.tracks.last);
      await c.toggleFavorite(c.tracks.first);
    });
    final container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => c)],
    );
    final key = GlobalKey();
    c.queue = c.tracks.reversed.toList();
    c.queueIndex = 0;
    c.recentTracks = c.queue.toList();
    await tester.runAsync(() => c.playQueueAt(0));
    expect(c.error, isNull);
    await c.audio.pause();
    await c.audio.seek(const Duration(seconds: 2));
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(key: key, child: const AuroraApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pumpAndSettle();

    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      if (!Platform.isWindows) return;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 1);
      final data = await picture.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      await tester.runAsync(() async {
        await Directory('build/screenshots').create(recursive: true);
        await File(
          'build/screenshots/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      });
    }

    await capture('aurora-redesign-home');
    for (final entry in {
      'Biblioteca': 'library',
      'Buscar': 'search',
      'Modo Vinilo': 'vinyl',
      'Cola de reproducción': 'queue',
      'Ajustes': 'settings',
    }.entries) {
      await tester.tap(find.byTooltip(entry.key).first);
      await tester.pumpAndSettle();
      await capture('aurora-redesign-${entry.value}');
    }
    c.setAccentPalette('purple');
    await tester.pumpAndSettle();
    await capture('aurora-102-settings-purple');
    await tester.tap(find.byTooltip('Inicio').first);
    await tester.pumpAndSettle();
    await capture('aurora-102-home-purple');
    await tester.tap(find.byTooltip('Descargas locales').first);
    await tester.pumpAndSettle();
    expect(find.text('Cambiar carpeta'), findsOneWidget);
    expect(find.text('Abrir carpeta'), findsOneWidget);
    await capture('aurora-redesign-downloads');

    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Inicio').first);
    await tester.pumpAndSettle();
    await capture('aurora-redesign-mobile-home');
    await tester.tap(find.byTooltip('Biblioteca').first);
    await tester.pumpAndSettle();
    await capture('aurora-redesign-mobile-library');
    expect(find.text('Importar de Spotify'), findsOneWidget);
    final preview = SpotifyImportDialog.show(
      tester.element(find.byType(Scaffold).first),
      result: const SpotifyImportResult(
        playlists: [
          SpotifyImportPlaylist(
            name: 'Música para el camino',
            tracks: [
              SpotifyImportTrack(title: 'Otra orilla', artist: 'Estudio'),
            ],
          ),
        ],
        skipped: 0,
      ),
      onImport: c.importSpotifyPlaylists,
    );
    await tester.pumpAndSettle();
    await capture('aurora-102-mobile-spotify-import');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await preview;
    await tester.binding.setSurfaceSize(const Size(1440, 900));

    await tester.pumpWidget(const SizedBox.shrink());
    await c.audio.play();
    var lyricsClosed = false;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: auroraTheme(Brightness.dark, const Color(0xffe86927)),
          home: Scaffold(
            body: ArtistModePage(
              controller: c,
              service: _FixtureLyrics(),
              onTogglePlay: () {},
              onClose: () => lyricsClosed = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('La música nos acompaña'), findsOneWidget);
    await tester.tap(find.text('Y seguimos escuchando'));
    await tester.pumpAndSettle();
    expect(c.audio.position, const Duration(seconds: 4));
    expect(c.audio.isPlaying, isTrue);
    await tester.tap(find.text('Una luz sobre el camino'));
    await tester.pumpAndSettle();
    expect(c.audio.position, Duration.zero);
    expect(c.audio.isPlaying, isTrue);
    await capture('aurora-redesign-lyrics');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpAndSettle();
    await capture('aurora-103-mobile-lyrics');
    await tester.tap(find.byTooltip('Salir del modo letra'));
    await tester.pumpAndSettle();
    expect(lyricsClosed, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(() async {
      await c.closed;
      await c.supportDirectory.delete(recursive: true);
    });
    await tester.binding.setSurfaceSize(null);
  });
}
