import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../jam/jam_models.dart' show isJamAddress, jamRandomSecret;
import '../library/library_database.dart';
import 'sync_store.dart';

/// Transferencia de la biblioteca (favoritos, listas, historial y gusto del DJ)
/// entre dos dispositivos **de la misma red**, sin pasar por el servidor en la
/// nube: el origen muestra un QR, el destino lo escanea y baja solo lo que
/// cambió desde la última vez. No gasta ni una petición del plan de Supabase.

const lanSyncPrefix = 'aurora-sync:';
const _kinds = ['favorites', 'playlists', 'history', 'taste'];
const _pageSize = 200;

/// Lo que viaja en el QR: dónde conectar, la clave de un solo uso y cuándo caduca.
class LanSyncInvite {
  const LanSyncInvite({
    required this.address,
    required this.port,
    required this.token,
    required this.deviceId,
    required this.expiresAt,
  });

  final String address;
  final int port;
  final String token;

  /// Identifica al origen: el destino recuerda hasta dónde le llegó de cada uno.
  final String deviceId;
  final DateTime expiresAt;

  String encode() =>
      lanSyncPrefix +
      base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'v': 1,
                'a': address,
                'p': port,
                't': token,
                'd': deviceId,
                'e': expiresAt.millisecondsSinceEpoch,
              }),
            ),
          )
          .replaceAll('=', '');

  /// Valida lo que se escanea: es entrada no confiable.
  static LanSyncInvite decode(
    String text, {
    bool allowLoopback = false,
    DateTime? now,
  }) {
    final raw = text.trim();
    if (!raw.startsWith(lanSyncPrefix) || raw.length > 1024) {
      throw const FormatException(
        'Ese código no es de una transferencia de Aurora.',
      );
    }
    final Object? json;
    try {
      final body = raw.substring(lanSyncPrefix.length);
      json = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(body))),
      );
    } catch (_) {
      throw const FormatException('El código está dañado.');
    }
    if (json is! Map || json['v'] != 1) {
      throw const FormatException('Versión de código no admitida.');
    }
    final address = json['a'], port = json['p'], token = json['t'];
    final device = json['d'], expires = json['e'];
    if (address is! String ||
        !isJamAddress(address, allowLoopback: allowLoopback)) {
      // Solo redes privadas: un código nunca puede apuntar a internet.
      throw const FormatException('El código no es de una red local.');
    }
    if (port is! int ||
        port < 1024 ||
        port > 65535 ||
        token is! String ||
        token.length < 32 ||
        token.length > 128 ||
        device is! String ||
        device.isEmpty ||
        device.length > 64 ||
        expires is! int) {
      throw const FormatException('El código no es válido.');
    }
    final until = DateTime.fromMillisecondsSinceEpoch(expires);
    if (!until.isAfter(now ?? DateTime.now())) {
      throw const FormatException(
        'El código caducó. Genera otro en el otro dispositivo.',
      );
    }
    return LanSyncInvite(
      address: address,
      port: port,
      token: token,
      deviceId: device,
      expiresAt: until,
    );
  }
}

/// Identificador estable de este dispositivo (no es personal: aleatorio).
String lanDeviceId(SharedPreferences preferences) {
  final saved = preferences.getString('lan.deviceId');
  if (saved != null && saved.isNotEmpty) return saved;
  final id = jamRandomSecret(12);
  preferences.setString('lan.deviceId', id);
  return id;
}

/// Servidor de solo lectura, en la IP privada elegida y un puerto aleatorio.
/// Exige la clave en cada petición, caduca solo y limita las peticiones.
class LanSyncServer {
  LanSyncServer(
    this.database, {
    required this.deviceId,
    this.ttl = const Duration(minutes: 5),
    this.maxRequests = 200,
    this.allowLoopback = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final LibraryDatabase database;
  final String deviceId;
  final Duration ttl;
  final int maxRequests;
  final bool allowLoopback;
  final DateTime Function() _clock;

  HttpServer? _server;
  Timer? _expiry;
  String _token = '';
  late DateTime _expires;
  int _requests = 0;

  bool get running => _server != null;

  Future<LanSyncInvite> start(String address) async {
    if (!isJamAddress(address, allowLoopback: allowLoopback)) {
      throw const FormatException(
        'Solo se puede transferir por una red local.',
      );
    }
    await stop();
    _token = jamRandomSecret(32);
    _expires = _clock().add(ttl);
    _requests = 0;
    final server = await HttpServer.bind(InternetAddress(address), 0);
    _server = server;
    unawaited(server.forEach(_handle));
    _expiry = Timer(ttl, () {
      if (identical(_server, server)) unawaited(stop());
    });
    return LanSyncInvite(
      address: address,
      port: server.port,
      token: _token,
      deviceId: deviceId,
      expiresAt: _expires,
    );
  }

  Future<void> stop() async {
    _expiry?.cancel();
    _expiry = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    final given = header.startsWith('Bearer ') ? header.substring(7) : '';
    if (given.length != _token.length) return false;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given.codeUnitAt(i) ^ _token.codeUnitAt(i);
    }
    return diff == 0; // comparación en tiempo constante
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      if (!_clock().isBefore(_expires) || ++_requests > maxRequests) {
        response.statusCode = HttpStatus.gone;
      } else if (request.method != 'GET' || !_authorized(request)) {
        response.statusCode = HttpStatus.unauthorized;
      } else {
        final segments = request.uri.pathSegments;
        final since = int.tryParse(request.uri.queryParameters['since'] ?? '0');
        if (segments.length != 2 ||
            segments[0] != 'lan' ||
            !_kinds.contains(segments[1]) ||
            since == null ||
            since < 0) {
          response.statusCode = HttpStatus.badRequest;
        } else {
          response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(await _page(segments[1], since)));
        }
      }
    } catch (_) {
      response.statusCode = HttpStatus.internalServerError;
    } finally {
      await response.close();
    }
  }

  /// Lo que cambió después de [since] (ms), de más antiguo a más nuevo.
  Future<Map<String, Object?>> _page(String kind, int since) async {
    final meta = await database.readSyncMeta(kind);
    // Lo anterior a cualquier sincronización tiene marca 0: va en la primera
    // transferencia (since == 0) y después solo lo que cambió.
    final keys =
        meta.keys
            .where(
              (k) =>
                  meta[k]!.updatedAt > since ||
                  (since == 0 && meta[k]!.updatedAt == 0),
            )
            .toList()
          ..sort((a, b) => meta[a]!.updatedAt.compareTo(meta[b]!.updatedAt));
    final rows = <Map<String, dynamic>>[];
    var last = since;
    for (final key in keys) {
      if (rows.length >= _pageSize) break;
      final m = meta[key]!;
      final row = await database.buildSyncRow(kind, key, m.deleted);
      last = m.updatedAt;
      if (row == null) continue;
      rows.add({
        ...row,
        'updated_at': DateTime.fromMillisecondsSinceEpoch(
          m.updatedAt,
          isUtc: true,
        ).toIso8601String(),
        'deleted': m.deleted,
      });
    }
    return {'rows': rows, 'next': last, 'more': keys.length > rows.length};
  }
}

