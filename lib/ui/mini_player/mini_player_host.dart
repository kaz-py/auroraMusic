import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/slush_theme.dart';
import 'song_card.dart';
import 'atelier_mini_player.dart';
import 'brasa_mini_player.dart';
import 'mini_player_gestures.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';
import 'modern_mini_player.dart';
import 'slush_mini_player_v2.dart';

export 'mini_player_desktop_controls.dart' show MiniPlayerDesktopControls;
export 'mini_player_gestures.dart' show MiniPlayerGestures;
export 'mini_player_model.dart'
    show MiniPlayerActions, MiniPlayerState, MuteMemory;
export 'mini_player_theme.dart' show MiniPlayerBuilder, MiniPlayerTheme;

/// Registro por `AppController.themeKind`. Cada tema vive en su archivo.
const Map<String, MiniPlayerTheme> miniPlayerThemes = {
  'atelier': atelierMiniPlayer,
  'modern': modernMiniPlayer,
  'brasa': brasaMiniPlayer,
  'slush': slushMiniPlayerV2,
};

/// Dónde se monta el host en el shell.
enum MiniPlayerPlacement {
  /// Final de la columna del cuerpo (móvil: sobre la navegación; con carril:
  /// al pie del contenido).
  body,

  /// Dentro de la zona inferior de Slush en móvil (`SlushBottomBar.mini`).
  bottomBar,
}

/// Mini reproductor: elige el tema, decide si se ve y a qué altura va.
///
/// El shell monta dos hosts (uno por [MiniPlayerPlacement]); [placementFor]
/// decide cuál dibuja, así que solo uno ocupa espacio. Como va en flujo
/// (columna del cuerpo o zona inferior), el shell reserva su altura sin
/// medir nada.
///
/// Visibilidad: oculto sin pista, en la sección 4 (reproductor completo) y en
/// la página oficial de YouTube Music (sección 10). Con Jam se ve el mismo mini
/// del tema: el estado ya limita «anterior», «siguiente» y reproducir según los
/// permisos de la Jam.
class MiniPlayerHost extends StatelessWidget {
  const MiniPlayerHost({
    super.key,
    required this.controller,
    required this.section,
    required this.rail,
    required this.placement,
    required this.onOpenPlayer,
    required this.onTogglePlay,
    this.jam,
    this.onOpenQueue,
    this.onOpenLyrics,
    this.onOpenMini,
    this.mute,
    this.themes = miniPlayerThemes,
  });

  final AppController controller;

  /// Sección activa del shell (4 = reproductor completo, 10 = YouTube Music).
  final int section;

  /// Diseño con carril lateral (ancho ≥ 600).
  final bool rail;
  final MiniPlayerPlacement placement;

  /// Abrir el reproductor completo (sección 4).
  final VoidCallback onOpenPlayer;

  /// Alternar reproducción (con el manejo de errores de Jam del shell).
  final VoidCallback onTogglePlay;
  final JamController? jam;

  /// Sección de cola (5) y letras (el diálogo del transporte); el shell los
  /// pasa. Sin ellos las acciones no hacen nada.
  final VoidCallback? onOpenQueue, onOpenLyrics;

  /// Modo mini (ventana compacta, solo Windows): entrada del menú de la
  /// canción. `null`: no hay ventana que reducir.
  final VoidCallback? onOpenMini;

  /// Memoria de silencio compartida con el atajo del shell.
  final MuteMemory? mute;

  final Map<String, MiniPlayerTheme> themes;

  /// Clave del tema vigente según el `ThemeData` activo.
  static String kindOf(BuildContext context) => isSlush(context)
      ? 'slush'
      : isBrasa(context)
      ? 'brasa'
      : isModern(context)
      ? 'modern'
      : 'atelier';

  /// Reglas de los temas nuevos.
  static bool isVisible({
    required bool hasTrack,
    required int section,
    required bool officialMusicPage,
  }) => hasTrack && section != 4 && section != 6 && !officialMusicPage;

