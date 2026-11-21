import '../metadata/spotify/spotify_embed.dart';
import '../metadata/spotify/spotify_link.dart';
import '../metadata/spotify/spotify_metadata_provider.dart';
import 'spotify_import.dart';

/// Lo que se trae de un enlace de Spotify.
class SpotifyLinkImport {
  const SpotifyLinkImport({
    required this.playlist,
    required this.truncated,
    required this.via,
  });
  final SpotifyImportPlaylist playlist;

  /// Spotify solo dejó leer las primeras 100 canciones (y no había otra vía).
  final bool truncated;

  /// `embed` (página pública) o `catalogo` (catálogo web, para más de 100).
  final String via;
}

/// Importa a Aurora una playlist, álbum, artista o canción **públicos** a
/// partir de su enlace, sin iniciar sesión:
/// 1. Página de incrustación pública (hasta 100 canciones, sin credenciales).
/// 2. Si llega al tope, el catálogo web que ya usa el navegador de Spotify para
///    traer el resto; si falla, se queda con las 100 y lo avisa.
class SpotifyLinkImporter {
  SpotifyLinkImporter({
    SpotifyEmbedClient? embed,
    SpotifyMetadataProvider? catalog,
  }) : _embed = embed ?? SpotifyEmbedClient(),
       _catalog = catalog;

  final SpotifyEmbedClient _embed;
  final SpotifyMetadataProvider? _catalog;

  /// Páginas de 50 del catálogo: 20 000 canciones como tope, igual que el archivo.
  static const _pageSize = 50;

  Future<SpotifyLinkImport> import(String text) async {
    final link = parseSpotifyLink(text);
    if (link == null) throw SpotifyEmbedException(spotifyLinkProblem(text));
    final page = await _embed.fetch(link);
    var tracks = page.tracks;
    var via = 'embed';
    var truncated = false;
    final catalog = _catalog;
    if (page.maybeTruncated && link.type != SpotifyEntityType.track) {
      truncated = true;
      if (catalog != null) {
        try {
          final full = await _allTracks(catalog, link, page.name);
          if (full.length > tracks.length) {
            tracks = full;
            via = 'catalogo';
            truncated = false;
          }
        } catch (_) {
          // Se queda con las 100 de la página pública.
        }
      }
    }
    return SpotifyLinkImport(
      playlist: SpotifyImportPlaylist(name: page.name, tracks: tracks),
      truncated: truncated,
      via: via,
    );
  }

  Future<List<SpotifyImportTrack>> _allTracks(
    SpotifyMetadataProvider catalog,
    SpotifyLink link,
    String name,
  ) async {
    final entity = SpotifyMetadataEntity(
      type: link.type,
      uri: link.uri,
      name: name,
    );
    final out = <SpotifyImportTrack>[];
    int? offset = 0;
    while (offset != null && out.length < maxSpotifyImportTracks) {
      final details = await catalog.details(
        entity,
        offset: offset,
        limit: _pageSize,
      );
      for (final track in details.tracks) {
        out.add(
          SpotifyImportTrack(
            title: track.title,
            artist: track.artist,
            album: track.album ?? '',
            uri: track.spotifyUri,
          ),
        );
      }
      offset = details.nextOffset;
    }
    return out;
  }
}
