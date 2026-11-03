import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/accent_transition.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import 'blurred_cover_backdrop.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Slush: «pegatina» de contorno grueso y sombra dura.
///
/// - Claro: losa de color vivo elegida por el acento de la portada (menta,
///   amarillo, lila o naranja), tinta encima, play negro.
/// - Oscuro: losa `raised` con contorno crema; el color vivo queda en el play y
///   en el progreso.
/// - Progreso: barra de segmentos de 5 px con mando cuadrado.
/// - Fondo difuminado: el artista pasa a Bagel Fat One en mayúsculas.
const MiniPlayerTheme slushMiniPlayerV2 = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool blurred,
  required bool wide,
}) => SlushMiniPlayer(
  state: state,
  actions: actions,
  blurred: blurred,
  wide: wide,
);

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

/// Ancho máximo del dock en pantallas con carril.
const double kSlushMiniMaxWidth = 720;

/// Ancho interior (sin contorno ni relleno) desde el que el móvil añade
/// «siguiente»; por debajo basta con deslizar.
const double _kNextMinInner = 330;

const double _kBar = 5, _kKnob = 10;

/// Colores ya resueltos de una de las dos caras (normal / sobre portada).
class _Look {
  const _Look({
    required this.fill,
    required this.stroke,
    required this.fg,
    required this.sub,
    required this.playFill,
    required this.playIcon,
    required this.barFilled,
    required this.barEmpty,
    required this.knobFill,
    required this.knobStroke,
    required this.heartFill,
    required this.onCover,
  });

  final Color fill, stroke, fg, sub;
  final Color playFill, playIcon;
  final Color barFilled, barEmpty, knobFill, knobStroke;
  final Color? heartFill;
  final bool onCover;

  factory _Look.of(BuildContext context, Color vivid, CoverTone? tone) {
    final p = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (tone != null) {
      return _Look(
        fill: dark ? p.raised : vivid,
        stroke: tone.foreground,
        fg: tone.foreground,
        sub: tone.secondary,
        playFill: vivid,
        playIcon: Slush.ink,
        barFilled: tone.foreground,
        barEmpty: tone.foreground.withAlpha(90),
        knobFill: vivid,
        knobStroke: tone.foreground,
        heartFill: null,
        onCover: true,
      );
    }
    final fill = dark ? p.raised : vivid;
    final fg = dark ? p.ink : slushOnColor(context, vivid);
    return _Look(
      fill: fill,
      stroke: p.line,
      fg: fg,
      // Sobre color vivo no hay gris: el artista va en tinta, más ligero.
      sub: dark ? p.ink2 : fg,
      playFill: dark ? vivid : Slush.ink,
      playIcon: dark ? Slush.ink : p.paper,
      barFilled: dark ? vivid : Slush.ink,
      barEmpty: Color.alphaBlend(
        (dark ? p.line : Slush.ink).withAlpha(dark ? 80 : 72),
        fill,
      ),
      knobFill: dark ? p.ink : p.paper,
      knobStroke: Slush.ink,
      heartFill: dark ? null : p.paper,
      onCover: false,
    );
  }
}

class SlushMiniPlayer extends StatefulWidget {
  const SlushMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.blurred,
    required this.wide,
    @visibleForTesting this.coverSource,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool blurred, wide;

  /// Origen de la portada difuminada (por defecto la caché de la app).
  final CoverBackdropSource? coverSource;

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
    final vivid = slushVividFor(AccentScope.of(context, Slush.mint));
    final radius = BorderRadius.circular(wide ? 32 : 28);

    Widget body(CoverTone? tone) => _Body(
      state: widget.state,
      actions: widget.actions,
      wide: wide,
      look: _Look.of(context, vivid, tone),
      vivid: vivid,
    );

    Widget content = widget.blurred
        ? BlurredCoverBackdrop(
            track: track,
            radius: radius,
            source: widget.coverSource,
            child: Builder(
              builder: (context) => body(
                BlurredCoverTheme.isActive(context)
                    ? BlurredCoverTheme.of(context)
                    : null,
              ),
            ),
          )
        : body(null);

    final base = _Look.of(context, vivid, null);
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

