import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'resolved_stream.dart';

/// Loopback range proxy in front of googlevideo (127.0.0.1 only).
///
/// The player sees one stable URL per video and any `Range`; upstream is read
/// in bounded chunks so an expired URL can be refreshed mid-stream. googlevideo
/// 3xx replies are followed (max 5 hops, https `*.googlevideo.com` only).
class AudioProxy {
  AudioProxy._(
    this._server,
    this._client,
    this.chunkBytes,
    int maxUpstream,
    this.headerTimeout,
    this.stallTimeout,
    this.allowRedirect,
  ) : _free = maxUpstream;

  static const _maxEntries = 64;
  static const _maxRedirects = 5;
  static const _redirects = {301, 302, 303, 307, 308};

  /// Only https hosts under googlevideo.com: a signed media URL must never
  /// be replayed (nor its Range answered) by an arbitrary host.
  static bool isGoogleVideoRedirect(Uri uri) =>
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.host.endsWith('.googlevideo.com');

  final bool Function(Uri target) allowRedirect;

  final HttpServer _server;
  final HttpClient _client;
  final int chunkBytes;
  final Duration headerTimeout;
  final Duration stallTimeout;
  final _entries = <String, _Entry>{};
  final _active = <_Ctx>{};
  final _waiters = Queue<Completer<void>>();
  int _free;
  bool _closed = false;
  Future<void>? _closing;

  static Future<AudioProxy> start({
    int chunkBytes = 4 << 20,
    int maxUpstream = 6,
    Duration headerTimeout = const Duration(seconds: 15),
    Duration stallTimeout = const Duration(seconds: 20),
    HttpClient? client,
    bool Function(Uri target)? allowRedirect,
  }) async {
    if (chunkBytes <= 0 || maxUpstream <= 0) throw ArgumentError('limits');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final http =
        client ??
        (HttpClient()
          ..userAgent = null
          ..connectionTimeout = headerTimeout);
    final proxy = AudioProxy._(
      server,
      http,
      chunkBytes,
      maxUpstream,
      headerTimeout,
      stallTimeout,
      allowRedirect ?? isGoogleVideoRedirect,
    );
    server.listen(
      (request) => unawaited(proxy._serve(request)),
      onError: (Object _) {},
    );
    return proxy;
  }

