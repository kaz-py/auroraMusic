import '../app_controller.dart';
import '../jam/jam_controller.dart';
import 'remote_control_server.dart';

/// Conecta la API de control remoto con el reproductor y con la Jam.
///
/// Con una Jam activa el reproductor lo gobierna la Jam (`AppController` ignora
/// pausa y salto), así que las órdenes pasan por [JamController], que respeta
/// los permisos del usuario en esa sala.
class AuroraRemoteActions implements RemoteControlActions {
  AuroraRemoteActions(
    this.app, {
    required this.currentJam,
    required this.ensureJam,
  });

  final AppController app;

  /// La Jam si ya existe (sin crearla).
  final JamController? Function() currentJam;

  /// La Jam de la interfaz, creándola si hace falta.
  final JamController? Function() ensureJam;

  JamController? get _activeJam {
    final jam = currentJam();
    return jam != null && jam.active ? jam : null;
  }

  Future<void> _viaJam(
    JamController jam,
    Future<void> Function() action,
  ) async {
    jam.error = null;
    await action();
    final problem = jam.error;
    if (problem != null) throw RemoteControlException(409, problem);
  }

  bool get _playing => app.audio.isPlaying;

  @override
  Future<void> play() async {
    final jam = _activeJam;
    if (jam != null) {
      if (!_playing) await _viaJam(jam, jam.togglePlayback);
      return;
    }
    await app.resumePlayback();
  }

  @override
  Future<void> pause() async {
    final jam = _activeJam;
    if (jam != null) {
      if (_playing) await _viaJam(jam, jam.togglePlayback);
      return;
    }
    await app.pausePlayback();
  }

  @override
  Future<void> toggle() async {
    final jam = _activeJam;
    if (jam != null) return _viaJam(jam, jam.togglePlayback);
    await app.togglePlayback();
  }

  @override
  Future<void> next() async {
    final jam = _activeJam;
    if (jam != null) return _viaJam(jam, jam.next);
    await app.next();
  }

  @override
  Future<void> previous() async {
    if (_activeJam != null) {
      throw const RemoteControlException(
        409,
        'En una Jam no se puede volver a la canción anterior.',
      );
    }
    await app.previous();
  }

  @override
  Future<Map<String, Object?>> startJam({String mode = 'auto'}) async {
    final jam = ensureJam();
    if (jam == null) {
      throw const RemoteControlException(
        503,
        'La interfaz de Aurora aún no está lista.',
      );
    }
    final already = jam.active;
    if (!already) {
      jam.error = null;
      final started = await jam.startHosting(
        mode: switch (mode) {
          'online' => JamHostMode.online,
          'lan' => JamHostMode.lan,
          _ => JamHostMode.auto,
        },
      );
      if (!started) {
        throw RemoteControlException(
          409,
          jam.error ?? 'No se pudo iniciar la Jam.',
        );
      }
    }
    return {'alreadyActive': already, ..._jamStatus(jam)};
  }

  Map<String, Object?> _jamStatus(JamController? jam) {
    if (jam == null || !jam.active) return {'jam': null};
    final invite = jam.service.invite;
    return {
      'jam': {
        'active': true,
        'host': jam.isHost,
        if (invite != null && invite.isRemote) 'code': invite.sessionId,
        'online': invite?.isRemote ?? false,
        'participants': jam.participants.length,
      },
    };
  }

  @override
  Map<String, Object?> status() {
    final track = app.currentTrack;
    return {
      'playing': _playing,
      'buffering': app.audio.isBuffering,
      'track': track == null
          ? null
          : {'id': track.id, 'title': track.title, 'artist': track.artist},
      'positionMs': app.audio.position.inMilliseconds,
      'durationMs': app.audio.duration.inMilliseconds,
      'queueLength': app.queue.length,
      ..._jamStatus(currentJam()),
    };
  }
}
