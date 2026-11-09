import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/api/voice.dart' as rust;
import '../remote/remote_control_server.dart';
import 'voice_model.dart';

/// Lo que el servicio necesita del motor de escucha (Rust); simulable.
abstract class VoiceListenerPort {
  List<rust.VoiceEvent> poll();
  double get level;
  bool get isRunning;
  void stop();
}

class _RustListener implements VoiceListenerPort {
  _RustListener(this._inner);
  final rust.VoiceListener _inner;
  @override
  List<rust.VoiceEvent> poll() => _inner.poll();
  @override
  double get level => _inner.level();
  @override
  bool get isRunning => _inner.isRunning();
  @override
  void stop() => _inner.stop();
}

enum VoiceState { off, downloading, starting, listening, error }

/// Comandos de voz: «Aurora, pausa», «Aurora, siguiente»… Apagados por
/// defecto. Al activarlos se descarga una vez el modelo (verificado) y se abre
/// el micrófono; el audio se reconoce en el equipo y no se guarda. Una orden
/// sin «Aurora» delante nunca llega aquí: el motor de Rust la descarta.
class VoiceCommandService extends ChangeNotifier {
  VoiceCommandService(
    this._prefs,
    this._actions, {
    required this.supportDirectory,
    bool? supported,
    String? Function()? libraryPath,
    Future<VoiceListenerPort> Function(String library, String modelDir)?
    startListener,
    Future<void> Function(File archive, VoiceDownloadProgress onProgress)?
    download,
    Future<void> Function(String archive, String dest)? installModel,
    bool Function(String dir)? modelInstalled,
    this.pollEvery = const Duration(milliseconds: 150),
    this.silentAfter = const Duration(seconds: 8),
  }) : supported = supported ?? (Platform.isWindows || Platform.isLinux),
       _libraryPath = libraryPath ?? _defaultLibraryPath,
       _startListener =
           startListener ??
           ((lib, dir) async => _RustListener(
             await rust.VoiceListener.start(libPath: lib, modelDir: dir),
           )),
       _download =
           download ??
           ((file, onProgress) => downloadVerified(
             VoiceModel.url,
             file,
             expectedBytes: VoiceModel.bytes,
             expectedSha256: VoiceModel.sha256Hex,
             onProgress: onProgress,
           )),
       _install =
           installModel ??
           ((archive, dest) =>
               rust.voiceInstallModel(archive: archive, dest: dest)),
       _modelInstalled =
           modelInstalled ?? ((dir) => rust.voiceModelInstalled(dir: dir));

  static const enabledKey = 'voiceCommandsEnabled';

  final SharedPreferences _prefs;
  final RemoteControlActions _actions;
  final Directory supportDirectory;
  final bool supported;
  final Duration pollEvery;
  final String? Function() _libraryPath;
  final Future<VoiceListenerPort> Function(String, String) _startListener;
  final Future<void> Function(File, VoiceDownloadProgress) _download;
  final Future<void> Function(String, String) _install;
  final bool Function(String) _modelInstalled;

  VoiceListenerPort? _listener;
  Timer? _timer;
  Future<void> _serial = Future.value();
  bool _disposed = false;

  VoiceState state = VoiceState.off;
  double progress = 0;
  String? error;

  /// Última orden ejecutada (texto para Ajustes) y cuándo.
  String? lastCommand;
  DateTime? lastCommandAt;
  bool awaitingCommand = false;
  double level = 0;

  /// El micrófono lleva [silentAfter] sin entregar sonido: suele ser que está
  /// silenciado o que Windows no deja a las apps de escritorio usarlo.
  bool microphoneSilent = false;
  DateTime? _quietSince;
  final Duration silentAfter;

  bool get enabled => supported && (_prefs.getBool(enabledKey) ?? false);

