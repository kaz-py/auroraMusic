import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_match.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Handler = FutureOr<(int, String)> Function(Uri uri);

class _Client extends Fake implements HttpClient {
  _Client(this.handler);
  final _Handler handler;
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _Request(await handler(url));
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
  final sent = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      sent[name.toLowerCase()] = value;
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

const _track = Track(
  id: 'yt:abc',
  title: 'Queen - Bohemian Rhapsody (Official Video Remastered)',
  artist: 'Queen - Topic',
  duration: Duration(seconds: 355),
);

String _item({
  String artist = 'Queen',
  String title = 'Bohemian Rhapsody',
  num duration = 355,
  String? synced =
      '[00:01.00]Is this the real life?\n[00:05.50]Is this just fantasy?',
  String? plain = 'Is this the real life?\nIs this just fantasy?',
}) => jsonEncode({
  'trackName': title,
  'artistName': artist,
  'albumName': 'A Night at the Opera',
  'duration': duration,
  'instrumental': false,
  'syncedLyrics': synced,
  'plainLyrics': plain,
});

LyricsService _svc(_Handler h) =>
    LyricsService(clientFactory: () => _Client(h), backoff: Duration.zero);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('aurora_lyr_'));
  tearDown(() async {
    // Windows puede tener aún abierto el archivo de caché un instante.
    for (var i = 0; i < 5 && await dir.exists(); i++) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  group('limpieza de metadatos', () {
    test('quita ruido de YouTube y usa el artista principal', () {
      expect(cleanArtist('Queen - Topic'), 'Queen');
      expect(cleanArtist('AdeleVEVO'), 'Adele');
      expect(cleanArtist('Bad Bunny, Jhay Cortez'), 'Bad Bunny');
      expect(cleanArtist('Daft Punk feat. Pharrell'), 'Daft Punk');
      expect(
        cleanTitle(
          'Queen - Bohemian Rhapsody (Official Video Remastered)',
          artist: 'Queen',
        ),
        'Bohemian Rhapsody',
      );
      expect(cleanTitle('Song [Lyrics] (feat. Someone)'), 'Song');
      expect(cleanTitle('Song ft. Other'), 'Song');
      expect(cleanTitle('Yesterday - Remastered 2009'), 'Yesterday');
      expect(cleanTitle('Hotel California (Live)'), 'Hotel California (Live)');
    });
    test('conserva japonés y acentos; normaliza sin diacríticos', () {
      expect(cleanTitle('千本桜 (Official Video)'), '千本桜');
      expect(
        normalizeLyricsKey('Canción de Ámbar'),
        'cancionedeambar'.replaceFirst('cancionedeambar', 'canciondeambar'),
      );
    });
  });

  group('puntuación de candidatos', () {
    LyricsMatch s(String artist, String title, num secs) =>
        scoreLyricsCandidate(
          wantedArtist: 'Queen',
          wantedTitle: 'Bohemian Rhapsody',
          wantedSeconds: 355,
          artist: artist,
          title: title,
          seconds: secs,
        );
    test('acepta la correcta con confianza alta y sincronía', () {
      final m = s('Queen', 'Bohemian Rhapsody', 354);
      expect(m.acceptable && m.syncOk, isTrue);
      expect(m.confidence, LyricsConfidence.high);
    });
    test('duración distinta: acepta como texto pero sin sincronía', () {
      final m = s('Queen', 'Bohemian Rhapsody', 362);
      expect(m.acceptable, isTrue);
      expect(m.syncOk, isFalse);
    });
    test('descarta otra canción u otro artista', () {
      expect(s('Queen', 'Another One Bites the Dust', 355).acceptable, isFalse);
      expect(s('Muse', 'Bohemian Rhapsody', 355).acceptable, isFalse);
    });
    test('penaliza versiones live/remix no pedidas', () {
      final live = s('Queen', 'Bohemian Rhapsody (Live)', 355);
      expect(live.score, lessThan(s('Queen', 'Bohemian Rhapsody', 355).score));
    });
    test('con feat. en el título pedido sigue encajando', () {
      final m = scoreLyricsCandidate(
        wantedArtist: 'Daft Punk',
        wantedTitle: cleanTitle('Get Lucky (feat. Pharrell Williams)'),
        wantedSeconds: 248,
        artist: 'Daft Punk',
        title: 'Get Lucky',
        seconds: 248,
      );
      expect(m.acceptable, isTrue);
    });
  });

  group('cascada', () {
    test('LRCLIB get ok: sincronizada, User-Agent de Aurora, cachea', () async {
      final seen = <Uri>[];
      final svc = _svc((u) {
        seen.add(u);
        return (200, _item());
      });
      final r = await svc.load(_track, dir);
      expect(r.kind, LyricsKind.synced);
      expect(r.source, 'LRCLIB');
      expect(r.confidence, LyricsConfidence.high);
      expect(seen.single.queryParameters['track_name'], 'Bohemian Rhapsody');
      expect(seen.single.queryParameters['artist_name'], 'Queen');
      expect(seen.single.queryParameters['duration'], '355');
      expect(LyricsService.userAgent, startsWith('Aurora/'));
      final offline = _svc((u) => (503, ''));
      final back = await offline.load(_track, dir);
      expect(back.kind, LyricsKind.synced);
      expect(back.fromCache, isTrue);
      // El disco no guarda el id crudo.
      final cached = Directory(
        '${dir.path}/lyrics',
      ).listSync().whereType<File>().map((f) => f.readAsStringSync()).join();
      expect(cached.contains('yt:abc'), isFalse);
    });

    test('get 404 → search encuentra', () async {
      final svc = _svc((u) {
        if (u.path == '/api/get') return (404, '{}');
        return (
          200,
          '[${_item(title: "Bohemian rhapsody (Live)", duration: 300)},${_item()}]',
        );
      });
      final r = await svc.load(_track, dir);
      expect(r.kind, LyricsKind.synced);
      expect(r.lines.first.text, 'Is this the real life?');
    });

    test('duración fuera de ±3 s: no usa la sincronía', () async {
      final svc = _svc(
        (u) => u.path == '/api/get' ? (200, _item(duration: 365)) : (404, ''),
      );
      final r = await svc.load(_track, dir);
      expect(r.kind, LyricsKind.plain);
      expect(r.text, contains('Is this just fantasy?'));
    });

    test('LRCLIB sin nada → lyrics.ovh plano', () async {
      final svc = _svc((u) {
        if (u.host == 'api.lyrics.ovh') {
          return (200, jsonEncode({'lyrics': 'hola mundo'}));
        }
        return u.path == '/api/search' ? (200, '[]') : (404, '{}');
      });
      final r = await svc.load(_track, dir);
      expect(r.kind, LyricsKind.plain);
      expect(r.source, 'lyrics.ovh');
      expect(r.confidence, LyricsConfidence.low);
    });

    test(
      'respuesta rara en todas las fuentes → sin letra y caché negativa 24 h',
      () async {
        var calls = 0;
        var clock = DateTime(2026, 1, 1);
        final svc = LyricsService(
          clientFactory: () => _Client((u) {
            calls++;
            return (200, 'esto no es json <html>');
          }),
          backoff: Duration.zero,
          now: () => clock,
        );
        expect((await svc.load(_track, dir)).kind, LyricsKind.notFound);
        final first = calls;
        expect((await svc.load(_track, dir)).kind, LyricsKind.notFound);
        expect(calls, first, reason: 'caché negativa vigente');
        clock = clock.add(const Duration(hours: 25));
        await svc.load(_track, dir);
        expect(calls, greaterThan(first), reason: 'caducó a las 24 h');
        clock = clock.add(const Duration(hours: 1));
        final before = calls;
        await svc.load(_track, dir, force: true);
        expect(
          calls,
          greaterThan(before),
          reason: 'Reintentar ignora la caché negativa',
        );
      },
    );

    test('fallo de red en todo: lanza y NO se cachea como sin letra', () async {
      var calls = 0;
      final svc = _svc((u) {
        calls++;
        return (503, '');
      });
      await expectLater(svc.load(_track, dir), throwsA(isA<HttpException>()));
      expect(calls, 3 * 3, reason: '3 fuentes x (1 + 2 reintentos)');
      final ok = _svc((u) => (200, _item()));
      expect((await ok.load(_track, dir)).kind, LyricsKind.synced);
    });

    test('timeout reintenta y luego se recupera', () async {
      var n = 0;
      final svc = _svc((u) {
        if (n++ < 2) throw TimeoutException('lento');
        return (200, _item());
      });
      expect((await svc.load(_track, dir)).kind, LyricsKind.synced);
    });

    test('cambiar de pista cancela la carga anterior', () async {
      final gate = Completer<void>();
      final svc = _svc((u) async {
        await gate.future;
        return (200, _item());
      });
      final first = svc.load(_track, dir);
      await Future<void>.delayed(Duration.zero);
      final other = svc.load(
        const Track(id: 'x', title: 'Otra', artist: 'Alguien'),
        dir,
      );
      gate.complete();
      expect((await first).kind, LyricsKind.notFound);
      await other;
    });

    test('candidates ordena por puntuación y choose cachea la elegida', () async {
      final svc = _svc(
        (u) => (
          200,
          '[${_item(title: "Otra cosa", artist: "Muse")},${_item(synced: null)}]',
        ),
      );
      final list = await svc.candidates(_track);
      expect(list.first.title, 'Bohemian Rhapsody');
      expect(list.first.synced, isFalse);
      final r = await svc.choose(_track, dir, list.first);
      expect(r.kind, LyricsKind.plain);
      final offline = _svc((u) => (503, ''));
      expect((await offline.load(_track, dir)).kind, LyricsKind.plain);
      // La elegida a mano no se pisa por la red.
      var asked = false;
      final again = _svc((u) {
        asked = true;
        return (200, _item());
      });
      expect((await again.load(_track, dir)).kind, LyricsKind.plain);
      expect(asked, isFalse);
    });

    test(
      'online primero: la respuesta nueva corrige una caché equivocada',
      () async {
        final wrong = _svc(
          (u) => (200, _item(synced: '[00:01.00]letra vieja', plain: null)),
        );
        await wrong.load(_track, dir);
        final fresh = _svc((u) => (200, _item()));
        final r = await fresh.load(_track, dir);
        expect(r.fromCache, isFalse);
        expect(r.lines.first.text, 'Is this the real life?');
        final offline = _svc((u) => (503, ''));
        expect(
          (await offline.load(_track, dir)).lines.first.text,
          'Is this the real life?',
        );
      },
    );

    test('LRCLIB sin resultado conserva la caché y no la borra', () async {
      await _svc((u) => (200, _item())).load(_track, dir);
      final none = _svc(
        (u) => u.path == '/api/search' ? (200, '[]') : (404, '{}'),
      );
      final r = await none.load(_track, dir);
      expect(r.kind, LyricsKind.synced);
      expect(r.fromCache, isTrue);
    });

    test(
      'red lenta con caché: avisa con la guardada y luego entrega la nueva',
      () async {
        await _svc(
          (u) => (200, _item(synced: '[00:01.00]guardada', plain: null)),
        ).load(_track, dir);
        final gate = Completer<void>();
        final slow = _svc((u) async {
          await gate.future;
          return (200, _item());
        });
        LyricsResult? interim;
        final fut = slow.load(
          _track,
          dir,
          slowAfter: const Duration(milliseconds: 20),
          onInterim: (r) => interim = r,
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(interim?.fromCache, isTrue);
        expect(interim?.lines.first.text, 'guardada');
        gate.complete();
        final r = await fut;
        expect(r.fromCache, isFalse);
        expect(r.lines.first.text, 'Is this the real life?');
      },
    );
  });

  group('LRC y desfase', () {
    test(
      'varias marcas, milisegundos, [mm:ss:xx], palabra a palabra y vacías',
      () {
        final l = LyricsService.parseLrc(
          '[ar:X]\n[01:02.345]a\n[00:01:50][00:03]<00:03.10>b <00:03.50>c\n[00:09.00]\n',
        );
        expect(l.map((e) => e.at.inMilliseconds), [1500, 3000, 62345]);
        expect(l[1].text, 'b c');
      },
    );
  });
}
