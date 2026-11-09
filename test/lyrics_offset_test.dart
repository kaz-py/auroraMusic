import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/ui/lyrics_offset_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// LRCLIB simulado: `get` no existe y `search` devuelve una sola versión.
class _Client extends Fake implements HttpClient {
  _Client(this.body);
  final String body;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(url.path.endsWith('/search') ? (200, body) : (404, '[]'));
  @override
  void close({bool force = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.reply);
  final (int, String) reply;
  @override
  final HttpHeaders headers = _Headers();
  @override
  Future<HttpClientResponse> close() async =>
      _Response(reply.$1, utf8.encode(reply.$2));
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.statusCode, this.payload);
  @override
  final int statusCode;
  final List<int> payload;
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

String _version(num duration) => jsonEncode([
  {
    'trackName': 'Canción',
    'artistName': 'Artista',
    'albumName': 'Álbum',
    'duration': duration,
    'instrumental': false,
    'syncedLyrics': '[00:01.00]Primera\n[00:05.00]Segunda',
    'plainLyrics': 'Primera\nSegunda',
  },
]);

Track _track(int seconds) => Track(
  id: 'yt:x',
  title: 'Canción',
  artist: 'Artista',
  duration: Duration(seconds: seconds),
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('aurora_off_'));
  tearDown(() async {
    for (var i = 0; i < 5 && await dir.exists(); i++) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  LyricsService service(String body) =>
      LyricsService(clientFactory: () => _Client(body), backoff: Duration.zero);

  test('user offsets are per track, clamped, and an explicit 0 wins', () async {
    final s = service('[]');
    final a = _track(200), b = Track(id: 'yt:y', title: 't', artist: 'a');
    expect(await s.readOffset(a, dir), 0);
    expect(await s.hasUserOffset(a, dir), isFalse);
    await s.writeOffset(a, dir, -2500);
    await s.writeOffset(b, dir, 700);
    expect(await s.readOffset(a, dir), -2500);
    expect(await s.readOffset(b, dir), 700);
    await s.writeOffset(a, dir, -9999999);
    expect(await s.readOffset(a, dir), -LyricsService.maxOffsetMs);
    // «Sin ajuste» elegido a mano gana a cualquier offset automático.
    await s.writeAutoOffset(a, dir, 4000, 'audio');
    await s.writeOffset(a, dir, 0);
    expect(await s.readOffset(a, dir), 0);
    expect(await s.hasUserOffset(a, dir), isTrue);
    expect(await s.readOffset(b, dir), 700, reason: 'no toca otras pistas');
  });

  test('automatic offsets apply until the user sets one', () async {
    final s = service('[]');
    final t = _track(200);
    await s.writeAutoOffset(t, dir, -12000, 'audio');
    expect(await s.readOffset(t, dir), -12000);
    expect((await s.readAutoOffset(t, dir))?.source, 'audio');
    await s.writeOffset(t, dir, 300);
    expect(await s.readOffset(t, dir), 300);
  });

  test(
    'a shorter synced version starts shifted by the length difference',
    () async {
      // El vídeo dura 12 s más que la versión de estudio: una intro de ~12 s.
      final s = service(_version(188));
      final up = await s.upgradeToSynced(_track(200), dir);
      expect(up?.kind, LyricsKind.synced);
      expect(await s.readOffset(_track(200), dir), -12000);
      expect((await s.readAutoOffset(_track(200), dir))?.source, 'duration');
      expect(await s.hasUserOffset(_track(200), dir), isFalse);
    },
  );

  test('a matching duration or a manual offset is never overwritten', () async {
    final exact = service(_version(200));
    expect(
      (await exact.upgradeToSynced(_track(201), dir))?.kind,
      LyricsKind.synced,
    );
    expect(await exact.readOffset(_track(201), dir), 0);

    final s = service(_version(188));
    await s.writeOffset(_track(200), dir, 1500);
    await s.upgradeToSynced(_track(200), dir);
    expect(await s.readOffset(_track(200), dir), 1500);
  });

  testWidgets('the controls step by half a second and reset', (tester) async {
    var value = -1000;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return LyricsOffsetControls(
                offsetMs: value,
                onChanged: (v) => update(() => value = v),
              );
            },
          ),
        ),
      ),
    );
    expect(find.textContaining('−1.0s'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyrics-later')));
    await tester.pump();
    expect(value, -1500);
    await tester.tap(find.byKey(const ValueKey('lyrics-earlier')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lyrics-earlier')));
    await tester.pump();
    expect(value, -500);
    await tester.tap(find.byKey(const ValueKey('lyrics-offset-reset')));
    await tester.pump();
    expect(value, 0);
    expect(find.text('Letra: sin ajuste'), findsOneWidget);
  });
}
