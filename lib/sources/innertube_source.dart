import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../bridge/api/sources.dart' as rust;
import '../core/source_backend.dart';
import '../dj/coherence.dart';
import '../follow/follow_models.dart';
import 'stream/audio_proxy.dart';
import 'stream/resolved_stream.dart';
import 'stream/stream_orchestrator.dart';
import 'youtube_request_policy.dart';

typedef InnerTubePost =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, Object?> body,
    );

/// YouTube Music search (InnerTube). Playback resolves through the stream
/// orchestrator and a loopback proxy, falling back to the official watch page
/// (web engine) when YouTube blocks it; yt-dlp stays for downloads and imports.
class InnerTubeSource extends SourceBackend {
  InnerTubeSource(
    this.delegate, {
    InnerTubePost? post,
    Future<AudioProxy> Function()? proxyFactory,
    StreamOrchestrator Function()? orchestratorFactory,
    bool? webFallback,
  }) : _post = post ?? _httpPost,
       // The hidden official player only exists on Windows (blank sheet on
       // Android, no WebView plugin on Linux).
       _webFallbackEnabled = webFallback ?? Platform.isWindows,
       _proxyFactory = proxyFactory ?? AudioProxy.start,
       _orchestratorFactory =
           orchestratorFactory ?? (() => StreamOrchestrator());

  final SourceBackend delegate;
  final InnerTubePost _post;
  final bool _webFallbackEnabled;
  final Future<AudioProxy> Function() _proxyFactory;
  final StreamOrchestrator Function() _orchestratorFactory;
  // Created on the first YouTube resolve, never in the constructor.
  StreamOrchestrator? _orchestrator;
  AudioQuality _quality = AudioQuality.high;
  AudioQuality get audioQuality => _quality;
  set audioQuality(AudioQuality q) {
    _quality = q;
    _orchestrator?.quality = q;
  }

  Future<AudioProxy>? _proxyFuture;
  AudioProxy? _proxy;
  String? _registeredId;
  int _resolveGeneration = 0;
  String? _currentVideoId;
  bool _disposed = false;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static const _clientVersion = '1.20250101.01.00';
  // YouTube Music search filters (one category byte differs).
  static const _params = {
    SearchKind.songs: 'EgWKAQIIAWoKEAkQBRAKEAMQBA==',
    SearchKind.albums: 'EgWKAQIYAWoKEAkQBRAKEAMQBA==',
    SearchKind.artists: 'EgWKAQIgAWoKEAkQBRAKEAMQBA==',
    SearchKind.videos: 'EgWKAQIQAWoKEAkQBRAKEAMQBA==',
  };
  static const _timeout = Duration(seconds: 15);

  static bool isValidVideoId(String id) => _videoId.hasMatch(id);

