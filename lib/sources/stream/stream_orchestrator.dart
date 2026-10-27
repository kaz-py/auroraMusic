import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../youtube_request_policy.dart';
import 'player_clients.dart';
import 'resolved_stream.dart';

typedef PlayerPost =
    Future<Map<String, dynamic>> Function(
      Uri url,
      Map<String, String> headers,
      Map<String, Object?> body,
    );

/// Non-2xx reply from [PlayerPost]. [HttpGet] never throws it: it returns
/// the status. Network failures throw [SocketException]/[TimeoutException].
class HttpStatusException implements Exception {
  const HttpStatusException(this.statusCode, [this.message = '']);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode $message'.trim();
}

class HttpGetResult {
  const HttpGetResult(
    this.statusCode, {
    this.body = const [],
    this.headers = const {},
  });

  final int statusCode;

  /// Raw bytes; the tail probe gets binary data, so never decode strictly.
  final List<int> body;
  final Map<String, String> headers;
}

typedef HttpGet =
    Future<HttpGetResult> Function(
      Uri url,
      Map<String, String> headers, {
      // Implementations declare a default (10 s).
      Duration timeout,
    });

const _requestTimeout = Duration(seconds: 10);
const _maxBody = 1 << 20; // the probe wants 256 bytes; never buffer a song

Future<T> _withClient<T>(
  Duration timeout,
  Future<T> Function(HttpClient client) run,
) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    return await run(client).timeout(timeout);
  } finally {
    client.close(force: true);
  }
}

Future<(HttpClientResponse, List<int>)> _read(HttpClientRequest request) async {
  final response = await request.close();
  final body = <int>[];
  await for (final chunk in response) {
    body.addAll(chunk);
    if (body.length >= _maxBody) break;
  }
  return (response, body);
}

Future<Map<String, dynamic>> defaultPlayerPost(
  Uri url,
  Map<String, String> headers,
  Map<String, Object?> body,
) => _withClient(_requestTimeout, (client) async {
  final request = await client.postUrl(url);
  headers.forEach(request.headers.set);
  request.add(utf8.encode(jsonEncode(body)));
  final (response, bytes) = await _read(request);
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpStatusException(response.statusCode, response.reasonPhrase);
  }
  return jsonDecode(utf8.decode(bytes, allowMalformed: true))
      as Map<String, dynamic>;
});

Future<HttpGetResult> defaultHttpGet(
  Uri url,
  Map<String, String> headers, {
  Duration timeout = _requestTimeout,
}) => _withClient(timeout, (client) async {
  final request = await client.getUrl(url);
  headers.forEach(request.headers.set);
  final (response, bytes) = await _read(request);
  final out = <String, String>{};
  response.headers.forEach((name, values) => out[name] = values.join(','));
  return HttpGetResult(response.statusCode, body: bytes, headers: out);
});

enum AudioQuality { high, normal, saver }

/// Resolves a videoId to a validated audio stream with client fallback.
class StreamOrchestrator {
  StreamOrchestrator({
    PlayerPost? post,
    HttpGet? get,
    List<PlayerClient>? clients,
    this.quality = AudioQuality.high,
    DateTime Function()? now,
  }) : _post = post ?? defaultPlayerPost,
       _get = get ?? defaultHttpGet,
       _clients = clients ?? defaultPlayerClients,
       _now = now ?? DateTime.now;

  static final _playerUri = Uri.parse(
    'https://music.youtube.com/youtubei/v1/player?prettyPrint=false',
  );
  static final _swUri = Uri.parse('https://music.youtube.com/sw.js_data');
  static const _cacheCap = 50;
  static const _blacklistTtl = Duration(minutes: 30);
  // Worst first, so one summary exception reflects the most actionable cause.
  static const _severity = [
    YouTubeFailure.blocked,
    YouTubeFailure.accessDenied,
    YouTubeFailure.transient,
    YouTubeFailure.other,
  ];

  AudioQuality quality;
  final PlayerPost _post;
  final HttpGet _get;
  final List<PlayerClient> _clients;
  final DateTime Function() _now;

