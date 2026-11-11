import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/sources/stream/player_clients.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';
import 'package:aurora_music/sources/youtube_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = PlayerClient(
  name: 'A',
  version: '1',
  id: 11,
  userAgent: 'UA-A',
  extraClient: {'osName': 'os-a'},
);
const _b = PlayerClient(name: 'B', version: '2', id: 22, userAgent: 'UA-B');

Map<String, dynamic> _fmt(
  int itag, {
  String mime = 'audio/webm; codecs="opus"',
  String quality = 'AUDIO_QUALITY_MEDIUM',
  Object? clen = '1000',
  int bitrate = 100,
  Map<String, dynamic>? track,
  bool cipher = false,
}) => {
  'itag': itag,
  'mimeType': mime,
  'audioQuality': quality,
  'bitrate': bitrate,
  'contentLength': ?clen,
  'audioTrack': ?track,
  if (cipher)
    'signatureCipher': 's=x&url=y'
  else
    'url': 'https://g/v?itag=$itag',
};

Map<String, dynamic> _ok(List<Map<String, dynamic>> formats) => {
  'playabilityStatus': {'status': 'OK'},
  'streamingData': {'expiresInSeconds': '21540', 'adaptiveFormats': formats},
};

Map<String, dynamic> _status(String status, [String reason = '']) => {
  'playabilityStatus': {'status': status, 'reason': reason},
};

class _Harness {
  _Harness({
    List<PlayerClient> clients = const [_a, _b],
    AudioQuality quality = AudioQuality.high,
  }) {
    orch = StreamOrchestrator(
      clients: clients,
      quality: quality,
      now: () => now,
      post: (url, headers, body) async {
        final client =
            (body['context'] as Map)['client']['clientName'] as String;
        posts.add((url: url, headers: headers, body: body, client: client));
        await gate?.future;
        return respond(client, body['videoId'] as String);
      },
      get: (url, headers, {timeout = const Duration(seconds: 10)}) async {
        gets.add((url: url, headers: headers));
        if (url.path == '/sw.js_data') {
          return HttpGetResult(
            swStatus,
            body: utf8.encode(')]}\'\n[[["x"],["en","Cgtvisitor%3D","Cgs2"]]]'),
          );
        }
        final error = probeError;
        if (error != null &&
            (probeErrorUa == null || probeErrorUa == headers['User-Agent'])) {
          throw error;
        }
        return HttpGetResult(probe(headers['User-Agent']!));
      },
    );
  }

  late final StreamOrchestrator orch;
  var now = DateTime.utc(2026, 1, 1);
  Completer<void>? gate;
  final posts =
      <
        ({
          Uri url,
          Map<String, String> headers,
          Map<String, Object?> body,
          String client,
        })
      >[];
  final gets = <({Uri url, Map<String, String> headers})>[];
  Map<String, dynamic> Function(String client, String video) respond = (_, _) =>
      _ok([_fmt(251)]);
  int Function(String userAgent) probe = (_) => 206;
  Object? probeError;
  String? probeErrorUa; // null: every client
  int swStatus = 200;

  /// Client of the first post made by a fresh resolve.
  Future<String> firstClient(String video) async {
    final before = posts.length;
    await orch.resolve(video, forceRefresh: true);
    return posts[before].client;
  }
}

