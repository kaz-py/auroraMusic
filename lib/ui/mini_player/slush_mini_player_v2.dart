import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import 'mini_player_desktop_controls.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Slush 2.0: cápsula con contorno de 2 px y sombra dura.
///
/// - Escritorio: cápsula de papel a todo el ancho, portada circular, Play lima
///   y progreso de 12 px (relleno violeta, mando lima de 22 px).
/// - Móvil: cápsula lila con portada circular, Play lima de 44 y progreso fino.
/// - Oscuro: cápsula `raised` con contorno crema; el lima queda en el Play.
const MiniPlayerTheme slushMiniPlayerV2 = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool wide,
}) => SlushMiniPlayer(state: state, actions: actions, wide: wide);

/// Color vivo de Slush más cercano al tono de [accent].
Color slushVividFor(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  if (hsl.saturation < .15) return Slush.lilac;
  final h = hsl.hue;
  if (h < 40 || h >= 340) return Slush.orange;
  if (h < 70) return Slush.yellow;
  if (h < 170) return Slush.mint;
  return Slush.lilac;
}

/// Ancho interior (sin contorno ni relleno) desde el que el móvil añade
/// «siguiente»; por debajo basta con deslizar.
const double _kNextMinInner = 330;

/// Móvil: barra fina de 4 px. Escritorio: pista de 12 px y mando de 22 px.
const double _kBar = 4, _kTrack = 12, _kKnob = 22;

/// Franja arrastrable del progreso (la barra va centrada). Más alta que la
/// barra para que sea fácil acertar con el ratón.
const double _kSeekHit = 32;

/// Tamaño del mando y grosor de la barra con el puntero encima.
const double _kKnobHover = 24, _kTrackHover = 14;

// Ancho fijo de la fila ancha (portada 52 + 14 + 6 + aleatorio 44 + anterior
// 44 + play 52 + siguiente 44 + corazón 44) y mínimo de título antes de
// plegar los controles.
const double _kWideFixed = 300, _kTitleMin = 140;

/// Colores ya resueltos del aspecto de la barra.
class _Look {
  const _Look({
    required this.fill,
    required this.stroke,
    required this.fg,
    required this.sub,
    required this.accent,
    required this.playFill,
    required this.playIcon,
    required this.barFilled,
    required this.barEmpty,
    required this.knobFill,
    required this.knobStroke,
    required this.heartFill,
  });

  final Color fill, stroke, fg, sub, accent;
  final Color playFill, playIcon;
  final Color barFilled, barEmpty, knobFill, knobStroke;
  final Color? heartFill;

  factory _Look.of(BuildContext context, {required bool wide}) {
    final p = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? p.raised : (wide ? p.paper : Slush.lilacHero);
    return _Look(
      fill: fill,
      stroke: p.line,
      fg: p.ink,
      // Sobre el lila el secundario sube a tinta plena (contraste AA).
      sub: dark || wide ? p.ink2 : Slush.ink,
      accent: p.violetAccent,
      playFill: Slush.lime,
      playIcon: Slush.ink,
      barFilled: wide ? (dark ? p.violetAccent : Slush.violet) : p.ink,
      barEmpty: wide
          ? p.inset
          : Color.alphaBlend(
              (dark ? p.line : Slush.ink).withAlpha(dark ? 80 : 56),
              fill,
            ),
      knobFill: Slush.lime,
      knobStroke: Slush.ink,
      heartFill: dark ? null : p.paper,
    );
  }
}

class SlushMiniPlayer extends StatefulWidget {
  const SlushMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.wide,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide;

  @override
  State<SlushMiniPlayer> createState() => _SlushMiniPlayerState();
}

