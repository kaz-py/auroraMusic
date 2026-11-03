import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import '../artwork.dart';
import 'blurred_cover_backdrop.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Brasa: barra acoplada al borde inferior, sin flotar,
/// con esquinas de 6 px arriba. Una línea fina de brasa en el borde superior es
/// a la vez el progreso (se enciende de izquierda a derecha hasta la posición);
/// el artista va en versalitas con la pista debajo, la hora en monoespaciada y
/// el botón de reproducir es un cuadrado de borde ámbar que se rellena al sonar.
/// Con el fondo de portada difuminada, el artista pasa a mayúsculas grandes y
/// condensadas sobre la portada oscurecida.
const MiniPlayerTheme brasaMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool blurred,
  required bool wide,
}) => BrasaMiniPlayer(
  state: state,
  actions: actions,
  blurred: blurred,
  wide: wide,
);

const _hairline = 2.0;
const _hairlineZone = 12.0;
const _corner = 6.0;
const _error = Color(0xffff8a7a);
const _mono = TextStyle(
  fontFamily: 'monospace',
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Hora `m:ss` (`h:mm:ss` desde la hora).
@visibleForTesting
String brasaClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final tail = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$tail' : '$m:$tail';
}

class BrasaMiniPlayer extends StatefulWidget {
  const BrasaMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.blurred,
    required this.wide,
    @visibleForTesting this.covers,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool blurred, wide;

  /// Origen de portadas difuminadas; por defecto la caché compartida.
  final CoverBackdropSource? covers;

  @override
  State<BrasaMiniPlayer> createState() => _BrasaMiniPlayerState();
}

class _BrasaMiniPlayerState extends State<BrasaMiniPlayer> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.state, track = s.track;
    if (track == null) return const SizedBox.shrink();
    final reduce = MediaQuery.disableAnimationsOf(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final minHeight = (widget.wide ? 64.0 : 60.0) * textScale.clamp(1.0, 1.5);
    final ember = Brasa.accent;
    final blurred = widget.blurred;

    Widget content(BuildContext context) {
      final tone = BlurredCoverTheme.of(context);
      return Stack(
        children: [
          if (blurred) const Positioned.fill(child: _Vignette()),
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: _Row(
              state: s,
              actions: widget.actions,
              wide: widget.wide,
              blurred: blurred,
              tone: tone,
              textScale: textScale,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: _hairlineZone,
            child: _Scrub(
              progress: s.progress,
              canSeek: s.canSeek,
              hover: _hover,
              ember: ember,
              blurred: blurred,
              reduce: reduce,
              onSeek: widget.actions.seek,
            ),
          ),
        ],
      );
    }

    return Material(
      color: Brasa.obsidian,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(_corner)),
      ),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: blurred
            ? BlurredCoverBackdrop(
                track: track,
                source: widget.covers,
                matchTheme: true,
                child: Builder(builder: content),
              )
            : Builder(builder: content),
      ),
    );
  }
}

