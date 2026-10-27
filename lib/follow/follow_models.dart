import '../core/source_backend.dart';

/// Álbum, sencillo o EP de la página de artista de YouTube Music.
class ArtistRelease {
  const ArtistRelease({
    required this.id,
    required this.title,
    this.kind = '',
    this.year,
    this.artworkUrl,
  });

  /// browseId del álbum (MPREb_…): `browseTracks` lo abre y reproduce.
  final String id;
  final String title;

  /// «Álbum», «Sencillo», «EP»… tal como lo escribe YouTube Music.
  final String kind;
  final int? year;
  final String? artworkUrl;
}

class ArtistPage {
  const ArtistPage({
    this.name,
    this.imageUrl,
    this.releases = const [],
    this.relatedArtists = const [],
  });
  final String? name;
  final String? imageUrl;
  final List<ArtistRelease> releases;

  /// Carrusel «Puede que también te guste» (nombres, sin duplicados).
  final List<String> relatedArtists;
}

class FollowedArtist {
  const FollowedArtist({
    required this.browseId,
    required this.name,
    required this.followedAt,
    this.imageUrl,
    this.lastReleaseId,
    this.lastReleaseTitle,
    this.knownReleases = const {},
    this.checkedAt,
  });

  final String browseId;
  final String name;
  final String? imageUrl;
  final DateTime followedAt;

  /// Lanzamiento más reciente visto en la última consulta.
  final String? lastReleaseId;
  final String? lastReleaseTitle;

  /// Todo lo ya visto: lo que no esté aquí es una novedad.
  final Set<String> knownReleases;

  /// null = aún sin línea base: la primera consulta no anuncia nada.
  final DateTime? checkedAt;

  FollowedArtist copyWith({
    String? lastReleaseId,
    String? lastReleaseTitle,
    Set<String>? knownReleases,
    DateTime? checkedAt,
  }) => FollowedArtist(
    browseId: browseId,
    name: name,
    imageUrl: imageUrl,
    followedAt: followedAt,
    lastReleaseId: lastReleaseId ?? this.lastReleaseId,
    lastReleaseTitle: lastReleaseTitle ?? this.lastReleaseTitle,
    knownReleases: knownReleases ?? this.knownReleases,
    checkedAt: checkedAt ?? this.checkedAt,
  );
}

class NewRelease {
  const NewRelease({
    required this.id,
    required this.artistId,
    required this.artistName,
    required this.title,
    required this.subtitle,
    required this.detectedAt,
    this.artworkUrl,
  });

  final String id;
  final String artistId;
  final String artistName;
  final String title;

  /// «Sencillo • Artista • 2026»; `browseTracks` toma el artista del 2.º trozo.
  final String subtitle;
  final String? artworkUrl;
  final DateTime detectedAt;

  /// Entrada reproducible con lo que ya existe (`openSearchEntry`).
  SearchEntry get entry => SearchEntry(
    kind: SearchKind.albums,
    browseId: id,
    title: title,
    subtitle: subtitle,
    artworkUrl: artworkUrl,
  );
}
