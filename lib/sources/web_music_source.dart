import 'dart:io';

import '../core/models.dart';
import '../core/source_backend.dart';

/// YouTube Music owns online playback; yt-dlp is only a video/tool utility.
class WebMusicSource extends SourceBackend {
  WebMusicSource(this.delegate, {this.audioOnly = false, this.metadataSearch});

  final SourceBackend delegate;
  final bool audioOnly;
  final Future<List<Track>> Function(String query, {int limit})? metadataSearch;
  final Map<String, HttpClient> _downloads = {};

  static final home = Uri.https('music.youtube.com', '/');
  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _playlistId = RegExp(r'^[A-Za-z0-9_-]{1,200}$');

  static bool isYouTubeUri(Uri uri) {
    final host = uri.host.toLowerCase();
    return const [
      'youtube.com',
      'youtu.be',
      'youtube-nocookie.com',
      'googlevideo.com',
    ].any((domain) => host == domain || host.endsWith('.$domain'));
  }

  static bool isOnlineYouTube(Track track) =>
      !track.isLocal &&
      (track.id.startsWith('yt:') ||
          isYouTubeUri(Uri.tryParse(track.pageUrl ?? '') ?? Uri()));

  /// Rebuild only official navigation parameters; never forward credentials,
  /// signed media URLs, arbitrary paths, or unrelated query parameters.
  static Uri officialUri([Uri? uri]) {
    if (uri == null) return home;
    const pageHosts = {
      'youtube.com',
      'www.youtube.com',
      'm.youtube.com',
      'music.youtube.com',
      'youtu.be',
      'www.youtu.be',
    };
    if (uri.scheme != 'https' ||
        !pageHosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw ArgumentError('Usa un enlace HTTPS oficial de YouTube Music.');
    }
    final segments = uri.pathSegments;
    final host = uri.host.toLowerCase();
    String? video;
    if (host == 'youtu.be' || host == 'www.youtu.be') {
      if (segments.length == 1) video = segments.first;
    } else if (uri.path == '/watch') {
      video = uri.queryParameters['v'];
    } else if (segments.length == 2 &&
        const {'shorts', 'embed', 'live'}.contains(segments.first)) {
      video = segments.last;
    }
    final playlist = uri.queryParameters['list'];
    if (video != null && !_videoId.hasMatch(video)) {
      throw ArgumentError('El identificador del video no es válido.');
    }
    if (playlist != null && !_playlistId.hasMatch(playlist)) {
      throw ArgumentError('El identificador de la lista no es válido.');
    }
    if (video != null) {
      return Uri.https('music.youtube.com', '/watch', {
        'v': video,
        'list': ?playlist,
      });
    }
    if (playlist != null && const {'/playlist', '/watch'}.contains(uri.path)) {
      return Uri.https('music.youtube.com', '/playlist', {'list': playlist});
    }
    if (host == 'music.youtube.com' && uri.path == '/search') {
      final query = uri.queryParameters['q'];
      if (query != null && query.length <= 500) {
        return Uri.https('music.youtube.com', '/search', {'q': query});
      }
    }
    return home;
  }

  static Uri uriForTrack(Track track) {
    final page = Uri.tryParse(track.pageUrl ?? '');
    if (page != null && isYouTubeUri(page)) {
      try {
        return officialUri(page);
      } on ArgumentError {
        return home;
      }
    }
    if (track.id.startsWith('yt:') &&
        _videoId.hasMatch(track.id.substring(3))) {
      return Uri.https('music.youtube.com', '/watch', {
        'v': track.id.substring(3),
      });
    }
    final query = '${track.title} ${track.artist}'.trim();
    return Uri.https('music.youtube.com', '/search', {
      'q': query.substring(0, query.length.clamp(0, 500)),
    });
  }

  static Uri _nativeUri(Track track) {
    final uri = Uri.tryParse(track.pageUrl ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        track.id.startsWith('yt:') ||
        isYouTubeUri(uri)) {
      throw StateError('YouTube Music se reproduce en su reproductor oficial.');
    }
    return uri;
  }

  @override
  bool get usesOfficialYouTubeMusic => !audioOnly;
  @override
  bool get usesYouTubeWebAudio => audioOnly;
  @override
  bool get supportsOnlineMetadataSearch => audioOnly && metadataSearch != null;

  /// An official page identifier for the WebView engine, never a media URL.
  static Uri audioUriForTrack(Track track) {
    final uri = uriForTrack(track);
    final video = uri.queryParameters['v'];
    if (uri.path != '/watch' || video == null || !_videoId.hasMatch(video)) {
      throw StateError('Agrega un enlace HTTPS de una canción de YouTube.');
    }
    return Uri.https('music.youtube.com', '/watch', {'v': video});
  }

