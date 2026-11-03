import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../artwork.dart';
import '../studio/studio_symbols.dart';
import 'blurred_cover_backdrop.dart';
import 'mini_player_desktop_controls.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Atelier Sonoro: una funda de disco con el vinilo
/// asomando, sobre papel cálido (oscuro: carbón cálido). La regla superior de
/// un píxel es a la vez el borde del dock y la línea de tiempo, con un nudo
/// minúsculo donde va la reproducción. Ver `docs/mini_player.md`.
const MiniPlayerTheme atelierMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool blurred,
  required bool wide,
}) => AtelierMiniPlayer(
  state: state,
  actions: actions,
  blurred: blurred,
  wide: wide,
);

/// Alto de la zona de la regla/nudo (también el aire sobre y bajo el contenido).
const double _kStrip = 5;

/// Alto de la franja que recibe el arrastre de la regla.
const double _kScrub = 12;

/// Ancho fijo (a escala 1) de lo que no son texto ni controles en el carril:
/// margen, funda con vinilo, hueco, corazón, anterior, play y siguiente.
const double _kWideFixed = 20 + 4 + 72 + 12 + 4 * 44;

/// Ancho completo de `MiniPlayerDesktopControls` (3 botones + silencio + slider).
const double _kDesktopFull = kMiniControlTarget * 4 + kMiniVolumeSlider;

/// Lado táctil de los botones.
const double _kTouch = 44;

class AtelierMiniPlayer extends StatelessWidget {
  const AtelierMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.blurred,
    required this.wide,
    this.source,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  /// Ajuste activo y la pista tiene portada: fondo difuminado + artista grande.
  final bool blurred;
  final bool wide;

  /// Origen de portadas del fondo; por defecto la caché compartida.
  final CoverBackdropSource? source;

  @override
  Widget build(BuildContext context) {
    final track = state.track;
    if (track == null) return const SizedBox.shrink();
    final paper = Theme.of(context).colorScheme.surfaceContainerLow;
    // La barra nunca crece más allá de ×1,5 (igual que el host): por encima
    // el texto se recorta con puntos.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Builder(
        builder: (context) {
          final scale = MediaQuery.textScalerOf(context).scale(1);
          final dock = _Dock(
            state: state,
            actions: actions,
            track: track,
            blurred: blurred,
            wide: wide,
            minHeight: (wide ? 64.0 : 56.0) * scale,
            scale: scale,
          );
          return ColoredBox(
            color: paper,
            child: blurred
                ? BlurredCoverBackdrop(
                    track: track,
                    source: source,
                    matchTheme: true,
                    child: dock,
                  )
                : dock,
          );
        },
      ),
    );
  }
}

/// Colores resueltos: los del tema, o los garantizados sobre la portada.
class _Ink {
  _Ink._({
    required this.fg,
    required this.sub,
    required this.accent,
    required this.onAccent,
    required this.track,
    required this.error,
  });

  factory _Ink.of(BuildContext context, {required bool over}) {
    final scheme = Theme.of(context).colorScheme;
    if (!over) {
      return _Ink._(
        fg: scheme.onSurface,
        sub: scheme.onSurfaceVariant,
        accent: scheme.primary,
        onAccent: scheme.onPrimary,
        track: scheme.outlineVariant,
        error: scheme.error,
      );
    }
    // Sobre la portada solo el texto del tono tiene contraste garantizado: el
    // acento cálido cede su sitio al color del texto (relleno y nudo incluidos).
    final tone = BlurredCoverTheme.of(context);
    final light = tone.foreground.computeLuminance() > .5;
    return _Ink._(
      fg: tone.foreground,
      sub: tone.secondary,
      accent: tone.foreground,
      onAccent: light ? const Color(0xff151312) : const Color(0xfffffaf5),
      track: tone.foreground.withValues(alpha: .32),
      error: tone.foreground,
    );
  }

