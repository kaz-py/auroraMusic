import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Lo que la API local puede pedirle a Aurora. La implementación real vive en
/// `AuroraRemoteActions`; las pruebas usan una simulada.
abstract class RemoteControlActions {
  Future<void> play();
  Future<void> pause();
  Future<void> toggle();
  Future<void> next();
  Future<void> previous();

  /// [mode]: `auto` (en línea si hay servidor, si no red local), `online` o `lan`.
  Future<Map<String, Object?>> startJam({String mode = 'auto'});
  Map<String, Object?> status();
}

/// Error con código HTTP y mensaje apto para mostrar.
class RemoteControlException implements Exception {
  const RemoteControlException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// API HTTP de control remoto (Stream Deck, scripts) solo en 127.0.0.1.
///
/// Seguridad: escucha únicamente en loopback; exige un token secreto en cada
/// petición; rechaza peticiones con `Origin` (un navegador no puede usarla
/// aunque adivine el puerto) y `Host` que no sea el propio (DNS rebinding); no
/// envía cabeceras CORS. Cuerpos de hasta 4 KiB.
///
/// Rutas (GET o POST, salvo `status`, que es GET):
/// `/v1/status`, `/v1/play`, `/v1/pause`, `/v1/toggle`, `/v1/next`,
/// `/v1/previous`, `/v1/jam/start` (`mode`: `auto`|`online`|`lan`).
/// El token va en `Authorization: Bearer <token>`, en `X-Aurora-Token` o en
/// `?token=` (para clientes que solo admiten una URL).
class RemoteControlServer {
  RemoteControlServer._(
    this._server,
    this._actions,
    this._token,
    this.actionTimeout,
  );

  static const defaultPort = 47890;
  static const maxBodyBytes = 4096;

  final HttpServer _server;
  final RemoteControlActions _actions;
  final String Function() _token;
  final Duration actionTimeout;

  int get port => _server.port;
  Uri get baseUri => Uri.parse('http://127.0.0.1:$port/v1');

  /// Escucha en `127.0.0.1:[port]` (0 = puerto libre). Lanza si está ocupado.
  static Future<RemoteControlServer> start({
    required RemoteControlActions actions,
    required String Function() token,
    int port = defaultPort,
    Duration actionTimeout = const Duration(seconds: 30),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    final remote = RemoteControlServer._(server, actions, token, actionTimeout);
    server.listen(
      (request) => unawaited(remote._handle(request)),
      onError: (Object _) {},
    );
    return remote;
  }

  Future<void> close() => _server.close(force: true);

  /// Token aleatorio de 128 bits en hexadecimal.
  static String generateToken() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  static bool _sameToken(String given, String expected) {
    final a = utf8.encode(given), b = utf8.encode(expected);
    var difference = a.length ^ b.length;
    for (var i = 0; i < max(a.length, b.length); i++) {
      difference |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
    }
    return difference == 0;
  }

  bool _hostAllowed(String? host) {
    if (host == null) return false;
    final lower = host.toLowerCase();
    return lower == '127.0.0.1' ||
        lower == 'localhost' ||
        lower == '127.0.0.1:$port' ||
        lower == 'localhost:$port';
  }

  String? _givenToken(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != null && auth.length > 7 && auth.startsWith('Bearer ')) {
      return auth.substring(7).trim();
    }
    return request.headers.value('x-aurora-token') ??
        request.uri.queryParameters['token'];
  }

  Future<void> _reply(
    HttpRequest request,
    int status,
    Map<String, Object?> body,
  ) async {
    final response = request.response
      ..statusCode = status
      ..headers.contentType = ContentType(
        'application',
        'json',
        charset: 'utf-8',
      )
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('X-Content-Type-Options', 'nosniff');
    response.add(utf8.encode(jsonEncode(body)));
    await response.close();
  }

  Future<Map<String, Object?>> _readBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) {
        throw const RemoteControlException(413, 'Cuerpo demasiado grande.');
      }
    }
    if (bytes.isEmpty) return const {};
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {}
    throw const RemoteControlException(
      400,
      'El cuerpo debe ser un objeto JSON.',
    );
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      // Un navegador siempre manda Origin en peticiones entre sitios.
      if (request.headers.value('origin') != null ||
          !_hostAllowed(request.headers.value(HttpHeaders.hostHeader))) {
        return await _reply(request, 403, {
          'ok': false,
          'error': 'Petición no permitida.',
        });
      }
      final given = _givenToken(request);
      if (given == null || !_sameToken(given, _token())) {
        request.response.headers.set(
          HttpHeaders.wwwAuthenticateHeader,
          'Bearer',
        );
        return await _reply(request, 401, {
          'ok': false,
          'error': 'Token inválido o ausente.',
        });
      }
      final method = request.method;
      if (method != 'GET' && method != 'POST') {
        request.response.headers.set(HttpHeaders.allowHeader, 'GET, POST');
        return await _reply(request, 405, {
          'ok': false,
          'error': 'Método no permitido.',
        });
      }
      final segments = request.uri.pathSegments.where((s) => s.isNotEmpty);
      final route = segments.join('/');
      if (request.contentLength > maxBodyBytes) {
        throw const RemoteControlException(413, 'Cuerpo demasiado grande.');
      }
      final body = method == 'POST'
          ? await _readBody(request)
          : const <String, Object?>{};
      final result = await _dispatch(route, request, body).timeout(
        actionTimeout,
        onTimeout: () => throw const RemoteControlException(
          504,
          'Aurora tardó demasiado en responder.',
        ),
      );
      await _reply(request, 200, {'ok': true, ...result});
    } on RemoteControlException catch (failure) {
      await _reply(request, failure.status, {
        'ok': false,
        'error': failure.message,
      });
    } catch (_) {
      try {
        await _reply(request, 500, {'ok': false, 'error': 'Error interno.'});
      } catch (_) {}
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String route,
    HttpRequest request,
    Map<String, Object?> body,
  ) async {
    switch (route) {
      case 'v1/status':
        return _actions.status();
      case 'v1/play':
        await _actions.play();
      case 'v1/pause':
        await _actions.pause();
      case 'v1/toggle':
        await _actions.toggle();
      case 'v1/next':
        await _actions.next();
      case 'v1/previous':
        await _actions.previous();
      case 'v1/jam/start':
        final mode =
            '${body['mode'] ?? request.uri.queryParameters['mode'] ?? 'auto'}';
        if (mode != 'auto' && mode != 'online' && mode != 'lan') {
          throw const RemoteControlException(
            400,
            'mode debe ser auto, online o lan.',
          );
        }
        return await _actions.startJam(mode: mode);
      default:
        throw const RemoteControlException(404, 'Ruta desconocida.');
    }
    return _actions.status();
  }
}
