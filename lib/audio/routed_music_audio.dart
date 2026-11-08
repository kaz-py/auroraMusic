import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';
import 'eq_model.dart';
import 'stream_guard.dart';

/// Aurora owns one queue; [ResolvedAudio.engine] selects the engine. The
/// official-site fallback plays in [web], everything else in [native]. One engine is
/// active at a time and only its completion reaches the controller.
class RoutedMusicAudio extends AudioBackend {
  RoutedMusicAudio({required this.native, required this.web})
    : _active = native {
    native.addListener(_nativeChanged);
    web.addListener(_webChanged);
    _nativeCompleted = native.completed.listen((_) {
      if (identical(_active, native)) _completed.add(null);
    });
    _webCompleted = web.completed.listen((_) {
      if (identical(_active, web)) _completed.add(null);
    });
  }

  final AudioBackend native;
  final AudioBackend web;
  AudioBackend _active;
  final _completed = StreamController<void>.broadcast();
  late final StreamSubscription<void> _nativeCompleted;
  late final StreamSubscription<void> _webCompleted;
  int _generation = 0;
  bool _disposed = false;
  double _volume = 0.75;
  String? webInitializationError;
  bool get usingWeb => identical(_active, web);

  void _nativeChanged() {
    if (!_disposed && !usingWeb) notifyListeners();
  }

  void _webChanged() {
    if (_disposed) return;
    if (usingWeb) {
      // System controls (Android Media3 session) follow web playback.
      unawaited(native.mirrorExternalPlayback(web).catchError((Object _) {}));
    }
    // The shell also listens for website access even while native is active.
    notifyListeners();
  }

  @override
  bool get supportsEqualizer => _active.supportsEqualizer;
  @override
  bool get supportsVisualization => _active.supportsVisualization;
  @override
  String? get lastError => _active.lastError;
  @override
  bool get isPlaying => _active.isPlaying;
  @override
  bool get isBuffering => _active.isBuffering;
  @override
  bool get adPlaying => usingWeb && web.adPlaying;
  @override
  Duration get position => _active.position;
  @override
  Duration get duration => _active.duration;
  @override
  double get volume => _volume;
  @override
  ValueListenable<List<double>> get spectrum => _active.spectrum;
  @override
  Stream<void> get completed => _completed.stream;
  @override
  Stream<String> get mediaActions => native.mediaActions;

  /// Track metadata always feeds the native session, whichever engine plays.
  @override
  Future<void> updateTrackMetadata(Track track) =>
      native.updateTrackMetadata(track);

  @override
  Future<void> initialize() async {
    await native.initialize();
    try {
      await web.initialize();
      webInitializationError = null;
    } catch (_) {
      webInitializationError =
          'No se pudo iniciar el reproductor de YouTube Music. Los archivos '
          'locales siguen disponibles; en Windows comprueba Microsoft Edge '
          'WebView2 Runtime.';
    }
  }

  @override
  Future<void> load(
    ResolvedAudio source, {
    Duration start = Duration.zero,
  }) async {
    final revision = ++_generation;
    final next = source.engine == AudioEngine.web ? web : native;
    if (identical(next, native)) assertNotRawYouTube(source.input);
    if (identical(next, web) && webInitializationError != null) {
      throw StateError(webInitializationError!);
    }
    if (identical(_active, next) && identical(next, web)) {
      await web.pause();
    } else {
      await _active.stop();
      if (identical(next, native)) {
        await native.mirrorExternalPlayback(null);
      }
    }
    if (_disposed || revision != _generation) return;
    _active = next;
    _active.setVolume(_volume);
    notifyListeners();
    await next.load(source, start: start);
  }

  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> seek(Duration position) => _active.seek(position);
  @override
  Future<void> stop() async {
    ++_generation;
    await _active.stop();
  }

  @override
  void setVolume(double value) {
    if (!value.isFinite || _disposed) return;
    _volume = value.clamp(0, 1);
    native.setVolume(_volume);
    web.setVolume(_volume);
  }

  @override
  void setEqualizer(
    bool enabled,
    List<EqBand> bands, {
    bool autoPreamp = true,
  }) => native.setEqualizer(enabled, bands, autoPreamp: autoPreamp);
  @override
  void setVisualizationEnabled(bool enabled) =>
      native.setVisualizationEnabled(enabled && !usingWeb);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    native.removeListener(_nativeChanged);
    web.removeListener(_webChanged);
    unawaited(_nativeCompleted.cancel());
    unawaited(_webCompleted.cancel());
    unawaited(_completed.close());
    native.dispose();
    web.dispose();
    super.dispose();
  }
}