  final _cache = <String, ResolvedStream>{}; // insertion-ordered: LRU
  final _servedBy = <String, String>{};
  final _generation = <String, int>{};
  final _inflight = <String, Future<ResolvedStream>>{};
  final _badUntil = <String, DateTime>{};
  final _blacklist = <String, DateTime>{};
  Future<String?>? _visitor;

  Future<ResolvedStream> resolve(
    String videoId, {
    bool forceRefresh = false,
    Duration? trackDuration,
    int? sameItag,
  }) {
    if (!forceRefresh) {
      final hit = _cache.remove(videoId);
      final horizon = _now().add(
        const Duration(seconds: 60) + (trackDuration ?? Duration.zero),
      );
      if (hit != null && hit.expiresAt.isAfter(horizon)) {
        return Future.value(_cache[videoId] = hit); // re-insert: LRU touch
      }
    }
    final key = '$videoId|$forceRefresh';
    late final Future<ResolvedStream> future;
    future = _inflight.putIfAbsent(
      key,
      () => _resolveFresh(videoId, sameItag).whenComplete(() {
        if (identical(_inflight[key], future)) _inflight.remove(key);
      }),
    );
    return future;
  }

  /// A playback failure: drops the cached URL and marks the issuing client bad
  /// (401/403/410 → 10 min, anything else → 2 min).
  void reportFailure(String videoId, {int? httpStatus, String? reason}) {
    _generation[videoId] = (_generation[videoId] ?? 0) + 1;
    _cache.remove(videoId);
    _inflight.remove('$videoId|true');
    _inflight.remove('$videoId|false');
    final client = _servedBy[videoId];
    if (client != null) _markBad(client, _isAuthStatus(httpStatus));
  }

  bool isBlacklisted(String videoId) {
    final until = _blacklist[videoId];
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _blacklist.remove(videoId);
    return false;
  }

  static bool _isAuthStatus(int? s) =>
      s == 400 || s == 401 || s == 403 || s == 410;

  void _markBad(String client, bool long) =>
      _badUntil[client] = _now().add(Duration(minutes: long ? 10 : 2));

  Iterable<PlayerClient> _ordered() {
    bool bad(PlayerClient c) => _now().isBefore(_badUntil[c.name] ?? _now());
    return [..._clients.where((c) => !bad(c)), ..._clients.where(bad)];
  }

  void _put<V>(Map<String, V> map, String key, V value) {
    map.remove(key);
    map[key] = value;
    if (map.length > _cacheCap) map.remove(map.keys.first);
  }

  Future<ResolvedStream> _resolveFresh(String videoId, int? sameItag) async {
    final generation = _generation[videoId] ?? 0;
    final failures = <StreamResolveException>[];
    for (final client in _ordered()) {
      try {
        final stream = await _tryClient(client, videoId, sameItag);
        if (generation == (_generation[videoId] ?? 0)) {
          _put(_cache, videoId, stream);
        }
        _put(_servedBy, videoId, client.name);
        return stream;
      } on StreamResolveException catch (e) {
        // Only UNPLAYABLE/ERROR produce `unavailable`: no client will differ.
        if (e.kind == YouTubeFailure.unavailable) rethrow;
        failures.add(e);
      }
    }
    final worst = failures.isEmpty
        ? const StreamResolveException(
            YouTubeFailure.other,
            'No YouTube client available',
          )
        : (failures.toList()..sort(
                (a, b) => _severity
                    .indexOf(a.kind)
                    .compareTo(_severity.indexOf(b.kind)),
              ))
              .first;
    if (worst.kind == YouTubeFailure.blocked ||
        worst.kind == YouTubeFailure.accessDenied) {
      _blacklist[videoId] = _now().add(_blacklistTtl);
    }
    throw worst;
  }

