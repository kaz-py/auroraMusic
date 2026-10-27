import 'dart:math' as math;

import '../core/models.dart';
import '../dj/ai_dj.dart';
import '../dj/coherence.dart';
import '../dj/suggestions_api.dart';
import 'spotify/spotify_metadata_provider.dart';
import 'youtube_match.dart';

/// Lo mínimo que el motor pide a Spotify. Solo usa operaciones que el proveedor
/// del repo ya tiene (búsqueda de artistas/playlists y detalle): ni
/// `recommendations`, ni `related-artists`, ni `audio-features` (retirados de la
/// API oficial para apps nuevas) ni consultas nuevas a la interfaz privada.
abstract class SpotifyCatalog {
  /// Canciones más populares de un artista.
  Future<List<Track>> artistTopTracks(String artist);

  /// Nombres de artistas que Spotify asocia a un género (búsqueda de artistas).
  Future<List<String>> artistsForGenre(String genre);

  /// Canciones de la primera playlist que devuelve la búsqueda.
  Future<List<Track>> playlistTracks(String query);
}

class ProviderSpotifyCatalog implements SpotifyCatalog {
  ProviderSpotifyCatalog(this.provider);
  final SpotifyMetadataProvider provider;

  @override
  Future<List<Track>> artistTopTracks(String artist) async {
    final page = await provider.search(
      artist,
      type: SpotifyEntityType.artist,
      limit: 3,
    );
    // Solo un artista cuyo nombre coincide: no el primer resultado a ciegas.
    final want = coherenceNorm(artist);
    final match = page.items
        .where((e) => coherenceNorm(e.name) == want)
        .firstOrNull;
    if (match == null) return const [];
    return (await provider.details(match)).tracks;
  }

  @override
  Future<List<String>> artistsForGenre(String genre) async => [
    for (final e in (await provider.search(
      genre,
      type: SpotifyEntityType.artist,
      limit: 15,
    )).items)
      e.name,
  ];

  @override
  Future<List<Track>> playlistTracks(String query) async {
    final page = await provider.search(
      query,
      type: SpotifyEntityType.playlist,
      limit: 3,
    );
    if (page.items.isEmpty) return const [];
    return (await provider.details(page.items.first, limit: 50)).tracks;
  }
}

const _discoveryGenres = [
  'jazz',
  'indie',
  'hip hop',
  'electronica',
  'latin',
  'rock',
  'pop',
  'soul',
  'reggae',
  'clásica',
  'r&b',
  'folk',
  'salsa',
  'metal',
  'funk',
  'bossa nova',
];

/// Fuentes de candidatos con metadatos de Spotify, ya emparejados con YouTube
/// Music por [matcher] (cada candidato trae un videoId reproducible):
///  * adjacent: artistas del género que más escuchas (que no sean los tuyos);
///    sin género conocido no aporta nada (buscar por nombre se salía del
///    perfil);
///  * discovery: un género fuera de tu burbuja (cuota mínima en la mezcla);
///  * similar: lo más popular de tus artistas favoritos.
List<RecSource> spotifyRecSources({
  required SpotifyCatalog catalog,
  required YoutubeMatcher matcher,
  int maxMatches = 8,
}) {
  Future<List<DjCandidate>> resolve(
    List<Track> spotify,
    Set<String> skipArtists,
    RecBucket bucket,
    String reason,
    int want,
    math.Random rnd,
  ) async {
    final pool =
        spotify.where((t) => !skipArtists.contains(djPrimaryArtist(t))).toList()
          ..shuffle(rnd);
    final out = <DjCandidate>[];
    // De tres en tres para no saturar la búsqueda de YouTube Music.
    for (var i = 0; i < pool.length && out.length < want; i += 3) {
      final matches = await Future.wait(
        pool
            .skip(i)
            .take(3)
            .map((t) => matcher.match(t).catchError((_) => null)),
      );
      for (var k = 0; k < matches.length; k++) {
        final m = matches[k];
        if (m == null) continue;
        final s = pool[i + k];
        out.add(
          DjCandidate(
            m.track.genres.isEmpty && s.genres.isNotEmpty
                ? m.track.copyWith(genres: s.genres)
                : m.track,
            reason,
            prior: 0.6 * m.confidence,
            bucket: bucket,
          ),
        );
      }
    }
    return out.take(want).toList();
  }

  math.Random rndOf(SessionContext c) => math.Random(c.seed);
  TasteProfile profileOf(SessionContext c) =>
      combineTasteProfiles(c.participants);
  Set<String> known(SessionContext c) => {
    ...c.favoriteArtists,
    ...tasteTop(profileOf(c), 'a:', 12),
  };

  return [
    RecSource(RecBucket.similar, (ctx, want) async {
      final rnd = rndOf(ctx);
      final artists = tasteTop(profileOf(ctx), 'a:', 6)..shuffle(rnd);
      if (artists.isEmpty) return const [];
      // Con lotes grandes (escalera de relajación) se usan dos artistas.
      final out = <DjCandidate>[];
      for (final artist in artists.take(want > maxMatches ? 2 : 1)) {
        out.addAll(
          await resolve(
            await catalog.artistTopTracks(artist),
            const {},
            RecBucket.similar,
            'Porque escuchas ${_cap(artist)}',
            math.min(want, maxMatches),
            rnd,
          ),
        );
      }
      return out;
    }),
    RecSource(RecBucket.adjacent, (ctx, want) async {
      final rnd = rndOf(ctx);
      final genres = tasteTop(profileOf(ctx), 'g:', 3);
      if (genres.isEmpty) return const [];
      final profile = profileOf(ctx);
      final names = await catalog.artistsForGenre(
        genres[rnd.nextInt(genres.length)],
      );
      final mine = known(ctx);
      final others =
          names.where((n) => !mine.contains(n.toLowerCase())).toList()
            ..shuffle(rnd);
      if (others.isEmpty) return const [];
      final seed = tasteTop(profile, 'a:', 1).firstOrNull;
      return resolve(
        await catalog.artistTopTracks(others.first),
        mine,
        RecBucket.adjacent,
        seed == null
            ? 'Artistas parecidos a tus gustos'
            : 'Artistas parecidos a ${_cap(seed)}',
        math.min(want, maxMatches),
        rnd,
      );
    }),
    RecSource(RecBucket.discovery, (ctx, want) async {
      final rnd = rndOf(ctx);
      final mine = tasteTop(profileOf(ctx), 'g:', 8).toSet();
      final fresh = [
        for (final g in _discoveryGenres)
          if (!mine.contains(g)) g,
      ];
      final genre =
          (fresh.isEmpty ? _discoveryGenres : fresh)[rnd.nextInt(
            (fresh.isEmpty ? _discoveryGenres : fresh).length,
          )];
      return resolve(
        await catalog.playlistTracks('$genre essentials'),
        known(ctx),
        RecBucket.discovery,
        'Descubrimiento',
        math.min(want, maxMatches),
        rnd,
      );
    }),
  ];
}

String _cap(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');
