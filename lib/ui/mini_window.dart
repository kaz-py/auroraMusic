import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/window_controls.dart';
import '../jam/jam_controller.dart';
import 'artwork.dart';
import 'mini_player/mini_player_desktop_controls.dart' show kMiniControlTarget;
import 'mini_player/mini_player_model.dart';

/// Modo mini (como el «Miniplayer» de Spotify): la ventana se reduce a una
/// tarjeta siempre visible con portada, título, progreso y controles. Sustituye
/// al shell mientras está activo; el estado del shell se conserva.
///
/// Los permisos de la Jam y los errores salen de [MiniPlayerState] y
/// [MiniPlayerActions] (los mismos de la barra), así que en una Jam «anterior»
/// no existe y «siguiente» solo vale con permiso o voto. Arrastrar el fondo
/// mueve la ventana.
class MiniWindowView extends StatefulWidget {
  const MiniWindowView({
    super.key,
    required this.controller,
    required this.onExit,
    required this.onTogglePlay,
    this.jam,
  });

  final AppController controller;
  final JamController? jam;

  /// Vuelve a la ventana normal.
  final VoidCallback onExit;
  final VoidCallback onTogglePlay;

  @override
  State<MiniWindowView> createState() => _MiniWindowViewState();
}

class _MiniWindowViewState extends State<MiniWindowView> {
  // Posición mostrada mientras se arrastra el control de progreso.
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.audio, ?widget.jam]),
      builder: (context, _) {
        final state = MiniPlayerState.fromController(c, jam: widget.jam);
        final actions = MiniPlayerActions.forController(
          c,
          jam: widget.jam,
          openPlayer: widget.onExit,
          togglePlay: widget.onTogglePlay,
        );
        return Material(
          color: Theme.of(context).colorScheme.surface,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => WindowControls.invoke('drag'),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: state.hasTrack
                  ? _body(context, state, actions)
                  : _empty(context),
            ),
          ),
        );
      },
    );
  }

  Widget _empty(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Row(
      children: [
        const Expanded(child: Text('No suena nada')),
        _exit(context),
      ],
    ),
  );

  Widget _exit(BuildContext context) => IconButton(
    tooltip: 'Salir del mini reproductor',
    onPressed: widget.onExit,
    icon: const Icon(Icons.open_in_full_rounded, size: 20),
    style: IconButton.styleFrom(
      fixedSize: const Size.square(40),
      minimumSize: const Size.square(40),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );

  Widget _body(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final track = state.track!;
    final progress = (_drag ?? state.progress).clamp(0.0, 1.0);
    final shown = state.duration * progress;

    Widget button(
      String tip,
      IconData icon,
      VoidCallback? onTap, {
      Color? color,
    }) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 22, color: color),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(kMiniControlTarget),
        minimumSize: const Size.square(kMiniControlTarget),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    final play = IconButton.filled(
      tooltip: state.buffering
          ? 'Cargando'
          : state.isPlaying
          ? 'Pausar'
          : 'Reproducir',
      onPressed: state.canTogglePlay ? actions.togglePlay : null,
      icon: state.buffering
          ? const SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          : Icon(
              state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 28,
            ),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(kMiniControlTarget),
        minimumSize: const Size.square(kMiniControlTarget),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, box) {
          // La portada cede ancho a los controles en la ventana más estrecha.
          final cover = math
              .min(box.maxHeight, box.maxWidth * .3)
              .clamp(56.0, 130.0);
          return Row(
            children: [
              Semantics(
                label: 'Portada de ${track.title}',
                child: Artwork(
                  track: track,
                  size: cover,
                  artworkContext: ArtworkContext.thumbnail,
                  radius: 8,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, side) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: side.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      miniSubtitle(state),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _exit(context),
                            ],
                          ),
                          SizedBox(
                            height: 28,
                            child: Row(
                              children: [
                                Text(
                                  miniClock(shown),
                                  style: text.labelSmall?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 4,
                                      thumbShape: const RoundSliderThumbShape(
                                        enabledThumbRadius: 6,
                                      ),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                            overlayRadius: 12,
                                          ),
                                    ),
                                    child: Slider(
                                      semanticFormatterCallback: (_) =>
                                          'Posición ${miniClock(shown)}',
                                      value: progress,
                                      onChanged: state.canSeek
                                          ? (v) => setState(() => _drag = v)
                                          : null,
                                      onChangeEnd: state.canSeek
                                          ? (v) {
                                              setState(() => _drag = null);
                                              actions.seek(v);
                                            }
                                          : null,
                                    ),
                                  ),
                                ),
                                Text(
                                  state.duration > Duration.zero
                                      ? miniClock(state.duration)
                                      : '--:--',
                                  style: text.labelSmall?.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              button(
                                state.liked
                                    ? 'Quitar de favoritos'
                                    : 'Añadir a favoritos',
                                state.liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                actions.toggleLike,
                                color: state.liked ? scheme.error : null,
                              ),
                              button(
                                state.previousLabel(),
                                Icons.skip_previous_rounded,
                                state.hasPrevious ? actions.previous : null,
                              ),
                              play,
                              button(
                                state.nextLabel(),
                                state.jamVoteSkip
                                    ? Icons.how_to_vote_outlined
                                    : Icons.skip_next_rounded,
                                state.hasNext ? actions.next : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