  Future<ResolvedStream> _tryClient(
    PlayerClient client,
    String videoId,
    int? sameItag,
  ) async {
    final visitor = await (_visitor ??= _fetchVisitorData(client));
    if (visitor == null) _visitor = null; // retry next time
    Map<String, dynamic> json;
    try {
      json = await _post(_playerUri, {
        'content-type': 'application/json',
        'accept': 'application/json',
        'x-goog-api-format-version': '1',
        'x-youtube-client-name': '${client.id}',
        'x-youtube-client-version': client.version,
        'x-origin': 'https://music.youtube.com',
        'referer': 'https://music.youtube.com/',
        'user-agent': client.userAgent,
        'accept-language': 'en-US,en;q=0.9',
        'x-goog-visitor-id': ?visitor,
      }, _body(client, videoId, visitor));
    } catch (e) {
      throw _fail(client, e);
    }

    final playability = json['playabilityStatus'];
    final status = playability is Map ? playability['status'] : null;
    final reason = playability is Map ? '${playability['reason']}' : '';
    if (status == 'UNPLAYABLE' || status == 'ERROR') {
      if (!reason.toLowerCase().contains('not a bot')) {
        throw const StreamResolveException(
          YouTubeFailure.unavailable,
          'Video unavailable',
        );
      }
    }
    if (status == 'LOGIN_REQUIRED' ||
        reason.toLowerCase().contains('not a bot')) {
      _markBad(client.name, false);
      throw const StreamResolveException(
        YouTubeFailure.blocked,
        'YouTube asked to sign in: not a bot check',
      );
    }
    final streaming = json['streamingData'];
    final expires = streaming is Map
        ? _int(streaming['expiresInSeconds'])
        : null;
    if (status != 'OK' || expires == null) {
      _markBad(client.name, false);
      throw StreamResolveException(
        YouTubeFailure.other,
        'Player response without playable streams ($status)',
      );
    }
    final format = _pickFormat(streaming['adaptiveFormats'], sameItag);
    if (format == null) {
      throw const StreamResolveException(
        YouTubeFailure.other,
        'No playable audio format',
      );
    }

    final url = Uri.parse(format['url'] as String); // checked in _isUsable
    final length = _int(format['contentLength'])!;
    final headers = {'User-Agent': client.userAgent};
    try {
      final probe = await _get(url, {
        ...headers,
        'Range': 'bytes=${length > 256 ? length - 256 : 0}-${length - 1}',
        'Accept-Encoding': 'identity',
      }, timeout: _requestTimeout);
      if (probe.statusCode < 200 || probe.statusCode >= 300) {
        throw HttpStatusException(probe.statusCode);
      }
    } catch (e) {
      throw _fail(client, e, probe: true);
    }
    return ResolvedStream(
      videoId: videoId,
      url: url,
      headers: headers,
      expiresAt: _expiry(url, expires),
      client: client.name,
      itag: _int(format['itag'])!,
      mimeType: format['mimeType'] as String,
      contentLength: length,
      duration: switch (_int(format['approxDurationMs'])) {
        final ms? when ms > 0 => Duration(milliseconds: ms),
        _ => null,
      },
    );
  }

  /// The CDN rejects a URL after its signed `expire` (unix seconds), which can
  /// be earlier than `expiresInSeconds`: honour whichever comes first.
  DateTime _expiry(Uri url, int expiresInSeconds) {
    final byTtl = _now().add(Duration(seconds: expiresInSeconds));
    final unix = int.tryParse(url.queryParameters['expire'] ?? '');
    if (unix == null) return byTtl;
    final signed = DateTime.fromMillisecondsSinceEpoch(
      unix * 1000,
      isUtc: _now().isUtc,
    );
    return signed.isBefore(byTtl) ? signed : byTtl;
  }

  Map<String, Object?> _body(PlayerClient c, String videoId, String? visitor) =>
      {
        'context': {
          'client': {
            'clientName': c.name,
            'clientVersion': c.version,
            ...c.extraClient,
            'gl': 'US',
            'hl': 'en',
            'visitorData': ?visitor,
          },
          'request': {'internalExperimentFlags': [], 'useSsl': true},
          'user': {'lockedSafetyMode': false},
        },
        'videoId': videoId,
        'contentCheckOk': true,
        'racyCheckOk': true,
      };

