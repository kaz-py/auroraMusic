import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../studio/equalizer_panel.dart' show showEqualizerSheet;
import '../studio/studio_transport.dart' show transportJamAudio;

/// Lo que un mini reproductor necesita pintar, derivado de [AppController]
/// (y de la Jam si la hay). Sin widgets ni plataforma: los temas solo leen.
///
/// Con audio de Jam ([jamActive]) la pista es la de la sesión, los permisos
/// salen de la Jam y no hay «anterior» (igual que `TransportNextButton` /
/// `TransportPreviousButton`).
@immutable
class MiniPlayerState {
  const MiniPlayerState({
    required this.track,
    required this.isPlaying,
    required this.progress,
    required this.buffering,
    required this.hasError,
    required this.liked,
    required this.hasNext,
    required this.hasPrevious,
    required this.jamActive,
    required this.canTogglePlay,
    this.jamHostName,
    this.canSeek = false,
    this.volume = 0.75,
    this.canSetVolume = true,
    this.queueLength = 0,
    this.equalizerAvailable = false,
    this.equalizerActive = false,
    this.lyricsAvailable = false,
  });

  /// Pista que suena (en Jam, la de la sesión). `null`: nada cargado.
  final Track? track;
  final bool isPlaying;

  /// 0..1; 0 mientras no se conoce la duración.
  final double progress;

  /// Resolviendo la pista o con el motor en búfer.
  final bool buffering;

  /// El motor de audio informa de un fallo en la pista actual.
  final bool hasError;
  final bool liked;
  final bool hasNext, hasPrevious;
  final bool jamActive;

  /// Pausar/reanudar permitido (en Jam depende del rol).
  final bool canTogglePlay;

  /// Con Jam y sin permiso, quién controla («Lo controla X»).
  final String? jamHostName;

  /// Se puede mover la posición: hay pista con duración conocida y, con Jam,
  /// solo el anfitrión.
  final bool canSeek;

  /// Volumen del motor, 0..1 (local: cada oyente el suyo, también en Jam).
  final double volume;

  /// El volumen siempre se puede cambiar (lo hace el motor local).
  final bool canSetVolume;

  /// Elementos de la cola personal.
  final int queueLength;

  /// Lo que decide `TransportEqualizerButton`: el motor actual admite EQ.
  final bool equalizerAvailable;

  /// El EQ está activo (el botón se tiñe).
  final bool equalizerActive;

  /// Hay pista de la que mostrar letra (el transporte siempre ofrece Letras).
  final bool lyricsAvailable;

  bool get muted => volume <= 0;
  bool get hasQueue => queueLength > 0;

  bool get hasTrack => track != null;

  factory MiniPlayerState.fromController(
    AppController c, {
    JamController? jam,
  }) {
    final jamAudio = transportJamAudio(c, jam);
    // La Jam es dueña del audio aunque aún no haya controlador de Jam: el
    // controlador personal no salta ni pausa en ese estado.
    final jamOwns = c.jamPlaybackActive;
    final track = c.nowTrack;
    final duration = c.audio.duration > Duration.zero
        ? c.audio.duration
        : track?.duration ?? Duration.zero;
    final progress = duration > Duration.zero
        ? (c.audio.position.inMilliseconds / duration.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final hasNext = jamAudio
        ? jam!.canSkip || jam.service.rules.votes
        : track != null &&
              !jamOwns &&
              c.queue.isNotEmpty &&
              (c.shuffle
                  ? c.queue.length > 1
                  : c.repeat == RepeatMode.all ||
                        c.queueIndex < c.queue.length - 1);
    return MiniPlayerState(
      track: track,
      isPlaying: c.audio.isPlaying,
      progress: progress,
      buffering: (c.busy && !jamAudio) || c.audio.isBuffering,
      hasError: c.audio.lastError != null,
      liked: track != null && c.favoriteIds.contains(track.id),
      hasNext: hasNext,
      hasPrevious: track != null && !jamOwns,
      jamActive: jamOwns,
      canTogglePlay: jamAudio ? jam!.canPause : track != null && !jamOwns,
      jamHostName: jamAudio && !jam!.canPause ? jam.hostName : null,
      canSeek:
          track != null &&
          duration > Duration.zero &&
          (jamOwns ? jamAudio && jam!.isHost : true),
      volume: c.audio.volume.clamp(0.0, 1.0),
      queueLength: c.queue.length,
      equalizerAvailable: c.eq.supported,
      equalizerActive: c.eq.active,
      lyricsAvailable: track != null,
    );
  }
}

/// Acciones del mini reproductor. Los temas las invocan; no contienen lógica.
///
/// [MiniPlayerHost] ya envuelve a cada tema en `MiniPlayerGestures`: tocar la
/// barra abre el reproductor, arrastrar hacia arriba lo abre y deslizar a los
/// lados salta de pista. Los temas **no** deben repetir esos gestos; solo
/// cablear sus botones (play, favorito, siguiente).
class MiniPlayerActions {
  const MiniPlayerActions({
    required this.openPlayer,
    required this.togglePlay,
    required this.next,
    required this.previous,
    required this.toggleLike,
    this.seek = _ignoreSeek,
    this.setVolume = _ignoreSeek,
    this.toggleMute = _ignoreVoid,
    this.openQueue = _ignoreVoid,
    this.openEqualizer = _ignoreVoid,
    this.openLyrics = _ignoreVoid,
  });

