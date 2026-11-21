import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:aurora_music/sources/stream/audio_proxy.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:flutter_test/flutter_test.dart';

/// Origen lento: sirve el rango pedido a trocitos, con pausas, para que el
/// reproductor tenga tiempo de cortar la conexión a mitad de la respuesta.
Future<HttpServer> _slowOrigin(Uint8List data) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((r) async {
    try {
      final m = RegExp(
        r'bytes=(\d+)-(\d+)',
      ).firstMatch(r.headers.value('range') ?? '');
      final a = m == null ? 0 : int.parse(m[1]!);
      final b = m == null ? data.length - 1 : int.parse(m[2]!);
      final end = b >= data.length ? data.length - 1 : b;
      r.response
        ..statusCode = 206
        ..headers.set('content-range', 'bytes $a-$end/${data.length}')
        ..headers.contentLength = end - a + 1;
      for (var i = a; i <= end; i += 8192) {
        r.response.add(
          data.sublist(i, i + 8192 > end + 1 ? end + 1 : i + 8192),
        );
        await r.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await r.response.close();
    } catch (_) {
      // El proxy puede cortar al origen cuando el reproductor se va.
    }
  });
  return server;
}

void main() {
  test('un RST del reproductor a mitad de la respuesta no deja errores sin '
      'capturar y el proxy sigue sirviendo', () async {
    final errors = <Object>[];
    final done = Completer<void>();
    unawaited(
      runZonedGuarded(
        () async {
          final data = Uint8List(2 * 1024 * 1024);
          for (var i = 0; i < data.length; i++) {
            data[i] = (i * 7 + 3) % 251;
          }
          final origin = await _slowOrigin(data);
          final proxy = await AudioProxy.start(
            chunkBytes: 256 * 1024,
            maxUpstream: 4,
            headerTimeout: const Duration(seconds: 5),
            stallTimeout: const Duration(seconds: 5),
          );
          try {
            final video = ResolvedStream(
              videoId: 'vid',
              url: Uri.parse('http://127.0.0.1:${origin.port}/s'),
              headers: const {'User-Agent': 'UA/1'},
              expiresAt: DateTime.now().add(const Duration(hours: 1)),
              client: 'test',
              itag: 251,
              backend: StreamBackend.proxy,
              mimeType: 'audio/webm',
              contentLength: data.length,
            );
            final u = proxy.register('vid', video, refresh: () async => video);

            final socket = await Socket.connect('127.0.0.1', u.port);
            socket.write(
              'GET ${u.path} HTTP/1.1\r\n'
              'Host: 127.0.0.1:${u.port}\r\n'
              'Range: bytes=0-\r\n\r\n',
            );
            var received = 0;
            final gotSome = Completer<void>();
            socket.listen(
              (c) {
                received += c.length;
                if (received > 20000 && !gotSome.isCompleted) {
                  gotSome.complete();
                }
              },
              onError: (Object _) {},
              cancelOnError: true,
            );
            await gotSome.future.timeout(const Duration(seconds: 5));
            // RST en lugar de FIN: SO_LINGER (nivel SOL_SOCKET=1, opción 13)
            // con l_onoff=1 y l_linger=0.
            socket.setRawOption(
              RawSocketOption(
                RawSocketOption.levelSocket,
                13,
                Uint8List.fromList([1, 0, 0, 0, 0, 0, 0, 0]),
              ),
            );
            socket.destroy();

            // El origen sigue enviando: aquí aparecería el error.
            await Future<void>.delayed(const Duration(seconds: 2));

            final http = HttpClient();
            final req = await http.getUrl(u);
            req.headers.set('range', 'bytes=0-999');
            final res = await req.close();
            final body = <int>[];
            await for (final c in res) {
              body.addAll(c);
            }
            http.close(force: true);
            expect(res.statusCode, anyOf(200, 206));
            expect(body, data.sublist(0, 1000));
          } finally {
            await proxy.close();
            await origin.close(force: true);
          }
          done.complete();
        },
        (e, s) {
          errors.add(e);
          if (!done.isCompleted) done.complete();
        },
      ),
    );
    await done.future.timeout(const Duration(seconds: 30));
    expect(errors, isEmpty, reason: 'errores no capturados: $errors');
  }, skip: !Platform.isLinux);
}
