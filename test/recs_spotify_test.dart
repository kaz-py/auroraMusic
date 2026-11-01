import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/reco_memory.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/jam/jam_suggestions.dart';
import 'package:aurora_music/metadata/spotify_recs.dart';
import 'package:aurora_music/metadata/youtube_match.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime(2026, 10, 17, 12);

Track sp(String title, String artist, {List<String> genres = const []}) =>
    Track(
      id: 'spotify:track:$title',
      title: title,
      artist: artist,
      genres: genres,
      duration: const Duration(minutes: 3),
      spotifyUri: 'spotify:track:${title.padRight(22, 'x')}',
      spotifyMatchPending: true,
    );

String vid(String s) => s.padRight(11, '_').substring(0, 11);

Track yt(String title, String artist) => Track(
  id: 'yt:${vid(title)}',
  title: title,
  artist: artist,
  duration: const Duration(minutes: 3),
  pageUrl: 'https://music.youtube.com/watch?v=${vid(title)}',
);

class FakeCatalog implements SpotifyCatalog {
  final calls = <String>[];
  @override
  Future<List<Track>> artistTopTracks(String artist) async {
    calls.add('top:$artist');
    return [for (var i = 0; i < 6; i++) sp('${artist}_t$i', artist)];
  }

  @override
  Future<List<String>> artistsForGenre(String genre) async {
    calls.add('genre:$genre');
    return ['otro1', 'otro2'];
  }

  @override
  Future<List<Track>> playlistTracks(String query) async {
    calls.add('pl:$query');
    return [
      for (var i = 0; i < 8; i++) sp('pl${i}_${query.length}', 'Banda $i'),
    ];
  }
}

YoutubeMatcher matcher() => YoutubeMatcher(
  persist: false,
  // Devuelve «el mismo tema» en YouTube a partir de la consulta.
  search: (q, kind) async {
    final words = q.split(' ');
    final title = words.first;
    final artist = words.skip(1).join(' ');
    return [yt(title, artist)];
  },
);

TasteProfile likes(List<Track> t) => buildTasteProfile(
  favorites: t,
  playlistTracks: const [],
  history: const [],
  events: const [],
  known: const {},
  now: now,
);

void main() {
  test(
    'las fuentes de Spotify devuelven pistas YouTube reproducibles',
    () async {
      final catalog = FakeCatalog();
      final sources = spotifyRecSources(catalog: catalog, matcher: matcher());
      final taste = ParticipantTaste(
        'yo',
        likes([
          const Track(
            id: 'yt:fav00000001',
            title: 'F',
            artist: 'queen',
            genres: ['rock'],
          ),
        ]),
      );
      final ctx = SessionContext(
        participants: [taste],
        limit: 10,
        seed: 4,
        now: now,
      );
      for (final s in sources) {
        final out = await s.fetch(ctx, 6);
        expect(out, isNotEmpty, reason: s.bucket.name);
        expect(out.every((c) => c.track.id.startsWith('yt:')), isTrue);
        expect(out.every((c) => c.reason.isNotEmpty), isTrue);
      }
      expect(catalog.calls.any((c) => c.startsWith('top:queen')), isTrue);
    },
  );

  test(
    'el motor con Spotify da razones y sobrevive si Spotify falla',
    () async {
      final good = SuggestionsApi(
        memory: RecsMemory(persist: false),
        sources: spotifyRecSources(catalog: FakeCatalog(), matcher: matcher()),
      );
      final taste = ParticipantTaste(
        'yo',
        likes([
          const Track(
            id: 'yt:fav00000001',
            title: 'F',
            artist: 'queen',
            genres: ['rock'],
          ),
        ]),
      );
      final out = await good.getSuggestions(
        SessionContext(participants: [taste], limit: 12, seed: 1, now: now),
      );
      expect(out.length, greaterThanOrEqualTo(8));
      expect(out.map((s) => s.bucket).toSet().length, greaterThan(1));

      final broken = SuggestionsApi(
        memory: RecsMemory(persist: false),
        sources: [
          RecSource(RecBucket.similar, (c, n) async => throw 'sin red'),
        ],
      );
      final fallback = await broken.getSuggestions(
        SessionContext(
          participants: [taste],
          library: [yt('uno', 'A'), yt('dos', 'B')],
          limit: 5,
          now: now,
        ),
      );
      expect(fallback.length, 2);
    },
  );

  test(
    'adaptador de la Jam con motor: razones, sin repetir y sin red',
    () async {
      Track rock(Track t) => t.copyWith(genres: ['rock']);
      final radio = [
        for (var i = 0; i < 12; i++) rock(yt('radio$i', 'Art $i')),
      ];
      JamSuggestionAdapter adapter({bool online = true}) =>
          JamSuggestionAdapter(
            related: (_) async => online ? radio : throw Exception('sin red'),
            seeds: () => [yt('semilla', 'S')],
            local: () => [
              for (var i = 0; i < 8; i++) rock(yt('local$i', 'Loc $i')),
            ],
            api: SuggestionsApi(memory: RecsMemory(persist: false)),
          );
      final api = adapter();
      final a = await api.build(current: rock(yt('actual', 'Z')));
      final b = await api.build(current: rock(yt('actual', 'Z')));
      expect(a.length, jamSuggestionsPerPerson);
      expect(a.every((s) => s.reason.isNotEmpty), isTrue);
      expect(a.any((s) => s.reason == 'Radio de YouTube'), isTrue);
      expect(
        {
          for (final s in a) s.track.key,
        }.intersection({for (final s in b) s.track.key}),
        isEmpty,
        reason: 'la memoria compartida evita repetir entre ciclos',
      );
      final offline = await adapter(online: false).build();
      expect(offline, isNotEmpty);
    },
  );
}
