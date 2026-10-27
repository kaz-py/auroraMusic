import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import 'slush_decor.dart';

const _ink = Slush.ink;
const _display = 'Bagel Fat One';

/// «2 h 04» / «45 min» a partir de la suma de duraciones; null si no hay datos.
String? slushTotalTime(Iterable<Track> tracks) {
  final min = tracks.fold<Duration>(Duration.zero, (a, t) => a + t.duration);
  if (min == Duration.zero) return null;
  final m = min.inMinutes;
  return m >= 60
      ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}'
      : '$m min';
}

/// Inicio de Slush: «PARA TI.» enorme sobre la onda, pegatinas, tarjeta lila
/// «Mix del día» y botones en píldora. Todo se dibuja, sin imágenes.
class SlushHome extends StatelessWidget {
  const SlushHome({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final AppController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final mix = c.recommendations.map((r) => r.track).toList();
    final pool = mix.isNotEmpty
        ? mix
        : c.tracks.where((t) => !t.isPendingSpotifyMatch).toList();
    void playAll() =>
        pool.isEmpty ? onSearch() : c.playTrack(pool.first, context: pool);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final wide = w >= 760;
        final h = wide
            ? (MediaQuery.sizeOf(context).height * .62).clamp(420.0, 640.0)
            : 430.0;
        final font = wide
            ? (h * .5).clamp(120.0, 240.0)
            : (w * .34).clamp(90.0, 150.0);
        final time = slushTotalTime(pool);
        final cardW = (w * .21).clamp(200.0, 300.0);
        final covers = [
          for (final t in [...c.recentTracks, ...pool]) t,
        ];
        return SizedBox(
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: -24,
                right: -24,
                child: IgnorePointer(
                  child: CustomPaint(painter: _RibbonPainter(wide ? .14 : .1)),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: Semantics(
                  header: true,
                  label: 'Para ti',
                  child: ExcludeSemantics(
                    child: Text(
                      'PARA\nTI.',
                      style: TextStyle(
                        fontFamily: _display,
                        fontSize: font,
                        height: .8,
                        letterSpacing: -font * .02,
                        color: _ink,
                        shadows: [
                          for (final o in const [
                            Offset(2, 0),
                            Offset(-2, 0),
                            Offset(0, 2),
                            Offset(0, -2),
                          ])
                            Shadow(color: _ink, offset: o),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: wide ? w * .38 : w * .52,
                top: h * .02,
                child: const SlushSticker('NUEVO', size: 92, angle: -.25),
              ),
              Positioned(
                left: wide ? w * .2 : w * .3,
                top: h * (wide ? .56 : .46),
                child: Transform.rotate(
                  angle: -.12,
                  child: const SizedBox(
                    width: 56,
                    height: 52,
                    child: CustomPaint(painter: _HeartPainter()),
                  ),
                ),
              ),
              if (wide) ...[
                for (final (i, dx, dy, ang, color) in [
                  (1, .06, .1, -.12, Slush.yellow),
                  (2, .03, .2, .2, Slush.mint),
                ])
                  Positioned(
                    right: w * dx,
                    top: h * dy,
                    child: Transform.rotate(
                      angle: ang,
                      child: _StackCard(
                        width: cardW * .92,
                        color: color,
                        track: covers.length > i ? covers[i] : null,
                      ),
                    ),
                  ),
                Positioned(
                  right: w * .08,
                  top: h * .02,
                  child: Transform.rotate(
                    angle: .1,
                    child: _MixCard(
                      width: cardW,
                      count: pool.length,
                      time: time,
                      cover: covers.firstOrNull,
                      onPlay: pool.isEmpty ? null : playAll,
                    ),
                  ),
                ),
                Positioned(
                  right: -w * .01,
                  top: h * .2,
                  child: Transform.rotate(
                    angle: .5,
                    child: const SizedBox(
                      width: 52,
                      height: 60,
                      child: CustomPaint(painter: _ArrowPainter()),
                    ),
                  ),
                ),
                Positioned(
                  left: w * .5,
                  top: h * .04,
                  child: const SlushDecor(SlushShape.bolt, size: 46),
                ),
                Positioned(
                  left: w * .34,
                  top: h * .6,
                  child: const SlushDecor(
                    SlushShape.star,
                    size: 30,
                    color: Slush.mint,
                    angle: .3,
                  ),
                ),
                Positioned(
                  left: w * .56,
                  top: h * .58,
                  child: const SlushDecor(SlushShape.dots, size: 44),
                ),
                Positioned(
                  right: w * .34,
                  top: h * .08,
                  child: const SlushDecor(
                    SlushShape.star,
                    size: 24,
                    color: Slush.lilac,
                  ),
                ),
                Positioned(
                  left: w * .44,
                  top: h * .8,
                  child: Transform.rotate(angle: -.14, child: const _DjTag()),
                ),
                Positioned(
                  right: w * .01,
                  top: h * .84,
                  child: const _NoteDisc(),
                ),
              ],
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Una mezcla de tus favoritos, listas y escuchas recientes.',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _PillButton(
                          'REPRODUCIR TODO',
                          Icons.play_arrow_rounded,
                          playAll,
                          dark: true,
                        ),
                        _PillButton(
                          'ABRIR DJ AUROR',
                          Icons.auto_awesome,
                          () => c.startDjSession(),
                        ),
                        _PillButton(
                          'ACTUALIZAR',
                          Icons.refresh,
                          c.refreshRecommendations,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton(this.label, this.icon, this.onTap, {this.dark = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool dark;

  @override
  Widget build(BuildContext context) => Material(
    color: dark ? _ink : Colors.white,
    shape: const StadiumBorder(side: BorderSide(color: _ink, width: 2)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: dark ? Colors.white : _ink),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
                color: dark ? Colors.white : _ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MixCard extends StatelessWidget {
  const _MixCard({
    required this.width,
    required this.count,
    required this.time,
    required this.onPlay,
    this.cover,
  });
  final Track? cover;
  final double width;
  final int count;
  final String? time;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Slush.lilac,
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: _ink, width: 2.5),
      boxShadow: Slush.hardShadow,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 1.08,
          child: ExcludeSemantics(
            child: cover == null
                ? CustomPaint(painter: const _CoverPainter())
                : LayoutBuilder(
                    builder: (_, b) => ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Artwork(
                        track: cover!,
                        size: b.maxWidth,
                        radius: 0,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MIX DEL DÍA',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    time == null
                        ? '$count canciones'
                        : '$count canciones · $time',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: 'Reproducir mix',
              child: Material(
                color: _ink,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPlay,
                  child: const SizedBox.square(
                    dimension: 40,
                    child: Icon(Icons.play_arrow_rounded, color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StackCard extends StatelessWidget {
  const _StackCard({required this.width, required this.color, this.track});
  final double width;
  final Color color;
  final Track? track;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: width * 1.05,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: _ink, width: 2.5),
      boxShadow: Slush.hardShadow,
    ),
    child: track == null
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Artwork(track: track!, size: width - 20, radius: 0),
          ),
  );
}

class _DjTag extends StatelessWidget {
  const _DjTag();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: ShapeDecoration(
      color: Colors.white,
      shape: const StadiumBorder(side: BorderSide(color: _ink, width: 2)),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: ShapeDecoration(
        color: Slush.lilac,
        shape: const StadiumBorder(side: BorderSide(color: _ink, width: 2)),
      ),
      child: const Text(
        'DJ AUROR',
        style: TextStyle(fontFamily: _display, fontSize: 16, color: _ink),
      ),
    ),
  );
}

class _NoteDisc extends StatelessWidget {
  const _NoteDisc();

  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: Slush.yellow,
      shape: BoxShape.circle,
      border: Border.all(color: _ink, width: 2.5),
      boxShadow: Slush.hardShadow,
    ),
    child: const Icon(Icons.music_note_rounded, color: _ink, size: 26),
  );
}

Paint _fill(Color c) => Paint()..color = c;
Paint _line(double w) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = _ink;

/// Cinta azul con bordes negros y líneas blancas, de lado a lado.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.thickness);
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(-w * .02, h * .5)
      ..cubicTo(w * .18, h * .78, w * .32, h * .2, w * .52, h * .38)
      ..cubicTo(w * .7, h * .55, w * .82, h * .8, w * 1.04, h * .46);
    final t = h * thickness;
    Paint stroke(double width, Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = c;
    canvas.drawPath(path, stroke(t + 8, _ink));
    canvas.drawPath(path, stroke(t, Slush.blue));
    canvas.drawPath(path, stroke(t * .55, Colors.white));
    canvas.drawPath(path, stroke(t * .3, Slush.blue));
  }

  @override
  bool shouldRepaint(_RibbonPainter old) => old.thickness != thickness;
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(w / 2, h * .95)
      ..cubicTo(-w * .2, h * .5, w * .1, -h * .1, w / 2, h * .3)
      ..cubicTo(w * .9, -h * .1, w * 1.2, h * .5, w / 2, h * .95)
      ..close();
    canvas.drawPath(p, _fill(Slush.orange));
    canvas.drawPath(p, _line(3));
    canvas.drawArc(
      Rect.fromLTWH(w * .16, h * .2, w * .2, h * .2),
      math.pi,
      math.pi * .6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => false;
}

class _ArrowPainter extends CustomPainter {
  const _ArrowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(w * .1, 0)
      ..lineTo(w, h * .55)
      ..lineTo(w * .55, h * .62)
      ..lineTo(w * .4, h)
      ..close();
    canvas.drawPath(p, _fill(Slush.violet));
    canvas.drawPath(p, _line(3));
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => false;
}

/// Portada geométrica del mix: ojo concéntrico y sol amarillo.
class _CoverPainter extends CustomPainter {
  const _CoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(18),
    );
    canvas.drawRRect(r, _fill(Slush.blue));
    canvas.save();
    canvas.clipRRect(r);
    final s = size.shortestSide;
    final c = Offset(size.width * .55, size.height * .58);
    for (final (rad, color, ring) in [
      (.36, Colors.white, true),
      (.27, Slush.blue, true),
      (.2, Colors.white, true),
      (.1, _ink, false),
    ]) {
      canvas.drawCircle(c, s * rad, _fill(color));
      if (ring) canvas.drawCircle(c, s * rad, _line(3));
    }
    final sun = Offset(size.width * .2, size.height * .2);
    canvas.drawCircle(sun, s * .09, _fill(Slush.yellow));
    canvas.drawCircle(sun, s * .09, _line(3));
    canvas.restore();
    canvas.drawRRect(r, _line(3));
  }

  @override
  bool shouldRepaint(_CoverPainter old) => false;
}