class _SlushMiniPlayerState extends State<SlushMiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(
    vsync: this,
    duration: SlushMotion.miniPlayerIn,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _in,
    curve: SlushMotion.easeOut,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (SlushMotion.reduce(context)) _in.duration = SlushMotion.reduced;
    _in.forward();
  }

  @override
  void dispose() {
    _curve.dispose();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.state.track;
    if (track == null) return const SizedBox.shrink();
    final wide = widget.wide;
    final p = context.slush;
    final reduce = SlushMotion.reduce(context);
    final radius = BorderRadius.circular(wide ? 40 : 32);

    final base = _Look.of(context, wide: wide);
    final content = _Body(
      state: widget.state,
      actions: widget.actions,
      wide: wide,
      look: base,
    );
    final face = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(borderRadius: radius, side: p.border),
      ),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: base.fill,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
        child: content,
      ),
    );

    // Sombra dura fija detrás de la cara (sin desenfoque).
    const e = SlushElevation.card;
    Widget pill = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: e.offset.dx,
          top: e.offset.dy,
          right: -e.offset.dx,
          bottom: -e.offset.dy,
          child: DecoratedBox(
            decoration: BoxDecoration(color: p.shadow, borderRadius: radius),
          ),
        ),
        face,
      ],
    );

    const margin = 16.0;
    pill = Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? margin : 0,
        0,
        wide ? margin + e.offset.dx : e.offset.dx,
        wide ? SlushSpacing.s16 : SlushSpacing.s12,
      ),
      child: pill,
    );
    return FadeTransition(
      opacity: _curve,
      child: reduce
          ? pill
          : AnimatedBuilder(
              animation: _curve,
              child: pill,
              builder: (_, child) => Transform.translate(
                offset: Offset(0, 8 * (1 - _curve.value)),
                child: child,
              ),
            ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.state,
    required this.actions,
    required this.wide,
    required this.look,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final track = state.track!;
    final reduce = SlushMotion.reduce(context);
    final cover = wide ? 56.0 : 48.0;
    final pad = wide ? 16.0 : 12.0;

    Widget swap(Widget child) => AnimatedSwitcher(
      duration: reduce ? SlushMotion.reduced : SlushMotion.sectionIn,
      reverseDuration: SlushMotion.sectionOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) =>
          SlushMotion.fadeSlide(animation, child, reduced: reduce),
      child: KeyedSubtree(key: ValueKey(track.id), child: child),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, wide ? 10 : 8, pad, wide ? 8 : 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final next = wide || box.maxWidth >= _kNextMinInner;
          // Ancho que sobra para los controles de escritorio tras portada,
          // transporte y un mínimo de título; ellos se pliegan solos.
          final room = box.maxWidth - _kWideFixed - _kTitleMin;
          final full = miniDesktopFull(actions);
          final noSlider = miniDesktopNoSlider(actions);
          final controls = room >= full
              ? full
              : room >= noSlider
              ? noSlider
              : kMiniControlTarget;
          // La hora solo si los controles caben enteros y sobra su ancho.
          final showTime = wide && room >= full + kMiniTimeWidth + 8;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MiniPlayerInfoTap(
                        actions: actions,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            swap(
                              _Cover(
                                track: track,
                                size: cover,
                                stroke: look.stroke,
                              ),
                            ),
                            SizedBox(width: wide ? 14 : 10),
                            Flexible(
                              child: swap(
                                _Titles(
                                  state: state,
                                  track: track,
                                  look: look,
                                  wide: wide,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (showTime) ...[
                    MiniPlayerTime(state: state, color: look.sub),
                    const SizedBox(width: 6),
                  ],
                  if (wide) ...[
                    SizedBox(
                      width: controls,
                      child: MiniPlayerDesktopControls(
                        state: state,
                        actions: actions,
                        color: look.fg,
                      ),
                    ),
                    // Aleatorio: solo en la fila ancha; activo = color de
                    // acento (playFill) y puntito, para no depender solo del tono.
                    _IconAction(
                      tooltip: state.shuffle
                          ? 'Aleatorio (activado)'
                          : 'Aleatorio',
                      icon: Icons.shuffle_rounded,
                      color: state.shuffle ? look.accent : look.fg,
                      dot: state.shuffle,
                      onTap: state.canShuffle ? actions.toggleShuffle : null,
                    ),
                    _IconAction(
                      tooltip: state.previousLabel(),
                      icon: Icons.skip_previous_rounded,
                      color: look.fg,
                      onTap: state.hasPrevious ? actions.previous : null,
                    ),
                  ],
                  _PlayButton(
                    state: state,
                    look: look,
                    size: wide ? 52 : 44,
                    onTap: state.canTogglePlay ? actions.togglePlay : null,
                  ),
                  if (next)
                    _IconAction(
                      tooltip: state.nextLabel(),
                      icon: state.jamVoteSkip
                          ? Icons.how_to_vote_outlined
                          : Icons.skip_next_rounded,
                      color: look.fg,
                      onTap: state.hasNext ? actions.next : null,
                    ),
                  _Heart(
                    liked: state.liked,
                    look: look,
                    onTap: actions.toggleLike,
                  ),
                ],
              ),
              SizedBox(height: state.canSeek ? 0 : (wide ? 8 : 6)),
              _SeekBar(
                progress: state.progress,
                canSeek: state.canSeek,
                thin: !wide,
                look: look,
                onSeek: actions.seek,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Progreso segmentado. Con [canSeek] es arrastrable (tocar o arrastrar mueve
/// el mando; `seek` se llama al soltar) y gana al deslizar de pista dentro de
/// la franja. Sin permiso solo se ve.
class _SeekBar extends StatefulWidget {
  const _SeekBar({
    required this.progress,
    required this.canSeek,
    required this.thin,
    required this.look,
    required this.onSeek,
  });

  final double progress;
  final bool canSeek, thin;
  final _Look look;
  final ValueChanged<double> onSeek;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _drag;
  bool _hover = false;

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
    final look = widget.look;
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    final percent = '${(value * 100).round()} %';
    // Con el puntero encima (o arrastrando) la barra y el mando crecen.
    final active = widget.canSeek && (_hover || _drag != null);
    final bar = ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: active ? 1.0 : 0.0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        builder: (context, grow, _) => CustomPaint(
          size: Size.fromHeight(
            widget.thin ? 10 : (widget.canSeek ? _kKnobHover : _kKnob),
          ),
          painter: _SmoothBarPainter(
            progress: value,
            thin: widget.thin,
            grow: grow,
            filled: look.barFilled,
            empty: look.barEmpty,
            knobFill: look.knobFill,
            knobStroke: look.knobStroke,
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      label: 'Progreso',
      value: percent,
      increasedValue: percent,
      decreasedValue: percent,
      onIncrease: widget.canSeek
          ? () => widget.onSeek((widget.progress + .05).clamp(0.0, 1.0))
          : null,
      onDecrease: widget.canSeek
          ? () => widget.onSeek((widget.progress - .05).clamp(0.0, 1.0))
          : null,
      child: widget.canSeek
          ? MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
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
                child: SizedBox(
                  height: _kSeekHit,
                  child: Center(child: bar),
                ),
              ),
            )
          : bar,
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.size, required this.stroke});

  final Track track;
  final double size;
  final Color stroke;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: stroke, width: SlushStroke.base),
    ),
    child: Artwork(
      track: track,
      size: size - 2 * SlushStroke.base,
      radius: size,
    ),
  );
}

class _Titles extends StatelessWidget {
  const _Titles({
    required this.state,
    required this.track,
    required this.look,
    required this.wide,
  });

  final MiniPlayerState state;
  final Track track;
  final _Look look;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final error = miniSubtitleIsError(state);
    final titleSize = wide ? 15.0 : 14.0, subSize = wide ? 13.0 : 12.0;
    final line = Text(
      track.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: titleSize,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: look.fg,
      ),
    );
    final artist = Text(
      miniSubtitle(state),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: subSize,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: look.sub,
      ),
    );
    final problem = Row(
      children: [
        Icon(Icons.error_outline_rounded, size: subSize + 2, color: look.sub),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            miniErrorNotice,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: subSize,
              height: 1.25,
              fontWeight: FontWeight.w800,
              color: look.sub,
            ),
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [line, error ? problem : artist],
    );
  }
}