  /// First `Cgt…`/`Cgs…` string of sw.js_data; null (and not cached) on failure.
  Future<String?> _fetchVisitorData(PlayerClient client) async {
    try {
      final r = await _get(_swUri, {'User-Agent': client.userAgent});
      if (r.statusCode != 200) return null;
      final text = utf8.decode(r.body, allowMalformed: true);
      return RegExp(r'"(Cg[ts][^"]*)"').firstMatch(text)?.group(1);
    } catch (_) {
      return null;
    }
  }

  /// Marks the client bad and maps the error to a classifiable exception.
  StreamResolveException _fail(PlayerClient c, Object e, {bool probe = false}) {
    final status = e is HttpStatusException ? e.statusCode : null;
    _markBad(c.name, probe && status != null || _isAuthStatus(status));
    if (status == 429) {
      return const StreamResolveException(
        YouTubeFailure.blocked,
        'YouTube rate limit: too many requests (HTTP 429)',
      );
    }
    if (status == 403) {
      return const StreamResolveException(
        YouTubeFailure.accessDenied,
        'HTTP 403 forbidden',
      );
    }
    if (status != null) {
      final message = 'HTTP $status';
      return StreamResolveException(
        YouTubeRequestPolicy.classify(message),
        message,
      );
    }
    if (e is TimeoutException) {
      return const StreamResolveException(
        YouTubeFailure.transient,
        'Request timed out',
      );
    }
    if (e is IOException) {
      return const StreamResolveException(
        YouTubeFailure.transient,
        'Connection error (SocketException)',
      );
    }
    return const StreamResolveException(
      YouTubeFailure.other,
      'Unexpected player response',
    );
  }

  Map<String, dynamic>? _pickFormat(Object? raw, int? sameItag) {
    final formats = [
      for (final f in raw is List ? raw : const [])
        if (f is Map<String, dynamic>) f,
    ];
    var candidates = [
      for (final f in formats)
        if (_isUsable(f, strictDub: true)) f,
    ];
    // Some tracks lack audioIsDefault: then accept anything not auto-dubbed.
    if (candidates.isEmpty) {
      candidates = [
        for (final f in formats)
          if (_isUsable(f, strictDub: false)) f,
      ];
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final ra = _rank(a), rb = _rank(b);
      for (var i = 0; i < ra.length; i++) {
        if (ra[i] != rb[i]) return rb[i].compareTo(ra[i]);
      }
      return 0;
    });
    return candidates.firstWhere(
      (f) => sameItag != null && _int(f['itag']) == sameItag,
      orElse: () => candidates.first,
    );
  }

  /// Plain-url audio with a known length, in the original language.
  bool _isUsable(Map<String, dynamic> f, {required bool strictDub}) {
    final track = f['audioTrack'];
    return '${f['mimeType']}'.startsWith('audio/') &&
        f['url'] is String &&
        Uri.tryParse(f['url'] as String) != null &&
        f['signatureCipher'] == null &&
        f['cipher'] == null &&
        (_int(f['contentLength']) ?? 0) > 0 &&
        _int(f['itag']) != null &&
        (track is! Map ||
            (track['isAutoDubbed'] != true &&
                (!strictDub || track['audioIsDefault'] == true)));
  }

  /// Compared descending; order depends on [quality].
  List<int> _rank(Map<String, dynamic> f) {
    final mime = '${f['mimeType']}';
    final opus = mime.contains('opus');
    final mp4a = mime.contains('mp4a');
    final bitrate = _int(f['bitrate']) ?? 0;
    return switch (quality) {
      AudioQuality.high => [
        switch (f['audioQuality']) {
          'AUDIO_QUALITY_HIGH' => 3,
          'AUDIO_QUALITY_MEDIUM' => 2,
          'AUDIO_QUALITY_LOW' => 1,
          _ => 0,
        },
        _int(f['audioChannels']) ?? 2,
        opus
            ? 2
            : mp4a
            ? 1
            : 0,
        bitrate,
      ],
      AudioQuality.normal => [
        bitrate <= 140000 ? 1 : 0,
        mp4a
            ? 2
            : opus
            ? 1
            : 0,
        bitrate,
      ],
      AudioQuality.saver => [opus ? 1 : 0, -bitrate],
    };
  }

  static int? _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v');
}
