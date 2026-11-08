import 'dart:async';

import 'package:flutter/foundation.dart';

import '../bridge/api/audio.dart' as rust_audio;
import '../bridge/api/playback.dart' as rust;
import '../core/audio_backend.dart';
import '../core/models.dart';
import 'audio_math.dart';
import 'eq_model.dart';
import 'stream_guard.dart';

/// Motor de audio de escritorio: archivos, el proxy local de YouTube y las URL
/// http(s) se decodifican y se mezclan en Rust (`rust/crates/aurora_playback`).
/// Un formato que Symphonia no maneja o la falta de dispositivo de salida son
/// errores de carga con su motivo; no hay motor de respaldo.
class RustMusicAudio extends AudioBackend {
  /// [engineFactory] existe para las pruebas (salida sin dispositivo).
  RustMusicAudio({rust.PlayerEngine Function()? engineFactory})
    : _engineFactory = engineFactory ?? rust.PlayerEngine.create;

  /// El motor de escritorio.
  static AudioBackend create() => RustMusicAudio();

  final rust.PlayerEngine Function() _engineFactory;
  rust.PlayerEngine? _engine;
  final _spectrum = ValueNotifier<List<double>>(List.filled(48, 0));
  final _completed = StreamController<void>.broadcast();
  Timer? _timer;
  ResolvedAudio? _resolved;
  Future<void> _operations = Future.value();
  int _generation = 0, _seekGeneration = 0, _ticks = 0;
  bool _disposed = false, _playing = false, _buffering = false;
  bool _playIntent = false, _loaded = false, _streaming = false;
  bool _completing = false, _visualization = true, _recoveringDevice = false;
  Duration _position = Duration.zero, _duration = Duration.zero;
  Duration _offset = Duration.zero;
  double _volume = 0.8;
  bool _eqEnabled = false, _eqAutoPreamp = true;
  List<EqBand> _eqBands = eqFlatBands();
  @override
  String? lastError;

  @override
  bool get isPlaying => _playing;
  @override
  bool get isBuffering => _buffering;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get volume => _volume;
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  /// Motivo por el que no se pudo abrir el dispositivo de salida.
  String? rustUnavailableReason;

