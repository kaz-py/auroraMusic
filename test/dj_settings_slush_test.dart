import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/dj_discovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track song(
  String id, {
  String artist = 'North',
  String? title,
  String? album,
  List<String> genres = const [],
}) => Track(
  id: id,
  title: title ?? 'Song $id',
  artist: artist,
  album: album,
  genres: genres,
  pageUrl: 'https://youtu.be/$id',
);

void main() {
  group('ajustes del DJ en el ranking', () {
    test('enfriar artistas apagado permite el mismo artista seguido', () {
      final candidates = [
        for (var i = 0; i < 5; i++) DjCandidate(song('a$i', artist: 'A'), 'r'),
        DjCandidate(song('b0', artist: 'B'), 'r'),
      ];
      List<String> rank({required bool cooldown}) => rankDjCandidates(
        candidates: candidates,
        profile: embedDjTrack(song('x', artist: 'A')),
        limit: 6,
        artistCooldown: cooldown,
      ).map((r) => r.track.artist).toList();
      final on = rank(cooldown: true);
      for (var i = 1; i < on.length; i++) {
        expect(on[i], isNot(on[i - 1]));
      }
      expect(on.length, lessThan(6));
      final off = rank(cooldown: false);
      expect(off, hasLength(6));
      expect([
        for (var i = 1; i < off.length; i++) off[i] == off[i - 1],
      ], contains(true));
    });

    test('más diversidad cambia el orden', () {
      final taste = song(
        'taste',
        artist: 'Ana',
        title: 'Night Drive',
        album: 'Neon',
        genres: ['synthwave'],
      );
      final candidates = [
        DjCandidate(
          song(
            'c1',
            artist: 'Ana',
            title: 'Night Drive',
            album: 'Neon',
            genres: ['synthwave'],
          ),
          'r',
        ),
        DjCandidate(
          song(
            'c2',
            artist: 'Bea',
            title: 'Night Drive',
            album: 'Neon',
            genres: ['synthwave'],
          ),
          'r',
        ),
        DjCandidate(
          song('c3', artist: 'Cid', title: 'Morning Coffee'),
          'r',
          prior: 1,
        ),
      ];
      List<String> rank(double diversity) => rankDjCandidates(
        candidates: candidates,
        profile: embedDjTrack(taste),
        limit: 3,
        lambda: 1 - diversity,
      ).map((r) => r.track.id).toList();
      expect(rank(0).take(2), ['c1', 'c2']);
      expect(rank(djMaxDiversity), isNot(rank(0)));
    });

    test('afinidad normalizada 0-1 y ausente sin perfil', () {
      final t = song('t', artist: 'Ana');
      final profile = embedDjTrack(t);
      expect(djAffinity(profile: profile, track: t), closeTo(1, 1e-6));
      expect(
        djAffinity(profile: List.filled(profile.length, 0.0), track: t),
        isNull,
      );
      final picks = rankDjCandidates(
        candidates: [DjCandidate(t, 'r', prior: 1)],
        profile: profile,
        limit: 1,
      );
      expect(picks.single.affinity, inInclusiveRange(0, 1));
    });

    test('valores por defecto y límites', () async {
      final app = await createTestController(tracks: [song('a')]);
      addTearDown(() => closeTestController(app));
      expect(app.djDiversity, closeTo(1 - djMmrLambda, 1e-9));
      expect(app.djArtistCooldown, isTrue);
      await app.setDjDiversity(5);
      expect(app.djDiversity, djMaxDiversity);
      await app.setDjArtistCooldown(false);
      expect(app.djArtistCooldown, isFalse);
    });
  });

  for (final size in [
    const Size(1280, 800),
    const Size(1920, 1080),
    const Size(390, 844),
    const Size(360, 740),
    const Size(600, 900),
    const Size(900, 800),
    const Size(1440, 900),
  ]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'DJ Slush se pinta a ${size.width.toInt()} px ${brightness.name} x$scale',
          (tester) async {
            late AppController app;
            // setUp fuera del reloj falso: el controlador abre SQLite real.
            await tester.runAsync(() async {
              app = await createTestController(
                tracks: [
                  song('a', title: 'Marea alta'),
                  song('b', artist: 'Otro'),
                ],
              );
            });
            addTearDown(() => tester.runAsync(() => closeTestController(app)));
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              MaterialApp(
                theme: slushTheme(brightness, const Color(0xff5fe0a0)),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: DjDiscoveryPage(controller: app, onSearch: () {}),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);
            expect(find.text('AUROR'), findsOneWidget);
            for (final label in ['Filtros', 'Diversidad', 'Enfriar artistas']) {
              await tester.scrollUntilVisible(
                find.text(label),
                200,
                scrollable: find.byType(Scrollable).first,
              );
              expect(find.text(label), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
            if (size.width >= 1920) {
              // Maqueta 04: los filtros van pegados al borde derecho del contenido
              // (máx. 1280 centrado).
              expect(
                tester.getTopRight(find.byKey(const ValueKey('dj-filters'))).dx,
                greaterThanOrEqualTo(size.width - 340),
              );
            }
          },
        );
      }
    }
  }
}