class LanSyncException implements Exception {
  const LanSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lo que se aplicó en el destino, por tipo.
class LanSyncResult {
  const LanSyncResult(this.applied);
  final Map<String, int> applied;
  int get total => applied.values.fold(0, (a, b) => a + b);
}

class LanSyncClient {
  LanSyncClient(
    this.database,
    this.preferences, {
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _factory = clientFactory ?? HttpClient.new;

  final LibraryDatabase database;
  final SharedPreferences preferences;
  final Duration timeout;
  final HttpClient Function() _factory;

  String _cursor(LanSyncInvite i, String kind) => 'lan.wm.${i.deviceId}.$kind';

  String _keyOf(String kind, Map<String, dynamic> row) => switch (kind) {
    'favorites' || 'history' => row['track_id'] as String,
    'playlists' => row['id'] as String,
    _ => '1',
  };

  Future<LanSyncResult> receive(LanSyncInvite invite) async {
    final applied = <String, int>{};
    final client = _factory()..connectionTimeout = timeout;
    try {
      for (final kind in _kinds) {
        var since = preferences.getInt(_cursor(invite, kind)) ?? 0;
        var count = 0;
        while (true) {
          final page = await _get(client, invite, kind, since);
          final rows = (page['rows'] as List)
              .whereType<Map>()
              .map((r) => Map<String, dynamic>.from(r))
              .toList();
          count += await _apply(kind, rows);
          final next = page['next'];
          if (next is int && next > since) {
            since = next;
            await preferences.setInt(_cursor(invite, kind), since);
          }
          if (page['more'] != true || rows.isEmpty) break;
        }
        applied[kind] = count;
      }
    } finally {
      client.close(force: true);
    }
    return LanSyncResult(applied);
  }

  Future<Map<String, dynamic>> _get(
    HttpClient client,
    LanSyncInvite invite,
    String kind,
    int since,
  ) async {
    try {
      final request = await client
          .getUrl(
            Uri.http('${invite.address}:${invite.port}', '/lan/$kind', {
              'since': '$since',
            }),
          )
          .timeout(timeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${invite.token}',
      );
      final response = await request.close().timeout(timeout);
      if (response.statusCode == HttpStatus.gone) {
        throw const LanSyncException(
          'El código caducó. Genera otro en el otro dispositivo.',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw LanSyncException(
          response.statusCode == HttpStatus.unauthorized
              ? 'El otro dispositivo rechazó el código.'
              : 'El otro dispositivo respondió ${response.statusCode}.',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) {
          throw const LanSyncException('La respuesta es demasiado grande.');
        }
      }
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, dynamic> || json['rows'] is! List) {
        throw const LanSyncException('Respuesta no válida.');
      }
      return json;
    } on LanSyncException {
      rethrow;
    } on TimeoutException {
      throw const LanSyncException(
        'No hubo respuesta. Comprueba que ambos estén en la misma red Wi-Fi y que el firewall permita a Aurora.',
      );
    } on SocketException {
      throw const LanSyncException(
        'No se pudo conectar. Comprueba que ambos estén en la misma red Wi-Fi.',
      );
    }
  }

  /// Aplica lo recibido con la misma regla que la nube: gana lo más reciente.
  Future<int> _apply(String kind, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return 0;
    final remote = <String, int>{};
    for (final r in rows) {
      final updated = DateTime.tryParse('${r['updated_at']}');
      if (updated == null) continue;
      try {
        remote[_keyOf(kind, r)] = updated.millisecondsSinceEpoch;
      } catch (_) {}
    }
    final winners = remoteWinners(await database.readSyncMeta(kind), remote);
    var applied = 0;
    for (final r in rows) {
      final String key;
      try {
        key = _keyOf(kind, r);
      } catch (_) {
        continue;
      }
      if (!winners.contains(key)) continue;
      if (await database.applyRemoteRow(kind, r)) {
        await database.setSyncMeta(
          kind,
          key,
          remote[key]!,
          r['deleted'] == true,
        );
        applied++;
      }
    }
    return applied;
  }
}
