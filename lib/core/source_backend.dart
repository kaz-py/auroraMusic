import 'dart:io';
import 'models.dart';

enum SearchKind { songs, albums, artists, videos }

/// Album or artist search hit; [browseId] opens its tracks via browse.
class SearchEntry {
  const SearchEntry({
    required this.kind,
    required this.browseId,
    required this.title,
    this.subtitle = '',
    this.artworkUrl,
  });
  final SearchKind kind;
  final String browseId;
  final String title;
  final String subtitle;
  final String? artworkUrl;
}

/// One page of search results; [continuation] is null on the last page.
class SearchPage {
  const SearchPage({
    this.tracks = const [],
    this.entries = const [],
    this.continuation,
  });
  final List<Track> tracks;
  final List<SearchEntry> entries;
  final String? continuation;
}

abstract class SourceBackend {
  bool get supportsExperimentalProgressivePlayback => false;

  /// Applies to the next resolve; an already loaded input keeps its mode.
  void setExperimentalProgressivePlayback(bool enabled) {}

  bool get supportsPlaybackCache => false;
  Future<({int bytes, int files})> playbackCacheInfo() async =>
      (bytes: 0, files: 0);

  /// Returns bytes removed while preserving the loaded audio at [protectedPath].
  Future<int> clearPlaybackCache({String? protectedPath}) async => 0;
  Future<List<Track>> search(String query, {int limit = 20});

  /// Paged, categorised search. Sources without it only offer songs.
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) async => continuation != null || kind != SearchKind.songs
      ? const SearchPage()
      : SearchPage(tracks: await search(query));

  /// Tracks of an album or an artist's top songs.
  Future<List<Track>> browseTracks(SearchEntry entry) async => const [];
  Future<List<Track>> importPlaylist(Uri url);
  Future<ResolvedAudio> resolve(Track track);

  /// Warms the stream URL of an upcoming track; must swallow its own errors.
  Future<void> prefetch(Track track) async {}

  /// Called before a bounded retry of an expired or interrupted stream.
  void invalidateResolvedAudio(Track track) {}
  void reportPlaybackFailure(String message) {}
  bool isExpiredStream(Track track) => false;
  String? get toolUpdateMessage => null;
  bool get updatingTools => false;
  Future<void> initializeUpdates({
    required bool Function() isPlaybackActive,
    required void Function() onStatusChanged,
  }) async {}
  Future<void> checkForUpdates() async {}

  /// Guarda el audio de [track] junto a [destination] y devuelve el archivo
  /// final. La fuente elige la extensión (la de [destination] es solo una
  /// sugerencia): en escritorio se conserva el formato original sin recodificar.
  Future<File> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  });
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async => throw UnsupportedError('La fuente no permite descargar videos.');
  Future<void> cancel(String jobId);
  Future<String> diagnose();
  Future<void> configureToolDirectory(String directory);
  Future<void> configureCookieFile(String? path);
  String? get cookieFile;
  String? get toolDirectory;
  void dispose();
}
