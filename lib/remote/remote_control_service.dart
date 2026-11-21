import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_control_server.dart';

/// Interruptor, puerto y token de la API de control remoto, y su servidor.
/// Apagada por defecto: sin activarla en Ajustes no abre ningún puerto.
class RemoteControlService extends ChangeNotifier {
  RemoteControlService(
    this._prefs,
    this._actions, {
    bool? supported,
    this.defaultPort = RemoteControlServer.defaultPort,
    this.discoveryFile,
  }) : supported = supported ?? (Platform.isWindows || Platform.isLinux);

  static const enabledKey = 'remoteControlEnabled';
  static const tokenKey = 'remoteControlToken';
  static const portKey = 'remoteControlPort';

  final SharedPreferences _prefs;
  final RemoteControlActions _actions;
  final int defaultPort;

  /// Archivo `remote_control.json` (URL y token) que lee el plugin de Stream
  /// Deck para conectarse solo. Existe únicamente mientras la API está activa.
  final File? discoveryFile;

  /// Solo escritorio: el Stream Deck está en el mismo PC.
  final bool supported;

  RemoteControlServer? _server;
  Future<void> _serial = Future.value();
  String? problem;
  bool _disposed = false;

  bool get enabled => supported && (_prefs.getBool(enabledKey) ?? false);
  bool get running => _server != null;
  int get port => _server?.port ?? (_prefs.getInt(portKey) ?? defaultPort);

  /// Token actual; se crea la primera vez que se pide.
  String get token {
    final saved = _prefs.getString(tokenKey);
    if (saved != null && saved.length >= 32) return saved;
    final fresh = RemoteControlServer.generateToken();
    unawaited(_prefs.setString(tokenKey, fresh));
    _cachedToken = fresh;
    return fresh;
  }

  String? _cachedToken;
  String _currentToken() => _cachedToken ?? token;

  String get baseUrl => 'http://127.0.0.1:$port/v1';

  /// Arranca si estaba activada (al abrir la app).
  Future<void> start() => _enqueue(() async {
    if (enabled) await _open();
  });

  Future<void> setEnabled(bool value) => _enqueue(() async {
    if (!supported) return;
    await _prefs.setBool(enabledKey, value);
    if (value) {
      await _open();
    } else {
      await _shut();
    }
    _notify();
  });

  /// Invalida el token anterior: lo que lo use deja de funcionar.
  Future<void> regenerateToken() async {
    final fresh = RemoteControlServer.generateToken();
    _cachedToken = fresh;
    await _prefs.setString(tokenKey, fresh);
    if (_server != null) await _writeDiscovery();
    _notify();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.catchError((Object _) {});
    return result;
  }

  Future<void> _open() async {
    if (_server != null) return;
    problem = null;
    _cachedToken = token;
    try {
      _server = await RemoteControlServer.start(
        actions: _actions,
        token: _currentToken,
        port: _prefs.getInt(portKey) ?? defaultPort,
      );
      await _writeDiscovery();
    } on SocketException {
      problem =
          'El puerto ${_prefs.getInt(portKey) ?? defaultPort} está ocupado.';
    }
    _notify();
  }

  /// Escritura atómica: el plugin nunca lee un archivo a medias.
  Future<void> _writeDiscovery() async {
    final file = discoveryFile;
    if (file == null) return;
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'baseUrl': baseUrl,
          'port': port,
          'token': _currentToken(),
        }),
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException {
      // Sin el archivo el plugin se configura a mano; la API sigue funcionando.
    }
  }

  Future<void> _deleteDiscovery() async {
    try {
      await discoveryFile?.delete();
    } on FileSystemException {
      // Ya no existe.
    }
  }

  Future<void> _shut() async {
    final server = _server;
    _server = null;
    problem = null;
    await server?.close();
    await _deleteDiscovery();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_shut());
    super.dispose();
  }
}
