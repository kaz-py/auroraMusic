import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../jam/transport/jam_config.dart';
import 'feature_flags.dart';

/// Cómo usa Aurora los servicios en línea (Supabase: cuenta, amigos, Jam en
/// línea). La red local (Jam por QR) no depende de esto.
enum OnlineMode {
  /// Se usan si el servidor responde; si no, Aurora sigue en modo local y lo
  /// vuelve a probar sola cada cierto tiempo.
  auto,

  /// Solo local: no se contacta con el servidor.
  off,
}

/// ¿Responde el servidor? Una comprobación barata (una petición a `/auth/v1/health`)
/// con resultado en caché: un proyecto pausado o sin cuota no hace esperar a
/// cada pantalla, y en cuanto vuelve se detecta y se avisa a quien escucha.
class OnlineStatus extends ChangeNotifier {
  OnlineStatus({
    required SharedPreferences preferences,
    bool? enabled,
    Future<bool> Function(Duration timeout)? probe,
    this.timeout = const Duration(seconds: 4),
    this.upTtl = const Duration(minutes: 5),
    this.downTtl = const Duration(minutes: 2),
    DateTime Function()? clock,
  }) : _enabled = enabled,
       _prefs = preferences,
       _probe = probe ?? _healthProbe,
       _clock = clock ?? DateTime.now;

  static const modeKey = 'onlineServicesMode';

  /// Interruptor general ([kSupabaseEnabled]): apagado, nada contacta con el servidor.
  final bool? _enabled;
  bool get enabled => _enabled ?? supabaseServicesEnabled;
  final SharedPreferences _prefs;
  final Future<bool> Function(Duration timeout) _probe;
  final Duration timeout, upTtl, downTtl;
  final DateTime Function() _clock;

  bool? _reachable;
  DateTime? _checkedAt;
  Future<bool>? _checking;
  Timer? _retry;
  final _recovered = <void Function()>[];

  OnlineMode get mode =>
      !enabled || _prefs.getString(modeKey) == OnlineMode.off.name
      ? OnlineMode.off
      : OnlineMode.auto;

  /// Último resultado conocido (`null` = todavía sin comprobar o en modo local).
  bool? get lastKnown => mode == OnlineMode.off ? false : _reachable;

  Future<void> setMode(OnlineMode value) async {
    await _prefs.setString(modeKey, value.name);
    _reachable = null;
    _checkedAt = null;
    _retry?.cancel();
    notifyListeners();
    if (value == OnlineMode.auto) unawaited(available(force: true));
  }

  /// Avisa cuando el servidor vuelve tras haber estado caído.
  void onRecovered(void Function() callback) => _recovered.add(callback);

  /// `true` si se pueden usar los servicios en línea ahora. Sin servidor
  /// configurado no hay nada que probar y se deja decidir al transporte.
  Future<bool> available({bool force = false}) {
    if (!enabled || mode == OnlineMode.off) return Future.value(false);
    final cached = _reachable;
    final at = _checkedAt;
    if (!force && cached != null && at != null) {
      final ttl = cached ? upTtl : downTtl;
      if (_clock().difference(at) < ttl) return Future.value(cached);
    }
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<bool> _check() async {
    bool ok;
    try {
      ok = await _probe(timeout);
    } catch (_) {
      ok = false;
    }
    final before = _reachable;
    _reachable = ok;
    _checkedAt = _clock();
    _retry?.cancel();
    if (!ok && mode == OnlineMode.auto) {
      // Sigue probando en segundo plano: al volver, todo se reconecta solo.
      _retry = Timer(downTtl, () => unawaited(available(force: true)));
    }
    if (before != ok) notifyListeners();
    if (ok && before == false) {
      for (final callback in List.of(_recovered)) {
        callback();
      }
    }
    return ok;
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }

  static Future<bool> _healthProbe(Duration timeout) async {
    final config = JamSupabaseConfig.fromEnvironment;
    if (config == null) return true; // nada que comprobar: decide el transporte
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .getUrl(Uri.parse('${config.url}/auth/v1/health'))
          .timeout(timeout);
      request.headers.set('apikey', config.anonKey);
      final response = await request.close().timeout(timeout);
      await response.drain<void>();
      // 5xx = proyecto pausado o caído; cualquier otra respuesta es un servidor vivo.
      return response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}
