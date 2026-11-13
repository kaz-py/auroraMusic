import 'package:flutter/material.dart';

import '../../theme/modern_cristal.dart';
import '../artwork.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';
import 'modern_mini_desktop.dart';
import 'modern_mini_parts.dart';

/// Mini reproductor de Modern «Cristal y aura». Con carril (`wide`) es la
/// barra flotante de [ModernMiniBar]; en móvil, una tarjeta de cristal de 64 px
/// y radio 20 teñida por la portada, con play de 44 px en el acento y una línea
/// de progreso de 2 px dentro del borde inferior que se arrastra para buscar.
const MiniPlayerTheme modernMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool wide,
}) => ModernMiniPlayer(state: state, actions: actions, wide: wide);

const double _target = 44;
const double _scrubHeight = 10;

/// Alto de la zona táctil de la línea: 24 px abarcan la línea (a 5 px del
/// borde inferior) y se quedan dentro de la tarjeta.
const double _scrubZone = 24;

/// Ancho de la tarjeta desde el que el móvil añade «siguiente»; por debajo
/// basta con deslizar.
const double _kNextMinInner = 330;

class ModernMiniPlayer extends StatelessWidget {
  const ModernMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.wide,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    if (wide) return ModernMiniBar(state: state, actions: actions);
    final c = Cristal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ModernMiniTint(
          track: track,
          builder: (context, tint) {
            // Relleno opaco aproximado del cristal teñido (para el contraste
            // del acento, que se ajusta contra la tarjeta y no contra el lienzo).
            final fill = tint == null
                ? c.canvas
                : Color.alphaBlend(tint.withValues(alpha: .17), c.canvas);
            return ModernGlass(
              radius: 20,
              tint: tint,
              clip: true,
              child: _Body(
                state: state,
                actions: actions,
                accent: modernMiniLegible(c.accent, fill, c.dark),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.actions,
    required this.accent,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  /// Acento ajustado contra la tarjeta (línea de progreso).
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final track = state.track!;

    final heart = ModernMiniSwitch(
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

    final play = ModernMiniPress(
      enabled: state.canTogglePlay,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const CircleBorder(),
          shadows: state.canTogglePlay
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: c.dark ? .35 : .25),
                    blurRadius: 16,
                    offset: const Offset(0, 3),
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
            fixedSize: const Size.square(_target),
            minimumSize: const Size.square(_target),
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

    final next = ModernMiniPress(
      enabled: state.hasNext,
      child: IconButton(
        tooltip: state.nextLabel(),
        onPressed: state.hasNext ? actions.next : null,
        style: _iconStyle(),
        color: c.text,
        icon: Icon(
          state.jamVoteSkip
              ? Icons.how_to_vote_outlined
              : Icons.skip_next_rounded,
          size: 26,
        ),
      ),
    );

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
          size: 48,
          artworkContext: ArtworkContext.thumbnail,
          radius: 12,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        final showNext = box.maxWidth >= _kNextMinInner;
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    SizedBox.square(dimension: 48, child: art),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ModernMiniText(state: state),
                      ),
                    ),
                    const SizedBox(width: 4),
                    heart,
                    play,
                    if (showNext) next,
                  ],
                ),
              ),
            ),
            _ScrubStrip(
              progress: state.progress,
              canSeek: state.canSeek,
              onSeek: actions.seek,
              color: accent,
              trackColor: c.text.withValues(alpha: .14),
            ),
          ],
        );
      },
    );
  }

  static ButtonStyle _iconStyle() => IconButton.styleFrom(
    fixedSize: const Size.square(_target),
    minimumSize: const Size.square(_target),
    padding: EdgeInsets.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );
}

