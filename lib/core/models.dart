enum RepeatMode { off, all, one }

enum DownloadStatus { queued, downloading, completed, failed, cancelled }

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.duration = Duration.zero,
    this.artworkUrl,
    this.pageUrl,
    this.localPath,
    this.album,
    this.genres = const [],
    this.spotifyUri,
    this.spotifyMatchPending = false,
  });
  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final String? artworkUrl;
  final String? pageUrl;
  final String? localPath;
  final String? album;
  final List<String> genres;
  final String? spotifyUri;
  final bool spotifyMatchPending;
  bool get isPendingSpotifyMatch => spotifyMatchPending;
  bool get isLocal => localPath != null;
  Track copyWith({
    String? localPath,
    Duration? duration,
    String? artworkUrl,
    bool clearLocalPath = false,
    String? pageUrl,
    String? spotifyUri,
    bool? spotifyMatchPending,
    List<String>? genres,
  }) => Track(
    id: id,
    title: title,
    artist: artist,
    duration: duration ?? this.duration,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    pageUrl: pageUrl ?? this.pageUrl,
    localPath: clearLocalPath ? null : localPath ?? this.localPath,
    album: album,
    genres: genres ?? this.genres,
    spotifyUri: spotifyUri ?? this.spotifyUri,
    spotifyMatchPending: spotifyMatchPending ?? this.spotifyMatchPending,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'durationMs': duration.inMilliseconds,
    'artworkUrl': artworkUrl,
    'pageUrl': pageUrl,
    'localPath': localPath,
    'album': album,
    'genres': genres,
    'spotifyUri': spotifyUri,
    'spotifyMatchPending': spotifyMatchPending,
  };
  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String,
    artist: json['artist'] as String,
    duration: Duration(
      milliseconds: (json['durationMs'] as num?)?.toInt() ?? 0,
    ),
    artworkUrl: json['artworkUrl'] as String?,
    pageUrl: json['pageUrl'] as String?,
    localPath: json['localPath'] as String?,
    album: json['album'] as String?,
    genres: (json['genres'] as List?)?.whereType<String>().toList() ?? const [],
    spotifyUri: json['spotifyUri'] as String?,
    spotifyMatchPending: json['spotifyMatchPending'] as bool? ?? false,
  );
}

class MusicPlaylist {
  const MusicPlaylist({
    required this.id,
    required this.name,
    this.trackIds = const [],
    this.photoPath,
  });
  final String id;
  final String name;
  final List<String> trackIds;

  /// Foto elegida por el usuario. No va en la tabla: el controlador la guarda
  /// en un mapa de preferencias y la inyecta al cargar/reemplazar.
  final String? photoPath;

  MusicPlaylist copyWith({String? name, List<String>? trackIds}) =>
      MusicPlaylist(
        id: id,
        name: name ?? this.name,
        trackIds: trackIds ?? this.trackIds,
        photoPath: photoPath,
      );

  MusicPlaylist withPhoto(String? path) =>
      MusicPlaylist(id: id, name: name, trackIds: trackIds, photoPath: path);
}

class DownloadJob {
  DownloadJob({
    required this.id,
    required this.track,
    this.status = DownloadStatus.queued,
    this.progress = 0,
    this.error,
    this.localPath,
    this.destinationRoot,
  });
  final String id;
  final Track track;
  DownloadStatus status;
  double progress;
  String? error;
  String? localPath;
  String? destinationRoot;
}

class ResolvedAudio {
  const ResolvedAudio({
    required this.input,
    this.headers = const {},
    this.duration = Duration.zero,
    this.validateCompletion,
  });
  final String input;
  final Map<String, String> headers;

  /// Progressive input must finish validation before a decoder EOF is trusted.
  final Future<void> Function()? validateCompletion;
  final Duration duration;
}
