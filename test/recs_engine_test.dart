import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final now = DateTime(2026, 10, 17, 12);

String vid(String s) => s.padRight(11, '_').substring(0, 11);

Track tr(String id, String artist, {List<String> genres = const []}) => Track(
  id: 'yt:${vid(id)}',
  title: 'Cancion $id',
  artist: artist,
  genres: genres,
  pageUrl: 'https://music.youtube.com/watch?v=${vid(id)}',
);

TasteProfile likes(List<Track> favs) => buildTasteProfile(
  favorites: favs,
  playlistTracks: const [],
  history: const [],
  events: const [],
  known: const {},
  now: now,
);

RecsMemory mem() => RecsMemory(persist: false);

/// 10 artistas x 6 canciones, con géneros repartidos.
List<Track> bigLibrary() => [
  for (var a = 0; a < 10; a++)
    for (var i = 0; i < 6; i++)
      tr('a${a}x$i', 'Artista $a', genres: [a.isEven ? 'rock' : 'pop']),
];

SessionContext ctx(
  List<Track> library, {
  int limit = 10,
  int? seed,
  List<ParticipantTaste>? who,
  List<Track> favs = const [],
}) => SessionContext(
  participants: who ?? [ParticipantTaste('yo', likes(favs))],
  library: library,
  limit: limit,
  seed: seed,
  now: now,
);

int maxPerArtist(List<Suggestion> out) {
  final counts = <String, int>{};
  for (final s in out) {
    counts.update(s.track.artist, (n) => n + 1, ifAbsent: () => 1);
  }
  return counts.values.reduce((a, b) => a > b ? a : b);
}

Set<String> ids(List<Suggestion> l) => {for (final s in l) s.track.id};

