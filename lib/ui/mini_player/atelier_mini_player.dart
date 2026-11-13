import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/atelier_theme.dart';
import '../shell/atelier_widgets.dart';
import '../studio/studio_symbols.dart';
import 'mini_player_desktop_controls.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Atelier («Papel y tinta»). Escritorio: barra de papel
/// de 76 px cuyo filete superior es la línea de progreso (terracota con rombo);
/// portada, título serif y favorito a la izquierda, transporte y tiempos al
/// centro, formato y controles a la derecha. Móvil: tira de 60 px sobre la
/// navegación, con portada, título serif y play circular.
const MiniPlayerTheme atelierMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool wide,
}) => AtelierMiniPlayer(state: state, actions: actions, wide: wide);

/// Alto de la zona de la regla/rombo en reposo.
const double _kStrip = 5;

/// Alto de la regla pintada con el puntero encima: cabe el rombo ampliado.
const double _kStripHover = 12;

/// Alto de la franja que recibe tocar o arrastrar la regla.
const double _kScrub = 24;

/// Margen lateral fijo de la regla: el radio del rombo ampliado.
const double _kScrubInset = 5;

/// Lado táctil de los botones.
const double _kTouch = 44;

class AtelierMiniPlayer extends StatelessWidget {
  const AtelierMiniPlayer({
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
    // La barra nunca crece más allá de ×1,5 (igual que el host): por encima
    // el texto se recorta con puntos.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: Builder(
        builder: (context) {
          final t = AtelierTokens.of(context);
          final scale = MediaQuery.textScalerOf(context).scale(1);
          if (wide) {
            return ColoredBox(
              color: t.paper,
              child: _Bar(
                state: state,
                actions: actions,
                track: track,
                minHeight: 76.0 * scale,
                scale: scale,
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.panel,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: t.rule),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _Strip(
                  state: state,
                  actions: actions,
                  track: track,
                  minHeight: 56.0 * scale,
                  scale: scale,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget _line(String s, TextStyle style) =>
    Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

/// Título serif y subtítulo (artista, o aviso de error con su icono).
Widget _titleBlock(
  BuildContext context,
  MiniPlayerState state,
  Track track, {
  required double size,
}) {
  final t = AtelierTokens.of(context);
  final error = miniSubtitleIsError(state);
  final color = error ? Theme.of(context).colorScheme.error : t.ink2;
  final sub = _line(miniSubtitle(state), t.ui(12.5, color: color, height: 1.2));
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _line(track.title, t.serif(size, height: 1.15)),
      const SizedBox(height: 2),
      error
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(StudioSymbols.error, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(child: sub),
              ],
            )
          : sub,
    ],
  );
}

class _Strip extends StatelessWidget {
  const _Strip({
    required this.state,
    required this.actions,
    required this.track,
    required this.minHeight,
    required this.scale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final Track track;
  final double minHeight, scale;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        final showHeart = box.maxWidth >= 330 - 24;
        return Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, _kStrip, 4, _kStrip),
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: MiniPlayerInfoTap(
                            actions: actions,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AtelierCover(
                                  track: track,
                                  size: 44 * math.min(scale, 1.25),
                                  shadow: false,
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: _titleBlock(
                                    context,
                                    state,
                                    track,
                                    size: 16.5,
                                  ),
                                ),
                              ],
                            ),
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
                          color: state.liked ? t.accentText : t.ink2,
                          onPressed: actions.toggleLike,
                        ),
                      _PlayButton(state: state, actions: actions, t: t),
                      _Quiet(
                        tooltip: state.nextLabel(),
                        icon: state.jamVoteSkip
                            ? Icons.how_to_vote_outlined
                            : StudioSymbols.skipNext,
                        color: t.ink,
                        onPressed: state.hasNext ? actions.next : null,
                      ),
                    ],
                  ),
                ),
                _Scrub(
                  progress: state.progress,
                  canSeek: state.canSeek,
                  onSeek: actions.seek,
                  rule: t.ink,
                  fill: t.accent,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.state,
    required this.actions,
    required this.track,
    required this.minHeight,
    required this.scale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final Track track;
  final double minHeight, scale;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final format = atelierFormat(track);
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, _kStrip + 4, 12, 4),
              child: LayoutBuilder(
                builder: (context, box) {
                  final roomy = box.maxWidth >= 1000;
                  return Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: MiniPlayerInfoTap(
                                  actions: actions,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AtelierCover(
                                        track: track,
                                        size: 48 * math.min(scale, 1.25),
                                        shadow: !MediaQuery.disableAnimationsOf(
                                          context,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Flexible(
                                        child: _titleBlock(
                                          context,
                                          state,
                                          track,
                                          size: 17,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _Quiet(
                                tooltip: state.liked
                                    ? 'Quitar de favoritos'
                                    : 'Añadir a favoritos',
                                icon: state.liked
                                    ? Icons.favorite
                                    : StudioSymbols.favorite,
                                color: state.liked ? t.accentText : t.ink2,
                                onPressed: actions.toggleLike,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: roomy ? 6 : 5,
                        child: _Center(
                          state: state,
                          actions: actions,
                          t: t,
                          showLine: roomy,
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: LayoutBuilder(
                            builder: (context, right) {
                              final chip =
                                  format != null &&
                                  right.maxWidth >=
                                      miniDesktopFull(actions) + 96;
                              return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (chip) ...[
                                    AtelierFormatChip(format),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: MiniPlayerDesktopControls(
                                      state: state,
                                      actions: actions,
                                      color: t.ink2,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            _Scrub(
              progress: state.progress,
              canSeek: state.canSeek,
              onSeek: actions.seek,
              rule: t.ink,
              fill: t.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// Zona central: aleatorio, anterior, play, siguiente y, si cabe, los
/// tiempos con una línea de posición.
class _Center extends StatelessWidget {
  const _Center({
    required this.state,
    required this.actions,
    required this.t,
    required this.showLine,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final AtelierTokens t;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final elapsed = state.elapsed, total = state.duration;
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Quiet(
          tooltip: state.shuffle ? 'Aleatorio (activado)' : 'Aleatorio',
          icon: Icons.shuffle_rounded,
          color: state.shuffle ? t.accentText : t.ink2,
          onPressed: state.canShuffle ? actions.toggleShuffle : null,
        ),
        _Quiet(
          tooltip: state.previousLabel(),
          icon: StudioSymbols.skipPrevious,
          color: t.ink,
          onPressed: state.hasPrevious ? actions.previous : null,
        ),
        _PlayButton(state: state, actions: actions, t: t),
        _Quiet(
          tooltip: state.nextLabel(),
          icon: state.jamVoteSkip
              ? Icons.how_to_vote_outlined
              : StudioSymbols.skipNext,
          color: t.ink,
          onPressed: state.hasNext ? actions.next : null,
        ),
      ],
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(fit: BoxFit.scaleDown, child: controls),
        if (showLine && total > Duration.zero)
          ExcludeSemantics(
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(atelierClock(elapsed), style: t.mono(size: 10.5)),
                ),
                Expanded(
                  child: AtelierLine(progress: state.progress, height: 12),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '-${atelierClock(total - elapsed)}',
                    textAlign: TextAlign.end,
                    style: t.mono(size: 10.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Franja de la regla, al borde de arriba y por encima del contenido. Con
/// [canSeek] se puede tocar o arrastrar (la posición se confirma al soltar) y
/// gana al deslizar de pista de la barra dentro de la franja. Con el puntero
/// encima o arrastrando, la franja crece a 24 px, la regla engorda y el nudo
/// crece (sin animación si están desactivadas).
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
  bool _hover = false;

  double _at(Offset local) {
    final w = (context.size?.width ?? 0) - 2 * _kScrubInset;
    return w <= 0 ? 0 : ((local.dx - _kScrubInset) / w).clamp(0.0, 1.0);
  }

  void _setHover(bool v) {
    if (v != _hover) setState(() => _hover = v);
  }

  void _commit(double fraction) {
    setState(() => _drag = null);
    widget.onSeek(fraction);
  }

  @override
  Widget build(BuildContext context) => Positioned(
    left: 0,
    right: 0,
    top: 0,
    // En reposo solo la franja de la regla (no tapa nada); con el puntero
    // encima o arrastrando crece a 24 px por encima del contenido.
    height: widget.canSeek && (_hover || _drag != null) ? _kScrub : _kStrip,
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()} %';
    final active = widget.canSeek && (_hover || _drag != null);
    final line = ExcludeSemantics(
      child: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: _kStripHover,
          child: RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: active ? 1.0 : 0.0),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              builder: (_, t, _) => CustomPaint(
                size: const Size.fromHeight(_kStripHover),
                painter: _TimelinePainter(
                  progress: value,
                  rule: widget.rule,
                  fill: widget.fill,
                  emphasis: t,
                ),
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
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => _setHover(true),
        onExit: (_) => _setHover(false),
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
      ),
    );
  }
}

/// Regla con el tramo recorrido y un nudo. [emphasis] (0 reposo, 1 puntero
/// encima) engorda la regla y agranda el nudo; el centro baja para que el nudo
/// ampliado no se corte por arriba.
class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.progress,
    required this.rule,
    required this.fill,
    this.emphasis = 0,
  });

  final double progress;
  final Color rule, fill;
  final double emphasis;

  @override
  void paint(Canvas canvas, Size size) {
    final r = _lerp(_kStrip / 2, _kScrubInset);
    final y = _lerp(_kStrip / 2, _kStripHover / 2);
    final ruleH = _lerp(1, 3), fillH = _lerp(1.5, 4);
    canvas.drawRect(
      Rect.fromLTWH(0, y - ruleH / 2, size.width, ruleH),
      Paint()..color = rule,
    );
    final x =
        _kScrubInset +
        progress.clamp(0.0, 1.0) * math.max(0, size.width - 2 * _kScrubInset);
    canvas.drawRect(
      Rect.fromLTRB(0, y - fillH / 2, x, y + fillH / 2),
      Paint()..color = fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x, y - r)
        ..lineTo(x + r, y)
        ..lineTo(x, y + r)
        ..lineTo(x - r, y)
        ..close(),
      Paint()..color = fill,
    );
  }

  double _lerp(double a, double b) => a + (b - a) * emphasis;

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.progress != progress ||
      old.rule != rule ||
      old.fill != fill ||
      old.emphasis != emphasis;
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
    required this.t,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final AtelierTokens t;

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
                    color: t.onAccent,
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
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          disabledBackgroundColor: t.accent.withValues(alpha: .3),
          disabledForegroundColor: t.onAccent.withValues(alpha: .6),
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
