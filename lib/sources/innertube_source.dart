import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
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
           orchestratorFactory ??
           (() => StreamOrchestrator(preferMp4a: Platform.isAndroid));

  final SourceBackend delegate;
  final InnerTubePost _post;
  final bool _webFallbackEnabled;
  final Future<AudioProxy> Function() _proxyFactory;
  final StreamOrchestrator Function() _orchestratorFactory;
  // Created on the first YouTube resolve, never in the constructor.
  StreamOrchestrator? _orchestrator;
  Future<AudioProxy>? _proxyFuture;
  AudioProxy? _proxy;
  String? _registeredId;
  int _resolveGeneration = 0;
  String? _currentVideoId;
  bool _disposed = false;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  static final _clock = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{2})$');
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
    String? token;
    void find(Object? node) {
      if (token != null) return;
      if (node is Map) {
        token =
            node['nextContinuationData']?['continuation'] as String? ??
            node['continuationItemRenderer']?['continuationEndpoint']?['continuationCommand']?['token']
                as String?;
        node.values.forEach(find);
      } else if (node is List) {
        node.forEach(find);
      }
    }

    find(data);
    if (kind == SearchKind.songs || kind == SearchKind.videos) {
      return SearchPage(tracks: parseSearch(data), continuation: token);
    }
    final wanted = kind == SearchKind.albums
        ? 'MUSIC_PAGE_TYPE_ALBUM'
        : 'MUSIC_PAGE_TYPE_ARTIST';
    final seen = <String>{};
    final entries = <SearchEntry>[];
    for (final row in _rows(data)) {
      final browse = row['navigationEndpoint']?['browseEndpoint'] as Map?;
      final id = browse?['browseId'] as String?;
      final page =
          browse?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
      final columns = _columns(row);
      if (id == null ||
          page != wanted ||
          columns.isEmpty ||
          columns.first.isEmpty ||
          !seen.add(id)) {
        continue;
      }
      entries.add(
        SearchEntry(
          kind: kind,
          browseId: id,
          title: (columns.first.first as Map)['text'] as String? ?? '',
          subtitle: columns.length > 1
              ? columns[1].map((r) => (r as Map)['text'] ?? '').join()
              : '',
          artworkUrl: _artwork(row['thumbnail']),
        ),
      );
    }
    return SearchPage(entries: entries, continuation: token);
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

  static List<Track> parseRelated(Map<String, dynamic> data) {
    final seen = <String>{};
    final tracks = <Track>[];
    void walk(Object? node) {
      if (node is Map) {
        final row = node['playlistPanelVideoRenderer'];
        if (row is Map) {
          final id = row['videoId'];
          final title = (row['title']?['runs'] as List?)?.firstOrNull;
          final artist = (row['longBylineText']?['runs'] as List?)?.firstOrNull;
          final length =
              ((row['lengthText']?['runs'] as List?)?.firstOrNull
                      as Map?)?['text']
                  as String?;
          final thumbs = row['thumbnail']?['thumbnails'] as List?;
          final art = (thumbs?.lastOrNull as Map?)?['url'] as String?;
          final titleText = (title as Map?)?['text'];
          if (id is String &&
              _videoId.hasMatch(id) &&
              titleText is String &&
              titleText.trim().isNotEmpty &&
              seen.add(id)) {
            final uri = Uri.tryParse(art ?? '');
            tracks.add(
              Track(
                id: 'yt:$id',
                title: titleText,
                artist:
                    ((artist as Map?)?['text'] as String?) ?? 'YouTube Music',
                duration: length == null
                    ? Duration.zero
                    : _clockOf(length) ?? Duration.zero,
                artworkUrl: uri != null && uri.scheme == 'https' ? art : null,
                pageUrl: 'https://music.youtube.com/watch?v=$id',
              ),
            );
          }
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(data);
    return tracks;
  }

  /// Página de artista (WEB_REMIX `browse`): álbumes, sencillos y EP.
  Future<ArtistPage> artistPage(String browseId) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(browseId)) {
      throw ArgumentError('Identificador de artista no válido.');
    }
    return parseArtistPage(
      await _post('browse', {'context': _context(), 'browseId': browseId}),
    );
  }

  /// Artistas afines según YouTube Music (carrusel de la página del artista).
  /// Cualquier fallo da lista vacía: es una pista, nunca un requisito.
  Future<List<String>> relatedArtists(String artist) async {
    try {
      final norm = coherenceNorm(artist);
      if (norm.isEmpty) return const [];
      final page = await searchPage(artist, SearchKind.artists);
      final hit = page.entries
          .where((e) => coherenceNorm(e.title) == norm)
          .firstOrNull;
      if (hit == null) return const [];
      return (await artistPage(hit.browseId)).relatedArtists;
    } catch (_) {
      return const [];
    }
  }

  static ArtistPage parseArtistPage(Map<String, dynamic> data) {
    final header = data['header'] as Map? ?? const {};
    final head =
        (header['musicImmersiveHeaderRenderer'] ??
                header['musicVisualHeaderRenderer'] ??
                header['musicHeaderRenderer'])
            as Map?;
    final name =
        ((head?['title']?['runs'] as List?)?.firstOrNull as Map?)?['text']
            as String?;
    final seen = <String>{};
    final releases = <ArtistRelease>[];
    final related = <String>[];
    final relatedKeys = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        final row = node['musicTwoRowItemRenderer'];
        if (row is Map) {
          final browse = row['navigationEndpoint']?['browseEndpoint'] as Map?;
          final id = browse?['browseId'] as String?;
          final page =
              browse?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
          final title =
              ((row['title']?['runs'] as List?)?.firstOrNull as Map?)?['text']
                  as String?;
          if (page == 'MUSIC_PAGE_TYPE_ARTIST' &&
              title != null &&
              title.trim().isNotEmpty &&
              relatedKeys.add(title.trim().toLowerCase())) {
            related.add(title.trim());
          }
          if (id != null &&
              page == 'MUSIC_PAGE_TYPE_ALBUM' &&
              title != null &&
              title.trim().isNotEmpty &&
              seen.add(id)) {
            final parts = [
              for (final r in (row['subtitle']?['runs'] as List? ?? const []))
                ((r as Map)['text'] as String? ?? '').trim(),
            ].where((t) => t.isNotEmpty && t != '•').toList();
            final year = parts
                .map((t) => RegExp(r'^(?:19|20)\d{2}$').hasMatch(t) ? t : null)
                .whereType<String>()
                .firstOrNull;
            releases.add(
              ArtistRelease(
                id: id,
                title: title.trim(),
                kind: parts.where((t) => t != year).firstOrNull ?? '',
                year: year == null ? null : int.parse(year),
                artworkUrl: _artwork(row['thumbnailRenderer']),
              ),
            );
          }
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(data['contents']);
    return ArtistPage(
      name: name,
      imageUrl: _artwork(head?['thumbnail']),
      releases: releases,
      relatedArtists: related,
    );
  }

  static List<Track> parseSearch(Map<String, dynamic> data) =>
      parseBrowseTracks(data);

  /// Track rows of a search, album page or artist songs shelf. A page header
  /// owns artist/album/artwork, so rows fall back to the given values.
  static List<Track> parseBrowseTracks(
    Map<String, dynamic> data, {
    String? artist,
    String? album,
    String? artwork,
  }) {
    final seen = <String>{};
    final tracks = <Track>[];
    for (final row in _rows(data)) {
      final track = _row(row, artist, album, artwork);
      if (track != null && seen.add(track.id)) tracks.add(track);
    }
    return tracks;
  }

  static List<Map> _rows(Object? root) {
    final rows = <Map>[];
    void walk(Object? node) {
      if (node is Map) {
        final row = node['musicResponsiveListItemRenderer'];
        if (row is Map) {
          rows.add(row);
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(root);
    return rows;
  }

  static List<List> _columns(Map row) =>
      (row['flexColumns'] as List? ?? const [])
          .map(
            (c) =>
                ((c as Map?)?['musicResponsiveListItemFlexColumnRenderer']
                        as Map?)?['text']?['runs']
                    as List? ??
                const [],
          )
          .toList();

  static Duration? _clockOf(String text) {
    final clock = _clock.firstMatch(text.trim());
    return clock == null
        ? null
        : Duration(
            hours: int.parse(clock[1] ?? '0'),
            minutes: int.parse(clock[2]!),
            seconds: int.parse(clock[3]!),
          );
  }

  static Track? _row(
    Map row,
    String? fbArtist,
    String? fbAlbum,
    String? fbArt,
  ) {
    final columns = _columns(row);
    if (columns.isEmpty || columns.first.isEmpty) return null;
    final titleRun = columns.first.first as Map;
    final id =
        row['playlistItemData']?['videoId'] as String? ??
        titleRun['navigationEndpoint']?['watchEndpoint']?['videoId'] as String?;
    final title = titleRun['text'] as String?;
    if (id == null || !_videoId.hasMatch(id) || title == null) return null;
    final artists = <String>[];
    String? album;
    Duration? duration;
    final details = columns.length > 1 ? columns[1] : const [];
    for (final run in details.whereType<Map>()) {
      final text = (run['text'] as String? ?? '').trim();
      final page =
          run['navigationEndpoint']?['browseEndpoint']?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType'];
      if (page == 'MUSIC_PAGE_TYPE_ALBUM') {
        album = text;
      } else if (page == 'MUSIC_PAGE_TYPE_ARTIST' ||
          page == 'MUSIC_PAGE_TYPE_USER_CHANNEL') {
        artists.add(text);
      } else {
        duration ??= _clockOf(text);
      }
    }
    if (artists.isEmpty && fbArtist != null) artists.add(fbArtist);
    if (artists.isEmpty && details.isNotEmpty) {
      final first = ((details.first as Map)['text'] as String? ?? '').trim();
      if (first.isNotEmpty && _clockOf(first) == null) artists.add(first);
    }
    final fixed =
        (((row['fixedColumns'] as List?)?.firstOrNull
                    as Map?)?['musicResponsiveListItemFixedColumnRenderer']
                as Map?)?['text']?['runs']
            as List?;
    duration ??= _clockOf(
      (fixed?.firstOrNull as Map?)?['text'] as String? ?? '',
    );
    return Track(
      id: 'yt:$id',
      title: title,
      artist: artists.isEmpty ? 'YouTube Music' : artists.join(', '),
      album: album ?? fbAlbum,
      duration: duration ?? Duration.zero,
      artworkUrl: _artwork(row['thumbnail']) ?? fbArt,
      pageUrl: 'https://music.youtube.com/watch?v=$id',
    );
  }

  static String? _artwork(Object? thumbnail) {
    final list =
        ((thumbnail as Map?)?['musicThumbnailRenderer']?['thumbnail']
                as Map?)?['thumbnails']
            as List? ??
        const [];
    Map? best;
    for (final image in list.whereType<Map>()) {
      final uri = Uri.tryParse(image['url'] as String? ?? '');
      if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
        continue;
      }
      if (best == null ||
          (image['width'] as num? ?? 0) > (best['width'] as num? ?? 0)) {
        best = image;
      }
    }
    final url = best?['url'] as String?;
    // Music thumbnails are resizable; the listing only offers 60/120 px.
    return url?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
  }

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

  StreamOrchestrator get _orch => _orchestrator ??= _orchestratorFactory();

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
  Future<void> download(
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
    final status = RegExp(r'\b(400|401|403|410)\b').firstMatch(message)?[1];
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
  String? get ffmpegExecutable => delegate.ffmpegExecutable;
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
