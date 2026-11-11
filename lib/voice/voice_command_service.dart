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

/// Modelo listo: existe con el tamaño exacto (el SHA-256 se comprobó al
/// descargarlo, y solo entonces se renombra desde `.part`).
bool _modelFileComplete(String path) {
  final file = File(path);
  return file.existsSync() && file.lengthSync() == VoiceModel.bytes;
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
    bool Function()? cpuSupported,
    Future<VoiceListenerPort> Function(String modelPath)? startListener,
    Future<void> Function(File target, VoiceDownloadProgress onProgress)?
    download,
    bool Function(String modelPath)? modelReady,
    this.pollEvery = const Duration(milliseconds: 150),
    this.silentAfter = const Duration(seconds: 8),
  }) : supported = supported ?? (Platform.isWindows || Platform.isLinux),
       _cpuSupported = cpuSupported ?? rust.voiceCpuSupported,
       _customStart = startListener,
       _download =
           download ??
           ((file, onProgress) => downloadVerified(
             VoiceModel.url,
             file,
             expectedBytes: VoiceModel.bytes,
             expectedSha256: VoiceModel.sha256Hex,
             onProgress: onProgress,
           )),
       _modelReady = modelReady ?? _modelFileComplete;

  static const enabledKey = 'voiceCommandsEnabled';
  static const lyricsSyncKey = 'lyricsAutoSync';
  static const diagnosticsKey = 'voiceDiagnostics';

  final SharedPreferences _prefs;
  final RemoteControlActions _actions;
  final Directory supportDirectory;
  final bool supported;
  final Duration pollEvery;
  final bool Function() _cpuSupported;
  final Future<VoiceListenerPort> Function(String modelPath)? _customStart;
  final Future<void> Function(File target, VoiceDownloadProgress) _download;
  final bool Function(String modelPath) _modelReady;

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

  /// Lo último que Whisper entendió (sea orden o no): sirve para ver por qué
  /// una orden no se reconoció.
  String? lastHeard;
  DateTime? lastHeardAt;
  bool awaitingCommand = false;
  double level = 0;

  /// El micrófono lleva [silentAfter] sin entregar sonido: suele ser que está
  /// silenciado o que Windows no deja a las apps de escritorio usarlo.
  bool microphoneSilent = false;
  DateTime? _quietSince;
  final Duration silentAfter;

  bool get enabled => supported && (_prefs.getBool(enabledKey) ?? false);

  /// Alinear las letras con el audio (usa el mismo modelo). Activada por
  /// defecto, pero solo trabaja cuando el modelo ya está descargado.
  bool get lyricsSyncEnabled =>
      supported && (_prefs.getBool(lyricsSyncKey) ?? true);

  /// Diagnóstico (opcional, apagado por defecto): guarda las últimas 40 frases
  /// con lo que Whisper entendió y lo que se hizo, en [diagnosticsDirectory].
  bool get diagnosticsEnabled =>
      supported && (_prefs.getBool(diagnosticsKey) ?? false);

  Directory get diagnosticsDirectory =>
      Directory(p.join(supportDirectory.path, 'voice', 'diagnostico'));

  Future<void> setDiagnostics(bool value) => _enqueue(() async {
    if (!supported) return;
    await _prefs.setBool(diagnosticsKey, value);
    if (_listener != null) {
      _end();
      await _begin(); // el motor lee la carpeta al arrancar
    }
    _notify();
  });

  Future<VoiceListenerPort> _openListener(String path) async {
    final custom = _customStart;
    if (custom != null) return custom(path);
    return _RustListener(
      await rust.VoiceListener.start(
        modelPath: path,
        diagnosticsDir: diagnosticsEnabled ? diagnosticsDirectory.path : null,
      ),
    );
  }

  /// Descarga del modelo por la alineación de letras (sin escuchar).
  bool modelBusy = false;
  String? modelError;

  /// El procesador y el modelo permiten analizar audio.
  bool get analysisReady =>
      supported && _cpuSupported() && _modelReady(_modelFile.path);

  String get modelPath => _modelFile.path;

  Future<void> setLyricsSync(bool value) => _enqueue(() async {
    if (!supported) return;
    await _prefs.setBool(lyricsSyncKey, value);
    modelError = null;
    if (value && !_modelReady(_modelFile.path)) {
      if (!_cpuSupported()) {
        modelError = _noAvx2;
      } else {
        modelBusy = true;
        progress = 0;
        _notify();
        try {
          await _fetchModel(listening: false);
        } catch (failure) {
          modelError = failure is VoiceModelException
              ? failure.message
              : '$failure';
        } finally {
          modelBusy = false;
        }
      }
    }
    _notify();
  });

  static const _noAvx2 =
      'Este procesador no admite AVX2, necesario para el reconocimiento de voz.';

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

  File get _modelFile => VoiceModel.file(supportDirectory);

  Future<void> _begin() async {
    if (_listener != null) return;
    error = null;
    try {
      if (!_cpuSupported()) throw const VoiceModelException(_noAvx2);
      if (!_modelReady(_modelFile.path)) await _fetchModel();
      state = VoiceState.starting;
      _notify();
      _listener = await _openListener(_modelFile.path);
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

  Future<void> _fetchModel({bool listening = true}) async {
    if (listening) {
      state = VoiceState.downloading;
      progress = 0;
      _notify();
    }
    await _download(_modelFile, (fraction) {
      progress = fraction.clamp(0, 1);
      _notify();
    });
    if (!_modelReady(_modelFile.path)) {
      throw const VoiceModelException(
        'El modelo de voz no quedó bien descargado. Inténtalo de nuevo.',
      );
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
    lastHeard = null;
    lastHeardAt = null;
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
      final heard = event.heard?.trim();
      if (heard != null && heard.isNotEmpty) {
        lastHeard = heard;
        lastHeardAt = DateTime.now();
      }
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