  Uri register(
    String videoId,
    ResolvedStream stream, {
    required Future<ResolvedStream> Function() refresh,
    void Function(int? status, String reason)? onFailure,
  }) {
    if (_closed) throw StateError('AudioProxy is closed.');
    final old = _entries.remove(videoId);
    final entry = _Entry(
      videoId,
      old?.token ?? _hex(16),
      old?.id ?? _hex(8),
      stream,
      refresh,
      onFailure,
    );
    _entries[videoId] = entry;
    while (_entries.length > _maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return Uri.parse(
      'http://127.0.0.1:${_server.port}/${entry.token}/a/${entry.id}',
    );
  }

  ResolvedStream? current(String videoId) => _entries[videoId]?.stream;

  /// Whether some response for this registration delivered the file's last
  /// byte (not that the whole file was played). Null when not registered.
  bool? servedToEnd(String videoId) => _entries[videoId]?.servedToEnd;

  /// Open downstream connections (test hook for leak checks).
  int get activeConnections => _active.length;

  /// In-flight requests keep their entry and finish; new ones get 404.
  void unregister(String videoId) => _entries.remove(videoId);

  Future<void> close() => _closing ??= () async {
    _closed = true;
    _entries.clear();
    for (final ctx in _active.toList()) {
      ctx.abort();
    }
    while (_waiters.isNotEmpty) {
      _waiters.removeFirst().completeError(StateError('closed'));
    }
    _client.close(force: true);
    await _server.close(force: true);
  }();

  static String _hex(int bytes) {
    final random = Random.secure();
    return List.generate(
      bytes,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> _acquire() {
    if (_closed) return Future.error(StateError('closed'));
    if (_free > 0) {
      _free--;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _free++;
    }
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final ctx = _Ctx();
    Socket? socket;
    var headersSent = false;
    try {
      if (request.headers.value('host') != '127.0.0.1:${_server.port}') {
        await _reply(response, HttpStatus.forbidden);
        return;
      }
      final isHead = request.method == 'HEAD';
      if (!isHead && request.method != 'GET') {
        await _reply(response, HttpStatus.methodNotAllowed);
        return;
      }
      final parts = request.uri.pathSegments;
      _Entry? entry;
      if (parts.length == 3 && parts[1] == 'a') {
        for (final e in _entries.values) {
          if (e.token == parts[0] && e.id == parts[2]) entry = e;
        }
      }
      if (entry == null) {
        await _reply(response, HttpStatus.notFound);
        return;
      }
      final rangeHeader = request.headers.value('range');
      // HttpServer cannot see a client leaving while we wait on upstream, so
      // the raw socket is owned from here on (one response per connection).
      socket = ctx.socket = await response.detachSocket(writeHeaders: false);
      _active.add(ctx);
      socket.listen(
        (_) {},
        onDone: ctx.abort,
        onError: (Object _) => ctx.abort(),
      );

      final total = entry.total ?? await _learnTotal(entry, ctx);
      final range = _parseRange(rangeHeader, total);
      if (range == null) {
        _head(socket, 416, 'Range Not Satisfiable', {
          'Content-Range': 'bytes */$total',
          'Content-Length': 0,
        });
        await socket.close();
        return;
      }
      final start = range[0], end = range[1];
      final partial = range[2] == 1;
      final headers = <String, Object>{
        'Content-Type': (entry.stream.mimeType ?? 'audio/webm').replaceAll(
          RegExp(r'[\r\n]'),
          '',
        ),
        'Accept-Ranges': 'bytes',
        'Content-Length': end - start + 1,
        if (partial) 'Content-Range': 'bytes $start-$end/$total',
      };
      void sendHead() {
        headersSent = true;
        _head(
          socket!,
          partial ? 206 : 200,
          partial ? 'Partial Content' : 'OK',
          headers,
        );
      }

      for (var pos = start; !isHead && pos <= end; pos += chunkBytes) {
        final last = min(pos + chunkBytes - 1, end);
        await _acquire();
        try {
          final upstream = await _open(entry, pos, last, ctx);
          if (!headersSent) sendHead();
          var got = 0;
          try {
            // Manual listen: abort() must cancel the body, because
            // HttpClientRequest.abort() is a no-op once headers arrived.
            final done = Completer<void>();
            void fail(Object error, [StackTrace? stack]) {
              if (!done.isCompleted) done.completeError(error, stack);
            }

            final sub = upstream
                .timeout(stallTimeout)
                .listen(null, cancelOnError: true);
            // Sin pausar el flujo: con la suscripción pausada, el socket TLS de
            // googlevideo hace que dart:io gire al 100 % de CPU mientras dura
            // la descarga. La memoria queda acotada por [chunkBytes] y el
            // vaciado se espera al final de cada tramo.
            sub.onData((data) {
              got += data.length;
              try {
                socket!.add(data);
              } catch (error, stack) {
                fail(error, stack);
                return;
              }
              // Mark before the flush: the player may hang up right after it.
              if (pos + got - 1 == total - 1) entry!.servedToEnd = true;
            });
            sub.onError(fail);
            sub.onDone(() {
              if (!done.isCompleted) done.complete();
            });
            ctx.cancelBody = () {
              sub.cancel();
              fail(_Fail(null, 'aborted'));
            };
            await done.future;
            ctx.cancelBody = null;
            await socket.flush();
            if (got != last - pos + 1) throw _Fail(null, 'premature EOF');
          } catch (_) {
            ctx.cancelBody?.call();
            ctx.upstream?.abort();
            rethrow;
          }
        } finally {
          _release();
        }
      }
      if (isHead) sendHead();
      if (!isHead && end == total - 1) entry.servedToEnd = true;
      ctx.finished = true;
      await socket.close();
    } catch (_) {
      ctx.upstream?.abort();
      try {
        if (socket != null && !headersSent && !ctx.aborted) {
          _head(socket, 410, 'Gone', {'Content-Length': 0});
          await socket.close();
        }
      } catch (_) {}
      // After headers the player sees a premature EOF / closed connection.
    } finally {
      ctx.finished = true;
      socket?.destroy();
      _active.remove(ctx);
    }
  }

  static void _head(Socket s, int status, String text, Map<String, Object> h) {
    final lines = h.entries.map((e) => '${e.key}: ${e.value}\r\n').join();
    s.write('HTTP/1.1 $status $text\r\n${lines}Connection: close\r\n\r\n');
  }

  static Future<void> _reply(HttpResponse response, int status) {
    response.statusCode = status;
    return response.close();
  }

  /// `[start, end, partial]` or null when unsatisfiable.
  static List<int>? _parseRange(String? header, int total) {
    if (header == null) return total == 0 ? null : [0, total - 1, 0];
    final m = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (m == null || (m[1]!.isEmpty && m[2]!.isEmpty)) return null;
    int start, end;
    if (m[1]!.isEmpty) {
      final n = int.parse(m[2]!);
      if (n == 0) return null;
      start = max(0, total - n);
      end = total - 1;
    } else {
      start = int.parse(m[1]!);
      end = m[2]!.isEmpty ? total - 1 : min(int.parse(m[2]!), total - 1);
    }
    if (start >= total || end < start) return null;
    return [start, end, 1];
  }

  Future<int> _learnTotal(_Entry entry, _Ctx ctx) async {
    await _acquire();
    try {
      final response = await _open(entry, 0, 0, ctx);
      final match = RegExp(
        r'/(\d+)$',
      ).firstMatch(response.headers.value('content-range') ?? '');
      if (match == null) throw _Fail(null, 'no total length');
      await response.drain<void>().timeout(stallTimeout);
      return entry.total ??= int.parse(match[1]!);
    } catch (_) {
      ctx.upstream?.abort();
      rethrow;
    } finally {
      _release();
    }
  }

  /// Opens one upstream chunk. Refreshes an expiring URL up front and, on
  /// 400/401/403/410 (googlevideo answers 400 to stale or mismatched URLs), reports once, refreshes (single-flight) and retries once.
  Future<HttpClientResponse> _open(_Entry entry, int a, int b, _Ctx ctx) async {
    var stream = entry.stream;
    if (stream.expiredAt(DateTime.now())) stream = await _renew(entry, stream);
    for (var attempt = 0; ; attempt++) {
      if (ctx.aborted || _closed) throw _Fail(null, 'aborted');
      HttpClientRequest? request;
      try {
        var target = stream.url;
        late HttpClientResponse response;
        // A redirect that cannot be followed: renewable like a stale URL.
        String? unfollowable;
        for (var hop = 0; ; hop++) {
          request = await _client.getUrl(target); // connectionTimeout bounds it
          ctx.upstream = request;
          if (ctx.aborted) request.abort();
          request.followRedirects = false;
          // El cuerpo se baja entero sin pausar; la conexión no debe quedar en
          // el pool a la espera de que el reproductor termine de leer.
          request.persistentConnection = false;
          request.headers
            ..set('range', 'bytes=$a-$b')
            ..set('accept-encoding', 'identity');
          for (final h in stream.headers.entries) {
            if (h.key.toLowerCase() == 'user-agent') {
              request.headers.set('user-agent', h.value);
            }
          }
          response = await request.close().timeout(headerTimeout);
          if (!_redirects.contains(response.statusCode)) break;
          // googlevideo's `rr*` front answers 302 to the cache node that
          // holds the file; the Range is repeated against the new URL.
          final location = response.headers.value('location');
          final next = location == null ? null : Uri.tryParse(location);
          request.abort();
          _discard(response);
          if (next == null) {
            unfollowable = 'redirect without a valid Location';
            break;
          }
          final to = target.resolve(next.toString());
          if (!allowRedirect(to)) {
            throw _Fail(response.statusCode, 'redirect to ${to.host} refused');
          }
          if (hop >= _maxRedirects) {
            unfollowable = 'too many redirects';
            break;
          }
          target = to;
        }
        final status = response.statusCode;
        if (unfollowable != null) {
          if (attempt == 0) {
            stream = await _renew(
              entry,
              stream,
              status: status,
              reason: unfollowable,
            );
            continue;
          }
          throw _Fail(status, unfollowable);
        }
        if (status == HttpStatus.partialContent) {
          final m = RegExp(
            r'^bytes (\d+)-(\d+)/',
          ).firstMatch(response.headers.value('content-range') ?? '');
          if (m == null ||
              int.parse(m[1]!) != a ||
              int.parse(m[2]!) != b ||
              (response.contentLength != -1 &&
                  response.contentLength != b - a + 1)) {
            _discard(response);
            throw _Fail(null, 'upstream range mismatch');
          }
          return response;
        }
        request.abort();
        _discard(response);
        // Other statuses (5xx, 416, ...) end as our 410 downstream.
        if (attempt == 0 && const {400, 401, 403, 410}.contains(status)) {
          stream = await _renew(
            entry,
            stream,
            status: status,
            reason: 'HTTP $status',
          );
          continue;
        }
        throw _Fail(status, 'HTTP $status');
      } catch (error) {
        request?.abort();
        if (error is _Fail) rethrow;
        throw _Fail(null, '$error');
      }
    }
  }

  Future<ResolvedStream> _renew(
    _Entry entry,
    ResolvedStream used, {
    int? status,
    String? reason,
  }) async {
    if (!identical(entry.stream, used)) return entry.stream; // already swapped
    var pending = entry.refreshing;
    if (pending == null) {
      if (reason != null) entry.onFailure?.call(status, reason);
      pending = entry.refreshing = entry
          .refresh()
          .then((fresh) {
            final known = entry.total;
            if (known != null &&
                fresh.contentLength != null &&
                fresh.contentLength != known) {
              throw _Fail(null, 'content length changed');
            }
            entry
              ..stream = fresh
              ..total ??= fresh.contentLength;
            return fresh;
          })
          .whenComplete(() => entry.refreshing = null);
    }
    try {
      return await pending;
    } catch (error) {
      throw error is _Fail ? error : _Fail(null, 'refresh failed: $error');
    }
  }
}

/// abort() is a no-op once headers arrived; drop the socket instead of
/// letting an unread body hold the upstream connection.
void _discard(HttpClientResponse response) {
  unawaited(
    response.detachSocket().then((s) => s.destroy(), onError: (Object _) {}),
  );
}

class _Entry {
  _Entry(
    this.videoId,
    this.token,
    this.id,
    this.stream,
    this.refresh,
    this.onFailure,
  ) : total = stream.contentLength;

  final String videoId;
  final String token;
  final String id;
  final Future<ResolvedStream> Function() refresh;
  final void Function(int? status, String reason)? onFailure;
  ResolvedStream stream;
  int? total;
  bool servedToEnd = false;
  Future<ResolvedStream>? refreshing;
}

class _Ctx {
  HttpClientRequest? upstream;
  Socket? socket;
  void Function()? cancelBody;
  bool aborted = false;
  bool finished = false;

  /// Client gone or proxy closing: stop upstream and drop the connection.
  void abort() {
    if (finished) return;
    aborted = true;
    cancelBody?.call();
    upstream?.abort();
    socket?.destroy();
  }
}

class _Fail implements Exception {
  _Fail(this.status, this.reason);
  final int? status;
  final String reason;

  @override
  String toString() => reason;
}