void main() {
  test('diversidad: tope por artista en lotes grandes', () async {
    final big = await SuggestionsApi(
      memory: mem(),
    ).getSuggestions(ctx(bigLibrary(), limit: 30, seed: 1));
    expect(big.length, 30);
    expect(maxPerArtist(big), lessThanOrEqualTo(6));
    final twenty = await SuggestionsApi(
      memory: mem(),
    ).getSuggestions(ctx(bigLibrary(), limit: 20, seed: 2));
    expect(maxPerArtist(twenty), lessThanOrEqualTo(4));
  });

  test('antirepetición en la misma sesión', () async {
    final api = SuggestionsApi(memory: mem());
    final lib = bigLibrary();
    final a = await api.getSuggestions(ctx(lib, limit: 12, seed: 1));
    final b = await api.getSuggestions(ctx(lib, limit: 12, seed: 1));
    expect(ids(a).intersection(ids(b)), isEmpty);
  });

  test('antirepetición entre sesiones (persistida)', () async {
    SharedPreferences.setMockInitialValues({});
    final m1 = RecsMemory();
    final lib = bigLibrary();
    final a = await SuggestionsApi(
      memory: m1,
    ).getSuggestions(ctx(lib, limit: 12, seed: 5));
    await m1.record(const [], now); // espera a que se guarde
    final m2 = RecsMemory(); // «app reiniciada»
    final b = await SuggestionsApi(
      memory: m2,
    ).getSuggestions(ctx(lib, limit: 12, seed: 5));
    expect(ids(a).intersection(ids(b)), isEmpty);
  });

  test('la memoria guarda como mucho 300 y el tiempo la envejece', () async {
    final m = mem();
    await m.record([for (var i = 0; i < 350; i++) tr('t$i', 'A$i')], now);
    expect(m.length, 300);
    expect(m.ageOf(tr('t349', 'A349'), now), Duration.zero);
    expect(m.ageOf(tr('t0', 'A0'), now), isNull); // la más vieja salió
    expect(
      m.ageOf(tr('t349', 'A349'), now.add(const Duration(days: 8)))! > m.window,
      isTrue,
    );
  });

  test(
    'exploración: otra semilla da otra lista, misma semilla la misma',
    () async {
      final lib = bigLibrary();
      Future<List<String>> run(int seed) async => [
        for (final s in await SuggestionsApi(memory: mem()).getSuggestions(
          ctx(lib, limit: 10, seed: seed, favs: lib.take(3).toList()),
        ))
          s.track.id,
      ];
      final a = await run(1), b = await run(2), a2 = await run(1);
      expect(a, a2);
      expect(a, isNot(b));
    },
  );

  test('sin semilla, dos sesiones distintas dan listas distintas', () async {
    final lib = bigLibrary();
    final x = await SuggestionsApi(memory: mem()).getSuggestions(ctx(lib));
    final y = await SuggestionsApi(memory: mem()).getSuggestions(ctx(lib));
    expect([
      for (final s in x) s.track.id,
    ], isNot([for (final s in y) s.track.id]));
  });

  test('pool agotado: relaja la ventana y no se queda vacío', () async {
    final api = SuggestionsApi(memory: mem());
    final lib = [for (var i = 0; i < 6; i++) tr('p$i', 'Art $i')];
    for (var round = 0; round < 4; round++) {
      final out = await api.getSuggestions(ctx(lib, limit: 6, seed: round));
      expect(out.length, 6, reason: 'ronda $round');
    }
  });

  test('sin red: fuentes que fallan caen a la biblioteca', () async {
    final api = SuggestionsApi(
      memory: mem(),
      fetchCandidates: (_) async => throw 'offline',
      sources: [
        RecSource(RecBucket.discovery, (c, n) async => throw 'sin red'),
      ],
    );
    final out = await api.getSuggestions(ctx(bigLibrary(), limit: 8, seed: 3));
    expect(out.length, 8);
    expect(out.every((s) => s.reason.isNotEmpty), isTrue);
  });

  test('mezcla de fuentes ≈ 50/30/5 y razones en español', () async {
    List<DjCandidate> pool(String p, int n) => [
      for (var i = 0; i < n; i++)
        DjCandidate(
          tr('$p$i', '$p artista $i', genres: ['rock']),
          '',
          prior: 0.5,
        ),
    ];
    final api = SuggestionsApi(
      memory: mem(),
      exploration: 0,
      sources: [
        RecSource(RecBucket.similar, (c, n) async => pool('s', 30)),
        RecSource(RecBucket.adjacent, (c, n) async => pool('j', 30)),
        RecSource(RecBucket.discovery, (c, n) async => pool('d', 30)),
      ],
    );
    final out = await api.getSuggestions(
      ctx(
        const [],
        limit: 20,
        seed: 1,
        favs: [
          tr('fav', 'Artista fav', genres: ['rock']),
        ],
      ),
    );
    int n(RecBucket b) => out.where((s) => s.bucket == b).length;
    expect(n(RecBucket.similar), inInclusiveRange(7, 12));
    expect(n(RecBucket.adjacent), inInclusiveRange(4, 8));
    expect(n(RecBucket.discovery), inInclusiveRange(2, 5));
    expect(out.any((s) => s.reason == 'Descubrimiento'), isTrue);
    expect(out.any((s) => s.reason.startsWith('Porque escuchas')), isTrue);
  });

  test('grupo con 3 gustos: turnos round-robin, todos representados', () async {
    List<Track> group(String p, String artist, String genre) => [
      for (var i = 0; i < 6; i++) tr('$p$i', '$artist $i', genres: [genre]),
    ];
    final rock = group('rk', 'Rock', 'rock');
    final jazz = group('jz', 'Jazz', 'jazz');
    final pop = group('pp', 'Pop', 'pop');
    final lib = [...rock, ...jazz, ...pop];
    for (var seed = 0; seed < 25; seed++) {
      final out = await SuggestionsApi(memory: mem()).getSuggestions(
        ctx(
          lib,
          limit: 9,
          seed: seed,
          who: [
            ParticipantTaste('ana', likes(rock.take(2).toList())),
            ParticipantTaste('beto', likes(jazz.take(2).toList())),
            ParticipantTaste('cris', likes(pop.take(2).toList())),
          ],
        ),
      );
      expect(
        {for (final s in out) s.track.genres.first},
        {'rock', 'jazz', 'pop'},
        reason: 'semilla $seed',
      );
      expect({for (final s in out) s.forParticipant}, {'ana', 'beto', 'cris'});
    }
  });

  test('no ofrece lo que ya está en la cola ni la pista actual', () async {
    final lib = bigLibrary();
    final out = await SuggestionsApi(memory: mem()).getSuggestions(
      SessionContext(
        participants: [ParticipantTaste('yo', likes(const []))],
        library: lib,
        current: lib[0],
        queueTail: lib.sublist(1, 10),
        limit: 20,
        now: now,
        seed: 1,
      ),
    );
    expect(
      ids(out).intersection({for (final t in lib.sublist(0, 10)) t.id}),
      isEmpty,
    );
  });
}
