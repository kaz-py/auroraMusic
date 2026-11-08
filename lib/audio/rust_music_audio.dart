import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../bridge/api/audio.dart' as rust_audio;
import '../bridge/api/playback.dart' as rust;
import '../core/audio_backend.dart';
import '../core/models.dart';
import 'audio_math.dart';
import 'eq_model.dart';
import 'music_audio.dart';
import 'stream_guard.dart';

/// Motor de audio de escritorio: archivos y el proxy local de YouTube se
/// decodifican y se mezclan en Rust (`rust/crates/aurora_playback`); lo que ese
/// motor no maneja (https remoto, formatos fuera de Symphonia, sin dispositivo)
/// pasa por [MusicAudio] (SoLoud + FFmpeg), que se inicia solo si hace falta.
///
/// `AURORA_AUDIO_ENGINE=soloud` fuerza el motor anterior.
class RustMusicAudio extends AudioBackend {
  /// [engineFactory] y [legacy] existen para las pruebas (salida sin dispositivo
  /// y motor anterior simulado).
  RustMusicAudio({
    MusicAudio? legacy,
    rust.PlayerEngine Function()? engineFactory,
  }) : _legacy = legacy ?? MusicAudio(),
       _engineFactory = engineFactory ?? rust.PlayerEngine.create;

  /// El motor de escritorio que corresponde a esta ejecución.
  static AudioBackend create() =>
      Platform.environment['AURORA_AUDIO_ENGINE']?.toLowerCase() == 'soloud'
      ? MusicAudio()
      : RustMusicAudio();

  final MusicAudio _legacy;
  final rust.PlayerEngine Function() _engineFactory;
  rust.PlayerEngine? _engine;
  bool _legacyReady = false, _usingLegacy = false, _rustUnavailable = false;
  final _spectrum = ValueNotifier<List<double>>(List.filled(48, 0));
  final _completed = StreamController<void>.broadcast();
  Timer? _timer;
  ResolvedAudio? _resolved;
  String? _ffmpeg;
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
  bool get isPlaying => _usingLegacy ? _legacy.isPlaying : _playing;
  @override
  bool get isBuffering => _usingLegacy ? _legacy.isBuffering : _buffering;
  @override
  Duration get position => _usingLegacy ? _legacy.position : _position;
  @override
  Duration get duration => _usingLegacy ? _legacy.duration : _duration;
  @override
  double get volume => _volume;
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  /// Motivo por el que no se pudo abrir el dispositivo con el motor nuevo.
  String? rustUnavailableReason;

  @override
  Future<void> initialize() async {
    try {
      _engine = _engineFactory();
    } catch (error) {
      _rustUnavailable = true;
      rustUnavailableReason = '$error';
      await _initLegacy();
      return;
    }
    _applyToEngine();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
  }

  Future<void> _initLegacy() async {
    if (_legacyReady) return;
    await _legacy.initialize();
    _legacyReady = true;
    _legacy.addListener(() {
      if (_usingLegacy && !_disposed) notifyListeners();
    });
    _legacy.completed.listen((_) {
      if (_usingLegacy && !_disposed) _completed.add(null);
    });
    _legacy.spectrum.addListener(() {
      if (_usingLegacy && !_disposed) _spectrum.value = _legacy.spectrum.value;
    });
    _legacy.setVolume(_volume);
    _legacy.setEqualizer(_eqEnabled, _eqBands, autoPreamp: _eqAutoPreamp);
    _legacy.setVisualizationEnabled(_visualization);
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
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) {
    assertNotRawYouTube(source.input);
    _playIntent = false;
    ++_seekGeneration;
    return _load(source, ffmpegExecutable: ffmpegExecutable, start: start);
  }

  Future<void> _load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) {
    final generation = ++_generation;
    return _serialize(() async {
      if (_disposed || generation != _generation) return;
      _resolved = source;
      _ffmpeg = ffmpegExecutable;
      if (_rustUnavailable || _engine == null) {
        await _loadLegacy(source, ffmpegExecutable, start);
        return;
      }
      final engine = _engine!;
      if (_usingLegacy) {
        await _legacy.stop();
        _usingLegacy = false;
      }
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
        if (result.unsupported) {
          await _loadLegacy(source, ffmpegExecutable, start);
          return;
        }
        _buffering = false;
        lastError = redactAudioError(result.message);
        notifyListeners();
        throw StateError(redactAudioError(result.message));
      }
      if (_duration == Duration.zero && result.durationMs != null) {
        _duration = Duration(milliseconds: result.durationMs!);
      }
      _loaded = true;
      _buffering = engine.state().buffering;
      notifyListeners();
    });
  }

  Future<void> _loadLegacy(
    ResolvedAudio source,
    String? ffmpegExecutable,
    Duration start,
  ) async {
    await _initLegacy();
    _engine?.stop();
    _loaded = false;
    _playing = false;
    _usingLegacy = true;
    _buffering = false;
    await _legacy.load(
      source,
      ffmpegExecutable: ffmpegExecutable,
      start: start,
    );
    notifyListeners();
  }

  void _tick() {
    final engine = _engine;
    if (_disposed || _usingLegacy || engine == null || !_loaded) return;
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
  /// hay ningún dispositivo, cae al motor anterior.
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
      try {
        _engine = _engineFactory();
      } catch (error) {
        _rustUnavailable = true;
        rustUnavailableReason = '$error';
      }
      _applyToEngine();
      if (source != null && !_disposed) {
        await _load(source, ffmpegExecutable: _ffmpeg, start: at);
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
    if (_usingLegacy) return _legacy.play();
    _playIntent = true;
    if (!_loaded) return;
    _engine?.play();
    _playing = true;
    _buffering = _engine?.state().buffering ?? false;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    if (_usingLegacy) return _legacy.pause();
    _playIntent = false;
    _engine?.pause();
    _playing = false;
    _spectrum.value = List.filled(48, 0);
    notifyListeners();
  }

  @override
  Future<void> seek(Duration target) async {
    if (_usingLegacy) return _legacy.seek(target);
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
    await _load(source, ffmpegExecutable: _ffmpeg, start: bounded);
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
      if (_usingLegacy) await _legacy.stop();
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
    if (_legacyReady) _legacy.setVolume(_volume);
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
    if (_legacyReady) {
      _legacy.setEqualizer(enabled, bands, autoPreamp: autoPreamp);
    }
  }

  @override
  void setVisualizationEnabled(bool enabled) {
    _visualization = enabled;
    _engine?.setVisualization(enabled: enabled);
    if (_legacyReady) _legacy.setVisualizationEnabled(enabled);
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
    _legacy.dispose();
    unawaited(_completed.close());
    _spectrum.dispose();
    super.dispose();
  }
}
