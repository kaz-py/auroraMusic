import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/dj_modes.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/ui/dj_discovery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track song(int n, {String prefix = 'sess'}) => Track(
  id: 'yt:$prefix${n.toString().padLeft(6, '0')}',
  title: 'Song $prefix $n',
  artist: 'Artist $prefix $n',
  pageUrl:
      'https://music.youtube.com/watch?v=$prefix${n.toString().padLeft(6, '0')}',
  duration: const Duration(minutes: 3),
);

class _Engine extends SuggestionsApi {
  _Engine(this.picks);
  final List<Track> picks;
  @override
  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async => [
    for (final t in picks) Suggestion(t, 'Radio de YouTube', ''),
  ];
}

void main() {
  late AppController app;
  late FakeAudio audio;

  Future<void> make(int size) async {
    audio = FakeAudio();
    app = await createTestController(
      tracks: [for (var i = 0; i < size; i++) song(i)],
      audio: audio,
      preferences: {'autoRefill': true},
    );
    addTearDown(() => closeTestController(app));
  }

  group('mezcla de nuevas y ya oídas', () {
    final heard = [for (var i = 0; i < 40; i++) song(i, prefix: 'heard')];
    final fresh = [for (var i = 0; i < 40; i++) song(i, prefix: 'fresh')];
    final heardIds = {for (final t in heard) t.id};
    final now = DateTime(2026, 10, 19, 12);

    Future<List<Suggestion>> run(
      DjMode mode, {
      RecsMemory? memory,
      Set<String> recentKeys = const {},
    }) {
      final api = SuggestionsApi(
        memory: memory ?? RecsMemory(persist: false),
        exploration: 0,
      );
      return api.getSuggestions(
        SessionContext(
          participants: const [],
          mode: mode,
          library: heard,
          extraCandidates: [
            for (final t in fresh) DjCandidate(t, 'Radio de YouTube'),
          ],
          limit: 20,
          now: now,
          seed: 7,
          remember: false,
          recentKeys: recentKeys,
          heardShare: djHeardShare(mode),
        ),
      );
    }

    test('la cuota de ya oídas cumple cada modo y el resto es nuevo', () async {
      for (final mode in DjMode.values) {
        final picks = await run(mode);
        final heardCount = picks.where((s) => heardIds.contains(s.track.id));
        final expected = djHeardShare(mode) * 20;
        expect(picks, hasLength(20), reason: mode.name);
        expect(
          heardCount.length,
          inInclusiveRange(expected.floor() - 1, expected.ceil() + 1),
          reason: '${mode.name}: ${heardCount.length} ya oídas',
        );
        expect(
          picks.length - heardCount.length,
          greaterThan(0),
          reason: '${mode.name}: debe haber nuevas',
        );
      }
      expect(
        djHeardShare(DjMode.relax),
        greaterThan(djHeardShare(DjMode.discover)),
      );
    });

    test(
      'una pista oída hace poco no vuelve; el mismo artista no va seguido',
      () async {
        final memory = RecsMemory(persist: false);
        // Las 10 primeras oídas sonaron hace 5 minutos (dentro del enfriamiento).
        await memory.record(
          heard.take(10),
          now.subtract(const Duration(minutes: 5)),
        );
        final recent = {for (final t in heard.take(10)) t.id};
        final picks = await run(
          DjMode.relax,
          memory: memory,
          recentKeys: {
            for (final t in heard.skip(10).take(5))
              ...recommendationTrackKeys(t),
          },
        );
        final ids = picks.map((s) => s.track.id).toList();
        expect(ids.toSet().length, ids.length, reason: 'sin duplicados');
        expect(ids.where(recent.contains), isEmpty);
        for (final t in heard.skip(10).take(5)) {
          expect(ids, isNot(contains(t.id)));
        }
        final artists = picks.map((s) => s.track.artist).toList();
        for (var i = 1; i < artists.length; i++) {
          expect(artists[i], isNot(artists[i - 1]));
        }
        expect(ids.any(heardIds.contains), isTrue);
      },
    );

    test(
      'sin cuota (Jam) la mezcla no cambia: solo candidatos externos',
      () async {
        final api = SuggestionsApi(
          memory: RecsMemory(persist: false),
          exploration: 0,
        );
        final picks = await api.getSuggestions(
          SessionContext(
            participants: const [],
            library: heard,
            extraCandidates: [for (final t in fresh) DjCandidate(t, 'x')],
            limit: 10,
            now: now,
            seed: 1,
            remember: false,
          ),
        );
        expect(picks.where((s) => heardIds.contains(s.track.id)), isEmpty);
      },
    );

    test('rankDjCandidates respeta la misma cuota', () {
      final picks = rankDjCandidates(
        candidates: [
          for (final t in heard) DjCandidate(t, 'oída', prior: 0.6),
          for (final t in fresh) DjCandidate(t, 'nueva', prior: 0.5),
        ],
        profile: List.filled(djVectorDims, 0),
        limit: 20,
        heardKeys: {for (final t in heard) ...recommendationTrackKeys(t)},
        heardShare: 0.4,
      );
      final n = picks.where((r) => heardIds.contains(r.track.id)).length;
      expect(n, inInclusiveRange(7, 9));
    });
  });

  group('mezcla de artistas con semilla dominante', () {
    Track by(String artist, int n) => Track(
      id: 'yt:${artist.toLowerCase()}$n',
      title: 'Tema $artist $n',
      artist: artist,
      pageUrl: 'https://music.youtube.com/watch?v=${artist.toLowerCase()}$n',
      duration: const Duration(minutes: 3),
    );
    final dominant = [for (var i = 0; i < 25; i++) by('Dominante', i)];
    final others = [
      for (var n = 0; n < 3; n++)
        for (var a = 0; a < 12; a++) by('Otro$a', n),
    ];

    int longestRun(List<String> artists) {
      var best = 1, run = 1;
      for (var i = 1; i < artists.length; i++) {
        run = artists[i] == artists[i - 1] ? run + 1 : 1;
        if (run > best) best = run;
      }
      return best;
    }

    test(
      'motor: máx. 1 seguida, <=30 % por artista y varios artistas',
      () async {
        final api = SuggestionsApi(
          memory: RecsMemory(persist: false),
          exploration: 0,
        );
        final picks = await api.getSuggestions(
          SessionContext(
            participants: const [],
            current: dominant.first,
            queueTail: [dominant.first],
            library: [...dominant, ...others],
            extraCandidates: [
              for (final t in dominant) DjCandidate(t, 'x', prior: 0.9),
            ],
            limit: 20,
            seed: 3,
            remember: false,
          ),
        );
        final artists = [for (final s in picks) s.track.artist];
        expect(artists, hasLength(20));
        expect(longestRun(artists), 1);
        expect(
          artists.where((a) => a == 'Dominante').length,
          lessThanOrEqualTo(6),
        );
        expect(artists.toSet().length, greaterThanOrEqualTo(8));
      },
    );

    test('DJ personal (rankDjCandidates): mismas garantías', () {
      final picks = rankDjCandidates(
        candidates: [
          for (final t in dominant) DjCandidate(t, 'x', prior: 0.9),
          for (final t in others) DjCandidate(t, 'y', prior: 0.3),
        ],
        profile: List.filled(djVectorDims, 0),
        limit: 12,
        current: dominant.first,
        queueTail: [dominant.first],
      );
      final artists = [for (final r in picks) r.track.artist];
      expect(longestRun(artists), 1);
      expect(
        artists.where((a) => a == 'Dominante').length,
        lessThanOrEqualTo(3),
      );
      expect(artists.toSet().length, greaterThanOrEqualTo(6));
    });

    test(
      'cola al reproducir: la elegida suena primero y el resto se mezcla',
      () async {
        audio = FakeAudio();
        app = await createTestController(
          tracks: [...dominant, ...others],
          audio: audio,
          preferences: {'autoRefill': true},
        );
        addTearDown(() => closeTestController(app));
        await app.playTrack(dominant[0], context: [dominant[0]]);
        for (var i = 0; i < 300 && app.queue.length < 11; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(app.currentTrack?.id, dominant[0].id);
        final tail = [for (final t in app.queue.skip(1)) t.artist];
        expect(tail.length, greaterThanOrEqualTo(10));
        expect(longestRun([dominant[0].artist, ...tail]), 1);
        expect(
          tail.where((a) => a == 'Dominante').length,
          lessThanOrEqualTo(3),
        );
        expect(tail.toSet().length, greaterThanOrEqualTo(4));
      },
    );
  });

  group('startDjSession', () {
    test('fija el modo, suena de inmediato y deja el DJ activo', () async {
      await make(8);
      await app.toggleFavorite(app.tracks.first);
      final ok = await app.startDjSession(mode: DjMode.relax);
      expect(ok, isTrue);
      expect(app.personalDjActive, isTrue);
      expect(app.djMode, DjMode.relax);
      expect(app.currentTrack, isNotNull);
      expect(audio.isPlaying, isTrue);
    });

    test('sin biblioteca ni motor no arranca y no deja el DJ activo', () async {
      await make(0);
      app.suggestionsApi = _Engine(const []);
      expect(await app.startDjSession(), isFalse);
      expect(app.personalDjActive, isFalse);
    });

    test('sin biblioteca toma la semilla del motor', () async {
      await make(0);
      app.suggestionsApi = _Engine([song(50), song(51), song(52)]);
      expect(await app.startDjSession(), isTrue);
      expect(app.personalDjActive, isTrue);
      expect(app.currentTrack?.id, song(50).id);
      expect(audio.isPlaying, isTrue);
    });

    test('pista elegida a mano no apaga el DJ ni vacía su cola', () async {
      await make(10);
      await app.toggleFavorite(app.tracks.first);
      await app.startDjSession();
      final ahead = app.queue.length - app.queueIndex - 1;
      await app.playTrack(song(9), replaceQueue: false);
      expect(app.personalDjActive, isTrue);
      expect(app.currentTrack?.id, song(9).id);
      expect(
        app.queue.length - app.queueIndex - 1,
        greaterThanOrEqualTo(ahead > 0 ? ahead - 1 : 0),
      );
    });

    test('reemplazar la cola detiene el DJ', () async {
      await make(10);
      await app.toggleFavorite(app.tracks.first);
      await app.startDjSession();
      await app.playTrack(song(3), context: [song(3), song(4)]);
      expect(app.personalDjActive, isFalse);
    });

    test('con Jam activa no arranca', () async {
      await make(4);
      await app.beginJamPlayback();
      expect(await app.startDjSession(), isFalse);
      expect(app.personalDjActive, isFalse);
    });
  });

  group('DjSessionCard', () {
    Future<void> mount(
      WidgetTester tester, {
      Size size = const Size(700, 1000),
      double scale = 1,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: DjDiscoveryPage(controller: app, onSearch: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('iniciar, cambiar de modo y detener', (tester) async {
      await tester.runAsync(() => make(8));
      await app.toggleFavorite(app.tracks.first);
      await mount(tester);
      expect(find.text('DJ detenido'), findsOneWidget);
      await tester.tap(find.text('Iniciar DJ'));
      await settle(tester);
      expect(app.personalDjActive, isTrue);
      expect(find.text('DJ activo · Descubrir'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Energía'));
      await settle(tester);
      expect(app.djMode, DjMode.energy);
      expect(find.text('DJ activo · Energía'), findsOneWidget);
      await tester.tap(find.text('Detener DJ'));
      await settle(tester);
      expect(app.personalDjActive, isFalse);
      expect(find.text('DJ detenido'), findsOneWidget);
      expect(audio.isPlaying, isTrue);
    });

    testWidgets('sin música avisa en vez de quedarse mudo', (tester) async {
      await tester.runAsync(() => make(0));
      app.suggestionsApi = _Engine(const []);
      await mount(tester);
      await tester.tap(find.text('Iniciar DJ'));
      await settle(tester);
      expect(find.textContaining('No hay con qué empezar'), findsOneWidget);
      expect(app.personalDjActive, isFalse);
    });

    testWidgets('sin desbordes a 320, 500 y 1400 con texto al 200%', (
      tester,
    ) async {
      await tester.runAsync(() => make(4));
      for (final w in [320.0, 500.0, 1400.0]) {
        await mount(tester, size: Size(w, 800), scale: 2);
        expect(tester.takeException(), isNull, reason: 'ancho $w');
      }
    });
  });
}
