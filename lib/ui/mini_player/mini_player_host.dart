import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../jam/jam_controller.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/slush_theme.dart';
import 'atelier_mini_player.dart';
import 'brasa_mini_player.dart';
import 'mini_player_gestures.dart';
import 'mini_player_legacy.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';
import 'modern_mini_player.dart';
import 'slush_mini_player_v2.dart';

export 'mini_player_desktop_controls.dart' show MiniPlayerDesktopControls;
export 'mini_player_gestures.dart' show MiniPlayerGestures;
export 'mini_player_legacy.dart' show MiniPlayerLegacyBars;
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
/// Visibilidad (temas nuevos): oculto sin pista, en la sección 4 (reproductor
/// completo) y en la página oficial de YouTube Music (sección 10). Los temas
/// `legacy` conservan sus reglas de antes.
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
    this.legacy,
    this.onOpenQueue,
    this.onOpenLyrics,
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

  /// Memoria de silencio compartida con el atajo del shell.
  final MuteMemory? mute;

  /// Imprescindible mientras algún tema sea `legacy`.
  final MiniPlayerLegacyBars? legacy;
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
  }) => hasTrack && section != 4 && !officialMusicPage;

  /// Slush en móvil lleva el mini dentro de su barra inferior; con Jam, un
  /// tema `legacy` cae al transporte del cuerpo como siempre.
  static MiniPlayerPlacement placementFor({
    required bool slush,
    required bool rail,
    required bool legacy,
    required bool jamAudio,
  }) => slush && !rail && !(legacy && jamAudio)
      ? MiniPlayerPlacement.bottomBar
      : MiniPlayerPlacement.body;

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
        final jamOwns = c.jamPlaybackActive;
        final mine = placementFor(
          slush: slush,
          rail: rail,
          legacy: theme.legacy,
          jamAudio: jamOwns,
        );
        if (mine != placement) return const SizedBox.shrink();

        final openVinyl = onOpenPlayer;
        if (theme.legacy) {
          // Antes: Slush ocultaba su barra en la sección 4 (salvo con Jam).
          if (slush && !jamOwns && section == 4) return const SizedBox.shrink();
          final bars = legacy;
          assert(bars != null, 'Un tema legacy necesita MiniPlayerLegacyBars');
          return MiniPlayerLegacyScope(
            controller: c,
            jam: jam,
            bars: bars!,
            rail: rail,
            onOpenVinyl: openVinyl,
            onTogglePlay: onTogglePlay,
            child: Builder(
              builder: (context) => theme.build(
                context,
                MiniPlayerState.fromController(c, jam: jam),
                _actions(context, c, openVinyl),
                blurred: false,
                wide: rail,
              ),
            ),
          );
        }

        final state = MiniPlayerState.fromController(c, jam: jam);
        if (!isVisible(
          hasTrack: state.hasTrack,
          section: section,
          officialMusicPage: false,
        )) {
          return const SizedBox.shrink();
        }
        final track = state.track!;
        final actions = _actions(context, c, openVinyl);
        final blurred =
            c.blurredCoverMode &&
            (track.artworkUrl?.trim().isNotEmpty ?? false);
        return MiniPlayerGestures(
          actions: actions,
          hasNext: state.hasNext,
          hasPrevious: state.hasPrevious,
          semanticsLabel: 'Mini reproductor: ${track.title}, ${track.artist}',
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: heightFor(context, wide: rail),
            ),
            child: theme.build(
              context,
              state,
              actions,
              blurred: blurred,
              wide: rail,
            ),
          ),
        );
      },
    );
  }

  MiniPlayerActions _actions(
    BuildContext context,
    AppController c,
    VoidCallback openPlayer,
  ) => MiniPlayerActions.forController(
    c,
    jam: jam,
    openPlayer: openPlayer,
    togglePlay: onTogglePlay,
    mute: mute,
    openQueue: onOpenQueue,
    openLyrics: onOpenLyrics,
    openEqualizer: equalizerOpener(context, c),
  );
}