  static Future<Map<String, dynamic>> _httpPost(
    String endpoint,
    Map<String, Object?> body,
  ) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(
        Uri.https('music.youtube.com', '/youtubei/v1/$endpoint', {
          'prettyPrint': 'false',
        }),
      );
      request.headers
        ..contentType = ContentType.json
        ..set('Origin', 'https://music.youtube.com');
      request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close().timeout(_timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          'YouTube Music respondió ${response.statusCode} a la búsqueda.',
        );
      }
      return jsonDecode(text) as Map<String, dynamic>;
    } on TimeoutException {
      throw StateError('YouTube Music no respondió a tiempo.');
    } on SocketException {
      throw StateError('Sin conexión con YouTube Music.');
    } finally {
      client.close(force: true);
    }
  }

  static Map<String, Object?> _context() => {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': _clientVersion,
      'hl': 'es',
    },
  };

  @override
  bool get supportsOnlineMetadataSearch => true;

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    if (limit <= 0) return [];
    final page = await searchPage(query, SearchKind.songs);
    return page.tracks.take(limit).toList();
  }

  @override
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) async {
    final text = query.trim();
    if (text.isEmpty) return const SearchPage();
    if (text.length > 500) {
      throw ArgumentError('La búsqueda es demasiado larga.');
    }
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      return continuation != null
          ? const SearchPage()
          : SearchPage(tracks: await delegate.search(text));
    }
    final data = await _post(
      'search',
      continuation == null
          ? {'context': _context(), 'query': text, 'params': _params[kind]}
          : {'context': _context(), 'continuation': continuation},
    );
    return parseSearchPage(data, kind);
  }

  @override
  Future<List<Track>> browseTracks(SearchEntry entry) async {
    final data = await _post('browse', {
      'context': _context(),
      'browseId': entry.browseId,
    });
    final album = entry.kind == SearchKind.albums;
    final artist = album
        ? entry.subtitle.split(' • ').skip(1).firstOrNull
        : entry.title;
    final tracks = parseBrowseTracks(
      data,
      artist: artist,
      album: album ? entry.title : null,
      artwork: album ? entry.artworkUrl : null,
    );
    if (album) return tracks;
    // Perfil de artista: la página solo trae las destacadas; «Mostrar todo»
    // (lista VL…) tiene el catálogo completo, con continuaciones.
    try {
      final all = await _artistAllSongs(data, artist);
      final seen = tracks.map((t) => t.id).toSet();
      return [...tracks, ...all.where((t) => seen.add(t.id))];
    } catch (_) {
      return tracks;
    }
  }

  Future<List<Track>> _artistAllSongs(
    Map<String, dynamic> page,
    String? artist,
  ) async {
    String? listId;
    void find(Object? node) {
      if (listId != null) return;
      if (node is Map) {
        final shelf = node['musicShelfRenderer'];
        if (shelf is Map) {
          final id =
              shelf['bottomEndpoint']?['browseEndpoint']?['browseId']
                  as String? ??
              (shelf['title']?['runs'] as List?)
                  ?.map((r) => (r as Map)['navigationEndpoint'])
                  .whereType<Map>()
                  .map((e) => e['browseEndpoint']?['browseId'])
                  .whereType<String>()
                  .firstOrNull;
          if (id != null && id.startsWith('VL')) {
            listId = id;
            return;
          }
        }
        node.values.forEach(find);
      } else if (node is List) {
        node.forEach(find);
      }
    }

    find(page);
    if (listId == null) return const [];
    var data = await _post('browse', {
      'context': _context(),
      'browseId': listId,
    });
    final out = <Track>[...parseBrowseTracks(data, artist: artist)];
    for (var i = 0; i < 20; i++) {
      String? token;
      void next(Object? node) {
        if (token != null) return;
        if (node is Map) {
          token =
              node['nextContinuationData']?['continuation'] as String? ??
              node['continuationItemRenderer']?['continuationEndpoint']?['continuationCommand']?['token']
                  as String?;
          node.values.forEach(next);
        } else if (node is List) {
          node.forEach(next);
        }
      }

      next(data);
      if (token == null) break;
      data = await _post('browse', {
        'context': _context(),
        'continuation': token,
      });
      final more = parseBrowseTracks(data, artist: artist);
      if (more.isEmpty) break;
      out.addAll(more);
    }
    return out;
  }

  static SearchPage parseSearchPage(
    Map<String, dynamic> data,
    SearchKind kind,
  ) {
    final page = rust.innertubeParseSearchPage(
      dataJson: jsonEncode(data),
      kind: switch (kind) {
        SearchKind.songs => rust.SourceSearchKind.songs,
        SearchKind.videos => rust.SourceSearchKind.videos,
        SearchKind.albums => rust.SourceSearchKind.albums,
        SearchKind.artists => rust.SourceSearchKind.artists,
      },
    );
    return SearchPage(
      tracks: [for (final t in page.tracks) _track(t)],
      entries: [
        for (final e in page.entries)
          SearchEntry(
            kind: kind,
            browseId: e.browseId,
            title: e.title,
            subtitle: e.subtitle,
            artworkUrl: e.artworkUrl,
          ),
      ],
      continuation: page.continuation,
    );
  }

  /// Parses `musicResponsiveListItemRenderer` rows of a search response.
  /// Radio/autoplay de una pista (endpoint `next`, sin clave ni tokens PO).
  /// 25: una sola llamada cubre el relleno de la cola (kQueueLookahead) aun
  /// después de los filtros de repetición y artista.
  Future<List<Track>> related(String videoId, {int limit = 25}) async {
    if (!_videoId.hasMatch(videoId) || limit <= 0) return [];
    final data = await _post('next', {
      'context': _context(),
      'videoId': videoId,
      'playlistId': 'RDAMVM$videoId',
      'isAudioOnly': true,
    });
    return parseRelated(
      data,
    ).where((t) => t.id != 'yt:$videoId').take(limit).toList();
  }

  static List<Track> parseRelated(Map<String, dynamic> data) => [
    for (final t in rust.innertubeParseRelated(dataJson: jsonEncode(data)))
      _track(t),
  ];

  /// Página de artista (WEB_REMIX `browse`): álbumes, sencillos y EP.
  Future<ArtistPage> artistPage(String browseId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(browseId)) {
      throw ArgumentError('Identificador de artista no válido.');
    }
    return parseArtistPage(
      await _post('browse', {'context': _context(), 'browseId': browseId}),
    );
  }

  /// Vacío solo si el artista no aparece; los errores de red o de formato se
  /// propagan para que [ArtistGraph] los registre como fallo.
  Future<List<String>> relatedArtists(String artist) async {
    final norm = coherenceNorm(artist);
    if (norm.isEmpty) return const [];
    final page = await searchPage(artist, SearchKind.artists);
    final hit = page.entries
        .where((e) => coherenceNorm(e.title) == norm)
        .firstOrNull;
    if (hit == null) return const [];
    return (await artistPage(hit.browseId)).relatedArtists;
  }

  static ArtistPage parseArtistPage(Map<String, dynamic> data) {
    final page = rust.innertubeParseArtistPage(dataJson: jsonEncode(data));
    return ArtistPage(
      name: page.name,
      imageUrl: page.imageUrl,
      releases: [
        for (final r in page.releases)
          ArtistRelease(
            id: r.id,
            title: r.title,
            kind: r.kind,
            year: r.year,
            artworkUrl: r.artworkUrl,
          ),
      ],
      relatedArtists: page.relatedArtists,
    );
  }

  static Track _track(rust.SourceTrack t) => Track(
    id: t.id,
    title: t.title,
    artist: t.artist,
    album: t.album,
    duration: Duration(milliseconds: t.durationMs),
    artworkUrl: t.artworkUrl,
    pageUrl: t.pageUrl,
  );

  static List<Track> parseSearch(Map<String, dynamic> data) =>
      parseBrowseTracks(data);

  /// Track rows of a search, album page or artist songs shelf. A page header
  /// owns artist/album/artwork, so rows fall back to the given values.
  /// El análisis vive en `rust/crates/aurora_sources`; una respuesta con un
  /// tipo inesperado lanza, igual que antes.
  static List<Track> parseBrowseTracks(
    Map<String, dynamic> data, {
    String? artist,
    String? album,
    String? artwork,
  }) => [
    for (final t in rust.innertubeParseBrowseTracks(
      dataJson: jsonEncode(data),
      artist: artist,
      album: album,
      artwork: artwork,
    ))
      _track(t),
  ];

  String? _youTubeId(Track track) {
    final page = Uri.tryParse(track.pageUrl ?? '');
    final id = track.id.startsWith('yt:')
        ? track.id.substring(3)
        : page?.host == 'youtu.be'
        ? page?.pathSegments.firstOrNull
        : page != null && page.host.endsWith('youtube.com')
        ? page.queryParameters['v']
        : null;
    return id != null && _videoId.hasMatch(id) ? id : null;
  }

  StreamOrchestrator get _orch =>
      _orchestrator ??= _orchestratorFactory()..quality = _quality;

  static Duration? _knownDuration(Track track) =>
      track.duration > Duration.zero ? track.duration : null;

  ResolvedAudio _webFallback(String id, Track track) => ResolvedAudio(
    input: Uri.https('music.youtube.com', '/watch', {'v': id}).toString(),
    duration: track.duration,
    engine: AudioEngine.web,
  );

  Future<AudioProxy> _startProxy() async {
    if (_disposed) throw StateError('La fuente ya se cerró.');
    final future = _proxyFuture ??= _proxyFactory();
    try {
      final proxy = await future;
      if (_disposed) throw StateError('La fuente ya se cerró.');
      return _proxy = proxy;
    } catch (_) {
      // A failed start must not be cached forever.
      if (identical(_proxyFuture, future)) _proxyFuture = null;
      rethrow;
    }
  }

  @override
  Future<void> prefetch(Track track) async {
    final id = _youTubeId(track);
    if (id == null || track.isLocal) return;
    try {
      await _orch.resolve(id, trackDuration: _knownDuration(track));
    } catch (_) {}
  }

  @override
  void invalidateResolvedAudio(Track track) {
    final id = _youTubeId(track);
    if (id == null) return;
    _orchestrator?.reportFailure(id);
    _proxy?.unregister(id);
    if (_registeredId == id) _registeredId = null;
  }

  @override
  bool isExpiredStream(Track track) {
    final id = _youTubeId(track);
    return id != null &&
        (_proxy?.current(id)?.expiredAt(DateTime.now()) ?? false);
  }

  @override
  Future<ResolvedAudio> resolve(Track track) async {
    if (track.isLocal && await File(track.localPath!).exists()) {
      return ResolvedAudio(input: track.localPath!, duration: track.duration);
    }
    final id = _youTubeId(track);
    if (id == null) {
      throw StateError(
        'Solo se pueden reproducir canciones de YouTube Music o archivos locales.',
      );
    }
    _currentVideoId = id;
    final generation = ++_resolveGeneration;
    final orch = _orch;
    if (_webFallbackEnabled && orch.isBlacklisted(id)) {
      return _webFallback(id, track);
    }
    final duration = _knownDuration(track);
    ResolvedStream stream;
    try {
      stream = await orch.resolve(id, trackDuration: duration);
    } on StreamResolveException catch (error) {
      // Network and removed videos are real errors; anything else (bot check,
      // login, ciphered or changed responses) still plays in the official player.
      if (error.kind == YouTubeFailure.transient ||
          error.kind == YouTubeFailure.unavailable) {
        rethrow;
      }
      if (_webFallbackEnabled) return _webFallback(id, track);
      if (generation != _resolveGeneration) rethrow; // user moved on
      // No official player here: one fresh attempt, then the real error.
      stream = await orch.resolve(
        id,
        forceRefresh: true,
        trackDuration: duration,
      );
    }
    final AudioProxy proxy;
    try {
      proxy = await _startProxy();
    } catch (_) {
      if (_disposed || !_webFallbackEnabled) rethrow;
      return _webFallback(id, track); // proxy unavailable: official player
    }
    // Only the newest resolve may drop the previous video; a superseded call
    // registers without unregistering (the registry's FIFO cap cleans up).
    if (generation == _resolveGeneration) {
      final previous = _registeredId;
      if (previous != null && previous != id) proxy.unregister(previous);
      _registeredId = id;
    }
    final uri = proxy.register(
      id,
      stream,
      refresh: () =>
          orch.resolve(id, forceRefresh: true, sameItag: stream.itag),
      onFailure: (status, reason) =>
          orch.reportFailure(id, httpStatus: status, reason: reason),
    );
    return ResolvedAudio(
      input: uri.toString(),
      duration: stream.duration ?? track.duration,
      validateCompletion: () => _checkServedToEnd(proxy, id),
    );
  }

  /// Players report a cut loopback connection as a normal end; only a stream
  /// whose last byte was delivered counts. Unknown (unregistered) is trusted.
  Future<void> _checkServedToEnd(AudioProxy proxy, String id) async {
    // The flag flips just after the final flush the player already saw.
    for (var i = 0; i < 10 && proxy.servedToEnd(id) == false; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (proxy.servedToEnd(id) == false) {
      throw StateError(
        'Premature EOF: YouTube audio ended before the file did',
      );
    }
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) => delegate.importPlaylist(url);
  @override
  Future<File> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) => delegate.download(
    track,
    destination,
    jobId: jobId,
    onProgress: onProgress,
  );
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
  Future<void> cancel(String jobId) => delegate.cancel(jobId);
  @override
  void reportPlaybackFailure(String message) {
    final id = _currentVideoId;
    if (id == null) return;
    var status = RegExp(r'\b(400|401|403|410)\b').firstMatch(message)?[1];
    // ffmpeg prints "Server returned 4XX Client Error, but not one of
    // 40{0,1,3,4}" for the 410 the loopback proxy answers on an upstream failure.
    if (status == null &&
        RegExp(r'4xx client error', caseSensitive: false).hasMatch(message)) {
      status = '410';
    }
    _orchestrator?.reportFailure(
      id,
      httpStatus: status == null ? null : int.parse(status),
      reason: message,
    );
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
    _disposed = true;
    final proxy = _proxyFuture;
    if (proxy != null) {
      unawaited(proxy.then((p) => p.close()).catchError((Object _) {}));
    }
    delegate.dispose();
  }
}
