import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/modern_cristal.dart';
import '../artwork.dart';
import '../studio/studio_symbols.dart';
import 'mini_player_desktop_controls.dart' show MiniPlayerInfoTap;
import 'mini_player_model.dart';
import 'modern_mini_parts.dart';

/// Barra flotante de Modern en escritorio (con carril): cristal de radio 24,
/// 88 px, con tres zonas: pista · transporte con onda de búsqueda · señal,
/// EQ, letras, cola y volumen. Sin sombra ni desenfoque en vivo.
///
/// Responsive: según el ancho de la barra (corregido por el tamaño de texto)
/// pierde primero el slider de volumen y luego el chip de formato; por debajo
/// de 760 pasa a una composición en columna con los botones en un `Wrap`.
/// Con texto > 1,3 los tiempos bajan debajo de la onda.
class ModernMiniBar extends StatelessWidget {
  const ModernMiniBar({super.key, required this.state, required this.actions});

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  static const double _padH = 16;
  static const double _cover = 56;

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: ModernGlass(
        radius: 24,
        padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: 8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: LayoutBuilder(
            builder: (context, box) {
              final eff =
                  (box.maxWidth + 2 * _padH) /
                  math.min(math.max(scale, 1), 1.6);
              final tier = eff >= 1080
                  ? 3
                  : eff >= 900
                  ? 2
                  : eff >= 760
                  ? 1
                  : 0;
              return tier == 0
                  ? _compact(context, scale)
                  : _row(context, scale, tier);
            },
          ),
        ),
      ),
    );
  }

  // --- Composiciones ----------------------------------------------------------

  Widget _row(BuildContext context, double scale, int tier) => Row(
    children: [
      Expanded(flex: 3, child: _trackZone(context)),
      const SizedBox(width: 16),
      Expanded(
        flex: 5,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _centre(context, scale),
          ),
        ),
      ),
      const SizedBox(width: 16),
      Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Controles del reproductor',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tier >= 2) ...[_chip(context), const SizedBox(width: 8)],
            ..._buttons(context, slider: tier >= 3),
          ],
        ),
      ),
    ],
  );

  Widget _compact(BuildContext context, double scale) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _trackZone(context),
      const SizedBox(height: 8),
      _centre(context, scale),
      const SizedBox(height: 4),
      Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Controles del reproductor',
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          runSpacing: 0,
          children: [_chip(context), ..._buttons(context, slider: false)],
        ),
      ),
    ],
  );

  // --- Zona 1: pista ----------------------------------------------------------

  Widget _trackZone(BuildContext context) {
    final c = Cristal.of(context);
    final track = state.track!;
    final art = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      child: DecoratedBox(
        key: ValueKey(track.id),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Artwork(
          track: track,
          size: _cover,
          artworkContext: ArtworkContext.thumbnail,
          radius: 12,
        ),
      ),
    );
    return Row(
      children: [
        Flexible(
          child: Align(
            alignment: Alignment.centerLeft,
            child: MiniPlayerInfoTap(
              actions: actions,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(dimension: _cover, child: art),
                  const SizedBox(width: 12),
                  Flexible(
                    child: ModernMiniText(
                      state: state,
                      titleSize: 15,
                      titleLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        _heart(context),
      ],
    );
  }

  Widget _heart(BuildContext context) {
    final c = Cristal.of(context);
    return ModernMiniSwitch(
      value: state.liked,
      child: IconButton(
        key: ValueKey(state.liked),
        tooltip: state.liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
        onPressed: actions.toggleLike,
        style: _iconStyle(),
        isSelected: state.liked,
        color: c.text2,
        icon: const Icon(Icons.favorite_border_rounded, size: 22),
        selectedIcon: Icon(Icons.favorite_rounded, size: 22, color: c.like),
      ),
    );
  }

  // --- Zona 2: transporte y onda ---------------------------------------------

  Widget _centre(BuildContext context, double scale) {
    final c = Cristal.of(context);
    final known = state.duration > Duration.zero;
    final elapsed = miniClock(known ? state.elapsed : Duration.zero);
    final total = known ? miniClock(state.duration) : '--:--';
    final style = Cristal.mono(11.5, color: c.text3, tracking: .02);
    Widget time(String text, {required bool end, required bool label}) {
      Widget t = Text(
        text,
        maxLines: 1,
        style: style,
        textAlign: end ? TextAlign.start : TextAlign.end,
      );
      t = label
          ? Semantics(
              label: 'Tiempo: $elapsed de $total',
              excludeSemantics: true,
              child: t,
            )
          : ExcludeSemantics(child: t);
      return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: t);
    }

    final wave = ModernWaveSeekBar(
      progress: state.progress,
      seed: state.track!.id,
      height: 24,
      barWidth: 2,
      gap: 2,
      onSeek: state.canSeek ? actions.seek : null,
    );
    final below = scale > 1.3;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _transport(context),
        const SizedBox(height: 4),
        if (below) ...[
          wave,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              time(elapsed, end: true, label: true),
              time(total, end: false, label: false),
            ],
          ),
        ] else
          Row(
            children: [
              SizedBox(
                width: 44,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: time(elapsed, end: false, label: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: wave),
              const SizedBox(width: 10),
              SizedBox(
                width: 44,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: time(total, end: true, label: false),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _transport(BuildContext context) {
    final c = Cristal.of(context);
    Widget skip(IconData icon, String tip, bool on, VoidCallback onTap) =>
        ModernMiniPress(
          enabled: on,
          child: IconButton(
            tooltip: tip,
            onPressed: on ? onTap : null,
            style: _iconStyle(),
            color: c.text,
            icon: Icon(icon, size: 26),
          ),
        );

    final play = ModernMiniPress(
      enabled: state.canTogglePlay,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const CircleBorder(),
          shadows: state.canTogglePlay
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: c.dark ? .40 : .30),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: IconButton(
          tooltip: state.buffering
              ? 'Cargando'
              : state.isPlaying
              ? 'Pausar'
              : 'Reproducir',
          onPressed: state.canTogglePlay ? actions.togglePlay : null,
          style: IconButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
            disabledBackgroundColor: c.accent.withValues(alpha: .38),
            disabledForegroundColor: c.onAccent,
            fixedSize: const Size.square(44),
            minimumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const CircleBorder(),
          ),
          icon: state.buffering
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.onAccent,
                  ),
                )
              : ModernMiniSwitch(
                  value: state.isPlaying,
                  child: Icon(
                    state.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    key: ValueKey(state.isPlaying),
                    size: 26,
                  ),
                ),
        ),
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ModernMiniTile(
          tip: state.shuffle ? 'Aleatorio (activado)' : 'Aleatorio',
          icon: Icons.shuffle_rounded,
          active: state.shuffle,
          onTap: state.canShuffle ? actions.toggleShuffle : null,
        ),
        const SizedBox(width: 4),
        skip(
          Icons.skip_previous_rounded,
          state.previousLabel(),
          state.hasPrevious,
          actions.previous,
        ),
        const SizedBox(width: 4),
        play,
        const SizedBox(width: 4),
        skip(
          state.jamVoteSkip
              ? Icons.how_to_vote_outlined
              : Icons.skip_next_rounded,
          state.nextLabel(),
          state.hasNext,
          actions.next,
        ),
      ],
    );
  }

  // --- Zona 3: señal y utilidades --------------------------------------------

  Widget _chip(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 132),
    child: MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: ModernSignalChip(label: modernFormatLabel(state.track!)),
    ),
  );

  List<Widget> _buttons(BuildContext context, {required bool slider}) {
    final eqTip = !state.equalizerAvailable
        ? state.equalizerUnavailableReason == null
              ? 'Ecualizador no disponible en este reproductor'
              : 'Ecualizador no disponible: ${state.equalizerUnavailableReason}'
        : 'Ecualizador${state.equalizerActive ? ' (activo)' : ''}';
    final queueTip = state.hasQueue
        ? 'Abrir cola (${state.queueLength})'
        : 'Abrir cola';
    return [
      ModernMiniTile(
        tip: eqTip,
        icon: StudioSymbols.equalizer,
        active: state.equalizerAvailable && state.equalizerActive,
        onTap: state.equalizerAvailable ? actions.openEqualizer : null,
      ),
      ModernMiniTile(
        tip: 'Letras',
        icon: StudioSymbols.lyrics,
        onTap: state.lyricsAvailable ? actions.openLyrics : null,
      ),
      ModernMiniTile(
        tip: queueTip,
        icon: StudioSymbols.queueMusic,
        onTap: actions.openQueue,
      ),
      ModernMiniTile(
        tip: state.muted ? 'Quitar silencio' : 'Silenciar',
        icon: state.muted
            ? Icons.volume_off_rounded
            : state.volume < .5
            ? Icons.volume_down_rounded
            : StudioSymbols.volumeUp,
        onTap: state.canSetVolume ? actions.toggleMute : null,
      ),
      if (slider) _VolumeLine(state: state, actions: actions),
      if (actions.openMini case final openMini?)
        ModernMiniTile(
          tip: 'Mini reproductor',
          icon: Icons.picture_in_picture_alt_rounded,
          onTap: openMini,
        ),
    ];
  }

  static ButtonStyle _iconStyle() => IconButton.styleFrom(
    fixedSize: const Size.square(44),
    minimumSize: const Size.square(44),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// Línea de volumen fina (blanca sobre blanco 24 %), 96 px.
class _VolumeLine extends StatelessWidget {
  const _VolumeLine({required this.state, required this.actions});

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return SizedBox(
      width: 96,
      height: 44,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: c.text,
          inactiveTrackColor: c.text.withValues(alpha: .24),
          thumbColor: c.text,
          overlayColor: c.text.withValues(alpha: .12),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Slider(
          semanticFormatterCallback: (value) =>
              'Volumen ${(value * 100).round()} por ciento',
          value: state.volume.clamp(0.0, 1.0),
          onChanged: state.canSetVolume ? actions.setVolume : null,
        ),
      ),
    );
  }
}
