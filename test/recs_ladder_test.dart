import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/jam/jam_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 19, 12);

String vid(String s) => s.padRight(11, '_').substring(0, 11);

Track tr(String id, String artist) => Track(
  id: 'yt:${vid(id)}',
  title: 'Cancion $id',
  artist: artist,
  pageUrl: 'https://music.youtube.com/watch?v=${vid(id)}',
);

TasteProfile empty() => buildTasteProfile(
  favorites: const [],
  playlistTracks: const [],
  history: const [],
  events: const [],
  known: const {},
  now: now,
);

SessionContext ctx(List<Track> library, {int limit = 10}) => SessionContext(
  participants: [ParticipantTaste('yo', empty())],
  library: library,
  limit: limit,
  seed: 1,
  now: now,
);

int sum(Map<RecBucket, int> m) => m.values.fold(0, (a, b) => a + b);

void main() {
  test('pool agotado: nunca vacío mientras quede algo', () async {
    final api = SuggestionsApi(memory: RecsMemory(persist: false));
    final lib = [for (var i = 0; i < 4; i++) tr('q$i', 'Art $i')];
    for (var round = 0; round < 5; round++) {
      final out = await api.getSuggestions(ctx(lib, limit: 4));
      expect(out.length, 4, reason: 'ronda $round');
    }
  });

  test('todo en memoria: repite lo sonado en vez de quedarse vacío', () async {
    final m = RecsMemory(persist: false);
    final lib = [for (var i = 0; i < 5; i++) tr('m$i', 'Mem $i')];
    await m.record(lib, now);
    final api = SuggestionsApi(memory: m);
    final out = await api.getSuggestions(ctx(lib, limit: 5));
    expect(out.length, 5);
    expect(api.lastDiagnostics.memoryTier, 0);
  });

  test('pocas fuentes: amplía fuentes y los contadores cuadran', () async {
    var calls = 0;
    final api = SuggestionsApi(
      memory: RecsMemory(persist: false),
      sources: [
        RecSource(RecBucket.discovery, (c, n) async {
          calls++;
          // 1.ª pasada escasa; la escalera («fuentes x3») trae más.
          return [
            for (var i = 0; i < (calls > 1 ? 14 : 1); i++)
              DjCandidate(tr('s$i', 'Fuente $i'), '', prior: 0.5),
          ];
        }),
      ],
    );
    final out = await api.getSuggestions(ctx(const [], limit: 10));
    final d = api.lastDiagnostics;
    expect(out.length, 10);
    expect(calls, 2);
    expect(d.ladder, contains('fuentes x3'));
    expect(d.gathered, greaterThanOrEqualTo(d.afterFilters));
    expect(d.afterFilters, greaterThanOrEqualTo(d.afterCoherence));
    expect(d.afterCoherence, greaterThanOrEqualTo(d.afterMemory));
    expect(d.afterMemory, greaterThanOrEqualTo(d.picked));
    expect(d.picked, out.length);
    expect(sum(d.gatheredByBucket), d.gathered);
    expect(sum(d.pickedByBucket), d.picked);
  });

  test('adapter con YouTube caído usa api.sources antes que lo local', () async {
    final api = SuggestionsApi(
      memory: RecsMemory(persist: false),
      sources: [
        RecSource(
          RecBucket.discovery,
          (c, n) async => [
            for (var i = 0; i < 12; i++)
              DjCandidate(tr('src$i', 'Otra $i'), 'Descubrimiento', prior: 0.5),
          ],
        ),
      ],
    );
    final adapter = JamSuggestionAdapter(
      api: api,
      related: (_) async => throw 'YouTube caído',
      seeds: () => [tr('r1', 'R1'), tr('r2', 'R2')],
      local: () => [for (var i = 0; i < 6; i++) tr('loc$i', 'Local $i')],
    );
    final out = await adapter.build(current: tr('cur', 'Actual'));
    expect(out, isNotEmpty);
    // La exploración es aleatoria: se garantiza que las fuentes entran, no la mayoría.
    expect(out.where((s) => s.track.artist.startsWith('Otra')), isNotEmpty);
  });

  test(
    'adapter: semillas deduplicadas (actual + recientes + favoritas)',
    () async {
      final asked = <String>[];
      final adapter = JamSuggestionAdapter(
        related: (t) async {
          asked.add(t.id);
          return [tr('x${asked.length}', 'X')];
        },
        seeds: () => [tr('a', 'A'), tr('b', 'B'), tr('cur', 'C')],
        favorites: () => [tr('b', 'B'), tr('f', 'F')],
        local: () => const [],
      );
      await adapter.build(current: tr('cur', 'C'));
      expect(asked.toSet().length, asked.length);
      expect(asked.length, 4); // cur, a, b, f
    },
  );
}