  // Shared search uses the controller's library. No yt-dlp listing is allowed.
  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    if (!audioOnly || limit <= 0) return [];
    final input = Uri.tryParse(query.trim());
    if (input == null || !isYouTubeUri(input)) {
      if (metadataSearch == null || query.trim().isEmpty) return [];
      // A pasted unrelated URL must not become a website search query.
      if (input?.hasScheme == true) return [];
      final results = await metadataSearch!(query.trim(), limit: limit);
      final seen = <String>{};
      final validated = <Track>[];
      for (final track in results) {
        if (track.isLocal || track.isPendingSpotifyMatch) continue;
        try {
          final official = audioUriForTrack(track);
          final id = 'yt:${official.queryParameters['v']}';
          if (!seen.add(id)) continue;
          validated.add(
            Track(
              id: id,
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              artworkUrl: track.artworkUrl,
              album: track.album,
              genres: track.genres,
              pageUrl: official.toString(),
            ),
          );
          if (validated.length == limit) break;
        } on StateError {
          continue;
        }
      }
      return validated;
    }
    final uri = officialUri(input);
    final video = uri.queryParameters['v'];
    if (uri.path != '/watch' || video == null) {
      throw StateError(
        'Agrega un enlace de una canción, no una lista completa.',
      );
    }
    return [
      Track(
        id: 'yt:$video',
        title: 'YouTube Music',
        artist: '',
        pageUrl: Uri.https('music.youtube.com', '/watch', {
          'v': video,
        }).toString(),
      ),
    ];
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) async => throw UnsupportedError(
    audioOnly
        ? 'Agrega canciones con sus enlaces; no se extraen listas de YouTube.'
        : 'Abre la lista en YouTube Music.',
  );

  @override
  Future<ResolvedAudio> resolve(Track track) async {
    if (track.isLocal && await File(track.localPath!).exists()) {
      return ResolvedAudio(input: track.localPath!, duration: track.duration);
    }
    if (audioOnly && isOnlineYouTube(track.copyWith(clearLocalPath: true))) {
      return ResolvedAudio(
        input: audioUriForTrack(track).toString(),
        duration: track.duration,
      );
    }
    return ResolvedAudio(
      input: _nativeUri(track).toString(),
      duration: track.duration,
    );
  }

  @override
  Future<File> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    // Validate even local tracks: a YouTube origin must never extract audio.
    final uri = _nativeUri(track);
    if (await destination.exists()) throw StateError('El destino ya existe.');
    final client = HttpClient();
    _downloads[jobId] = client;
    Directory? temporaryDirectory;
    IOSink? sink;
    try {
      // Follow redirects ourselves so a non-YouTube URL cannot redirect to media
      // extracted from YouTube or downgrade TLS.
      var target = uri;
      HttpClientResponse? response;
      for (var redirects = 0; redirects <= 5; redirects++) {
        final request = await client.getUrl(target);
        request.followRedirects = false;
        response = await request.close();
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null || redirects == 5) {
          throw StateError('Redirección de audio no válida.');
        }
        target = _nativeUri(
          track.copyWith(pageUrl: target.resolve(location).toString()),
        );
      }
      if (response == null || response.statusCode != HttpStatus.ok) {
        throw StateError('No se pudo descargar el audio.');
      }
      await destination.parent.create(recursive: true);
      temporaryDirectory = await destination.parent.createTemp(
        '.aurora-native-',
      );
      final temporary = File('${temporaryDirectory.path}/audio');
      sink = temporary.openWrite();
      var bytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        bytes += chunk.length;
        if (response.contentLength > 0) {
          onProgress?.call(bytes / response.contentLength);
        }
      }
      await sink.close();
      sink = null;
      if (bytes == 0 ||
          (response.contentLength >= 0 && bytes != response.contentLength)) {
        throw StateError('La descarga de audio está incompleta.');
      }
      if (await destination.exists()) throw StateError('El destino ya existe.');
      await temporary.rename(destination.path);
      onProgress?.call(1);
      return destination;
    } finally {
      client.close(force: true);
      _downloads.remove(jobId);
      try {
        await sink?.close();
      } finally {
        if (temporaryDirectory != null && await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      }
    }
  }

  @override
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) => delegate.downloadVideo(
    url,
    destination,
    jobId: jobId,
    onProgress: onProgress,
  );
  @override
  Future<void> cancel(String jobId) async {
    _downloads.remove(jobId)?.close(force: true);
    await delegate.cancel(jobId);
  }

  @override
  String? get toolUpdateMessage => delegate.toolUpdateMessage;
  @override
  bool get updatingTools => delegate.updatingTools;
  @override
  Future<void> initializeUpdates({
    required bool Function() isPlaybackActive,
    required void Function() onStatusChanged,
  }) => delegate.initializeUpdates(
    isPlaybackActive: isPlaybackActive,
    onStatusChanged: onStatusChanged,
  );
  @override
  Future<void> checkForUpdates() => delegate.checkForUpdates();
  @override
  Future<String> diagnose() => delegate.diagnose();
  @override
  Future<void> configureToolDirectory(String directory) =>
      delegate.configureToolDirectory(directory);
  @override
  Future<void> configureCookieFile(String? path) =>
      delegate.configureCookieFile(path);
  @override
  String? get cookieFile => delegate.cookieFile;
  @override
  String? get toolDirectory => delegate.toolDirectory;
  @override
  void dispose() {
    for (final client in _downloads.values) {
      client.close(force: true);
    }
    _downloads.clear();
    delegate.dispose();
  }
}
