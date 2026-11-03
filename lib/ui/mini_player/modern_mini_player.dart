import 'package:flutter/material.dart';

import '../../theme/accent_transition.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../artwork.dart';
import 'blurred_cover_backdrop.dart';
import 'mini_player_desktop_controls.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Modern: tarjeta flotante de 18 px de radio sobre la
/// navegación (móvil) o centrada al pie del contenido (carril). Portada de
/// 11 px de radio, play circular en el acento, corazón de contorno y una línea
/// de progreso de 2 px dentro del borde inferior que se arrastra para buscar.
const MiniPlayerTheme modernMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool blurred,
  required bool wide,
}) => ModernMiniPlayer(
  state: state,
  actions: actions,
  blurred: blurred,
  wide: wide,
);

const double _radius = 18;
const double _coverRadius = 11;
const double _target = 44;
const double _scrubHeight = 10;

class ModernMiniPlayer extends StatelessWidget {
  const ModernMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.blurred,
    required this.wide,
    this.source,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool blurred, wide;

  /// Origen de portadas del fondo difuminado (pruebas); por defecto el compartido.
  final CoverBackdropSource? source;

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final dark = isDarkTheme(context);
    final accent = AccentScope.of(context, scheme.tertiary);
    final fill = coverTint(scheme.surfaceContainerLow, accent, .07);
    final edge = Color.lerp(
      scheme.outlineVariant,
      accent,
      .35,
    )!.withValues(alpha: blurred ? .5 : .28);
    const radius = BorderRadius.all(Radius.circular(_radius));

    Widget body = _Body(
      state: state,
      actions: actions,
      blurred: blurred,
      wide: wide,
      fill: fill,
    );
    if (blurred) {
      body = BlurredCoverBackdrop(
        track: track,
        radius: radius,
        source: source,
        child: body,
      );
    }
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .38 : .10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: edge),
        ),
        child: ClipRRect(borderRadius: radius, child: body),
      ),
    );
    return Padding(
      padding: wide
          ? const EdgeInsets.fromLTRB(16, 6, 16, 12)
          : const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: !wide
                ? double.infinity
                : MediaQuery.sizeOf(context).width >= 1100
                ? 960
                : 760,
          ),
          child: MouseRegion(cursor: SystemMouseCursors.click, child: card),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.actions,
    required this.blurred,
    required this.wide,
    required this.fill,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool blurred, wide;

  /// Color opaco de la tarjeta (contra el que se ajusta el acento).
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = BlurredCoverTheme.of(context);
    final onCover = BlurredCoverTheme.isActive(context);
    final track = state.track!;
    final cover = wide ? 48.0 : 44.0;

    final inkOn = onCover ? tone.foreground : scheme.onSurface;
    final inkSoft = onCover ? tone.secondary : scheme.onSurfaceVariant;
    // Con fondo claro u oscuro el acento del tema se ajusta contra el color de
    // la tarjeta (más clara que el lienzo), no contra el lienzo.
    final accent = _legible(scheme.tertiary, fill, isDarkTheme(context));
    final playFill = onCover ? tone.foreground : accent;
    final playInk = onCover
        ? (tone.foreground.computeLuminance() > .5 ? Tracky.navy : Colors.white)
        : (coverContrast(Colors.white, accent) >
                  coverContrast(Tracky.navy, accent)
              ? Colors.white
              : Tracky.navy);
    final liked = isDarkTheme(context) ? Tracky.coral : const Color(0xffd32f2f);
    final likedInk = onCover ? tone.foreground : liked;

    final primaryStyle = theme.textTheme.titleMedium!.copyWith(
      fontSize: blurred ? 17 : 14.5,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: blurred ? -.34 : -.2,
      color: inkOn,
    );
    final secondaryStyle = theme.textTheme.bodySmall!.copyWith(
      fontSize: 12.5,
      height: 1.25,
      letterSpacing: -.1,
      color: inkSoft,
    );

    final String? note = miniSubtitleIsError(state)
        ? miniErrorNotice
        : state.jamHostName != null
        ? 'Lo controla ${state.jamHostName}'
        : null;
    final errorInk = onCover ? tone.foreground : scheme.error;

    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          blurred ? track.artist : track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: primaryStyle,
        ),
        if (note != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (miniSubtitleIsError(state)) ...[
                Icon(Icons.error_outline_rounded, size: 14, color: errorInk),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondaryStyle.copyWith(
                    color: miniSubtitleIsError(state) ? errorInk : inkSoft,
                  ),
                ),
              ),
            ],
          )
        else
          Text(
            miniSubtitle(state, artistProminent: blurred),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondaryStyle,
          ),
      ],
    );

    final heart = _Switch(
      value: state.liked,
      child: IconButton(
        key: ValueKey(state.liked),
        tooltip: state.liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
        onPressed: actions.toggleLike,
        style: _iconStyle(),
        isSelected: state.liked,
        color: inkSoft,
        icon: const Icon(Icons.favorite_border_rounded, size: 22),
        selectedIcon: Icon(Icons.favorite_rounded, size: 22, color: likedInk),
      ),
    );

    final play = _Press(
      enabled: state.canTogglePlay,
      child: IconButton(
        tooltip: state.buffering
            ? 'Cargando'
            : state.isPlaying
            ? 'Pausar'
            : 'Reproducir',
        onPressed: state.canTogglePlay ? actions.togglePlay : null,
        style: IconButton.styleFrom(
          backgroundColor: playFill,
          foregroundColor: playInk,
          disabledBackgroundColor: playFill.withValues(alpha: .38),
          disabledForegroundColor: playInk,
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
                  color: playInk,
                ),
              )
            : _Switch(
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
    );

    Widget skip(IconData icon, String label, bool on, VoidCallback onTap) =>
        _Press(
          enabled: on,
          child: IconButton(
            tooltip: label,
            onPressed: on ? onTap : null,
            style: _iconStyle(),
            color: inkOn,
            icon: Icon(icon, size: 26),
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
          borderRadius: BorderRadius.circular(_coverRadius),
          border: Border.all(color: inkOn.withValues(alpha: .10)),
        ),
        child: Artwork(
          track: track,
          size: cover,
          artworkContext: ArtworkContext.thumbnail,
          radius: _coverRadius,
        ),
      ),
    );

    // Tarjeta < 640 px: controles sin slider de volumen.
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 640;
        return Stack(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8, 6, wide ? 12 : 8, _scrubHeight),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _target),
                child: Row(
                  children: [
                    SizedBox.square(dimension: cover, child: art),
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    const SizedBox(width: 4),
                    heart,
                    if (wide)
                      skip(
                        Icons.skip_previous_rounded,
                        'Anterior',
                        state.hasPrevious,
                        actions.previous,
                      ),
                    play,
                    if (wide)
                      skip(
                        Icons.skip_next_rounded,
                        'Siguiente',
                        state.hasNext,
                        actions.next,
                      ),
                    if (wide)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width:
                              kMiniControlTarget * 4 +
                              (compact ? 0 : kMiniVolumeSlider),
                          child: MiniPlayerDesktopControls(
                            state: state,
                            actions: actions,
                            color: inkSoft,
                            compact: compact,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 0,
              height: _scrubHeight,
              child: _ScrubLine(
                progress: state.progress,
                canSeek: state.canSeek,
                onSeek: actions.seek,
                color: onCover ? tone.foreground : accent,
                trackColor: inkOn.withValues(alpha: .14),
              ),
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

/// Acerca [c] a claro (tema oscuro) u oscuro hasta llegar a 3:1 con [bg].
Color _legible(Color c, Color bg, bool dark) {
  var hsl = HSLColor.fromColor(c);
  for (var i = 0; i < 100 && coverContrast(c, bg) < 3; i++) {
    hsl = hsl.withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0, 1));
    c = hsl.toColor();
  }
  return c;
}

/// Cambio de icono: escala 0,8 → 1 con fundido; con movimiento reducido solo
/// fundido.
class _Switch extends StatelessWidget {
  const _Switch({required this.value, required this.child});
  final Object value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: still ? 120 : 180),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => still
          ? FadeTransition(opacity: animation, child: child)
          : FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: .8, end: 1.0).animate(animation),
                child: child,
              ),
            ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    );
  }
}