  final VoidCallback openPlayer, togglePlay, next, previous, toggleLike;

  /// Fracción 0..1 de la pista; solo tiene efecto si `MiniPlayerState.canSeek`.
  final ValueChanged<double> seek;

  /// Volumen 0..1 (ver `MiniPlayerState.canSetVolume`).
  final ValueChanged<double> setVolume;

  /// Silencia o restaura el volumen anterior ([MuteMemory]).
  final VoidCallback toggleMute;

  /// Sección de cola (5), como el transporte.
  final VoidCallback openQueue;

  /// Hoja del ecualizador (`showEqualizerSheet`); solo si
  /// `MiniPlayerState.equalizerAvailable`.
  final VoidCallback openEqualizer;

  /// Letras (el diálogo que abre el transporte).
  final VoidCallback openLyrics;

  static void _ignoreSeek(double _) {}
  static void _ignoreVoid() {}

  /// Acciones sobre los métodos existentes del controlador y la Jam.
  /// [togglePlay] permite al shell conservar su manejo de errores de Jam.
  factory MiniPlayerActions.forController(
    AppController c, {
    JamController? jam,
    required VoidCallback openPlayer,
    VoidCallback? togglePlay,
    MuteMemory? mute,
    VoidCallback? openQueue,
    VoidCallback? openLyrics,
    VoidCallback? openEqualizer,
  }) {
    final jamAudio = transportJamAudio(c, jam);
    return MiniPlayerActions(
      openPlayer: openPlayer,
      togglePlay:
          togglePlay ??
          () =>
              unawaited(jamAudio ? jam!.togglePlayback() : c.togglePlayback()),
      next: () {
        if (!jamAudio) return unawaited(c.next());
        if (jam!.canSkip) return unawaited(jam.next());
        if (jam.service.rules.votes) jam.service.voteSkip();
      },
      previous: () {
        if (!jamAudio) unawaited(c.previous());
      },
      toggleLike: () {
        final track = c.nowTrack;
        if (track != null) unawaited(c.toggleFavorite(track));
      },
      setVolume: c.setVolume,
      toggleMute: () => (mute ?? MuteMemory()).toggle(c),
      openQueue: openQueue ?? _ignoreVoid,
      openLyrics: openLyrics ?? _ignoreVoid,
      openEqualizer: openEqualizer ?? _ignoreVoid,
      seek: (fraction) {
        final duration = c.audio.duration > Duration.zero
            ? c.audio.duration
            : c.nowTrack?.duration ?? Duration.zero;
        if (duration <= Duration.zero) return;
        final position = Duration(
          milliseconds: (duration.inMilliseconds * fraction.clamp(0.0, 1.0))
              .round(),
        );
        unawaited(jamAudio ? jam!.seek(position) : c.seek(position));
      },
    );
  }
}

/// Recuerda el volumen previo al silenciar. Una sola instancia por shell, para
/// que el atajo de silencio y el botón del mini reproductor se restauren igual.
class MuteMemory {
  double _before = 0.7;

  /// Silencia (guardando el volumen) o restaura el último volumen no nulo.
  void toggle(AppController c) {
    if (c.audio.volume > 0) {
      _before = c.audio.volume;
      c.setVolume(0);
    } else {
      c.setVolume(_before);
    }
  }
}

/// Abre la hoja del ecualizador desde [context] (cada oyente tiene el suyo).
VoidCallback equalizerOpener(BuildContext context, AppController c) =>
    () => showEqualizerSheet(context, c);
