import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/remote/remote_control_server.dart';
import 'package:flutter_test/flutter_test.dart';

class _Actions implements RemoteControlActions {
  final calls = <String>[];
  Object? failure;
  Completer<void>? hang;

  Future<void> _record(String name) async {
    calls.add(name);
    final wait = hang;
    if (wait != null) await wait.future;
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> play() => _record('play');
  @override
  Future<void> pause() => _record('pause');
  @override
  Future<void> toggle() => _record('toggle');
  @override
  Future<void> next() => _record('next');
  @override
  Future<void> previous() => _record('previous');
  @override
  Future<Map<String, Object?>> startJam({String mode = 'auto'}) async {
    await _record('jam:$mode');
    return {
      'alreadyActive': false,
      'jam': {'code': 'ABCD1234'},
    };
  }

  @override
  Map<String, Object?> status() => {'playing': calls.isNotEmpty};
}

void main() {
  const token = 'secreto-de-prueba-0123456789abcdef';
  late _Actions actions;
  late RemoteControlServer server;
  late HttpClient client;

  setUp(() async {
    actions = _Actions();
    server = await RemoteControlServer.start(
      actions: actions,
      token: () => token,
      port: 0,
      actionTimeout: const Duration(milliseconds: 400),
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, {
    Map<String, String> headers = const {},
    String? body,
    bool auth = true,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (auth) request.headers.set('Authorization', 'Bearer $token');
    headers.forEach(request.headers.set);
    if (body != null) request.write(body);
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    return (response.statusCode, jsonDecode(text) as Map<String, dynamic>);
  }

  test('rejects missing or wrong tokens without running the action', () async {
    expect((await call('POST', '/v1/next', auth: false)).$1, 401);
    final wrong = await call(
      'POST',
      '/v1/next',
      auth: false,
      headers: {'Authorization': 'Bearer otro'},
    );
    expect(wrong.$1, 401);
    expect((await call('GET', '/v1/next?token=casi', auth: false)).$1, 401);
    expect(actions.calls, isEmpty);
  });

  test('accepts the token as Bearer, X-Aurora-Token or query', () async {
    expect((await call('POST', '/v1/pause')).$1, 200);
    expect(
      (await call(
        'POST',
        '/v1/pause',
        auth: false,
        headers: {'X-Aurora-Token': token},
      )).$1,
      200,
    );
    expect((await call('GET', '/v1/pause?token=$token', auth: false)).$1, 200);
    expect(actions.calls, ['pause', 'pause', 'pause']);
  });

  test('routes each command to its action', () async {
    for (final name in ['play', 'pause', 'toggle', 'next', 'previous']) {
      final result = await call('POST', '/v1/$name');
      expect(result.$1, 200, reason: name);
      expect(result.$2['ok'], isTrue);
    }
    expect(actions.calls, ['play', 'pause', 'toggle', 'next', 'previous']);
    final status = await call('GET', '/v1/status');
    expect(status.$2['playing'], isTrue);
  });

  test('starts a Jam with the requested mode and validates it', () async {
    final auto = await call('POST', '/v1/jam/start');
    expect(auto.$1, 200);
    expect(auto.$2['jam'], {'code': 'ABCD1234'});
    await call('POST', '/v1/jam/start', body: '{"mode":"lan"}');
    await call('GET', '/v1/jam/start?mode=online');
    expect(actions.calls, ['jam:auto', 'jam:lan', 'jam:online']);
    final bad = await call('POST', '/v1/jam/start', body: '{"mode":"nube"}');
    expect(bad.$1, 400);
    expect(actions.calls, hasLength(3));
  });

  test(
    'browser requests (Origin) and foreign Host headers are refused',
    () async {
      final origin = await call(
        'POST',
        '/v1/next',
        headers: {'Origin': 'https://example.test'},
      );
      expect(origin.$1, 403);
      final host = await call(
        'POST',
        '/v1/next',
        headers: {'Host': 'evil.example:${server.port}'},
      );
      expect(host.$1, 403);
      final local = await call(
        'POST',
        '/v1/next',
        headers: {'Host': 'localhost:${server.port}'},
      );
      expect(local.$1, 200);
      expect(actions.calls, ['next']);
    },
  );

  test('unknown routes, methods and bodies get precise errors', () async {
    expect((await call('POST', '/v1/volar')).$1, 404);
    expect((await call('POST', '/otra/cosa')).$1, 404);
    expect((await call('PUT', '/v1/next')).$1, 405);
    expect((await call('DELETE', '/v1/next')).$1, 405);
    expect((await call('POST', '/v1/jam/start', body: '[1]')).$1, 400);
    expect((await call('POST', '/v1/jam/start', body: 'no-json')).$1, 400);
    // Un cuerpo enorme se corta antes de leerlo: 413 o conexión cerrada.
    try {
      expect((await call('POST', '/v1/jam/start', body: 'x' * 5000)).$1, 413);
    } on HttpException {
      // El servidor cerró sin leer el resto: igual de válido.
    }
    expect(actions.calls, isEmpty);
  });

  test(
    'action failures keep their status; unexpected ones are generic',
    () async {
      actions.failure = const RemoteControlException(409, 'Lo controla Ana.');
      final conflict = await call('POST', '/v1/toggle');
      expect(conflict.$1, 409);
      expect(conflict.$2, {'ok': false, 'error': 'Lo controla Ana.'});
      actions.failure = StateError('detalle interno con /ruta/secreta');
      final broken = await call('POST', '/v1/next');
      expect(broken.$1, 500);
      expect(broken.$2['error'], 'Error interno.');
    },
  );

  test('an action that never finishes answers 504', () async {
    actions.hang = Completer<void>();
    final slow = await call('POST', '/v1/next');
    expect(slow.$1, 504);
    actions.hang!.complete();
  });

  test('only listens on loopback and rotates tokens live', () async {
    expect(server.baseUri.host, '127.0.0.1');
    var current = token;
    final other = await RemoteControlServer.start(
      actions: actions,
      token: () => current,
      port: 0,
    );
    addTearDown(other.close);
    Future<int> status(String bearer) async {
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:${other.port}/v1/status'),
      );
      request.headers.set('Authorization', 'Bearer $bearer');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    }

    expect(await status(token), 200);
    current = RemoteControlServer.generateToken();
    expect(await status(token), 401);
    expect(await status(current), 200);
    expect(current, hasLength(32));
  });
}
