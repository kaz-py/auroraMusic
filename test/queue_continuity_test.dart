// Continuidad de la cola: motor lento, radio, relleno al empezar la última
// pista y aleatorio que no «consume» lo saltado.
import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/audio_backend.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/queue_policy.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

String vid(String prefix, int n) =>
    '$prefix${n.toString().padLeft(11 - prefix.length, '0')}';

Track song(String prefix, int n) => Track(
  id: 'yt:${vid(prefix, n)}',
  title: '$prefix song $n',
  artist: '$prefix artist $n',
  pageUrl: 'https://music.youtube.com/watch?v=${vid(prefix, n)}',
  duration: const Duration(minutes: 3),
);

Future<void> eventually(bool Function() ok) async {
  for (var i = 0; i < 300; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw TestFailure('timeout');
}

class _Engine extends SuggestionsApi {
  _Engine(this.behavior);
  final Future<List<Suggestion>> Function() behavior;
  @override
  Future<List<Suggestion>> getSuggestions(SessionContext ctx) => behavior();
}

/// Radio de YouTube simulada; el audio lo resuelve el FakeSource.
class _RadioSource extends InnerTubeSource {
  _RadioSource(this.radio) : super(FakeSource(), post: (_, _) async => {});
  final List<Track> radio;
  @override
  Future<List<Track>> related(String videoId, {int limit = 25}) async =>
      radio.take(limit).toList();
  @override
  Future<ResolvedAudio> resolve(Track track) => delegate.resolve(track);
}

/// Como Android/web: `isPlaying` llega después por evento, no al dar play.
class _LateAudio extends FakeAudio {
  @override
  Future<void> play() async => notifyListeners();
}

void main() {
  group('motor con presupuesto', () {
    SessionContext ctx({int limit = 10}) => SessionContext(
      participants: [
        ParticipantTaste(
          'self',
          buildTasteProfile(
            favorites: const [],
            playlistTracks: const [],
            history: const [],
            events: const [],
            known: const {},
            now: DateTime(2026, 10, 24),
          ),
        ),
      ],
      now: DateTime(2026, 10, 24),
      limit: limit,
      seed: 1,
      remember: false,
    );

    test('una fuente colgada no tumba lo que ya llegó', () async {
      final fast = [for (var i = 0; i < 12; i++) song('fast', i)];
      final api = SuggestionsApi(
        memory: RecsMemory(persist: false),
        sourceTimeout: const Duration(seconds: 3),
        budget: const Duration(milliseconds: 300),
        sources: [
          RecSource(
            RecBucket.similar,
            (_, _) async => [for (final t in fast) DjCandidate(t, 'rápida')],
          ),
          RecSource(
            RecBucket.adjacent,
            (_, _) => Completer<List<DjCandidate>>().future,
          ),
        ],
      );
      final clock = Stopwatch()..start();
      final out = await api.getSuggestions(ctx());
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      expect(out, isNotEmpty);
      expect(out.every((s) => s.track.id.startsWith('yt:fast')), isTrue);
    });

    test('sin tiempo para la escalera devuelve la primera pasada', () async {
      var calls = 0;
      final api = SuggestionsApi(
        memory: RecsMemory(persist: false),
        sourceTimeout: const Duration(seconds: 3),
        budget: const Duration(milliseconds: 250),
        sources: [
          RecSource(RecBucket.similar, (_, _) async {
            // 1ª pasada: pocas y lentas (casi todo el presupuesto); la
            // escalera («fuentes x3») se cuelga.
            if (++calls > 1) return Completer<List<DjCandidate>>().future;
            await Future<void>.delayed(const Duration(milliseconds: 180));
            return [
              for (var i = 0; i < 3; i++) DjCandidate(song('few', i), 'poca'),
            ];
          }),
        ],
      );
      final clock = Stopwatch()..start();
      final out = await api.getSuggestions(ctx());
      expect(clock.elapsed, lessThan(const Duration(seconds: 1)));
      expect(out.map((s) => s.track.id), contains(song('few', 0).id));
    });
  });

  test('la radio pide hasta 25 pistas por llamada', () async {
    final rows = [
      for (var i = 0; i < 30; i++)
        {
          'playlistPanelVideoRenderer': {
            'videoId': vid('rad', i),
            'title': {
              'runs': [
                {'text': 'Radio $i'},
              ],
            },
            'longBylineText': {
              'runs': [
                {'text': 'Artista $i'},
              ],
            },
          },
        },
    ];
    final source = InnerTubeSource(
      FakeSource(),
      post: (_, _) async => {'contents': rows},
    );
    expect(await source.related(vid('seed', 0)), hasLength(25));
  });

  group('cola que no termina', () {
    late FakeAudio audio;

    Future<AppController> make({
      AudioBackend? backend,
      SourceBackend? source,
      List<Track>? library,
      Future<List<Suggestion>> Function()? engine,
    }) async {
      audio = (backend as FakeAudio?) ?? FakeAudio();
      final app = await createTestController(
        tracks: library ?? [song('lib', 0)],
        audio: audio,
        source: source,
        preferences: {'autoRefill': true},
      );
      addTearDown(() => closeTestController(app));
      if (engine != null) app.suggestionsApi = _Engine(engine);
      return app;
    }

    test('motor colgado: entra la radio de YouTube', () async {
      final radio = [for (var i = 0; i < 25; i++) song('radio', i)];
      final app = await make(
        source: _RadioSource(radio),
        engine: () => Completer<List<Suggestion>>().future,
      );
      app.refillEngineTimeout = const Duration(milliseconds: 80);
      final seed = song('lib', 0);
      await app.playTrack(seed);
      final ids = radio.map((t) => t.id).toSet();
      // Sin relación con la semilla solo entran las 3 más coherentes.
      await eventually(() => app.queue.skip(1).any((t) => ids.contains(t.id)));
    });

    test('rellena al EMPEZAR la última pista (sin esperar a que acabe, '
        'aunque isPlaying llegue tarde)', () async {
      final app = await make(
        backend: _LateAudio(),
        library: [for (var i = 0; i < 12; i++) song('lib', i)],
      );
      await app.playTrack(song('lib', 0));
      await eventually(() => app.queue.length >= 1 + kQueueLookahead);
      expect(app.queueIndex, 0);
    });

    test('un relleno en curso al terminar la pista se espera', () async {
      final picks = [for (var i = 0; i < 12; i++) song('slow', i)];
      final app = await make(
        engine: () async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return [for (final t in picks) Suggestion(t, 'motor', '')];
        },
      );
      await app.playTrack(song('lib', 0));
      // Termina antes de que el motor conteste.
      audio.position = audio.duration;
      audio.completions.add(null);
      await eventually(() => app.currentTrack?.id != song('lib', 0).id);
      expect(app.currentTrack!.id, startsWith('yt:slow'));
      expect(audio.isPlaying, isTrue);
    });
  });

  group('aleatorio', () {
    final tracks = [for (var i = 0; i < 4; i++) song('shuf', i)];
    late FakeAudio audio;

    Future<AppController> start() async {
      audio = FakeAudio();
      final app = await createTestController(tracks: tracks, audio: audio);
      addTearDown(() => closeTestController(app));
      await app.playTrack(tracks[0], context: tracks);
      app.setShuffle(true);
      return app;
    }

    test(
      'saltar no consume: la cola sigue entera y nunca repite seguido',
      () async {
        final app = await start();
        var previous = app.currentTrack!.id;
        final seen = <String>{previous};
        // Más saltos que pistas: antes la cola se agotaba y se paraba.
        for (var i = 0; i < 20; i++) {
          audio.position = const Duration(seconds: 10);
          await app.next();
          final now = app.currentTrack!.id;
          expect(now, isNot(previous), reason: 'repetida seguida en $i');
          expect(audio.isPlaying, isTrue, reason: 'se paró en $i');
          seen.add(now);
          previous = now;
        }
        expect(app.queue.map((t) => t.id), tracks.map((t) => t.id));
        // Lo saltado vuelve a tener oportunidad: incluida la primera.
        expect(seen, hasLength(tracks.length));
      },
    );

    test('lo escuchado no vuelve hasta que reinicia la vuelta', () async {
      final app = await start();
      final listened = app.currentTrack!.id;
      audio.position = const Duration(minutes: 2); // ≥30 s y ≥30 %
      await app.next();
      for (var i = 0; i < 20; i++) {
        audio.position = Duration.zero;
        await app.next();
        expect(app.currentTrack!.id, isNot(listened));
        expect(audio.isPlaying, isTrue);
      }
      expect(app.queue, hasLength(tracks.length));
    });
  });
}