/// Escala 0,96 mientras se pulsa (respuesta al bajar el dedo). Sin movimiento
/// reducido no hay escala.
class _Press extends StatefulWidget {
  const _Press({required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled && !still ? .96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Línea de progreso de 2 px (4 px con ratón encima o arrastrando, con
/// tirador). Arrastrar o tocar busca; solo se confirma al soltar, no por
/// fotograma. Sin permiso de búsqueda (Jam sin ser anfitrión) es solo visual.
class _ScrubLine extends StatefulWidget {
  const _ScrubLine({
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
  State<_ScrubLine> createState() => _ScrubLineState();
}

class _ScrubLineState extends State<_ScrubLine> {
  bool _hover = false;
  double? _drag;

  double _at(Offset local) {
    final w = (context.size?.width ?? 0);
    return w <= 0 ? 0 : (local.dx / w).clamp(0.0, 1.0);
  }

  void _seekTo(double f) {
    setState(() => _drag = null);
    widget.onSeek(f);
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()} %';
    final line = CustomPaint(
      painter: _LinePainter(
        value: value,
        thick: widget.canSeek && (_hover || _drag != null),
        color: widget.color,
        trackColor: widget.trackColor,
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
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
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
    required this.thick,
    required this.color,
    required this.trackColor,
  });

  final double value;
  final bool thick;
  final Color color, trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = thick ? 4.0 : 2.0;
    final y = size.height - 5;
    final track = RRect.fromLTRBR(
      0,
      y - h / 2,
      size.width,
      y + h / 2,
      Radius.circular(h / 2),
    );
    canvas.drawRRect(track, Paint()..color = trackColor);
    final x = size.width * value;
    if (x > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, y - h / 2, x, y + h / 2, Radius.circular(h / 2)),
        Paint()..color = color,
      );
    }
    if (thick) canvas.drawCircle(Offset(x, y), 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.value != value ||
      old.thick != thick ||
      old.color != color ||
      old.trackColor != trackColor;
}
