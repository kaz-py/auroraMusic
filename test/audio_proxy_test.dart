import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_music/sources/stream/audio_proxy.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Upstream stand-in with Range support, request log and failure toggles.
class FakeUpstream {
  FakeUpstream(int length) : data = Uint8List(length) {
    for (var i = 0; i < length; i++) {
      data[i] = (i * 7 + 3) % 251;
    }
  }

  final Uint8List data;
  late final HttpServer server;
  final log = <Map<String, String>>[];
  final forbid = <String>{}; // always 403
  final redirect = <String, String>{}; // path -> 302 Location
  final forbidAfterFirst = <String>{}; // 403 unless range starts at 0
  final failWith500 = <String>{};
  final badRequest = <String>{}; // always 400, like a stale signed URL
  final hangHeaders = <String>{};
  final hangBody = <String>{}; // half a chunk, then silence
  Completer<void>? gate; // holds requests whose range start > 0

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) => unawaited(_handle(r)));
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${server.port}/$path');
  int hung = 0; // detached sockets: HttpServer stops watching those
  int get openSockets => server.connectionsInfo().total + hung;
  int requestsFor(String path) => log.where((l) => l[':path'] == path).length;

  Future<void> _hang(
    HttpRequest r, {
    required bool writeHeaders,
    List<int> body = const [],
  }) async {
    final socket = await r.response.detachSocket(writeHeaders: writeHeaders);
    hung++;
    socket.add(body);
    var counted = true;
    void gone() {
      if (counted) hung--;
      counted = false;
    }

    socket.listen((_) {}, onDone: gone, onError: (Object _) => gone());
  }

  Future<void> _handle(HttpRequest r) async {
    final path = r.uri.path.substring(1);
    final entry = <String, String>{':path': path};
    r.headers.forEach((name, values) => entry[name] = values.join(','));
    log.add(entry);
    final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(entry['range'] ?? '')!;
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    if (redirect.containsKey(path)) {
      r.response
        ..statusCode = 302
        ..headers.set('location', redirect[path]!);
      await r.response.close();
      return;
    }
    if (hangHeaders.contains(path)) return _hang(r, writeHeaders: false);
    if (forbid.contains(path) || (forbidAfterFirst.contains(path) && a > 0)) {
      r.response.statusCode = 403;
      await r.response.close();
      return;
    }
    if (badRequest.contains(path)) {
      r.response.statusCode = 400;
      await r.response.close();
      return;
    }
    if (failWith500.contains(path)) {
      r.response.statusCode = 500;
      await r.response.close();
      return;
    }
    if (a > 0 && gate != null) await gate!.future;
    final slice = data.sublist(a, b + 1);
    r.response
      ..statusCode = 206
      ..headers.set('content-range', 'bytes $a-$b/${data.length}')
      ..headers.contentLength = slice.length;
    if (hangBody.contains(path)) {
      return _hang(
        r,
        writeHeaders: true,
        body: slice.sublist(0, slice.length ~/ 2),
      );
    }
    r.response.add(slice);
    await r.response.close();
  }
}

class Got {
  Got(this.status, this.headers, this.body);
  final int status;
  final HttpHeaders headers;
  final List<int> body;
}