void _expireTest() {
  test('expiresAt honours an earlier signed `expire` of the URL', () async {
    final h = _Harness();
    final unix =
        h.now.add(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;
    h.respond = (_, _) => _ok([
      {..._fmt(251, clen: 1000), 'url': 'https://g/v?itag=251&expire=$unix'},
    ]);
    final s = await h.orch.resolve('vid1');
    expect(s.expiresAt, h.now.add(const Duration(minutes: 5)));
  });
}

Future<StreamResolveException> _failure(Future<ResolvedStream> f) async {
  try {
    await f;
  } on StreamResolveException catch (e) {
    return e;
  }
  throw StateError('resolve should have failed');
}

void main() {
  _expireTest();
  test('VISIONOS request shape and visitorData', () async {
    final h = _Harness(clients: defaultPlayerClients);
    final s = await h.orch.resolve('vid1');
    final p = h.posts.single;
    expect(
      p.url.toString(),
      'https://music.youtube.com/youtubei/v1/player?prettyPrint=false',
    );
    expect(p.url.queryParameters.containsKey('key'), isFalse);
    expect(p.headers['x-youtube-client-name'], '101');
    expect(p.headers['x-youtube-client-version'], '0.1');
    expect(p.headers['x-goog-api-format-version'], '1');
    expect(p.headers['x-origin'], 'https://music.youtube.com');
    expect(p.headers['referer'], 'https://music.youtube.com/');
    expect(p.headers['user-agent'], contains('Safari/605'));
    expect(p.headers['x-goog-visitor-id'], 'Cgtvisitor%3D');
    final body = p.body;
    final client = (body['context'] as Map)['client'] as Map;
    expect(client, {
      'clientName': 'VISIONOS',
      'clientVersion': '0.1',
      'osName': 'visionOS',
      'osVersion': '1.3.21O771',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice14,1',
      'gl': 'US',
      'hl': 'en',
      'visitorData': 'Cgtvisitor%3D',
    });
    expect((body['context'] as Map)['request'], {
      'internalExperimentFlags': [],
      'useSsl': true,
    });
    expect((body['context'] as Map)['user'], {'lockedSafetyMode': false});
    expect(body['videoId'], 'vid1');
    expect(body['contentCheckOk'], isTrue);
    expect(body['racyCheckOk'], isTrue);
    expect(s.headers, {'User-Agent': defaultPlayerClients.first.userAgent});
    expect(s.client, 'VISIONOS');
    expect(s.expiresAt, h.now.add(const Duration(seconds: 21540)));
    expect(s.backend, StreamBackend.direct);
    // visitorData is fetched once per process.
    await h.orch.resolve('vid2');
    expect(h.gets.where((g) => g.url.path == '/sw.js_data'), hasLength(1));
  });

  test(
    'tail probe uses the last 256 bytes, identity encoding and UA',
    () async {
      final h = _Harness();
      await h.orch.resolve('v');
      final probe = h.gets.last;
      expect(probe.headers['Range'], 'bytes=744-999');
      expect(probe.headers['Accept-Encoding'], 'identity');
      expect(probe.headers['User-Agent'], 'UA-A');
    },
  );

  test('probe network error costs the client 2 min', () async {
    final h = _Harness()
      ..probeError = const SocketException('down')
      ..probeErrorUa = 'UA-A';
    expect((await h.orch.resolve('v1')).client, 'B');
    h.probeError = null;
    expect(await h.firstClient('v2'), 'B');
    h.now = h.now.add(const Duration(minutes: 3));
    expect(await h.firstClient('v3'), 'A');
  });

  test('length <= 256 probes from byte 0', () async {
    final h = _Harness()..respond = (_, _) => _ok([_fmt(1, clen: '100')]);
    await h.orch.resolve('v');
    expect(h.gets.last.headers['Range'], 'bytes=0-99');
  });

  test('visitorData failure is not cached and retried', () async {
    final h = _Harness()..swStatus = 500;
    await h.orch.resolve('v');
    expect(h.posts.last.headers.containsKey('x-goog-visitor-id'), isFalse);
    h.swStatus = 200;
    await h.orch.resolve('v', forceRefresh: true);
    expect(h.posts.last.headers['x-goog-visitor-id'], 'Cgtvisitor%3D');
    expect(h.gets.where((g) => g.url.path == '/sw.js_data'), hasLength(2));
  });

  test('forceRefresh with sameItag returns that itag', () async {
    final h = _Harness()
      ..respond = (_, _) =>
          _ok([_fmt(251), _fmt(140, mime: 'audio/mp4; codecs="mp4a.40.2"')]);
    expect((await h.orch.resolve('v')).itag, 251);
    expect(
      (await h.orch.resolve('v', forceRefresh: true, sameItag: 140)).itag,
      140,
    );
  });

  test('failed forceRefresh keeps the cached stream', () async {
    final h = _Harness();
    final first = await h.orch.resolve('v');
    h.respond = (_, _) => throw const SocketException('down');
    await _failure(h.orch.resolve('v', forceRefresh: true));
    expect(await h.orch.resolve('v'), same(first));
  });

  test('malformed url is skipped without aborting clients', () async {
    final h = _Harness()
      ..respond = (_, _) => _ok([
        {..._fmt(1, quality: 'AUDIO_QUALITY_HIGH'), 'url': 'http://[bad'},
        _fmt(2),
      ]);
    expect((await h.orch.resolve('v')).itag, 2);
  });

  test('tracks without audioIsDefault still resolve', () async {
    final h = _Harness()
      ..respond = (_, _) => _ok([
        _fmt(1, track: {'id': 'en'}),
        _fmt(2, track: {'isAutoDubbed': true}),
      ]);
    expect((await h.orch.resolve('v')).itag, 1);
  });

  group('format selection', () {
    Future<int> pick(
      List<Map<String, dynamic>> formats, {
      AudioQuality quality = AudioQuality.high,
      int? sameItag,
    }) async {
      final h = _Harness(quality: quality)..respond = (_, _) => _ok(formats);
      return (await h.orch.resolve('v', sameItag: sameItag)).itag;
    }

    final mp4 = 'audio/mp4; codecs="mp4a.40.2"';

    test('skips cipher formats and non-audio', () async {
      expect(
        await pick([
          _fmt(1, cipher: true, quality: 'AUDIO_QUALITY_HIGH'),
          _fmt(2, mime: 'video/mp4; codecs="avc1"'),
          _fmt(3, quality: 'AUDIO_QUALITY_LOW'),
        ]),
        3,
      );
      final h = _Harness()..respond = (_, _) => _ok([_fmt(1, cipher: true)]);
      expect((await _failure(h.orch.resolve('v'))).kind, YouTubeFailure.other);
    });

    test('skips formats without contentLength', () async {
      expect(
        await pick([
          _fmt(1, clen: null, quality: 'AUDIO_QUALITY_HIGH'),
          _fmt(2),
        ]),
        2,
      );
    });

    test('ranks quality, then codec, then bitrate', () async {
      expect(
        await pick([
          _fmt(251),
          _fmt(140, mime: mp4, quality: 'AUDIO_QUALITY_HIGH'),
        ]),
        140,
      );
      expect(await pick([_fmt(140, mime: mp4), _fmt(251)]), 251);
      expect(await pick([_fmt(251, bitrate: 50), _fmt(250, bitrate: 90)]), 250);
    });

    test('quality picks the itag per preset', () async {
      final formats = [
        _fmt(140, mime: mp4, bitrate: 130000),
        _fmt(251, bitrate: 160000),
        _fmt(250, bitrate: 70000),
        _fmt(249, bitrate: 50000),
        _fmt(139, mime: mp4, bitrate: 48000),
      ];
      expect(await pick(formats), 251);
      expect(await pick(formats, quality: AudioQuality.normal), 140);
      expect(await pick(formats, quality: AudioQuality.saver), 249);
    });

    test('changing quality drops cached streams', () async {
      final h = _Harness()
        ..respond = (_, _) =>
            _ok([_fmt(251, bitrate: 160000), _fmt(249, bitrate: 50000)]);
      expect((await h.orch.resolve('v')).itag, 251);
      h.orch.quality = AudioQuality.saver;
      expect((await h.orch.resolve('v')).itag, 249);
    });

    test('skips dubbed audio tracks', () async {
      expect(
        await pick([
          _fmt(
            1,
            quality: 'AUDIO_QUALITY_HIGH',
            track: {'audioIsDefault': false},
          ),
          _fmt(
            2,
            quality: 'AUDIO_QUALITY_HIGH',
            track: {'audioIsDefault': true, 'isAutoDubbed': true},
          ),
          _fmt(3, track: {'audioIsDefault': true, 'isAutoDubbed': false}),
        ]),
        3,
      );
    });

    test('sameItag is preferred when present', () async {
      final formats = [_fmt(251), _fmt(140, mime: mp4)];
      expect(await pick(formats, sameItag: 140), 140);
      expect(await pick(formats, sameItag: 999), 251);
    });
  });

  test('LOGIN_REQUIRED moves to the next client', () async {
    final h = _Harness()
      ..respond = (c, _) =>
          c == 'A' ? _status('LOGIN_REQUIRED') : _ok([_fmt(7)]);
    final s = await h.orch.resolve('v');
    expect([s.client, s.itag], ['B', 7]);
    expect(h.posts.map((p) => p.client), ['A', 'B']);
  });

  test('tail probe 403 moves on and marks the client bad for 10 min', () async {
    final h = _Harness()..probe = (ua) => ua == 'UA-A' ? 403 : 206;
    expect((await h.orch.resolve('v1')).client, 'B');
    h.probe = (_) => 206;
    // A is bad: tried last, not removed.
    expect(await h.firstClient('v2'), 'B');
    h.now = h.now.add(const Duration(minutes: 9));
    expect(await h.firstClient('v3'), 'B');
    h.now = h.now.add(const Duration(minutes: 2));
    expect(await h.firstClient('v4'), 'A');
  });

  test('network error marks the client bad for 2 min only', () async {
    var fail = true;
    final h = _Harness()
      ..respond = (c, _) {
        if (c == 'A' && fail) throw const SocketException('down');
        return _ok([_fmt(1)]);
      };
    expect((await h.orch.resolve('v1')).client, 'B');
    fail = false;
    expect(await h.firstClient('v2'), 'B');
    h.now = h.now.add(const Duration(minutes: 3));
    expect(await h.firstClient('v3'), 'A');
  });

  test('bad clients are still tried when they are all that is left', () async {
    final h = _Harness(clients: [_a])..probe = (_) => 403;
    await _failure(h.orch.resolve('v'));
    h.probe = (_) => 206;
    expect((await h.orch.resolve('v')).client, 'A');
  });

  test('reportFailure TTL: 403 is 10 min, null status is 2 min', () async {
    final h = _Harness();
    await h.orch.resolve('v');
    h.orch.reportFailure('v', httpStatus: 403);
    expect(await h.firstClient('w'), 'B');
    h.now = h.now.add(const Duration(minutes: 3));
    expect(await h.firstClient('w2'), 'B');
    h.now = h.now.add(const Duration(minutes: 8));
    expect(await h.firstClient('w3'), 'A');

    h.orch.reportFailure('w3'); // no status: served by A, short penalty
    expect(await h.firstClient('x'), 'B');
    h.now = h.now.add(const Duration(minutes: 3));
    expect(await h.firstClient('y'), 'A');
  });

  group('cache', () {
    test('hit only while expiry exceeds now + 60 s + track duration', () async {
      final h = _Harness();
      final first = await h.orch.resolve('v');
      expect(await h.orch.resolve('v'), same(first));
      expect(h.posts, hasLength(1));
      // 21540 s lifetime vs. 6 h + 60 s needed.
      await h.orch.resolve('v', trackDuration: const Duration(hours: 6));
      expect(h.posts, hasLength(2));
      await h.orch.resolve('v', trackDuration: const Duration(hours: 1));
      expect(h.posts, hasLength(2));
      h.now = h.now.add(const Duration(seconds: 21540 - 59));
      await h.orch.resolve('v');
      expect(h.posts, hasLength(3));
    });

    test('forceRefresh bypasses the cache', () async {
      final h = _Harness();
      await h.orch.resolve('v');
      await h.orch.resolve('v', forceRefresh: true);
      expect(h.posts, hasLength(2));
    });

    test('LRU keeps 50 entries', () async {
      final h = _Harness();
      for (var i = 0; i < 51; i++) {
        await h.orch.resolve('v$i');
      }
      expect(h.posts, hasLength(51));
      await h.orch.resolve('v50');
      expect(h.posts, hasLength(51));
      await h.orch.resolve('v0'); // evicted
      expect(h.posts, hasLength(52));
    });
  });

  group('concurrency', () {
    test('10 concurrent resolves share one post', () async {
      final h = _Harness()..gate = Completer<void>();
      final futures = [for (var i = 0; i < 10; i++) h.orch.resolve('v')];
      await pumpEventQueue();
      h.gate!.complete();
      final results = await Future.wait(futures);
      expect(h.posts, hasLength(1));
      expect(results.toSet(), hasLength(1));
    });

    test('forced calls join only forced in-flight calls', () async {
      final h = _Harness()..gate = Completer<void>();
      final normal = h.orch.resolve('v');
      await pumpEventQueue();
      final forced1 = h.orch.resolve('v', forceRefresh: true);
      final forced2 = h.orch.resolve('v', forceRefresh: true);
      await pumpEventQueue();
      h.gate!.complete();
      await Future.wait([normal, forced1, forced2]);
      expect(h.posts, hasLength(2));
    });

    test('resolve after reportFailure does not join the stale one', () async {
      final h = _Harness()..gate = Completer<void>();
      final stale = h.orch.resolve('v');
      await pumpEventQueue();
      h.orch.reportFailure('v', httpStatus: 403);
      final fresh = h.orch.resolve('v');
      await pumpEventQueue();
      expect(h.posts, hasLength(2));
      h.gate!.complete();
      await Future.wait([stale, fresh]);
    });

    test('reportFailure during a resolve is not undone by it', () async {
      final h = _Harness()..gate = Completer<void>();
      final pending = h.orch.resolve('v');
      await pumpEventQueue();
      h.orch.reportFailure('v', httpStatus: 403);
      h.gate!.complete();
      await pending;
      expect(h.posts, hasLength(1));
      await h.orch.resolve('v'); // stale result was not cached
      expect(h.posts, hasLength(2));
    });
  });

  group('all clients fail', () {
    test('bot check: blocked', () async {
      final h = _Harness()
        ..respond = (_, _) =>
            _status('LOGIN_REQUIRED', "Sign in to confirm you're not a bot");
      final e = await _failure(h.orch.resolve('v'));
      expect(e.kind, YouTubeFailure.blocked);
      expect(YouTubeRequestPolicy.classify(e.message), YouTubeFailure.blocked);
    });

    test('probe 403 everywhere: accessDenied', () async {
      final h = _Harness()..probe = (_) => 403;
      final e = await _failure(h.orch.resolve('v'));
      expect(e.kind, YouTubeFailure.accessDenied);
      expect(
        YouTubeRequestPolicy.classify(e.message),
        YouTubeFailure.accessDenied,
      );
    });

    test('player 429 and 403 map to blocked / accessDenied', () async {
      for (final (code, kind) in [
        (429, YouTubeFailure.blocked),
        (403, YouTubeFailure.accessDenied),
      ]) {
        final h = _Harness()
          ..respond = (_, _) => throw HttpStatusException(code);
        final e = await _failure(h.orch.resolve('v'));
        expect(e.kind, kind);
        expect(YouTubeRequestPolicy.classify(e.message), kind);
      }
    });

    test('network errors: transient', () async {
      for (final error in [
        const SocketException('x'),
        TimeoutException('x'),
        const HttpStatusException(503),
      ]) {
        final h = _Harness()..respond = (_, _) => throw error;
        final e = await _failure(h.orch.resolve('v'));
        expect(e.kind, YouTubeFailure.transient);
        expect(
          YouTubeRequestPolicy.classify(e.message),
          YouTubeFailure.transient,
        );
      }
    });

    test('UNPLAYABLE: unavailable, stops early', () async {
      final h = _Harness()..respond = (_, _) => _status('UNPLAYABLE', 'x');
      final e = await _failure(h.orch.resolve('v'));
      expect(e.kind, YouTubeFailure.unavailable);
      expect(
        YouTubeRequestPolicy.classify(e.message),
        YouTubeFailure.unavailable,
      );
      expect(h.posts, hasLength(1));
    });

    test('other failures', () async {
      final h = _Harness()..respond = (_, _) => {'weird': true};
      final e = await _failure(h.orch.resolve('v'));
      expect(e.kind, YouTubeFailure.other);
    });
  });
}