  final Color fg, sub, accent, onAccent, track, error;
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.state,
    required this.actions,
    required this.track,
    required this.blurred,
    required this.wide,
    required this.minHeight,
    required this.scale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final Track track;
  final bool blurred, wide;
  final double minHeight, scale;

  @override
  Widget build(BuildContext context) {
    final ink = _Ink.of(
      context,
      over: blurred && BlurredCoverTheme.isActive(context),
    );
    final base = Theme.of(context).textTheme.titleLarge!;
    final cover = (wide ? 54.0 : 46.0) * math.min(scale, 1.25);
    final edge = wide ? 20.0 : 12.0;

    Text line(String s, TextStyle style) =>
        Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    // Barra normal: título en la cara de display, artista en cursiva pequeña.
    // Sello (difuminado): el artista manda; el título pasa a cursiva pequeña.
    final headline = blurred
        ? line(
            track.artist,
            base.copyWith(
              fontSize: wide ? 26 : 22,
              height: 1.05,
              fontWeight: FontWeight.w500,
              letterSpacing: -.4,
              color: ink.fg,
            ),
          )
        : line(
            track.title,
            base.copyWith(
              fontSize: wide ? 18 : 16.5,
              height: 1.15,
              fontWeight: FontWeight.w500,
              letterSpacing: -.1,
              color: ink.fg,
            ),
          );
    final small = TextStyle(
      fontSize: wide ? 14.5 : 14,
      height: 1.2,
      fontStyle: FontStyle.italic,
    );
    final detail = miniSubtitleIsError(state)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(StudioSymbols.error, size: 14, color: ink.error),
              const SizedBox(width: 4),
              Flexible(
                child: line(
                  miniSubtitle(state),
                  base.merge(small).copyWith(color: ink.error),
                ),
              ),
            ],
          )
        : line(
            miniSubtitle(state, artistProminent: blurred),
            base.merge(small).copyWith(color: ink.sub),
          );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [headline, detail],
    );

    final playing = state.isPlaying && !state.buffering && !state.hasError;
    return LayoutBuilder(
      builder: (context, box) {
        final showHeart = box.maxWidth >= 330;
        return Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _kScrub,
                  child: _Scrub(
                    progress: state.progress,
                    canSeek: state.canSeek,
                    onSeek: actions.seek,
                    rule: ink.track,
                    fill: ink.accent,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(edge, _kStrip, 4, _kStrip),
                  child: Row(
                    children: [
                      _Sleeve(
                        track: track,
                        size: cover,
                        spinning: playing,
                        accent: ink.accent,
                        onAccent: ink.onAccent,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: wide ? 460 : double.infinity,
                            ),
                            child: text,
                          ),
                        ),
                      ),
                      if (showHeart)
                        _Quiet(
                          tooltip: state.liked
                              ? 'Quitar de favoritos'
                              : 'Añadir a favoritos',
                          icon: state.liked
                              ? Icons.favorite
                              : StudioSymbols.favorite,
                          color: state.liked ? ink.accent : ink.sub,
                          onPressed: actions.toggleLike,
                        ),
                      if (wide)
                        _Quiet(
                          tooltip: 'Anterior',
                          icon: StudioSymbols.skipPrevious,
                          color: ink.fg,
                          onPressed: state.hasPrevious
                              ? actions.previous
                              : null,
                        ),
                      _PlayButton(state: state, actions: actions, ink: ink),
                      _Quiet(
                        tooltip: 'Siguiente',
                        icon: StudioSymbols.skipNext,
                        color: ink.fg,
                        onPressed: state.hasNext ? actions.next : null,
                      ),
                      if (wide)
                        SizedBox(
                          width: math.min(
                            _kDesktopFull,
                            math.max(
                              kMiniControlTarget,
                              box.maxWidth - _kWideFixed * scale - 150,
                            ),
                          ),
                          child: MiniPlayerDesktopControls(
                            state: state,
                            actions: actions,
                            color: ink.sub,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Funda cuadrada (radio 6) con el vinilo asomando por la derecha. Con la
/// pista sonando el disco gira despacio (solo `transform`); con movimiento
/// reducido se queda quieto.
class _Sleeve extends StatefulWidget {
  const _Sleeve({
    required this.track,
    required this.size,
    required this.spinning,
    required this.accent,
    required this.onAccent,
  });

  final Track track;
  final double size;
  final bool spinning;
  final Color accent, onAccent;

  @override
  State<_Sleeve> createState() => _SleeveState();
}

class _SleeveState extends State<_Sleeve> with SingleTickerProviderStateMixin {
  late final _turns = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Sleeve old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final move = widget.spinning && !MediaQuery.disableAnimationsOf(context);
    if (move && !_turns.isAnimating) {
      _turns.repeat();
    } else if (!move && _turns.isAnimating) {
      _turns.stop();
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final disc = size * .92;
    final left = size * .34;
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox(
        width: left + disc,
        height: size,
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: (size - disc) / 2,
              width: disc,
              height: disc,
              child: RepaintBoundary(
                child: RotationTransition(
                  turns: _turns,
                  child: CustomPaint(
                    painter: _VinylPainter(
                      rim: scheme.onSurface.withValues(alpha: .28),
                      label: widget.accent,
                      ink: widget.onAccent,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: Artwork(track: widget.track, size: size, radius: 6),
            ),
          ],
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  const _VinylPainter({
    required this.rim,
    required this.label,
    required this.ink,
  });

  final Color rim, label, ink;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xff12100f));
    canvas.drawCircle(
      c,
      r - .5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rim,
    );
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = const Color(0x2effffff);
    for (final f in const [.86, .74, .62, .5]) {
      canvas.drawCircle(c, r * f, groove);
    }
    // Dos reflejos opuestos: lo que hace visible el giro.
    final sheen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .16
      ..strokeCap = StrokeCap.round
      ..color = const Color(0x1fffffff);
    final ring = Rect.fromCircle(center: c, radius: r * .68);
    canvas.drawArc(ring, -.9, .7, false, sheen);
    canvas.drawArc(ring, math.pi - .9, .7, false, sheen);
    canvas.drawCircle(c, r * .3, Paint()..color = label);
    canvas.drawCircle(c + Offset(r * .15, 0), r * .045, Paint()..color = ink);
    canvas.drawCircle(c, r * .04, Paint()..color = const Color(0xff12100f));
  }

  @override
  bool shouldRepaint(_VinylPainter old) =>
      old.rim != rim || old.label != label || old.ink != ink;
}

/// Franja táctil de 12 px con la regla de 5 px arriba. Con [canSeek] se puede
/// tocar o arrastrar (la posición se confirma al soltar) y gana al deslizar de
/// pista de la barra dentro de la franja.
class _Scrub extends StatefulWidget {
  const _Scrub({
    required this.progress,
    required this.canSeek,
    required this.onSeek,
    required this.rule,
    required this.fill,
  });

  final double progress;
  final bool canSeek;
  final ValueChanged<double> onSeek;
  final Color rule, fill;

  @override
  State<_Scrub> createState() => _ScrubState();
}

class _ScrubState extends State<_Scrub> {
  double? _drag;

  double _at(Offset local) {
    final w = context.size?.width ?? 0;
    return w <= 0 ? 0 : (local.dx / w).clamp(0.0, 1.0);
  }

  void _commit(double fraction) {
    setState(() => _drag = null);
    widget.onSeek(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()} %';
    final line = ExcludeSemantics(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: _kStrip,
          child: RepaintBoundary(
            child: CustomPaint(
              size: const Size.fromHeight(_kStrip),
              painter: _TimelinePainter(
                progress: value,
                rule: widget.rule,
                fill: widget.fill,
              ),
            ),
          ),
        ),
      ),
    );
    if (!widget.canSeek) {
      return IgnorePointer(
        child: Semantics(
          label: 'Progreso de la pista',
          value: percent,
          child: line,
        ),
      );
    }
    return Semantics(
      container: true,
      label: 'Posición',
      value: percent,
      increasedValue: percent,
      decreasedValue: percent,
      onIncrease: () => widget.onSeek((widget.progress + .05).clamp(0.0, 1.0)),
      onDecrease: () => widget.onSeek((widget.progress - .05).clamp(0.0, 1.0)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapUp: (d) => _commit(_at(d.localPosition)),
        onHorizontalDragStart: (d) =>
            setState(() => _drag = _at(d.localPosition)),
        onHorizontalDragUpdate: (d) =>
            setState(() => _drag = _at(d.localPosition)),
        onHorizontalDragEnd: (_) => _commit(_drag ?? widget.progress),
        onHorizontalDragCancel: () => setState(() => _drag = null),
        child: line,
      ),
    );
  }
}

/// Regla de un píxel con el tramo recorrido y un nudo de 5 px.
class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.progress,
    required this.rule,
    required this.fill,
  });

  final double progress;
  final Color rule, fill;

  @override
  void paint(Canvas canvas, Size size) {
    const r = _kStrip / 2;
    final y = size.height / 2;
    canvas.drawRect(
      Rect.fromLTWH(0, y - .5, size.width, 1),
      Paint()..color = rule,
    );
    final x = r + progress.clamp(0.0, 1.0) * math.max(0, size.width - 2 * r);
    canvas.drawRect(
      Rect.fromLTRB(0, y - .75, x, y + .75),
      Paint()..color = fill,
    );
    canvas.drawCircle(Offset(x, y), r, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.progress != progress || old.rule != rule || old.fill != fill;
}

/// Botón sin relleno, 44 × 44, con un hundimiento breve al pulsar.
class _Quiet extends StatelessWidget {
  const _Quiet({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _Press(
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      style: IconButton.styleFrom(
        fixedSize: const Size.square(_kTouch),
        minimumSize: const Size.square(_kTouch),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: color,
        disabledForegroundColor: color.withValues(alpha: .4),
      ),
    ),
  );
}

/// Play/pausa: círculo cálido de 44 px. Buffering: anillo (o reloj de arena
/// quieto con movimiento reducido).
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.state,
    required this.actions,
    required this.ink,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final _Ink ink;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final enabled = state.canTogglePlay;
    final Widget glyph = state.buffering
        ? still
              ? Icon(StudioSymbols.hourglassEmpty, size: 22)
              : SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ink.onAccent,
                  ),
                )
        : Icon(
            state.isPlaying ? StudioSymbols.pause : StudioSymbols.playArrow,
            size: 26,
          );
    return _Press(
      child: IconButton(
        tooltip: !enabled && state.jamHostName != null
            ? 'Lo controla ${state.jamHostName}'
            : state.isPlaying
            ? 'Pausar'
            : 'Reproducir',
        onPressed: enabled ? actions.togglePlay : null,
        icon: glyph,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(_kTouch),
          minimumSize: const Size.square(_kTouch),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const CircleBorder(),
          backgroundColor: ink.accent,
          foregroundColor: ink.onAccent,
          disabledBackgroundColor: ink.accent.withValues(alpha: .3),
          disabledForegroundColor: ink.onAccent.withValues(alpha: .6),
        ),
      ),
    );
  }
}

/// Hundimiento al pulsar (100 ms, ease-out); sin él con movimiento reducido.
class _Press extends StatefulWidget {
  const _Press({required this.child});
  final Widget child;

  @override
  State<_Press> createState() => _PressState();
}

class _PressState extends State<_Press> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down && !MediaQuery.disableAnimationsOf(context) ? .93 : 1,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      child: widget.child,
    ),
  );
}
