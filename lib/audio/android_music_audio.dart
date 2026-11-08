import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';
import 'audio_math.dart';
import 'eq_model.dart';
import 'stream_guard.dart';

/// Android's service owns playback; the application controller owns the queue.
class AndroidMusicAudio extends AudioBackend {
  AndroidMusicAudio({
    MethodChannel channel = const MethodChannel('aurora/audio'),
    EventChannel events = const EventChannel('aurora/audio/events'),
  }) : _channel = channel,
       _events = events;

  final MethodChannel _channel;
  final EventChannel _events;
  final _spectrum = ValueNotifier<List<double>>(const []);
  final _completed = StreamController<void>.broadcast();
  final _mediaActions = StreamController<String>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  ResolvedAudio? _source;
  int _generation = 0;
  int? _completedGeneration;
  bool _disposed = false, _playing = false, _buffering = false;
  Duration _position = Duration.zero, _duration = Duration.zero;
  double _volume = 0.8;
  bool _supportsEqualizer = false;

  // Native EQ availability depends on the device; FFT is not exposed.
  @override
  bool get supportsEqualizer => _supportsEqualizer;
  @override
  bool get supportsVisualization => false;
  @override
  Stream<String> get mediaActions => _mediaActions.stream;

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
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> initialize() async {
    if (_disposed) throw StateError('El reproductor esta cerrado.');
    _subscription ??= _events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object error) => _fail(error),
    );
    final state = await _channel.invokeMapMethod<String, dynamic>('initialize');
    if (state != null) _onEvent(state);
  }

  Future<void> _invoke(String method, [Map<String, Object?>? arguments]) async {
    if (_disposed) return;
    final generation = _generation;
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } catch (error) {
      if (!_disposed && generation == _generation) _fail(error);
      rethrow;
    }
  }

  void _fail(Object error) {
    if (_disposed) return;
    lastError = redactAudioError(error);
    _playing = false;
    _buffering = false;
    notifyListeners();
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map || raw['generation'] != _generation) return;
    switch (raw['type']) {
      case 'state':
        if (raw['supportsEqualizer'] is bool) {
          _supportsEqualizer = raw['supportsEqualizer'] as bool;
        }
        _playing = raw['playing'] == true;
        _buffering = raw['buffering'] == true;
        final position = raw['positionMs'];
        final duration = raw['durationMs'];
        final volume = raw['volume'];
        if (position is num) {
          _position = Duration(
            milliseconds: position.toInt().clamp(0, 1 << 53),
          );
        }
        if (duration is num) {
          _duration = Duration(
            milliseconds: duration.toInt().clamp(0, 1 << 53),
          );
        }
        if (volume is num && volume.isFinite) {
          _volume = volume.clamp(0, 1).toDouble();
        }
        if (raw['error'] is String) lastError = redactAudioError(raw['error']);
        notifyListeners();
      case 'completed':
        if (_completedGeneration == _generation || lastError != null) return;
        _completedGeneration = _generation;
        unawaited(_finish(_generation, _source));
      case 'error':
        _fail(raw['message'] ?? 'No se pudo reproducir el audio.');
      case 'action':
        final action = raw['action'];
        if (const [
          'next',
          'previous',
          'play',
          'pause',
          'stop',
        ].contains(action)) {
          _mediaActions.add(action as String);
        } else if (action == 'seek' && raw['positionMs'] is num) {
          // Session seeks while the web engine plays go to the controller.
          _mediaActions.add('seek:${(raw['positionMs'] as num).toInt()}');
        }
    }
  }

  Future<void> _finish(int generation, ResolvedAudio? source) async {
    try {
      await source?.validateCompletion?.call();
      if (_disposed || generation != _generation || lastError != null) return;
      _playing = false;
      _buffering = false;
      notifyListeners();
      _completed.add(null);
    } catch (error) {
      if (!_disposed && generation == _generation) _fail(error);
    }
  }

  @override
  Future<void> load(
    ResolvedAudio source, {
    Duration start = Duration.zero,
  }) async {
    assertNotRawYouTube(source.input);
    ++_generation;
    _source = source;
    _completedGeneration = null;
    lastError = null;
    _playing = false;
    _buffering = true;
    _duration = source.duration;
    _position = start < Duration.zero ? Duration.zero : start;
    notifyListeners();
    await _invoke('load', {
      'generation': _generation,
      'input': source.input,
      'headers': source.headers,
      'durationMs': source.duration.inMilliseconds,
      'startMs': _position.inMilliseconds,
    });
  }

  Future<void> updateMetadata({
    required String id,
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    String? artworkUrl,
  }) => _invoke('metadata', {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'durationMs': duration?.inMilliseconds,
    'artworkUrl': artworkUrl,
  });

  @override
  Future<void> updateTrackMetadata(Track track) => updateMetadata(
    id: track.id,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    artworkUrl: track.artworkUrl,
  );

  /// Keeps the Media3 session, notification and foreground service in step
  /// with web playback so Android does not freeze the app in background.
  @override
  Future<void> mirrorExternalPlayback(AudioBackend? playback) async {
    if (_disposed) return;
    // Not _invoke: a session-mirror failure must not mark native audio failed.
    await _channel.invokeMethod<void>('external', {
      'active': playback != null,
      'playing': playback?.isPlaying ?? false,
      'buffering': playback?.isBuffering ?? false,
      'positionMs': playback?.position.inMilliseconds ?? 0,
      'durationMs': playback?.duration.inMilliseconds ?? 0,
    });
  }

  @override
  Future<void> play() => _invoke('play');
  @override
  Future<void> pause() => _invoke('pause');
  @override
  Future<void> seek(Duration position) => _invoke('seek', {
    'positionMs': position.inMilliseconds.clamp(
      0,
      _duration > Duration.zero ? _duration.inMilliseconds : 1 << 53,
    ),
  });

  @override
  Future<void> stop() async {
    ++_generation;
    _source = null;
    _completedGeneration = null;
    lastError = null;
    _playing = false;
    _buffering = false;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
    await _invoke('stop', {'generation': _generation});
  }

  @override
  void setVolume(double value) {
    if (_disposed || !value.isFinite) return;
    _volume = value.clamp(0, 1);
    notifyListeners();
    unawaited(_invoke('volume', {'volume': _volume}).catchError((Object _) {}));
  }

  @override
  void setEqualizer(
    bool enabled,
    List<EqBand> bands, {
    bool autoPreamp = true,
  }) {
    if (_disposed || !_supportsEqualizer) return;
    // EqBand ya viene acotada y finita; siempre ocho bandas.
    final fixed = [
      for (var i = 0; i < eqBandCount; i++)
        i < bands.length ? bands[i] : EqBand(eqDefaultFrequencies[i]),
    ];
    unawaited(
      _invoke('equalizer', {
        'enabled': enabled,
        'autoPreamp': autoPreamp,
        'bands': [for (final b in fixed) b.toJson()],
      }).catchError((Object _) {}),
    );
  }

  @override
  void setVisualizationEnabled(bool enabled) {}

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    unawaited(_subscription?.cancel());
    unawaited(_channel.invokeMethod<void>('dispose').catchError((Object _) {}));
    unawaited(_completed.close());
    unawaited(_mediaActions.close());
    _spectrum.dispose();
    super.dispose();
  }
}