  /// Ruta de `libvosk`, junto a las herramientas de Aurora.
  static String? _defaultLibraryPath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final name = Platform.isWindows ? 'libvosk.dll' : 'libvosk.so';
    for (final candidate in [
      p.join(exeDir, 'tools', 'vosk', name),
      p.join(exeDir, 'lib', name),
    ]) {
      if (File(candidate).existsSync()) return candidate;
    }
    // Linux: biblioteca del sistema (LD_LIBRARY_PATH / ld.so.cache).
    return Platform.isLinux ? name : null;
  }

  static const _labels = {
    rust.VoiceIntent.pause: 'Pausa',
    rust.VoiceIntent.resume: 'Continuar',
    rust.VoiceIntent.play: 'Reproducir',
    rust.VoiceIntent.next: 'Siguiente',
    rust.VoiceIntent.previous: 'Anterior',
  };

  /// Al abrir la app: si estaba activada, vuelve a escuchar.
  Future<void> start() => _enqueue(() async {
    if (enabled) await _begin();
  });

  Future<void> setEnabled(bool value) => _enqueue(() async {
    if (!supported) return;
    await _prefs.setBool(enabledKey, value);
    if (value) {
      await _begin();
    } else {
      _end();
      state = VoiceState.off;
      error = null;
      _notify();
    }
  });

  Future<void> _enqueue(Future<void> Function() action) {
    final result = _serial.then((_) => action());
    _serial = result.catchError((Object _) {});
    return result;
  }

  Directory get _modelDir => VoiceModel.directory(supportDirectory);

  Future<void> _begin() async {
    if (_listener != null) return;
    error = null;
    try {
      final library = _libraryPath();
      if (library == null) {
        throw const VoiceModelException(
          'Falta la biblioteca de voz (libvosk). Reinstala Aurora.',
        );
      }
      if (!_modelInstalled(_modelDir.path)) await _fetchModel();
      state = VoiceState.starting;
      _notify();
      _listener = await _startListener(library, _modelDir.path);
      state = VoiceState.listening;
      _timer = Timer.periodic(pollEvery, (_) => _poll());
    } catch (failure) {
      state = VoiceState.error;
      error = failure is VoiceModelException
          ? failure.message
          : '$failure'.replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), '');
    }
    _notify();
  }

  Future<void> _fetchModel() async {
    state = VoiceState.downloading;
    progress = 0;
    _notify();
    final archive = File(
      p.join(supportDirectory.path, 'voice', '${VoiceModel.name}.zip'),
    );
    try {
      await _download(archive, (fraction) {
        progress = fraction.clamp(0, 1);
        _notify();
      });
      await _install(archive.path, _modelDir.path);
    } finally {
      try {
        if (await archive.exists()) await archive.delete();
      } on FileSystemException {
        // Se borra en la siguiente descarga.
      }
    }
  }

  void _end() {
    _timer?.cancel();
    _timer = null;
    _listener?.stop();
    _listener = null;
    awaitingCommand = false;
    level = 0;
    microphoneSilent = false;
    _quietSince = null;
  }

  void _poll() {
    final listener = _listener;
    if (listener == null || _disposed) return;
    level = listener.level;
    if (level > 0) {
      _quietSince = null;
      microphoneSilent = false;
    } else {
      _quietSince ??= DateTime.now();
      microphoneSilent = DateTime.now().difference(_quietSince!) >= silentAfter;
    }
    for (final event in listener.poll()) {
      if (event.stopped != null) {
        _end();
        state = VoiceState.error;
        error = event.stopped;
        break;
      }
      if (event.wake) {
        awaitingCommand = true;
      } else if (event.intent != null) {
        awaitingCommand = false;
        unawaited(_run(event.intent!));
      }
    }
    _notify();
  }

  Future<void> _run(rust.VoiceIntent intent) async {
    lastCommand = _labels[intent];
    lastCommandAt = DateTime.now();
    try {
      switch (intent) {
        case rust.VoiceIntent.play:
        case rust.VoiceIntent.resume:
          await _actions.play();
        case rust.VoiceIntent.pause:
          await _actions.pause();
        case rust.VoiceIntent.next:
          await _actions.next();
        case rust.VoiceIntent.previous:
          await _actions.previous();
      }
      error = null;
    } on RemoteControlException catch (failure) {
      error = failure.message;
    } catch (_) {
      error = 'No se pudo ejecutar la orden.';
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _end();
    super.dispose();
  }
}
