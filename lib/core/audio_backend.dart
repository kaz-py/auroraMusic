import 'package:flutter/foundation.dart';
import '../audio/eq_model.dart';
import 'models.dart';

abstract class AudioBackend extends ChangeNotifier {
  bool get supportsEqualizer => true;
  bool get supportsVisualization => true;
  String? get lastError;
  bool get isPlaying;
  bool get isBuffering;
  Duration get position;
  Duration get duration;
  double get volume;
  ValueListenable<List<double>> get spectrum;
  Stream<void> get completed;
  Stream<String> get mediaActions => const Stream.empty();
  Track? get currentTrackMetadata => null;

  /// Lo que está cargado ahora (archivo o proxy local), si el motor puede
  /// decodificarlo aparte; `null` si no (reproductor web, Android).
  ResolvedAudio? get currentSource => null;
  Future<void> updateTrackMetadata(Track track) async {}

  /// True while the web player is showing an advertisement.
  bool get adPlaying => false;

  /// Lets a native media session reflect [playback] owned by another engine;
  /// null returns the session to this backend.
  Future<void> mirrorExternalPlayback(AudioBackend? playback) async {}
  Future<void> initialize();
  Future<void> load(ResolvedAudio source, {Duration start = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  void setVolume(double volume);

  /// Aplica el ecualizador paramétrico; solo si [supportsEqualizer].
  void setEqualizer(bool enabled, List<EqBand> bands, {bool autoPreamp = true});
  void setVisualizationEnabled(bool enabled);
}
