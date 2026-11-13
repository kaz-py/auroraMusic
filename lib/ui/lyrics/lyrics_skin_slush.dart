import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../mini_player/blurred_cover_backdrop.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import 'lyrics_skin.dart';

/// Piel del modo letra del tema Slush: portada difuminada con velo violeta y
/// retícula de puntos, texto blanco, botones de papel con borde de tinta y
/// Play lima. La composición es la de siempre (ver [LyricsSkin]).
final LyricsSkin slushLyricsSkin = LyricsSkin(
  backdrop: _backdrop,
  exitButton: _exit,
  iconButtonStyle: _iconStyle,
  cover: _cover,
  title: (context, tone) => slushHeadline(30, color: Colors.white),
  subtitle: (context, tone) => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: _lilacWhite,
  ),
  progress: _progress,
  lineStyle: _lineStyle,
  lineBuilder: _line,
  playButton: _play,
  controlIconColor: (tone, {required active}) => Slush.ink,
);

const _paper = Color(0xfffff8ec);
const _lilacWhite = Color(0xffeee6ff);
const _white = CoverTone(
  foreground: Colors.white,
  secondary: _lilacWhite,
  scrim: Slush.violetDeep,
);

/// Las mismas dimensiones que usa la página para pasar a composición compacta.
bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

Widget _backdrop(BuildContext context, Track? track, Widget child) =>
    BlurredCoverBackdrop(
      track: track,
      child: BlurredCoverTheme(
        tone: _white,
        active: true,
        // El velo envuelve al contenido (no es hermano) para que el texto lo
        // tenga como fondo resuelto.
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xe65b3fe0), Color(0xeb2b1a86), Color(0xf50a0a0a)],
              stops: [0, .55, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(child: CustomPaint(painter: _Dots())),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );

/// Retícula de puntos al 13 %: se pinta una vez (sin estado ni animación).
class _Dots extends CustomPainter {
  const _Dots();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .13);
    const step = 22.0;
    for (var y = step / 2; y < size.height; y += step) {
      for (var x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_Dots old) => false;
}

Widget _exit(BuildContext context, LyricsExitArgs a) => SlushPressable(
  onTap: a.onPressed,
  minSize: 44,
  child: DecoratedBox(
    decoration: BoxDecoration(
      color: Slush.lime,
      borderRadius: BorderRadius.circular(SlushRadius.pill),
      border: Border.all(color: Slush.ink, width: 2),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: a.compact ? 14 : 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 20, color: Slush.ink),
            const SizedBox(width: 8),
            Text(
              a.compact ? 'Salir' : 'Salir del modo letra',
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Slush.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

ButtonStyle _iconStyle(CoverTone tone) => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size.square(44)),
  minimumSize: const WidgetStatePropertyAll(Size.square(44)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: const WidgetStatePropertyAll(CircleBorder()),
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.selected) ? Slush.lilac : _paper,
  ),
  foregroundColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.disabled)
        ? Slush.ink.withValues(alpha: .38)
        : Slush.ink,
  ),
  iconColor: WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.disabled)
        ? Slush.ink.withValues(alpha: .38)
        : Slush.ink,
  ),
  side: const WidgetStatePropertyAll(BorderSide(color: Slush.ink, width: 2)),
);

Widget _cover(BuildContext context, Widget artwork, double size) =>
    Transform.rotate(
      angle: -2 * 3.1415926535 / 180,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Slush.ink, width: 2),
          boxShadow: const [BoxShadow(color: Slush.ink, offset: Offset(4, 6))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: artwork,
        ),
      ),
    );

TextStyle _lineStyle(
  BuildContext context,
  CoverTone tone, {
  required bool active,
  required double size,
}) {
  final compact = _compact(context);
  final px = active ? (compact ? 34.0 : 56.0) : (compact ? 27.0 : 40.0);
  return slushHeadline(
    px,
    height: 1.1,
    color: active ? Colors.white : Colors.white.withValues(alpha: .4),
  );
}

Widget _line(BuildContext context, LyricsLineArgs a) {
  final text = AnimatedDefaultTextStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    style: a.style,
    child: Text(a.text),
  );
  if (!a.active) return text;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      text,
      const SizedBox(height: 6),
      DecoratedBox(
        decoration: BoxDecoration(
          color: Slush.lime,
          borderRadius: BorderRadius.circular(3),
        ),
        child: const SizedBox(width: 72, height: 5),
      ),
    ],
  );
}

Widget _play(BuildContext context, LyricsPlayArgs a) {
  final compact = _compact(context);
  final size = compact ? 64.0 : 76.0;
  final enabled = a.onPressed != null;
  return Tooltip(
    message: a.tooltip,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: a.tooltip,
      excludeSemantics: true,
      child: SlushPressable(
        key: const ValueKey('slush-lyrics-play'),
        onTap: a.onPressed,
        radius: compact ? 30 : size / 2,
        elevation: SlushElevation.card,
        minSize: size,
        child: Opacity(
          opacity: enabled ? 1 : .5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Slush.lime,
              borderRadius: BorderRadius.circular(compact ? 30 : size / 2),
              border: Border.all(color: Slush.ink, width: 2),
            ),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: a.buffering
                    ? const SizedBox.square(
                        dimension: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Slush.ink,
                        ),
                      )
                    : Icon(
                        a.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 40,
                        color: Slush.ink,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _progress(BuildContext context, LyricsProgressArgs a) {
  final times = const TextStyle(
    fontFamily: 'Inter',
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  return SizedBox(
    height: 44,
    child: Row(
      children: [
        Text(miniClock(a.position), style: times),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 12,
              trackShape: _SeekTrack(),
              thumbShape: const _SeekThumb(),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              overlayColor: Colors.white24,
            ),
            child: Slider(
              semanticFormatterCallback: (_) =>
                  'Posición ${miniClock(a.position)}',
              value: a.value.clamp(0.0, 1.0),
              onChanged: a.onChanged,
              onChangeEnd: a.onChangeEnd,
            ),
          ),
        ),
        Text(
          a.duration > Duration.zero ? miniClock(a.duration) : '--:--',
          style: times,
        ),
      ],
    ),
  );
}

/// Pista crema con borde de tinta y relleno violeta hasta el pulgar.
class _SeekTrack extends SliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final h = sliderTheme.trackHeight ?? 12;
    return Rect.fromLTWH(
      offset.dx + 11,
      offset.dy + (parentBox.size.height - h) / 2,
      parentBox.size.width - 22,
      h,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final canvas = context.canvas;
    final r = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    canvas.drawRRect(r, Paint()..color = _paper);
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(
      Rect.fromLTRB(rect.left, rect.top, thumbCenter.dx, rect.bottom),
      Paint()..color = Slush.violet,
    );
    canvas.restore();
    canvas.drawRRect(
      r.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Slush.ink,
    );
  }
}

/// Pulgar lima de 22 px con borde de tinta.
class _SeekThumb extends SliderComponentShape {
  const _SeekThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.square(22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 11, Paint()..color = Slush.lime);
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Slush.ink,
    );
  }
}