  @override
  Future<void> initialize() async {
    _openEngine();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  /// Abre la salida de audio; `false` (con el motivo en [rustUnavailableReason])
  /// si no hay dispositivo. Se reintenta en cada carga: pueden haber conectado
  /// unos auriculares entretanto.
  bool _openEngine() {
    if (_engine != null) return true;
    try {
      _engine = _engineFactory();
    } catch (error) {
      rustUnavailableReason = '$error';
      return false;
    }
    rustUnavailableReason = null;
    _applyToEngine();
    return true;
  }

  void _applyToEngine() {
    final engine = _engine;
    if (engine == null) return;
    engine.setVolume(volume: _volume);
    engine.setVisualization(enabled: _visualization);
    _pushEqualizer();
  }

  void _pushEqualizer() {
    final engine = _engine;
    if (engine == null) return;
    final active = [
      for (var i = 0; i < eqBandCount; i++)
        if (i < _eqBands.length) _eqBands[i],
    ];
    engine.setEqualizer(
      enabled: _eqEnabled,
      bands: [
        for (final b in _eqBands.take(eqBandCount))
          rust_audio.EqBandParams(
            frequency: b.frequency,
            gainDb: b.gainDb,
            q: b.q,
          ),
      ],
      targetPreamp: _eqEnabled && _eqAutoPreamp ? eqAutoPreamp(active) : 1,
    );
  }

  Future<void> _serialize(Future<void> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<void> load(ResolvedAudio source, {Duration start = Duration.zero}) {
    assertNotRawYouTube(source.input);
    _playIntent = false;
    ++_seekGeneration;
    return _load(source, start: start);
  }

  Future<void> _load(ResolvedAudio source, {Duration start = Duration.zero}) {
    final generation = ++_generation;
    return _serialize(() async {
      if (_disposed || generation != _generation) return;
      _resolved = source;
      if (!_openEngine()) {
        _loaded = false;
        _playing = false;
        _buffering = false;
        final message =
            'No hay un dispositivo de salida de audio disponible. '
                    '${redactAudioError(rustUnavailableReason ?? '')}'
                .trim();
        lastError = message;
        notifyListeners();
        throw StateError(message);
      }
      final engine = _engine!;
      engine.stop();
      _loaded = false;
      _completing = false;
      _offset = start;
      _position = start;
      _duration = source.duration;
      lastError = null;
      final scheme = Uri.tryParse(source.input)?.scheme;
      _streaming = scheme == 'http' || scheme == 'https';
      _playing = false;
      _buffering = true;
      notifyListeners();
      final result = await engine.load(
        input: source.input,
        headers: [
          for (final h in source.headers.entries)
            rust.PlayerHeader(name: h.key, value: h.value),
        ],
        startMs: start.inMilliseconds,
      );
      if (_disposed || generation != _generation) {
        engine.stop();
        return;
      }
      if (!result.ok) {
        _buffering = false;
        final message = result.unsupported
            ? 'Formato de audio no admitido: ${redactAudioError(result.message)}'
            : redactAudioError(result.message);
        lastError = message;
        notifyListeners();
        throw StateError(message);
      }
      if (_duration == Duration.zero && result.durationMs != null) {
        _duration = Duration(milliseconds: result.durationMs!);
      }
      _loaded = true;
      _buffering = engine.state().buffering;
      notifyListeners();
    });
  }

  void _tick() {
    final engine = _engine;
    if (_disposed || engine == null || !_loaded) return;
    final state = engine.state();
    if (state.deviceLost && !_recoveringDevice) {
      unawaited(_recoverDevice());
      return;
    }
    final error = state.error;
    if (error != null) {
      _fail(redactAudioError(error));
      return;
    }
    _position = _offset + Duration(microseconds: state.consumedUs);
    final wasBuffering = _buffering;
    _buffering = state.buffering;
    // Un cambio de «cargando» se avisa al momento: el botón de pausa no espera
    // al siguiente aviso periódico.
    if (wasBuffering != _buffering) notifyListeners();
    if (state.ended && _playing && !_completing) {
      _completing = true;
      unawaited(_finish(_generation, state));
      return;
    }
    if (_playing && _visualization && !_buffering) {
      _spectrum.value = spectrumBars(engine.spectrum());
    }
    if (++_ticks % 6 == 0) notifyListeners();
  }

  /// La salida de audio desapareció (auriculares desenchufados, dispositivo
  /// deshabilitado): se abre un motor nuevo y se sigue por donde iba. Si ya no
  /// hay ningún dispositivo, la carga falla con su motivo.
  Future<void> _recoverDevice() async {
    _recoveringDevice = true;
    final source = _resolved;
    final resume = _playing || _playIntent;
    final at = _position;
    _loaded = false;
    try {
      _engine?.stop();
      _engine?.dispose();
      _engine = null;
      if (source != null && !_disposed) {
        await _load(source, start: at);
        if (resume && !_disposed) await play();
      }
    } catch (error) {
      _fail(redactAudioError(error));
    } finally {
      _recoveringDevice = false;
    }
  }

  void _fail(String message) {
    lastError = message;
    _playing = false;
    _buffering = false;
    _loaded = false;
    _engine?.stop();
    _spectrum.value = List.filled(48, 0);
    if (!_disposed) notifyListeners();
  }

  Future<void> _finish(int generation, rust.PlayerStateInfo state) async {
    try {
      await _resolved?.validateCompletion?.call();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _fail(redactAudioError(error));
      }
      return;
    }
    if (_disposed || generation != _generation) return;
    final decoded = Duration(microseconds: state.decodedUs);
    final consumed = Duration(microseconds: state.consumedUs);
    // Un flujo de red cortado antes de tiempo no es un final: solo se acepta
    // si lo oído cubre lo decodificado y esto, la duración esperada.
    if (_streaming &&
        !isCompleteAudioStream(
          isPlaying: _playing,
          isBuffering: false,
          cleanEof: true,
          decoded: decoded,
          consumed: consumed,
          expected: _duration > _offset ? _duration - _offset : Duration.zero,
        )) {
      debugPrint(
        'Aurora EOF: decoded=${decoded.inMicroseconds}, '
        'consumed=${consumed.inMicroseconds}, '
        'duration=${_duration.inMicroseconds}, offset=${_offset.inMicroseconds}',
      );
      _fail('El audio terminó antes de completar la reproducción.');
      return;
    }
    _position = _streaming || _duration == Duration.zero
        ? _offset + consumed
        : _duration;
    _playing = false;
    _buffering = false;
    _spectrum.value = List.filled(48, 0);
    notifyListeners();
    _completed.add(null);
  }

  @override
  Future<void> play() async {
    _playIntent = true;
    if (!_loaded) return;
    _engine?.play();
    _playing = true;
    _buffering = _engine?.state().buffering ?? false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playIntent = false;
    _engine?.pause();
    _playing = false;
    _spectrum.value = List.filled(48, 0);
    notifyListeners();
  }

  @override
  Future<void> seek(Duration target) async {
    final source = _resolved;
    if (source == null) return;
    final bounded = Duration(
      microseconds: target.inMicroseconds.clamp(
        0,
        _duration > Duration.zero
            ? _duration.inMicroseconds
            : target.inMicroseconds.abs(),
      ),
    );
    final request = ++_seekGeneration;
    await _load(source, start: bounded);
    if (shouldResumeAfterSeek(
      request: request,
      latestRequest: _seekGeneration,
      playIntent: _playIntent,
    )) {
      await play();
    }
  }

  @override
  Future<void> stop() {
    ++_generation;
    ++_seekGeneration;
    _playIntent = false;
    return _serialize(() async {
      _engine?.stop();
      _loaded = false;
      _playing = false;
      _buffering = false;
      _position = Duration.zero;
      _resolved = null;
      _spectrum.value = List.filled(48, 0);
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void setVolume(double volume) {
    _volume = volume.clamp(0, 1);
    _engine?.setVolume(volume: _volume);
    notifyListeners();
  }

  @override
  void setEqualizer(
    bool enabled,
    List<EqBand> bands, {
    bool autoPreamp = true,
  }) {
    _eqEnabled = enabled;
    _eqBands = bands;
    _eqAutoPreamp = autoPreamp;
    _pushEqualizer();
  }

  @override
  void setVisualizationEnabled(bool enabled) {
    _visualization = enabled;
    _engine?.setVisualization(enabled: enabled);
    if (!enabled) _spectrum.value = List.filled(48, 0);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    _engine?.stop();
    _engine?.dispose();
    _engine = null;
    unawaited(_completed.close());
    _spectrum.dispose();
    super.dispose();
  }
}
