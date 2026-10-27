import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';
import 'audio_math.dart';
import 'eq_dsp.dart';
import 'eq_model.dart';
import 'stream_guard.dart';

/// Name of the shared library a dlopen error says is missing, or `null`.
String? missingSharedLibrary(String error) => RegExp(
  r'([\w.+-]+\.so[\d.]*): cannot open shared object file',
).firstMatch(error)?.group(1);

/// A single native mixer: playback, EQ and FFT all use the same output.
class MusicAudio extends AudioBackend {
  // Lazy: SoLoud.instance loads the native library, whose load errors must
  // surface inside initialize()'s try.
  late final SoLoud _engine = SoLoud.instance;
  bool _engineReady = false;
  static const _pcm = MethodChannel('aurora/pcm');
  final _spectrum = ValueNotifier<List<double>>(List.filled(48, 0));
  final _completed = StreamController<void>.broadcast();
  AudioSource? _sound;
  SoundHandle? _handle;
  Process? _decoder;
  String? _androidSession;
  Timer? _timer;
  AudioData? _fft;
  ResolvedAudio? _resolved;
  String? _ffmpeg;
  Future<void> _operations = Future.value();
  int _generation = 0;
  int _seekGeneration = 0;
  bool _disposed = false, _playing = false, _buffering = false;
  bool _playIntent = false;
  bool _streaming = false, _ended = false, _visualization = true;
  Duration _position = Duration.zero, _duration = Duration.zero;
  Duration _offset = Duration.zero;
  int _decodedFrames = 0;
  double _volume = 0.8;
  double _preamp = 1;
  // EQ paramétrico en Dart sobre el PCM que alimenta el mixer; los archivos
  // locales cargados en modo disco no pasan por Dart y usan el filtro nativo.
  final _eq = ParametricEqualizer();
  bool _eqEnabled = false, _eqAutoPreamp = true;
  List<EqBand> _eqBands = eqFlatBands();
  // Cuanto menos audio ya procesado espera en el búfer, antes se oye un cambio.
  static const _bufferLimitBytes = 320000;
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
  // Native EqFilter's sqrt-bin interpolation anchors, at a 48 kHz mixer.
  static const _nativeAnchors = [
    375.0,
    1500.0,
    3375.0,
    6000.0,
    9375.0,
    13500.0,
    18375.0,
    24000.0,
  ];
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> initialize() async {
    try {
      await _engine.init(sampleRate: 48000, bufferSize: 1024);
    } catch (e) {
      final lib = Platform.isLinux ? missingSharedLibrary('$e') : null;
      if (lib == null) rethrow;
      throw StateError(
        'Falta la biblioteca del sistema $lib. Instala el paquete .deb de '
        'Aurora o ejecuta install.sh, que comprueba las dependencias. '
        'Detalle: $e',
      );
    }
    _engineReady = true;
    _engine.setVisualizationEnabled(_visualization);
    _fft = AudioData(GetSamplesKind.linear);
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
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
      await _release();
      if (_disposed || generation != _generation) return;
      _resolved = source;
      _ffmpeg = ffmpegExecutable;
      _offset = start;
      _position = start;
      _duration = source.duration;
      _decodedFrames = 0;
      _ended = false;
      lastError = null;
      final scheme = Uri.tryParse(source.input)?.scheme;
      final local = scheme != 'https' && scheme != 'http';
      final extension = source.input.toLowerCase().split('.').last;
      _streaming =
          !(local && const ['mp3', 'wav', 'ogg', 'flac'].contains(extension));
      _buffering = _streaming;
      notifyListeners();
      try {
        if (!_streaming) {
          final sound = await _engine.loadFile(
            source.input,
            mode: LoadMode.disk,
          );
          if (generation != _generation || _disposed) {
            await _engine.disposeSource(sound);
            return;
          }
          _sound = sound;
          _duration = _engine.getLength(sound);
          _handle = await _engine.play(
            sound,
            paused: true,
            volume: _volume * _preamp,
          );
          if (start > Duration.zero) _engine.seek(_handle!, start);
        } else {
          final sound = _engine.setBufferStream(
            maxBufferSizeBytes: 1024 * 1024,
            bufferingType: BufferingType.released,
            bufferingTimeNeeds: 0.25,
            sampleRate: 48000,
            channels: Channels.stereo,
            format: BufferType.f32le,
            onBuffering: (buffering, handle, time) {
              if (!_disposed && generation == _generation) {
                _buffering = buffering;
                notifyListeners();
              }
            },
          );
          _sound = sound;
          _handle = await _engine.play(
            sound,
            paused: true,
            volume: _volume * _preamp,
          );
          if (Platform.isAndroid) {
            final result = await _pcm
                .invokeMapMethod<String, dynamic>('start', {
                  'input': source.input,
                  'headers': source.headers,
                  'offsetMs': start.inMilliseconds,
                });
            final session = result!['sessionId'] as String;
            if (generation != _generation || _disposed) {
              await _pcm.invokeMethod<void>('stop', {'sessionId': session});
              return;
            }
            _androidSession = session;
            unawaited(
              _pump(
                generation,
                sound,
                () async =>
                    await _pcm.invokeMethod<Uint8List>('read', {
                      'sessionId': session,
                      'maxBytes': 65536,
                    }) ??
                    Uint8List(0),
              ),
            );
          } else {
            if (ffmpegExecutable == null || ffmpegExecutable.isEmpty) {
              throw StateError(
                'Configura la ruta de FFmpeg para reproducir este formato.',
              );
            }
            final args = <String>[
              '-nostdin',
              '-hide_banner',
              '-loglevel',
              'error',
            ];
            if (start > Duration.zero) {
              args.addAll(['-ss', '${start.inMicroseconds / 1000000}']);
            }
            args.addAll(ffmpegHttpsOptions(source.input));
            if (source.headers.isNotEmpty) {
              for (final entry in source.headers.entries) {
                if (entry.key.contains(RegExp(r'[\r\n]')) ||
                    entry.value.contains(RegExp(r'[\r\n]'))) {
                  throw ArgumentError('Cabecera inválida');
                }
              }
              args.addAll([
                '-headers',
                source.headers.entries
                    .map((e) => '${e.key}: ${e.value}\r\n')
                    .join(),
              ]);
            }
            args.addAll([
              '-i',
              source.input,
              '-vn',
              '-f',
              'f32le',
              '-acodec',
              'pcm_f32le',
              '-ar',
              '48000',
              '-ac',
              '2',
              'pipe:1',
            ]);
            final process = await Process.start(
              ffmpegExecutable,
              args,
              runInShell: false,
            );
            if (generation != _generation || _disposed) {
              process.kill();
              return;
            }
            _decoder = process;
            var stderr = '';
            process.stderr
                .transform(const Utf8Decoder(allowMalformed: true))
                .listen((text) {
                  stderr = (stderr + text);
                  if (stderr.length > 4096) {
                    stderr = stderr.substring(stderr.length - 4096);
                  }
                });
            final iterator = StreamIterator(process.stdout);
            unawaited(
              _pump(generation, sound, () async {
                if (await iterator.moveNext()) {
                  return Uint8List.fromList(iterator.current);
                }
                final code = await process.exitCode;
                if (code != 0) {
                  throw StateError(
                    stderr.trim().isEmpty
                        ? 'FFmpeg no pudo decodificar el audio.'
                        : stderr.trim(),
                  );
                }
                return Uint8List(0);
              }).whenComplete(iterator.cancel),
            );
          }
        }
        if (generation == _generation && !_disposed) {
          _syncNativeEq();
          notifyListeners();
        }
      } catch (error) {
        if (generation == _generation && !_disposed) {
          await _release();
          lastError = redactAudioError(error);
          notifyListeners();
        }
        throw StateError(redactAudioError(error));
      }
    });
  }

  Future<void> _pump(
    int generation,
    AudioSource sound,
    Future<Uint8List> Function() read,
  ) async {
    var remainder = Uint8List(0);
    try {
      while (!_disposed && generation == _generation) {
        // Backpressure includes the decoder pipe and prevents whole-track PCM accumulation.
        while (!_disposed &&
            generation == _generation &&
            (!_playing || _engine.getBufferSize(sound) > _bufferLimitBytes)) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        if (_disposed || generation != _generation) return;
        final bytes = await read();
        if (_disposed || generation != _generation) return;
        while (!_disposed && generation == _generation && !_playing) {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        if (_disposed || generation != _generation) return;
        if (bytes.isEmpty) {
          if (remainder.isNotEmpty) throw StateError('Audio PCM incompleto');
          await _resolved?.validateCompletion?.call();
          if (_disposed || generation != _generation) return;
          _engine.setDataIsEnded(sound);
          _ended = true;
          return;
        }
        final combined = Uint8List(remainder.length + bytes.length)
          ..setAll(0, remainder)
          ..setAll(remainder.length, bytes);
        final aligned = combined.length - combined.length % 8;
        _eq.process(Float32List.view(combined.buffer, 0, aligned ~/ 4));
        // Some process streams deliver large chunks; feed bounded pieces.
        for (var offset = 0; offset < aligned; offset += 65536) {
          while (!_disposed &&
              generation == _generation &&
              (!_playing || _engine.getBufferSize(sound) > _bufferLimitBytes)) {
            await Future<void>.delayed(const Duration(milliseconds: 30));
          }
          if (_disposed || generation != _generation) return;
          _engine.addAudioDataStream(
            sound,
            Uint8List.sublistView(
              combined,
              offset,
              math.min(offset + 65536, aligned),
            ),
          );
          _decodedFrames += math.min(65536, aligned - offset) ~/ 8;
        }
        remainder = Uint8List.fromList(combined.sublist(aligned));
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        lastError = redactAudioError(error);
        _playing = false;
        _buffering = false;
        await _serialize(() async {
          if (generation == _generation) await _release();
        });
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }
  }

  void _tick() {
    if (_disposed || _sound == null || _handle == null) return;
    try {
      if (!_engine.getIsValidVoiceHandle(_handle!)) {
        if (_playing && _streaming && _ended && !_buffering) {
          final decoded = Duration(
            microseconds: _decodedFrames * 1000000 ~/ 48000,
          );
          final consumed = _engine.getStreamTimeConsumed(_sound!);
          if (!isCompleteAudioStream(
            isPlaying: _playing,
            isBuffering: _buffering,
            cleanEof: _ended,
            decoded: decoded,
            consumed: consumed,
            expected: _duration > _offset ? _duration - _offset : Duration.zero,
          )) {
            debugPrint(
              'Aurora EOF: decoded=${decoded.inMicroseconds}, '
              'consumed=${consumed.inMicroseconds}, '
              'duration=${_duration.inMicroseconds}, offset=${_offset.inMicroseconds}',
            );
            lastError = 'El audio terminó antes de completar la reproducción.';
            _playing = false;
            _buffering = false;
            final generation = _generation;
            unawaited(
              _serialize(() async {
                if (generation == _generation) await _release();
              }),
            );
            notifyListeners();
            return;
          }
          _position = _offset + consumed;
          _playing = false;
          _buffering = false;
          _spectrum.value = List.filled(48, 0);
          notifyListeners();
          _completed.add(null);
        } else if (_playing && !_streaming) {
          _playing = false;
          _buffering = false;
          if (_duration > Duration.zero) _position = _duration;
          _spectrum.value = List.filled(48, 0);
          notifyListeners();
          _completed.add(null);
        }
        return;
      }
      _position = _streaming
          ? _offset + _engine.getStreamTimeConsumed(_sound!)
          : _engine.getPosition(_handle!);
      _buffering = _streaming && _playing && _engine.getPause(_handle!);
      if (_playing && _visualization && !_buffering) {
        _fft!.updateSamples();
        final data = _fft!.getAudioData();
        if (data.length >= 256) {
          _spectrum.value = spectrumBars(data);
        }
      }
      // Position notifications are cheaper than rebuilding the UI at FFT rate.
      if (++_ticks % 6 == 0) notifyListeners();
    } catch (error) {
      lastError = redactAudioError(error);
    }
  }

  int _ticks = 0;

  @override
  Future<void> play() async {
    _playIntent = true;
    if (_handle == null) return;
    _engine.setPause(_handle!, false);
    _playing = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    _playIntent = false;
    if (_handle != null) _engine.setPause(_handle!, true);
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
    if (!_streaming && _handle != null) {
      _engine.seek(_handle!, bounded);
      _position = bounded;
      notifyListeners();
      return;
    }
    final request = ++_seekGeneration;
    await _load(source, ffmpegExecutable: _ffmpeg, start: bounded);
    if (shouldResumeAfterSeek(
          request: request,
          latestRequest: _seekGeneration,
          playIntent: _playIntent,
        ) &&
        _handle != null) {
      await play();
    }
  }

  @override
  Future<void> stop() {
    ++_generation;
    ++_seekGeneration;
    _playIntent = false;
    return _serialize(() async {
      await _release();
      _position = Duration.zero;
      _resolved = null;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _release() async {
    _playing = false;
    _buffering = false;
    final process = _decoder;
    _decoder = null;
    process?.kill();
    final session = _androidSession;
    _androidSession = null;
    if (session != null) {
      try {
        await _pcm.invokeMethod<void>('stop', {'sessionId': session});
      } catch (_) {}
    }
    final handle = _handle;
    _handle = null;
    final sound = _sound;
    _sound = null;
    if (handle != null) await _engine.stop(handle);
    if (sound != null) await _engine.disposeSource(sound);
    if (!_disposed) _spectrum.value = List.filled(48, 0);
  }

  @override
  void setVolume(double volume) {
    _volume = volume.clamp(0, 1);
    if (_handle != null) _engine.setVolume(_handle!, _volume * _preamp);
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
    _eq.configure(enabled: enabled, bands: bands, autoPreamp: autoPreamp);
    _syncNativeEq();
  }

  /// Respaldo para archivos locales en modo disco: el filtro nativo tiene
  /// ocho bandas fijas, así que se muestrea la curva en sus anclas.
  void _syncNativeEq() {
    if (!_engineReady) return;
    final eq = _engine.filters.equalizerFilter;
    if (_streaming || !_eqEnabled || _sound == null) {
      if (eq.isActive) eq.deactivate();
      _preamp = 1;
      if (_handle != null) _engine.setVolume(_handle!, _volume);
      return;
    }
    final gains = [for (final f in _nativeAnchors) eqResponseDb(_eqBands, f)];
    final targetPreamp = _eqAutoPreamp ? equalizerPreamp(gains) : 1.0;
    // Lower first when adding boost or activating boosted bands.
    _preamp = math.min(_preamp, targetPreamp);
    if (_handle != null) _engine.setVolume(_handle!, _volume * _preamp);
    if (!eq.isActive) eq.activate();
    final bands = [
      eq.band1,
      eq.band2,
      eq.band3,
      eq.band4,
      eq.band5,
      eq.band6,
      eq.band7,
      eq.band8,
    ];
    for (var i = 0; i < bands.length; i++) {
      bands[i].value = equalizerGain(gains[i]);
    }
    _preamp = targetPreamp;
    if (_handle != null) _engine.setVolume(_handle!, _volume * _preamp);
  }

  @override
  void setVisualizationEnabled(bool enabled) {
    _visualization = enabled;
    if (_engineReady) _engine.setVisualizationEnabled(enabled);
    if (!enabled) _spectrum.value = List.filled(48, 0);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _timer?.cancel();
    unawaited(
      _serialize(() async {
        await _release();
        _fft?.dispose();
        if (_engineReady) _engine.deinit();
        _spectrum.dispose();
        await _completed.close();
      }),
    );
    super.dispose();
  }
}
