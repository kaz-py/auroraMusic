import 'dart:convert';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/artist_graph.dart';
import 'package:aurora_music/dj/coherence.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 10, 17, 12);
String vid(String s) => s.padRight(11, '_').substring(0, 11);
Track tr(
  String id,
  String title,
  String artist, {
  List<String> genres = const [],
}) => Track(
  id: 'yt:${vid(id)}',
  title: title,
  artist: artist,
  genres: genres,
  pageUrl: 'https://music.youtube.com/watch?v=${vid(id)}',
);

Future<List<Suggestion>> run(
  List<Track> pool,
  Track current, {
  int limit = 3,
  Set<String> favs = const {},
}) {
  final api = SuggestionsApi(
    memory: RecsMemory(persist: false),
    exploration: 0,
  );
  return api.getSuggestions(
    SessionContext(
      participants: [
        ParticipantTaste(
          'yo',
          buildTasteProfile(
            favorites: [current],
            playlistTracks: const [],
            history: const [],
            events: const [],
            known: const {},
            now: now,
          ),
        ),
      ],
      current: current,
      favoriteArtists: favs,
      extraCandidates: [
        for (final t in pool) DjCandidate(t, 'Radio', bucket: RecBucket.radio),
      ],
      limit: limit,
      now: now,
      seed: 1,
      remember: false,
    ),
  );
}

void main() {
  final cur = tr('cur', 'Usseewa', 'Ado');
  final bad = tr(
    'bad',
    'Ado (Teledrama Theme Song)',
    'Anushka Weerakkody & Neluka Deemantha',
  );

  test(
    'título con nombre de artista pero otro artista: fuera si hay relacionadas',
    () async {
      final good = tr('g1', 'Show', 'Ado');
      final feat = tr('g2', 'Otra', 'Vocaloid X feat. Ado');
      final r = await run([bad, good, feat], cur);
      expect(r.map((s) => s.track.id), isNot(contains(bad.id)));
      expect(r.first.coherence, greaterThan(0.8));
      expect(
        scoreCoherence(bad, CoherenceContext(artists: ['Ado'])).score,
        lessThan(0.2),
      );
    },
  );

  test('feat. del artista correcto sube', () {
    final ctx = CoherenceContext(artists: ['Ado']);
    expect(
      scoreCoherence(tr('a', 'Cancion (feat. Ado)', 'Otro'), ctx).score,
      greaterThan(0.8),
    );
  });

  test('todo dudoso: nunca vacío', () async {
    final r = await run([bad, tr('b2', 'Ado Ado', 'Nadie')], cur, limit: 2);
    expect(r, hasLength(2));
    final ranked = CoherenceFilter.rank([
      DjCandidate(bad, 'x'),
    ], CoherenceContext(artists: ['Ado']));
    expect(ranked, hasLength(1));
  });

  test(
    'palabra común en el título sin género: rechazo duro; con género solo baja',
    () {
      final ctx = CoherenceContext(artists: ['Love'], genres: ['pop']);
      final hard = scoreCoherence(tr('a', 'Love me', 'Otro'), ctx);
      expect(hard.hardReject, isTrue);
      final soft = scoreCoherence(
        tr('b', 'Love me', 'Otro', genres: ['pop']),
        ctx,
      );
      expect(soft.hardReject, isFalse);
      expect(soft.score, lessThan(0.5));
    },
  );

  test('acentos y japonés', () {
    final ctx = CoherenceContext(artists: ['Beyoncé', '米津玄師']);
    expect(
      scoreCoherence(tr('a', 'x', 'BEYONCE'), ctx).score,
      greaterThan(0.9),
    );
    expect(
      scoreCoherence(tr('b', 'x', '米津玄師 - Topic'), ctx).score,
      greaterThan(0.9),
    );
    expect(scoreCoherence(tr('c', 'x', 'Otro'), ctx).score, lessThan(0.5));
  });

  test('sin referencia ni Spotify: neutro', () {
    expect(scoreCoherence(tr('a', 'x', 'Y'), CoherenceContext()).score, 0.5);
  });

  test('artista afín puntúa entre colaboración y mismo género', () {
    final ctx = CoherenceContext(
      artists: ['A'],
      neighbors: ['B'],
      genres: ['pop'],
    );
    final afin = scoreCoherence(tr('n', 'x', 'B'), ctx);
    expect(afin.score, 0.75);
    expect(afin.reason, 'Artista afín');
    expect(
      scoreCoherence(tr('g', 'x', 'Otro', genres: ['pop']), ctx).score,
      0.60,
    );
    expect(scoreCoherence(tr('z', 'x', 'Otro'), ctx).score, 0.25);
  });

  group('motor con vecindario', () {
    late ArtistGraph graph;
    final seed = tr('seed', 'Semilla', 'A');

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        ArtistGraph.prefsKey: jsonEncode({
          'a': {
            't': DateTime.now().millisecondsSinceEpoch,
            'ok': true,
            'n': ['b', 'c', 'd'],
            'g': <String>[],
          },
        }),
      });
      graph = ArtistGraph(preferences: await SharedPreferences.getInstance());
    });

    Future<List<Suggestion>> suggest(
      List<DjCandidate> pool, {
      int limit = 3,
      List<Track> queueTail = const [],
    }) =>
        SuggestionsApi(
          memory: RecsMemory(persist: false),
          exploration: 0,
          graph: graph,
        ).getSuggestions(
          SessionContext(
            participants: const [],
            current: seed,
            queueTail: queueTail,
            extraCandidates: pool,
            limit: limit,
            now: now,
            seed: 1,
            remember: false,
          ),
        );

    test(
      'afín con prior bajo gana a uno sin relación con prior alto',
      () async {
        final b = tr('b1', 'Tema B', 'B');
        final z = tr('z1', 'Tema Z', 'Z');
        final out = await suggest([
          DjCandidate(z, 'z', prior: 0.5),
          DjCandidate(b, 'b', prior: 0.1),
        ], limit: 2);
        expect(out.first.track.id, b.id);
        expect(out.first.coherenceReason, 'Artista afín');
      },
    );

    test('con bastantes afines lo no relacionado no entra', () async {
      final z = tr('z1', 'Tema Z', 'Z');
      final out = await suggest([
        DjCandidate(z, 'z', prior: 0.5),
        for (final a in ['B', 'C', 'D'])
          DjCandidate(tr('${a}1', 'Tema $a', a), a, prior: 0.1),
      ]);
      expect(out, hasLength(3));
      expect(out.map((s) => s.track.id), isNot(contains(z.id)));
    });

    test('la cola no deriva la semilla', () async {
      final z2 = tr('z2', 'Otro Z', 'Z');
      final out = await suggest(
        [DjCandidate(z2, 'z', prior: 0.5)],
        limit: 1,
        queueTail: [tr('z1', 'Tema Z', 'Z')],
      );
      expect(out.single.track.id, z2.id);
      expect(out.single.coherence, lessThan(0.5));
    });
  });
}