  /// Slush en móvil lleva el mini dentro de su barra inferior (también con
  /// Jam); el resto, en el cuerpo.
  static MiniPlayerPlacement placementFor({
    required bool slush,
    required bool rail,
  }) =>
      slush && !rail ? MiniPlayerPlacement.bottomBar : MiniPlayerPlacement.body;

  /// Altura mínima de la barra: 56 en móvil, 64 con carril, crece hasta ×1,5
  /// con el tamaño de texto (por encima el contenido se recorta con puntos,
  /// nunca desborda). Cumple el táctil de 44 con holgura.
  static double heightFor(BuildContext context, {required bool wide}) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    return (wide ? 64.0 : 56.0) * scale;
  }

  @override
  Widget build(BuildContext context) {
    final kind = kindOf(context);
    final theme = themes[kind] ?? themes['atelier']!;
    return ListenableBuilder(
      listenable: Listenable.merge([controller, controller.eq, ?jam]),
      builder: (context, _) {
        final c = controller;
        if (section == 10 && c.usesOfficialYouTubeMusic) {
          return const SizedBox.shrink();
        }
        final slush = kind == 'slush';
        final mine = placementFor(slush: slush, rail: rail);
        if (mine != placement) return const SizedBox.shrink();

        final openVinyl = onOpenPlayer;
        final state = MiniPlayerState.fromController(c, jam: jam);

        if (!isVisible(
          hasTrack: state.hasTrack,
          section: section,
          officialMusicPage: false,
        )) {
          return const SizedBox.shrink();
        }
        final track = state.track!;
        // Con carril (escritorio) solo la portada y el título abren el menú
        // de la canción (compartir, enviar a un amigo, añadir a una lista…); el
        // resto de la barra no responde al clic y el modo Vinilo queda como
        // entrada del menú. En móvil el toque sobre la barra lleva al
        // reproductor.
        final actions = _actions(
          context,
          c,
          openVinyl,
          openMenu: rail
              ? (at) => _openSongMenu(
                  context,
                  c,
                  track,
                  at,
                  openVinyl,
                  onOpenMini,
                  onOpenQueue,
                )
              : null,
        );

        return MiniPlayerGestures(
          actions: actions,
          hasNext: state.hasNext,
          hasPrevious: state.hasPrevious,
          tapOpens: !rail,
          onLongPress: rail
              ? null
              : (at) => _openSongMenu(
                  context,
                  c,
                  track,
                  at,
                  openVinyl,
                  onOpenMini,
                  onOpenQueue,
                ),
          semanticsLabel: 'Mini reproductor: ${track.title}, ${track.artist}',
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: heightFor(context, wide: rail),
            ),
            child: theme.build(context, state, actions, wide: rail),
          ),
        );
      },
    );
  }

  MiniPlayerActions _actions(
    BuildContext context,
    AppController c,
    VoidCallback openPlayer, {
    ValueChanged<Offset>? openMenu,
  }) => MiniPlayerActions.forController(
    c,
    jam: jam,
    openPlayer: openPlayer,
    togglePlay: onTogglePlay,
    mute: mute,
    openQueue: onOpenQueue,
    openLyrics: onOpenLyrics,
    openMini: onOpenMini,
    openMenu: openMenu,
    openEqualizer: equalizerOpener(context, c),
  );
}

void _openSongMenu(
  BuildContext context,
  AppController c,
  Track track,
  Offset at,
  VoidCallback openVinyl,
  VoidCallback? openMini,
  VoidCallback? openQueue,
) => unawaited(
  showSongCard(
    context,
    c,
    track,
    at,
    extras: [
      (label: 'Abrir Modo Vinilo', icon: Icons.album_outlined, run: openVinyl),
      if (openMini != null)
        (
          label: 'Abrir el mini reproductor',
          icon: Icons.picture_in_picture_alt_rounded,
          run: openMini,
        ),
    ],
    openQueue: openQueue,
  ),
);