    if (wide) {
      pill = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kSlushMiniMaxWidth),
        child: pill,
      );
    }
    final margin = wide
        ? SlushSpacing.margin(MediaQuery.sizeOf(context).width)
        : 0.0;
    pill = Padding(
      padding: EdgeInsets.fromLTRB(
        margin,
        0,
        margin,
        wide ? SlushSpacing.s16 : SlushSpacing.s12,
      ),
      child: pill,
    );
    // Con carril el dock se encoge a su pastilla: los gestos no cubren franjas
    // vacías a los lados.
    if (wide) pill = Center(widthFactor: 1, child: pill);

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
    required this.vivid,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide;
  final _Look look;
  final Color vivid;

  @override
  Widget build(BuildContext context) {
    final track = state.track!;
    final reduce = SlushMotion.reduce(context);
    final cover = wide ? 52.0 : 44.0;
    final pad = wide ? 12.0 : 10.0;

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
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  swap(_Cover(track: track, size: cover, stroke: look.stroke)),
                  SizedBox(width: wide ? 14 : 10),
                  Expanded(
                    child: swap(
                      _Titles(
                        track: track,
                        look: look,
                        wide: wide,
                        error: state.hasError,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (wide)
                    _IconAction(
                      tooltip: 'Anterior',
                      icon: Icons.skip_previous_rounded,
                      color: look.fg,
                      onTap: state.hasPrevious ? actions.previous : null,
                    ),
                  _PlayButton(
                    state: state,
                    look: look,
                    size: wide ? 52 : 44,
                    onTap: state.canTogglePlay ? actions.togglePlay : null,
                  ),
                  if (next)
                    _IconAction(
                      tooltip: 'Siguiente',
                      icon: Icons.skip_next_rounded,
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
              SizedBox(height: wide ? 8 : 6),
              Semantics(
                label: 'Progreso',
                value: '${(state.progress * 100).round()} %',
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: const Size.fromHeight(_kKnob),
                    painter: _SegmentBarPainter(
                      progress: state.progress,
                      filled: look.barFilled,
                      empty: look.barEmpty,
                      knobFill: look.knobFill,
                      knobStroke: look.knobStroke,
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

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.size, required this.stroke});

  final Track track;
  final double size;
  final Color stroke;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(SlushRadius.r12),
      border: Border.all(color: stroke, width: SlushStroke.base),
    ),
    child: Artwork(
      track: track,
      size: size - 2 * SlushStroke.base,
      radius: SlushRadius.r12 - SlushStroke.base,
    ),
  );
}

class _Titles extends StatelessWidget {
  const _Titles({
    required this.track,
    required this.look,
    required this.wide,
    required this.error,
  });

  final Track track;
  final _Look look;
  final bool wide, error;

  @override
  Widget build(BuildContext context) {
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
      track.artist,
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
            'No se pudo reproducir',
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

    if (look.onCover) {
      // Artista como protagonista: Bagel Fat One en mayúsculas.
      final size = wide ? 26.0 : 20.0;
      final scaler = MediaQuery.textScalerOf(
        context,
      ).clamp(maxScaleFactor: 1.5);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            track.artist.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textScaler: scaler,
            style: TextStyle(
              fontFamily: 'Bagel Fat One',
              fontSize: size,
              height: 1.1,
              letterSpacing: -size * .01,
              color: look.fg,
            ),
          ),
          error
              ? problem
              : Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: subSize,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: look.sub,
                  ),
                ),
        ],
      );
    }
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
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

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
          child: Icon(icon, size: 28, color: color),
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

/// Progreso en segmentos de 5 px con mando cuadrado. Solo pinta: sin
/// animación propia; se repinta cuando cambia la posición.
class _SegmentBarPainter extends CustomPainter {
  const _SegmentBarPainter({
    required this.progress,
    required this.filled,
    required this.empty,
    required this.knobFill,
    required this.knobStroke,
  });

  final double progress;
  final Color filled, empty, knobFill, knobStroke;

  static const _segment = 10.0, _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final n = math.max(1, ((w + _gap) / (_segment + _gap)).floor());
    final sw = (w - _gap * (n - 1)) / n;
    final top = (h - _kBar) / 2;
    final p = progress.clamp(0.0, 1.0);
    final knobX = p * (w - _kKnob);
    final split = p >= 1 ? w : knobX + _kKnob / 2;
    const radius = Radius.circular(1.5);
    RRect seg(int i) => RRect.fromLTRBR(
      i * (sw + _gap),
      top,
      i * (sw + _gap) + sw,
      top + _kBar,
      radius,
    );

    final paint = Paint()..color = empty;
    for (var i = 0; i < n; i++) {
      canvas.drawRRect(seg(i), paint);
    }
    canvas
      ..save()
      ..clipRect(Rect.fromLTWH(0, 0, split, h));
    paint.color = filled;
    for (var i = 0; i < n; i++) {
      canvas.drawRRect(seg(i), paint);
    }
    canvas.restore();

    final knob = RRect.fromRectAndRadius(
      Rect.fromLTWH(knobX, (h - _kKnob) / 2, _kKnob, _kKnob),
      const Radius.circular(2),
    );
    canvas.drawRRect(knob, paint..color = knobFill);
    canvas.drawRRect(
      knob.deflate(1),
      paint
        ..color = knobStroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_SegmentBarPainter old) =>
      old.progress != progress ||
      old.filled != filled ||
      old.empty != empty ||
      old.knobFill != knobFill ||
      old.knobStroke != knobStroke;
}