/// Bordes oscurecidos de la portada difuminada: solo restan luz, así que no
/// tocan el contraste del texto que garantiza el velo.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) => const IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0x80000000),
            Color(0x00000000),
            Color(0x00000000),
            Color(0x80000000),
          ],
          stops: [0, .14, .86, 1],
        ),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.state,
    required this.actions,
    required this.wide,
    required this.blurred,
    required this.tone,
    required this.textScale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide, blurred;
  final CoverTone tone;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    final ember = Brasa.accent;
    return LayoutBuilder(
      builder: (context, c) {
        final timeWidth = 80.0 * textScale + 8;
        // Ancho que se reserva al bloque de texto antes de sumar la hora.
        final fixed = wide ? 300.0 : 156.0;
        final showTime = c.maxWidth - fixed - timeWidth >= (wide ? 150 : 132);

        final info = _Info(
          state: state,
          blurred: blurred,
          tone: tone,
          cover: wide ? 48 : 40,
          ember: ember,
        );
        final heart = _Key(
          label: state.liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
          onTap: actions.toggleLike,
          backing: blurred,
          icon: Icon(
            state.liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            size: 19,
            color: state.liked ? ember : tone.secondary,
          ),
        );
        final play = _PlayKey(
          state: state,
          onTap: state.canTogglePlay ? actions.togglePlay : null,
          blurred: blurred,
          ember: ember,
        );
        final time = _Time(state: state, tone: tone);

        if (!wide) {
          return Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: Row(
              children: [
                Expanded(child: info),
                if (showTime) ...[const SizedBox(width: 8), time],
                heart,
                play,
              ],
            ),
          );
        }
        final divider = Container(
          width: 1,
          height: 32,
          color: Colors.white.withValues(alpha: blurred ? .22 : .10),
        );
        return Padding(
          padding: const EdgeInsets.only(left: 14, right: 8),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(child: info),
                    heart,
                    const SizedBox(width: 6),
                  ],
                ),
              ),
              divider,
              Expanded(
                flex: 2,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _Key(
                        label: 'Pista anterior',
                        onTap: state.hasPrevious ? actions.previous : null,
                        backing: blurred,
                        icon: Icon(
                          Icons.skip_previous_rounded,
                          size: 22,
                          color: tone.foreground,
                        ),
                      ),
                      const SizedBox(width: 4),
                      play,
                      const SizedBox(width: 4),
                      _Key(
                        label: 'Pista siguiente',
                        onTap: state.hasNext ? actions.next : null,
                        backing: blurred,
                        icon: Icon(
                          Icons.skip_next_rounded,
                          size: 22,
                          color: tone.foreground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (showTime) ...[
                divider,
                SizedBox(
                  width: timeWidth + 16,
                  child: Align(alignment: Alignment.centerRight, child: time),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Portada cuadrada, artista en versalitas y pista debajo.
class _Info extends StatelessWidget {
  const _Info({
    required this.state,
    required this.blurred,
    required this.tone,
    required this.cover,
    required this.ember,
  });

  final MiniPlayerState state;
  final bool blurred;
  final CoverTone tone;
  final double cover;
  final Color ember;

  @override
  Widget build(BuildContext context) {
    final track = state.track!;
    final artist = track.artist.trim().isEmpty ? '—' : track.artist;
    return Row(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: .14),
              width: 1,
            ),
          ),
          child: Artwork(
            track: track,
            size: cover,
            radius: 4,
            artworkContext: ArtworkContext.thumbnail,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: blurred ? FontWeight.w800 : FontWeight.w700,
                    fontSize: blurred ? 19 : 11.5,
                    height: blurred ? 1.02 : 1.25,
                    letterSpacing: blurred ? -.2 : 1.4,
                    color: blurred ? tone.foreground : ember,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: blurred ? 12 : 13,
                    height: 1.3,
                    color: blurred ? tone.secondary : tone.foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `1:23 / 3:45` en monoespaciada; con fallo del motor, `ERR`.
class _Time extends StatelessWidget {
  const _Time({required this.state, required this.tone});

  final MiniPlayerState state;
  final CoverTone tone;

  @override
  Widget build(BuildContext context) {
    final total = state.track!.duration;
    if (state.hasError) {
      return Text(
        'ERR',
        maxLines: 1,
        style: _mono.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _error,
        ),
      );
    }
    final elapsed = total * state.progress;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: brasaClock(elapsed),
            style: TextStyle(color: tone.foreground),
          ),
          TextSpan(
            text: ' / ${total > Duration.zero ? brasaClock(total) : '--:--'}',
            style: TextStyle(color: tone.secondary),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: _mono.copyWith(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        letterSpacing: .4,
      ),
    );
  }
}

/// Tecla de 44 px: la zona táctil es la de la tecla, el trazo visible un
/// cuadrado de [chip]. Sin movimiento reducido encoge al pulsar; con él solo
/// baja la opacidad.
class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.icon,
    this.chip = 36,
    this.fill,
    this.border,
    this.backing = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget icon;
  final double chip;
  final Color? fill, border;

  /// Fondo oscuro tras el glifo para que el ámbar resista sobre la portada.
  final bool backing;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onTap != null;
    final fill =
        widget.fill ??
        (widget.backing ? Colors.black.withValues(alpha: .55) : null);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: 44,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => setState(() => _down = true),
            onPointerUp: (_) => setState(() => _down = false),
            onPointerCancel: (_) => setState(() => _down = false),
            child: Opacity(
              opacity: enabled ? 1 : .4,
              child: AnimatedScale(
                scale: _down && !reduce ? .92 : 1,
                duration: const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _down && reduce ? .7 : 1,
                  duration: const Duration(milliseconds: 100),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: widget.onTap,
                      // La pulsación la sigue el Listener de fuera: responde al bajar el dedo.
                      customBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOut,
                          width: widget.chip,
                          height: widget.chip,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(4),
                            border: widget.border == null
                                ? null
                                : Border.all(color: widget.border!, width: 1.5),
                          ),
                          child: widget.icon,
                        ),
                      ),
                    ),
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

/// Reproducir/pausar: cuadrado de borde ámbar que se rellena al sonar; con
/// búfer, un anillo; con fallo, reintento en rojo.
class _PlayKey extends StatelessWidget {
  const _PlayKey({
    required this.state,
    required this.onTap,
    required this.blurred,
    required this.ember,
  });

  final MiniPlayerState state;
  final VoidCallback? onTap;
  final bool blurred;
  final Color ember;

  @override
  Widget build(BuildContext context) {
    final error = state.hasError;
    final accent = error ? _error : ember;
    final playing = state.isPlaying && !error;
    final label = error
        ? 'Error de reproducción, reintentar'
        : state.jamHostName != null
        ? 'Lo controla ${state.jamHostName}'
        : playing
        ? 'Pausar'
        : 'Reproducir';
    final Widget icon = state.buffering && !error
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: playing ? Brasa.void_ : accent,
            ),
          )
        : Icon(
            error
                ? Icons.replay_rounded
                : playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 24,
            color: playing ? Brasa.void_ : accent,
          );
    return _Key(
      label: label,
      onTap: onTap,
      chip: 40,
      fill: playing
          ? accent
          : blurred
          ? Colors.black.withValues(alpha: .55)
          : Colors.transparent,
      border: accent,
      icon: icon,
    );
  }
}

