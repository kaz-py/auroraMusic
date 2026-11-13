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

  /// Lo que está cargado ahora (archivo o proxy local), si el motor puede
  /// decodificarlo aparte; `null` si no (Android).
  ResolvedAudio? get currentSource => null;
  Future<void> updateTrackMetadata(Track track) async {}

  Future<void> initialize();
  Future<void> load(ResolvedAudio source, {Duration start = Duration.zero});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();

  /// Corta la pista actual para cargar otra (cambio de pista). Igual que
  /// [stop], pero Android conserva viva la sesión del sistema (servicio en
  /// primer plano y notificación) mientras se resuelve la siguiente: desde
  /// segundo plano no puede volver a entrar en primer plano y el proceso se
  /// congela.
  Future<void> interrupt() => stop();
  Future<void> seek(Duration position);
  void setVolume(double volume);

  /// Aplica el ecualizador paramétrico; solo si [supportsEqualizer].
  void setEqualizer(bool enabled, List<EqBand> bands, {bool autoPreamp = true});
  void setVisualizationEnabled(bool enabled);
}