/// Franja de la línea de progreso: 10 px en reposo (para no tapar los botones)
/// y 24 px con el ratón encima, para que adelantar sea fácil. Pegada al borde
/// inferior; la línea no se mueve al crecer la zona.
class _ScrubStrip extends StatefulWidget {
  const _ScrubStrip({
    required this.progress,
    required this.canSeek,
    required this.onSeek,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final bool canSeek;
  final ValueChanged<double> onSeek;
  final Color color, trackColor;

  @override
  State<_ScrubStrip> createState() => _ScrubStripState();
}

class _ScrubStripState extends State<_ScrubStrip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 14,
    right: 14,
    bottom: 0,
    height: widget.canSeek && _hover ? _scrubZone : _scrubHeight,
    child: _ScrubLine(
      progress: widget.progress,
      canSeek: widget.canSeek,
      onSeek: widget.onSeek,
      color: widget.color,
      trackColor: widget.trackColor,
      hover: _hover,
      onHover: (v) => setState(() => _hover = v),
    ),
  );
}

/// Línea de progreso de 2 px (4 px con ratón encima o arrastrando, con
/// tirador, animado 120 ms) y cursor de mano.
/// Arrastrar o tocar busca; solo se confirma al soltar, no por
/// fotograma. Sin permiso de búsqueda (Jam sin ser anfitrión) es solo visual.
class _ScrubLine extends StatefulWidget {
  const _ScrubLine({
    required this.progress,
    required this.canSeek,
    required this.onSeek,
    required this.color,
    required this.trackColor,
    required this.hover,
    required this.onHover,
  });

  final double progress;
  final bool canSeek, hover;
  final ValueChanged<double> onSeek;
  final ValueChanged<bool> onHover;
  final Color color, trackColor;

  @override
  State<_ScrubLine> createState() => _ScrubLineState();
}

class _ScrubLineState extends State<_ScrubLine> {
  double? _drag;

  double _at(Offset local) {
    final w = (context.size?.width ?? 0) - 10;
    return w <= 0 ? 0 : ((local.dx - 5) / w).clamp(0.0, 1.0);
  }

  void _seekTo(double f) {
    setState(() => _drag = null);
    widget.onSeek(f);
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()} %';
    final active = widget.canSeek && (widget.hover || _drag != null);
    final line = TweenAnimationBuilder<double>(
      tween: Tween(end: active ? 1.0 : 0.0),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      builder: (_, grow, _) => CustomPaint(
        painter: _LinePainter(
          value: value,
          grow: grow,
          color: widget.color,
          trackColor: widget.trackColor,
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Posición',
      value: percent,
      increasedValue: percent,
      decreasedValue: percent,
      onIncrease: widget.canSeek
          ? () => widget.onSeek((widget.progress + .05).clamp(0.0, 1.0))
          : null,
      onDecrease: widget.canSeek
          ? () => widget.onSeek((widget.progress - .05).clamp(0.0, 1.0))
          : null,
      child: ExcludeSemantics(
        child: widget.canSeek
            ? MouseRegion(
                cursor: SystemMouseCursors.click,
                onEnter: (_) => widget.onHover(true),
                onExit: (_) => widget.onHover(false),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _seekTo(_at(d.localPosition)),
                  onHorizontalDragStart: (d) =>
                      setState(() => _drag = _at(d.localPosition)),
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _drag = _at(d.localPosition)),
                  onHorizontalDragEnd: (_) => _seekTo(_drag ?? widget.progress),
                  onHorizontalDragCancel: () => setState(() => _drag = null),
                  child: line,
                ),
              )
            : IgnorePointer(child: line),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.value,
    required this.grow,
    required this.color,
    required this.trackColor,
  });

  final double value;

  /// 0 = reposo (2 px, sin tirador), 1 = activa (4 px, tirador de 5 px).
  final double grow;
  final Color color, trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = 2.0 + 2.0 * grow;
    final y = size.height - 5;
    final track = RRect.fromLTRBR(
      0,
      y - h / 2,
      size.width,
      y + h / 2,
      Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    const r = 5.0;
    final x = r + (size.width - 2 * r) * value;
    if (x > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, y - h / 2, x, y + h / 2, Radius.circular(h / 2)),
        Paint()..color = color,
      );
    }
    if (grow > 0) {
      canvas.drawCircle(Offset(x, y), r * grow, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.value != value ||
      old.grow != grow ||
      old.color != color ||
      old.trackColor != trackColor;
}