/// Franja superior de 12 px con la línea de brasa. Con [canSeek] es arrastrable
/// (tocar o arrastrar mueve la marca; la posición se confirma al soltar) y gana
/// al deslizar de pista de la barra dentro de la franja. Sin permiso (Jam sin ser
/// anfitrión) solo se ve. Con el cursor encima o arrastrando, la marca de la
/// cabeza crece a un cuadrado.
class _Scrub extends StatefulWidget {
  const _Scrub({
    required this.progress,
    required this.canSeek,
    required this.hover,
    required this.ember,
    required this.blurred,
    required this.reduce,
    required this.onSeek,
  });

  final double progress;
  final bool canSeek, hover, blurred, reduce;
  final Color ember;
  final ValueChanged<double> onSeek;

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
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(
            end: widget.canSeek && (widget.hover || _drag != null) ? 1 : 0,
          ),
          duration: widget.reduce
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (_, knob, _) => CustomPaint(
            painter: _HairlinePainter(
              progress: value,
              ember: widget.ember,
              knob: knob,
              blurred: widget.blurred,
            ),
          ),
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
      child: widget.canSeek
          ? GestureDetector(
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
            )
          : IgnorePointer(child: line),
    );
  }
}

/// Línea de brasa del borde superior: pista tenue, tramo encendido en
/// degradado hasta la posición, resplandor y marca en la cabeza.
class _HairlinePainter extends CustomPainter {
  const _HairlinePainter({
    required this.progress,
    required this.ember,
    required this.knob,
    required this.blurred,
  });

  final double progress, knob;
  final Color ember;
  final bool blurred;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final track = Rect.fromLTWH(0, 0, w, _hairline);
    if (blurred) {
      // Fondo oscuro bajo la línea: el ámbar mantiene ≥ 3 sobre cualquier portada.
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, _hairline + 1),
        Paint()..color = Colors.black.withValues(alpha: .6),
      );
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, 10),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ember.withValues(alpha: .22), ember.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, w, 10)),
      );
    }
    canvas.drawRect(track, Paint()..color = ember.withValues(alpha: .24));
    final x = (w * progress.clamp(0.0, 1.0)).toDouble();
    if (x > 0) {
      final lit = Rect.fromLTWH(0, 0, x, _hairline);
      canvas
        ..drawRect(
          Rect.fromLTRB(math.max(0, x - 36), 0, x, _hairline),
          Paint()
            ..color = ember.withValues(alpha: .6)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        )
        ..drawRect(
          lit,
          Paint()
            ..shader = LinearGradient(
              colors: [ember.withValues(alpha: .4), ember],
            ).createShader(lit),
        )
        ..drawRect(Rect.fromLTWH(x - 1, 0, 2, 5), Paint()..color = Brasa.cream);
    }
    if (knob > 0) {
      final side = 10 * knob;
      final cx = x.clamp(side / 2, math.max(side / 2, w - side / 2)).toDouble();
      final box = Rect.fromLTWH(cx - side / 2, 0, side, side).deflate(1);
      canvas
        ..drawRect(box, Paint()..color = Brasa.cream)
        ..drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = ember,
        );
    }
  }

  @override
  bool shouldRepaint(_HairlinePainter old) =>
      old.progress != progress ||
      old.knob != knob ||
      old.ember != ember ||
      old.blurred != blurred;
}