/// Botón circular de relieve de pegatina: se hunde sobre su sombra al pulsar.
class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.state,
    required this.look,
    required this.size,
    required this.onTap,
  });

  final MiniPlayerState state;
  final _Look look;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = SlushMotion.reduce(context);
    final Widget icon;
    if (state.buffering) {
      icon = reduce
          ? Icon(Icons.more_horiz_rounded, color: look.playIcon, size: 26)
          : SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: look.playIcon,
              ),
            );
    } else {
      final playing = state.isPlaying;
      icon = Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        key: ValueKey(playing),
        color: look.playIcon,
        size: 28,
      );
    }
    final tip = state.jamHostName != null
        ? 'Lo controla ${state.jamHostName}'
        : state.isPlaying
        ? 'Pausar'
        : 'Reproducir';
    return Tooltip(
      message: tip,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: SlushPressable(
          onTap: onTap,
          semanticLabel: tip,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: look.playFill,
              shape: CircleBorder(
                side: BorderSide(color: look.stroke, width: SlushStroke.base),
              ),
            ),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduce ? SlushMotion.reduced : SlushMotion.select,
                  switchInCurve: SlushMotion.easeOut,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: reduce
                        ? child
                        : ScaleTransition(
                            scale: Tween(begin: .8, end: 1.0).animate(a),
                            child: child,
                          ),
                  ),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
    this.dot = false,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Opacity(
      opacity: onTap == null ? .45 : 1,
      child: SlushPressable(
        elevation: SlushElevation.none,
        onTap: onTap,
        semanticLabel: tooltip,
        child: SizedBox.square(
          dimension: SlushControl.touch,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              if (dot)
                Positioned(
                  bottom: 4,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Corazón de pegatina: con favorito se rellena de rosa y da un salto corto.
class _Heart extends StatefulWidget {
  const _Heart({required this.liked, required this.look, required this.onTap});

  final bool liked;
  final _Look look;
  final VoidCallback onTap;

  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  @override
  void didUpdateWidget(_Heart old) {
    super.didUpdateWidget(old);
    if (widget.liked && !old.liked && !SlushMotion.reduce(context)) {
      _pop.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look, liked = widget.liked;
    final tip = liked ? 'Quitar de favoritos' : 'Guardar en favoritos';
    return Tooltip(
      message: tip,
      child: SlushPressable(
        elevation: SlushElevation.none,
        onTap: widget.onTap,
        semanticLabel: tip,
        child: ScaleTransition(
          scale: TweenSequence([
            TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.22), weight: 40),
            TweenSequenceItem(tween: Tween(begin: 1.22, end: 1.0), weight: 60),
          ]).chain(CurveTween(curve: SlushMotion.easeOut)).animate(_pop),
          child: SizedBox.square(
            dimension: SlushControl.touch,
            child: Center(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: liked ? Slush.pink : look.heartFill,
                  shape: CircleBorder(
                    side: BorderSide(
                      color: look.stroke,
                      width: SlushStroke.base,
                    ),
                  ),
                ),
                child: SizedBox.square(
                  dimension: 34,
                  child: Icon(
                    liked ? Icons.favorite_rounded : Icons.favorite_border,
                    size: 18,
                    color: liked ? Slush.ink : look.fg,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Progreso liso. Escritorio: pista crema de 12 px con contorno, relleno
/// violeta y mando lima de 22 px; móvil: línea de 4 px sin mando. Solo pinta.
class _SmoothBarPainter extends CustomPainter {
  const _SmoothBarPainter({
    required this.progress,
    required this.thin,
    required this.filled,
    required this.empty,
    required this.knobFill,
    required this.knobStroke,
    this.grow = 0,
  });

  final double progress;
  final bool thin;
  final Color filled, empty, knobFill, knobStroke;

  /// 0 en reposo, 1 con el puntero encima: engorda la pista y el mando.
  final double grow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = progress.clamp(0.0, 1.0);
    if (thin) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, (h - _kBar) / 2, w, _kBar),
        const Radius.circular(_kBar / 2),
      );
      canvas.drawRRect(r, Paint()..color = empty);
      canvas
        ..save()
        ..clipRect(Rect.fromLTWH(0, 0, w * p, h))
        ..drawRRect(r, Paint()..color = filled)
        ..restore();
      return;
    }
    final trackH = lerpDouble(_kTrack, _kTrackHover, grow)!;
    final knob = lerpDouble(_kKnob, _kKnobHover, grow)!;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, (h - trackH) / 2, w, trackH),
      Radius.circular(trackH / 2),
    );
    final paint = Paint()..color = empty;
    canvas.drawRRect(track, paint);
    final cx = knob / 2 + p * (w - knob);
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, cx, h))
      ..drawRRect(track, paint..color = filled)
      ..restore();
    canvas.drawRRect(
      track.deflate(1),
      paint
        ..color = knobStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    paint.style = PaintingStyle.fill;
    final c = Offset(cx, h / 2);
    canvas.drawCircle(c, knob / 2, paint..color = knobFill);
    canvas.drawCircle(
      c,
      knob / 2 - 1,
      paint
        ..color = knobStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SmoothBarPainter old) =>
      old.progress != progress ||
      old.thin != thin ||
      old.grow != grow ||
      old.filled != filled ||
      old.empty != empty ||
      old.knobFill != knobFill ||
      old.knobStroke != knobStroke;
}
