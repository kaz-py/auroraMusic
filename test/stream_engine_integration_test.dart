import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:aurora_music/sources/stream/audio_proxy.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _track = Track(
  id: 'yt:19y35jAcG6k',
  title: '120',
  artist: 'Bad Bunny',
  duration: Duration(seconds: 152),
  pageUrl: 'https://music.youtube.com/watch?v=19y35jAcG6k',
);

const _length = 300 * 1024;
const _chunk = 64 * 1024;

void main() {
  late Uint8List data;
  late HttpServer upstream;
  late List<String> ranges;
  late int forbidOnceAt; // range start answered with 403 one time; -1: never
  late int posts;
  late AudioProxy proxy;
  late InnerTubeSource source;
  late HttpClient http;

  setUp(() async {
    data = Uint8List.fromList([
      for (var i = 0; i < _length; i++) (i * 7 + 3) % 251,
    ]);
    ranges = [];
    forbidOnceAt = -1;
    posts = 0;
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    upstream.listen((r) async {
      final m = RegExp(
        r'bytes=(\d+)-(\d+)',
      ).firstMatch(r.headers.value('range') ?? '');
      if (m == null) {
        r.response.statusCode = 400;
        return r.response.close();
      }
      ranges.add(m[0]!);
      final a = int.parse(m[1]!);
      final b = int.parse(m[2]!);
      if (a == forbidOnceAt) {
        forbidOnceAt = -1;
        r.response.statusCode = 403;
        return r.response.close();
      }
      r.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $a-$b/$_length')
        ..headers.contentLength = b - a + 1
        ..add(data.sublist(a, b + 1));
      await r.response.close();
    });
    source = InnerTubeSource(
      FakeSource(),
      proxyFactory: () async =>
          proxy = await AudioProxy.start(chunkBytes: _chunk),
      orchestratorFactory: () => StreamOrchestrator(
        post: (url, headers, body) async {
          posts++;
          return {
            'playabilityStatus': {'status': 'OK'},
            'streamingData': {
              'expiresInSeconds': '21540',
              'adaptiveFormats': [
                {
                  'itag': 251,
                  'mimeType': 'audio/webm; codecs="opus"',
                  'audioQuality': 'AUDIO_QUALITY_MEDIUM',
                  'bitrate': 128000,
                  'contentLength': '$_length',
                  'url': 'http://127.0.0.1:${upstream.port}/audio',
                },
              ],
            },
          };
        },
        get: (url, headers, {timeout = const Duration(seconds: 10)}) async =>
            url.path == '/sw.js_data'
            ? const HttpGetResult(
                200,
                body: [
                  ...[41, 93, 125, 39, 10],
                ],
              )
            : const HttpGetResult(206), // tail probe
      ),
    );
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    source.dispose();
    await upstream.close(force: true);
  });

  Future<(int, HttpHeaders, List<int>)> read(
    String url, {
    String? range,
  }) async {
    final req = await http.getUrl(Uri.parse(url));
    if (range != null) req.headers.set('range', range);
    final res = await req.close();
    final body = <int>[];
    await for (final c in res) {
      body.addAll(c);
    }
    return (res.statusCode, res.headers, body);
  }

  Future<void> eventually(bool Function() ok) async {
    for (var i = 0; i < 300 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(ok(), isTrue);
  }

  test('resolve to loopback: full read, range read, completion', () async {
    final audio = await source.resolve(_track);
    expect(audio.headers, isEmpty);
    expect(Uri.parse(audio.input).host, '127.0.0.1');

    final full = await read(audio.input);
    expect(full.$1, 200);
    expect(full.$3, data);
    expect(ranges.length, greaterThanOrEqualTo(5)); // 300 KiB / 64 KiB chunks
    await audio.validateCompletion!();

    final part = await read(audio.input, range: 'bytes=200000-');
    expect(part.$1, 206);
    expect(
      part.$2.value('content-range'),
      'bytes 200000-${_length - 1}/$_length',
    );
    expect(part.$3, data.sublist(200000));
    expect(posts, 1);
  });

  test('a 403 mid-stream re-resolves and still returns the bytes', () async {
    final audio = await source.resolve(_track);
    forbidOnceAt = _chunk; // second chunk
    final full = await read(audio.input);
    expect(full.$3, data);
    expect(posts, 2);
    expect(
      ranges.where((r) => r == 'bytes=$_chunk-${2 * _chunk - 1}'),
      hasLength(2),
    );
  });

  test('dispose closes the proxy and leaks no upstream sockets', () async {
    final audio = await source.resolve(_track);
    final port = Uri.parse(audio.input).port;
    await read(audio.input);
    http.close(force: true);
    source.dispose();
    await eventually(() => proxy.activeConnections == 0);
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
    await eventually(() => upstream.connectionsInfo().total == 0);
  });
}