void main() {
  const chunk = 1024;
  late FakeUpstream up;
  late AudioProxy proxy;
  late HttpClient http;

  Future<void> startProxy({
    int chunkBytes = chunk,
    int maxUpstream = 6,
    Duration header = const Duration(seconds: 5),
    Duration stall = const Duration(seconds: 5),
    bool Function(Uri)? allowRedirect,
  }) async {
    proxy = await AudioProxy.start(
      chunkBytes: chunkBytes,
      maxUpstream: maxUpstream,
      headerTimeout: header,
      stallTimeout: stall,
      allowRedirect: allowRedirect,
    );
  }

  ResolvedStream stream({
    String path = 's1',
    String id = 'vid',
    int? length = -1,
    Duration life = const Duration(hours: 1),
  }) => ResolvedStream(
    videoId: id,
    url: up.url(path),
    headers: const {'User-Agent': 'UA/1'},
    expiresAt: DateTime.now().add(life),
    client: 'test',
    itag: 251,
    backend: StreamBackend.proxy,
    mimeType: 'audio/webm',
    contentLength: length == -1 ? up.data.length : length,
  );

  Uri register(
    ResolvedStream s, {
    Future<ResolvedStream> Function()? refresh,
    void Function(int?, String)? onFailure,
  }) => proxy.register(
    s.videoId,
    s,
    refresh: refresh ?? () async => stream(),
    onFailure: onFailure,
  );

  Future<Got> fetch(Uri u, {String? range, String method = 'GET'}) async {
    final req = await http.openUrl(method, u);
    if (range != null) req.headers.set('range', range);
    final res = await req.close();
    final body = <int>[];
    await for (final c in res) {
      body.addAll(c);
    }
    return Got(res.statusCode, res.headers, body);
  }

  Future<void> eventually(bool Function() ok) async {
    for (var i = 0; i < 300 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      ok(),
      isTrue,
      reason: "open sockets: ${up.server.connectionsInfo().total}",
    );
  }

  setUp(() async {
    up = FakeUpstream(5000);
    await up.start();
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await eventually(() => proxy.activeConnections == 0);
    await proxy.close();
    await eventually(() => up.openSockets == 0); // no leaked sockets
    await up.server.close(force: true);
  });

  test('url shape and token stable per video', () async {
    await startProxy();
    final a = register(stream());
    final again = register(stream());
    final other = register(stream(id: 'other'));
    expect(
      a.toString(),
      matches(RegExp(r'^http://127\.0\.0\.1:\d+/[0-9a-f]{32}/a/[0-9a-f]{16}$')),
    );
    expect(again, a);
    expect(other.pathSegments.first, isNot(a.pathSegments.first));
  });

  test('rejects bad host, token, id and methods', () async {
    await startProxy();
    final u = register(stream());
    final s = await Socket.connect('127.0.0.1', u.port);
    s.write('GET ${u.path} HTTP/1.1\r\nHost: localhost:${u.port}\r\n\r\n');
    final head = await s
        .cast<List<int>>()
        .transform(systemEncoding.decoder)
        .first;
    expect(head, startsWith('HTTP/1.1 403'));
    s.destroy();
    final p = u.pathSegments;
    expect(
      (await fetch(u.replace(path: '/${'0' * 32}/a/${p[2]}'))).status,
      404,
    );
    expect(
      (await fetch(u.replace(path: '/${p[0]}/a/${'0' * 16}'))).status,
      404,
    );
    expect((await fetch(u.replace(path: '/${p[0]}/b/${p[2]}'))).status, 404);
    expect((await fetch(u, method: 'POST')).status, 405);
    expect(up.log, isEmpty);
  });

  test('no range: 200 full body through bounded chunks', () async {
    await startProxy();
    final r = await fetch(register(stream()));
    expect(r.status, 200);
    expect(r.headers.contentLength, 5000);
    expect(r.body, up.data);
    expect(up.log.map((l) => l['range']), [
      'bytes=0-1023',
      'bytes=1024-2047',
      'bytes=2048-3071',
      'bytes=3072-4095',
      'bytes=4096-4999',
    ]);
  });

  test('206 for open, closed and suffix ranges', () async {
    await startProxy();
    final u = register(stream());
    var r = await fetch(u, range: 'bytes=3000-');
    expect(r.status, 206);
    expect(r.headers.value('content-range'), 'bytes 3000-4999/5000');
    expect(r.body, up.data.sublist(3000));
    r = await fetch(u, range: 'bytes=100-2500');
    expect(r.headers.value('content-range'), 'bytes 100-2500/5000');
    expect(r.body, up.data.sublist(100, 2501));
    r = await fetch(u, range: 'bytes=-700');
    expect(r.status, 206);
    expect(r.headers.value('content-range'), 'bytes 4300-4999/5000');
    expect(r.body, up.data.sublist(4300));
    r = await fetch(u, range: 'bytes=4990-9999');
    expect(r.headers.value('content-range'), 'bytes 4990-4999/5000');
  });

  test('416 when start is past the end', () async {
    await startProxy();
    final r = await fetch(register(stream()), range: 'bytes=5000-');
    expect(r.status, 416);
    expect(r.headers.value('content-range'), 'bytes */5000');
  });

  test('forwards only range, accept-encoding and stream user-agent', () async {
    await startProxy();
    final u = register(stream());
    final req = await http.getUrl(u);
    req.headers
      ..set('cookie', 'a=b')
      ..set('referer', 'https://x')
      ..set('authorization', 'secret')
      ..set('user-agent', 'Player/9');
    await (await req.close()).drain<void>();
    const allowed = {
      ':path',
      'range',
      'accept-encoding',
      'user-agent',
      'host',
      'connection',
    };
    for (final l in up.log) {
      expect(l.keys.toSet().difference(allowed), isEmpty);
      expect(l['user-agent'], 'UA/1');
      expect(l['accept-encoding'], 'identity');
    }
  });

  test(
    'unknown length is learned with bytes=0-0, HEAD needs no body',
    () async {
      await startProxy();
      final u = register(stream(length: null));
      final head = await fetch(u, method: 'HEAD');
      expect(head.status, 200);
      expect(head.headers.contentLength, 5000);
      expect(up.log.map((l) => l['range']), ['bytes=0-0']);
      final r = await fetch(u, range: 'bytes=10-20');
      expect(r.body, up.data.sublist(10, 21));
      expect(up.log.where((l) => l['range'] == 'bytes=0-0'), hasLength(1));
    },
  );

  test('expiring URL is refreshed before the first chunk', () async {
    await startProxy();
    var refreshes = 0;
    final u = register(
      stream(path: 'old', life: const Duration(seconds: 10)),
      refresh: () async {
        refreshes++;
        return stream(path: 'new');
      },
    );
    final r = await fetch(u);
    expect(r.body, up.data);
    expect(refreshes, 1);
    expect(up.requestsFor('old'), 0);
    expect(proxy.current('vid')!.url.path, '/new');
  });

  test('403 mid-stream: report once, refresh once, retry same chunk', () async {
    await startProxy();
    up.forbidAfterFirst.add('old');
    final failures = <int?>[];
    var refreshes = 0;
    final u = register(
      stream(path: 'old'),
      onFailure: (status, _) => failures.add(status),
      refresh: () async {
        refreshes++;
        return stream(path: 'new');
      },
    );
    final r = await fetch(u);
    expect(r.status, 200);
    expect(r.body, up.data);
    expect(failures, [403]);
    expect(refreshes, 1);
    expect(
      up.log.where((l) => l[':path'] == 'new').first['range'],
      'bytes=1024-2047',
    );
  });

  test('400 on a stale URL is refreshed once like a 403', () async {
    await startProxy();
    up.badRequest.add('old');
    final failures = <int?>[];
    final u = register(
      stream(path: 'old'),
      onFailure: (status, _) => failures.add(status),
      refresh: () async => stream(path: 'new'),
    );
    final r = await fetch(u);
    expect(r.status, 200);
    expect(r.body, up.data);
    expect(failures, [400]);
  });

  test('403 twice before headers answers 410, reports once', () async {
    await startProxy();
    up.forbid.addAll(['old', 'new']);
    final failures = <int?>[];
    final u = register(
      stream(path: 'old'),
      onFailure: (status, _) => failures.add(status),
      refresh: () async => stream(path: 'new'),
    );
    final r = await fetch(u);
    expect(r.status, 410);
    expect(failures, [403]);
    expect(up.log, hasLength(2));
  });

  test(
    'failed refresh and changed length answer 410 without 2nd report',
    () async {
      await startProxy();
      up.forbid.addAll(['old', 'old2']);
      var failures = 0;
      final broken = register(
        stream(path: 'old'),
        onFailure: (_, _) => failures++,
        refresh: () async => throw const SocketException('offline'),
      );
      expect((await fetch(broken)).status, 410);
      expect(failures, 1);
      final changed = register(
        stream(path: 'old2', id: 'v2'),
        onFailure: (_, _) => failures++,
        refresh: () async => stream(path: 'new', id: 'v2', length: 4999),
      );
      expect((await fetch(changed)).status, 410);
      expect(failures, 2);
    },
  );

  test('failure after headers aborts the socket', () async {
    await startProxy();
    up.forbidAfterFirst.addAll(['old', 'new']);
    final u = register(
      stream(path: 'old'),
      refresh: () async => stream(path: 'new'),
    );
    await expectLater(fetch(u), throwsA(anything));
  });

  test('concurrent requests share one refresh', () async {
    await startProxy();
    up.forbid.add('old');
    final release = Completer<void>();
    var refreshes = 0;
    var failures = 0;
    final u = register(
      stream(path: 'old'),
      onFailure: (_, _) => failures++,
      refresh: () async {
        refreshes++;
        await release.future;
        return stream(path: 'new');
      },
    );
    final all = Future.wait([fetch(u), fetch(u), fetch(u)]);
    await eventually(() => up.requestsFor('old') == 3);
    release.complete();
    for (final r in await all) {
      expect(r.body, up.data);
    }
    expect(refreshes, 1);
    expect(failures, 1);
  });

  test('client disconnect aborts upstream', () async {
    await startProxy();
    up.hangBody.add('s1');
    final req = await http.getUrl(register(stream()));
    final res = await req.close();
    await res.first; // some bytes arrived; upstream now silent
    expect(up.openSockets, greaterThan(0));
    http.close(force: true);
    await eventually(() => up.openSockets == 0);
  });

  test('stall timeout aborts a silent upstream', () async {
    await startProxy(stall: const Duration(milliseconds: 150));
    up.hangBody.add('s1');
    await expectLater(fetch(register(stream())), throwsA(anything));
    await eventually(() => up.openSockets == 0);
  });

  test('header timeout answers 410', () async {
    await startProxy(header: const Duration(milliseconds: 150));
    up.hangHeaders.add('s1');
    expect((await fetch(register(stream()))).status, 410);
    await eventually(() => up.openSockets == 0);
  });

  test('unregister keeps in-flight requests, blocks new ones', () async {
    await startProxy();
    up.gate = Completer<void>();
    final u = register(stream());
    final inFlight = fetch(u);
    await eventually(() => up.log.length == 2);
    proxy.unregister('vid');
    expect(proxy.current('vid'), isNull);
    expect((await fetch(u)).status, 404);
    up.gate!.complete();
    expect((await inFlight).body, up.data);
  });

  test('registry keeps the 64 newest videos', () async {
    await startProxy();
    final urls = [for (var i = 0; i < 65; i++) register(stream(id: 'v$i'))];
    expect(proxy.current('v0'), isNull);
    expect(proxy.current('v1'), isNotNull);
    expect((await fetch(urls.first)).status, 404);
    expect((await fetch(urls.last, range: 'bytes=0-9')).status, 206);
  });

  test('close aborts in-flight work and rejects registration', () async {
    await startProxy();
    up.hangBody.add('s1');
    final req = await http.getUrl(register(stream()));
    final res = await req.close();
    await res.first;
    final done = () async {
      try {
        await res.drain<void>();
        return null;
      } catch (e) {
        return e;
      }
    }();
    await proxy.close();
    expect(await done, isNotNull);
    await eventually(() => up.openSockets == 0);
    expect(() => register(stream()), throwsStateError);
    await proxy.close();
  });

  test('servedToEnd only after the last byte was written', () async {
    await startProxy();
    expect(proxy.servedToEnd('vid'), isNull);
    final u = register(stream());
    await fetch(u, range: 'bytes=0-2000');
    expect(proxy.servedToEnd('vid'), isFalse);
    await fetch(u, method: 'HEAD');
    expect(proxy.servedToEnd('vid'), isFalse);
    await fetch(u, range: 'bytes=4000-');
    await eventually(
      () => proxy.servedToEnd('vid') == true,
    ); // set right after flush
    expect(proxy.servedToEnd('nope'), isNull);
    // A new registration starts clean; an aborted read never counts.
    up.hangBody.add('s2');
    final u2 = register(stream(path: 's2'));
    final res = await (await http.getUrl(u2)).close();
    await res.first;
    http.close(force: true);
    http = HttpClient();
    await eventually(() => proxy.activeConnections == 0);
    expect(proxy.servedToEnd('vid'), isFalse);
  });

  test('upstream 206 that does not match the request is refused', () async {
    await startProxy();
    final bad = up.data;
    final rogue = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => rogue.close(force: true));
    rogue.listen((r) async {
      r.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes 5-1028/5000')
        ..headers.contentLength = 1024
        ..add(bad.sublist(5, 1029));
      await r.response.close();
    });
    final s = stream();
    final u = register(
      ResolvedStream(
        videoId: 'vid',
        url: Uri.parse('http://127.0.0.1:${rogue.port}/x'),
        expiresAt: s.expiresAt,
        client: 'test',
        itag: 251,
        contentLength: 5000,
      ),
    );
    expect((await fetch(u)).status, 410);
  });

  test('slow reader gets backpressure, no stall while paused', () async {
    await up.server.close(force: true);
    up = FakeUpstream(16 << 20);
    await up.start();
    await startProxy(
      chunkBytes: 1 << 20,
      stall: const Duration(milliseconds: 200),
    );
    final u = register(stream());
    final socket = await Socket.connect('127.0.0.1', u.port);
    var received = 0;
    final sub = socket.listen((d) => received += d.length);
    socket.write('GET ${u.path} HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\n\r\n');
    await eventually(() => received > 0);
    sub.pause();
    await Future<void>.delayed(const Duration(milliseconds: 700)); // > 3 stalls
    expect(proxy.activeConnections, 1);
    expect(up.log.length, lessThan(16)); // proxy did not read ahead unbounded
    sub.resume();
    await eventually(() => received >= (16 << 20));
    await eventually(() => proxy.servedToEnd('vid') == true);
    expect(up.log, hasLength(16));
    socket.destroy();
  });

  test(
    'client leaving during a pending flush raises no uncaught error',
    () async {
      final errors = <Object>[];
      final done = Completer<void>();
      runZonedGuarded(() async {
        try {
          await up.server.close(force: true);
          up = FakeUpstream(16 << 20);
          await up.start();
          await startProxy(chunkBytes: 1 << 20);
          final u = register(stream());
          final socket = await Socket.connect('127.0.0.1', u.port);
          final sub = socket.listen((_) {});
          socket.write(
            'GET ${u.path} HTTP/1.1\r\nHost: 127.0.0.1:${u.port}\r\n\r\n',
          );
          await eventually(() => up.log.isNotEmpty);
          sub.pause();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          socket.destroy();
          await eventually(() => proxy.activeConnections == 0);
          await eventually(() => up.openSockets == 0);
          await Future<void>.delayed(const Duration(milliseconds: 100));
          done.complete();
        } catch (e, s) {
          done.completeError(e, s);
        }
      }, (e, s) => errors.add(e));
      await done.future;
      expect(errors, isEmpty);
    },
  );

  test('upstream slot is released after errors', () async {
    await startProxy(maxUpstream: 1);
    up.failWith500.add('bad');
    final bad = register(stream(path: 'bad', id: 'bad'));
    for (var i = 0; i < 3; i++) {
      expect((await fetch(bad)).status, 410);
    }
    final ok = register(stream(id: 'good'));
    expect((await fetch(ok)).body, up.data);
  });

  // googlevideo `rr*` fronts answer 302 to the cache node holding the file.
  group('redirects', () {
    bool loopbackOnly(Uri u) => u.host == '127.0.0.1';

    test('302 to an allowed host is followed and served as 206', () async {
      await startProxy(allowRedirect: loopbackOnly);
      up.redirect['front'] = up.url('node').toString();
      var refreshed = 0;
      final u = register(
        stream(path: 'front'),
        refresh: () async {
          refreshed++;
          return stream(path: 'front');
        },
      );
      final got = await fetch(u, range: 'bytes=10-1999');
      expect(got.status, 206);
      expect(got.body, up.data.sublist(10, 2000));
      expect(refreshed, 0);
      // Every hop repeats the exact Range and the player UA.
      final node = up.log.where((l) => l[':path'] == 'node').toList();
      expect(node.first['range'], 'bytes=10-1033');
      expect(node.first['user-agent'], 'UA/1');
      expect(up.requestsFor('front'), up.requestsFor('node'));
    });

    test('redirect to a non-googlevideo host is refused', () async {
      await startProxy();
      up.redirect['front'] = 'https://evil.example.com/steal';
      var refreshed = 0;
      final u = register(
        stream(path: 'front'),
        refresh: () async {
          refreshed++;
          return stream(path: 'front');
        },
      );
      expect((await fetch(u, range: 'bytes=0-99')).status, 410);
      expect(up.requestsFor('front'), 1);
      expect(refreshed, 0);
    });

    test('default policy accepts only https googlevideo hosts', () async {
      await startProxy(); // tearDown expects a running proxy
      expect(
        AudioProxy.isGoogleVideoRedirect(
          Uri.parse('https://rr1---sn-abc.googlevideo.com/videoplayback?x=1'),
        ),
        isTrue,
      );
      for (final bad in [
        'http://rr1---sn-a.googlevideo.com/videoplayback',
        'https://googlevideo.com.evil.example/videoplayback',
        'https://evil.example/rr1---sn-a.googlevideo.com',
        'https://u:p@rr1---sn-a.googlevideo.com/videoplayback',
        'https://rr1---sn-a.googlevideo.com:8443/videoplayback',
      ]) {
        expect(
          AudioProxy.isGoogleVideoRedirect(Uri.parse(bad)),
          isFalse,
          reason: bad,
        );
      }
    });

    test('redirect loop is bounded, renews once and ends as 410', () async {
      await startProxy(allowRedirect: loopbackOnly);
      up.redirect['a'] = up.url('b').toString();
      up.redirect['b'] = up.url('a').toString();
      var refreshed = 0;
      final reasons = <String>[];
      final u = register(
        stream(path: 'a'),
        refresh: () async {
          refreshed++;
          return stream(path: 'a');
        },
        onFailure: (s, r) => reasons.add('$s $r'),
      );
      expect((await fetch(u, range: 'bytes=0-99')).status, 410);
      expect(refreshed, 1);
      expect(reasons, ['302 too many redirects']);
      expect(up.log.length, 12); // (1 + 5 hops) x 2 attempts, no endless chase
    });
  });
}
