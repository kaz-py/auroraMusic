import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
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
  setUp(() async => dir = await Directory.systemTemp.createTemp('aurora_adj_'));
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

  const synced = LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration(seconds: 2), 'Primera'),
      LyricLine(Duration(seconds: 7), 'Segunda'),
      LyricLine(Duration(seconds: 12), 'Tercera'),
    ],
    source: 'LRCLIB',
  );
  const plain = LyricsResult(
    LyricsKind.plain,
    text: 'Primera\n\n  Segunda  \nTercera\n',
    source: 'LRCLIB',
  );

  test('adjusts are stored per track and survive a reload', () async {
    final s = service('[]');
    final a = _track(200), b = Track(id: 'yt:y', title: 't', artist: 'a');
    expect(await s.readAdjust(a, dir), isNull);
    await s.writeAdjust(
      a,
      dir,
      const LyricsAdjust(source: 'duration', shiftMs: 12000),
    );
    await s.writeAdjust(
      b,
      dir,
      const LyricsAdjust(source: 'audio', startsMs: [1, 2]),
    );
    final read = await s.readAdjust(a, dir);
    expect(read?.shiftMs, 12000);
    expect(
      read?.settled,
      isFalse,
      reason: 'una estimación por duración se puede mejorar',
    );
    expect((await s.readAdjust(b, dir))?.settled, isTrue);
    expect((await s.readAdjust(b, dir))?.startsMs, [1, 2]);
  });

  test(
    'a shift moves a synced lyric; start times replace it; plain lyrics get times',
    () {
      final shifted = LyricsService.applyAdjust(
        synced,
        const LyricsAdjust(source: 'duration', shiftMs: 12000),
      );
      expect(shifted.lines.map((l) => l.at.inSeconds), [14, 19, 24]);
      expect(shifted.lines.map((l) => l.text), [
        'Primera',
        'Segunda',
        'Tercera',
      ]);

      final timed = LyricsService.applyAdjust(
        synced,
        const LyricsAdjust(source: 'audio', startsMs: [3000, 9500, 20000]),
      );
      expect(timed.lines.map((l) => l.at.inMilliseconds), [3000, 9500, 20000]);

      final fromPlain = LyricsService.applyAdjust(
        plain,
        const LyricsAdjust(source: 'audio', startsMs: [34000, 37000, 40000]),
      );
      expect(fromPlain.kind, LyricsKind.synced);
      expect(fromPlain.lines.map((l) => l.text), [
        'Primera',
        'Segunda',
        'Tercera',
      ]);
      expect(fromPlain.lines.first.at, const Duration(seconds: 34));
      expect(fromPlain.source, 'LRCLIB');
    },
  );

  test(
    'an adjust that does not fit the lyric is ignored, never half applied',
    () {
      final wrongCount = LyricsService.applyAdjust(
        plain,
        const LyricsAdjust(source: 'audio', startsMs: [1000, 2000]),
      );
      expect(wrongCount.kind, LyricsKind.plain);
      final noShift = LyricsService.applyAdjust(
        synced,
        const LyricsAdjust(source: 'audio', tried: true),
      );
      expect(identical(noShift, synced), isTrue);
      // Un desplazamiento nunca deja tiempos negativos.
      final early = LyricsService.applyAdjust(
        synced,
        const LyricsAdjust(source: 'duration', shiftMs: -5000),
      );
      expect(early.lines.first.at, Duration.zero);
    },
  );

  test('adjusted() always starts from the raw lyric (idempotent)', () async {
    final s = service('[]');
    final t = _track(200);
    await s.writeAdjust(
      t,
      dir,
      const LyricsAdjust(source: 'duration', shiftMs: 10000),
    );
    final once = await s.adjusted(t, dir, synced);
    final twice = await s.adjusted(t, dir, synced);
    expect(once.lines.first.at, twice.lines.first.at);
    expect(once.lines.first.at, const Duration(seconds: 12));
    // Sin ajuste, o con una letra sin contenido, no cambia nada.
    final other = Track(id: 'yt:none', title: 't', artist: 'a');
    expect(identical(await s.adjusted(other, dir, synced), synced), isTrue);
    const none = LyricsResult(LyricsKind.notFound);
    expect(identical(await s.adjusted(t, dir, none), none), isTrue);
  });

  test(
    'a shorter synced version records the length difference as a shift',
    () async {
      // El vídeo dura 12 s más que la versión de estudio: una intro de ~12 s.
      final s = service(_version(188));
      final up = await s.upgradeToSynced(_track(200), dir);
      expect(up?.kind, LyricsKind.synced);
      final adjust = await s.readAdjust(_track(200), dir);
      expect(adjust?.shiftMs, 12000);
      expect(adjust?.source, 'duration');
      final shown = await s.adjusted(_track(200), dir, up!);
      expect(shown.lines.first.at, const Duration(seconds: 13));
    },
  );

  test(
    'a matching duration writes nothing, and a measured adjust is not overwritten',
    () async {
      final exact = service(_version(200));
      expect(
        (await exact.upgradeToSynced(_track(201), dir))?.kind,
        LyricsKind.synced,
      );
      expect(await exact.readAdjust(_track(201), dir), isNull);

      final s = service(_version(188));
      await s.writeAdjust(
        _track(200),
        dir,
        const LyricsAdjust(source: 'audio', shiftMs: 3000),
      );
      await s.upgradeToSynced(_track(200), dir);
      expect((await s.readAdjust(_track(200), dir))?.shiftMs, 3000);
    },
  );
}
