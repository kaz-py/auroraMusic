import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(
  id: 'fixture-track',
  artist: 'Fixture Artist',
  title: 'Fixture Artist - Fixture Song (Official Video)',
  duration: Duration(seconds: 180),
  pageUrl: 'https://example.test/fixture-track',
);

class _ResponseClient extends Fake implements HttpClient {
  _ResponseClient(this.status, this.payload, this.onUri);

  final int status;
  final List<int> payload;
  final void Function(Uri uri) onUri;
  Duration? _connectionTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    onUri(url);
    final request = _ResponseRequest();
    request.response.status = status;
    request.response.payload = payload;
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _ResponseRequest extends Fake implements HttpClientRequest {
  final response = _Response();

  @override
  final HttpHeaders headers = _Headers();

  @override
  Future<HttpClientResponse> close() async => response;
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  int status = 200;
  List<int> payload = const [];

  @override
  int get statusCode => status;

  @override
  int get contentLength => payload.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(payload).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Directory> _temporaryDirectory() =>
    Directory.systemTemp.createTemp('aurora_lyrics_behavior_');

String _payload({
  String artist = 'Fixture Artist',
  String title = 'Fixture Song',
  num duration = 180,
  String lyrics = '[00:01.00]fixture line one\n[00:02.00]fixture line two',
}) => jsonEncode({
  'artistName': artist,
  'trackName': title,
  'duration': duration,
  'syncedLyrics': lyrics,
  'plainLyrics': null,
});

void main() {
  group('LyricsService behavior', () {
    late Directory directory;
    final requestedUris = <Uri>[];

    setUp(() async {
      directory = await _temporaryDirectory();
      requestedUris.clear();
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test(
      'requests exact artist, cleaned title, and HTTPS LRCLIB endpoint',
      () async {
        final service = LyricsService(
          clientFactory: () =>
              _ResponseClient(200, utf8.encode(_payload()), requestedUris.add),
        );
        final result = await service.load(_track, directory);

        expect(result.kind, LyricsKind.synced);
        expect(requestedUris, isNotEmpty);
        expect(requestedUris.first.scheme, 'https');
        expect(requestedUris.first.host, 'lrclib.net');
        expect(requestedUris.first.path, '/api/get');
        expect(requestedUris.first.queryParameters, {
          'artist_name': 'Fixture Artist',
          'track_name': 'Fixture Song',
          'duration': '180',
        });
        service.dispose();
      },
    );

    for (final mismatch in [
      ('artist', _payload(artist: 'Another Artist')),
      ('title', _payload(title: 'Another Song')),
      ('duration', _payload(duration: 190)),
    ]) {
      test('rejects ${mismatch.$1} mismatch', () async {
        final service = LyricsService(
          clientFactory: () =>
              _ResponseClient(200, utf8.encode(mismatch.$2), requestedUris.add),
        );
        final result = await service.load(_track, directory);
        expect(result.kind, LyricsKind.notFound);
        service.dispose();
      });
    }

    test('rejects responses larger than the bounded payload', () async {
      final oversized = utf8.encode(_payload(lyrics: 'x' * (1024 * 1024)));
      final service = LyricsService(
        clientFactory: () => _ResponseClient(200, oversized, requestedUris.add),
      );

      await expectLater(service.load(_track, directory), throwsFormatException);
      service.dispose();
    });

    test('serves the cached result offline without a second request', () async {
      var requestCount = 0;
      final service = LyricsService(
        clientFactory: () => _ResponseClient(
          200,
          utf8.encode(_payload()),
          (_) => requestCount++,
        ),
      );
      final first = await service.load(_track, directory);
      service.dispose();

      final offline = LyricsService(
        clientFactory: () => throw StateError('Offline cache should be used'),
      );
      final second = await offline.load(_track, directory);
      expect(first.lines.map((line) => line.text), [
        'fixture line one',
        'fixture line two',
      ]);
      expect(second.lines.map((line) => line.text), [
        'fixture line one',
        'fixture line two',
      ]);
      expect(requestCount, 1);
      offline.dispose();
    });

    test('dispose cancels pending lookup and discards its result', () async {
      final gate = Completer<void>();
      final client = _PendingClient(gate);
      final service = LyricsService(clientFactory: () => client);
      final pending = service.load(_track, directory);
      await Future<void>.delayed(Duration.zero);
      service.dispose();
      gate.complete();

      expect((await pending).kind, LyricsKind.notFound);
    });
  });
}

class _PendingClient extends Fake implements HttpClient {
  _PendingClient(this.gate);
  final Completer<void> gate;
  Duration? _connectionTimeout;

  @override
  Duration? get connectionTimeout => _connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _connectionTimeout = value;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    await gate.future;
    final request = _ResponseRequest();
    request.response.payload = utf8.encode(_payload());
    return request;
  }

  @override
  void close({bool force = false}) {}
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}
