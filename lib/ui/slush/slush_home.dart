import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';

const _display = 'Bagel Fat One';

/// Blanco cálido decorativo de los dibujos (no es texto).
const _cream = Color(0xfffffdf8);

/// «2 h 04» / «45 min» a partir de la suma de duraciones; null si no hay datos.
String? slushTotalTime(Iterable<Track> tracks) {
  final min = tracks.fold<Duration>(Duration.zero, (a, t) => a + t.duration);
  if (min == Duration.zero) return null;
  final m = min.inMinutes;
  return m >= 60
      ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}'
      : '$m min';
}

/// Inicio de Slush: «PARA TI.» enorme sobre la cinta, una pegatina, tarjeta
/// lila «Mix del día» (la tarjeta héroe) y botones en píldora. Todo se
/// dibuja, sin imágenes. Con texto grande (>= 1,3×) o menos de 340 px el
/// layout pasa a columna lineal: titular, mix, texto y botones.
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
        // Ancho de contenido (sin la barra lateral): 760 equivale a ~840 de
        // pantalla con el riel.
        final wide = w >= 760;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final linear = scale > 1.3 || w < 340;
        final time = slushTotalTime(pool);
        final cardW = (w * .21).clamp(200.0, 300.0);
        final covers = [
          for (final t in [...c.recentTracks, ...pool]) t,
        ];
        final texts = _Cta(
          onPlay: playAll,
          onDj: () => c.startDjSession(),
          onRefresh: c.refreshRecommendations,
        );
        if (linear) {
          final font = (w * .34).clamp(72.0, 150.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Headline(font: font),
              const SizedBox(height: SlushSpacing.s16),
              Align(
                alignment: Alignment.centerLeft,
                child: _MixCard(
                  width: math.min(w - 4, 300),
                  count: pool.length,
                  time: time,
                  cover: covers.firstOrNull,
                  onPlay: pool.isEmpty ? null : playAll,
                ),
              ),
              const SizedBox(height: SlushSpacing.s24),
              texts,
            ],
          );
        }
        final h = wide
            ? (MediaQuery.sizeOf(context).height * .62).clamp(420.0, 640.0)
            : 430.0 + (scale - 1) * 160;
        final font = wide
            ? (h * .5).clamp(120.0, 240.0)
            : (w * .34).clamp(90.0, 150.0);
        return SizedBox(
          height: h,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                left: -SlushSpacing.s24,
                right: -SlushSpacing.s24,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _RibbonPainter(
                      wide ? .14 : .1,
                      context.slush.line,
                    ),
                  ),
                ),
              ),
              Positioned(left: 0, top: 0, child: _Headline(font: font)),
              // Una pegatina por debajo de 700 px; con la cinta y el corazón
              // no pasan de dos en pantallas anchas.
              Positioned(
                left: wide ? w * .38 : w * .52,
                top: h * .02,
                child: const SlushSticker('NUEVO', size: 92, angle: -.25),
              ),
              if (wide) ...[
                Positioned(
                  left: w * .2,
                  top: h * .56,
                  child: Transform.rotate(
                    angle: -.12,
                    child: SizedBox(
                      width: 56,
                      height: 52,
                      child: CustomPaint(
                        painter: _HeartPainter(context.slush.line),
                      ),
                    ),
                  ),
                ),
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
              ],
              Positioned(left: 0, right: 0, bottom: 0, child: texts),
            ],
          ),
        );
      },
    );
  }
}

/// «PARA TI.» enorme; el escalado de texto se limita a 1,3×.
class _Headline extends StatelessWidget {
  const _Headline({required this.font});
  final double font;

  @override
  Widget build(BuildContext context) {
    final ink = context.slush.ink;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
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
              color: ink,
              shadows: [
                for (final o in const [
                  Offset(1.5, 0),
                  Offset(-1.5, 0),
                  Offset(0, 1.5),
                  Offset(0, -1.5),
                ])
                  Shadow(color: ink, offset: o),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frase y botones de la parte baja del Inicio.
class _Cta extends StatelessWidget {
  const _Cta({
    required this.onPlay,
    required this.onDj,
    required this.onRefresh,
  });
  final VoidCallback onPlay;
  final VoidCallback onDj;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'Una mezcla de tus favoritos, listas y escuchas recientes.',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          height: 1.4,
          color: context.slush.ink,
        ),
      ),
      const SizedBox(height: SlushSpacing.s12),
      // El hueco extra abajo/derecha deja sitio a la sombra de los botones.
      Padding(
        padding: const EdgeInsets.only(right: 3, bottom: 4),
        child: Wrap(
          spacing: SlushSpacing.s12,
          runSpacing: SlushSpacing.s12,
          children: [
            _PillButton(
              'REPRODUCIR TODO',
              Icons.play_arrow_rounded,
              onPlay,
              primary: true,
            ),
            _PillButton('ABRIR DJ AUROR', Icons.auto_awesome, onDj),
            _PillButton('ACTUALIZAR', Icons.refresh, onRefresh),
          ],
        ),
      ),
    ],
  );
}

/// Botón en píldora de 48 de alto. El primario es menta (una acción
/// principal por vista); los demás, papel.
class _PillButton extends StatelessWidget {
  const _PillButton(this.label, this.icon, this.onTap, {this.primary = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final fill = primary ? Slush.mint : p.paper;
    final fg = primary ? Slush.ink : p.ink;
    return SlushPressable(
      onTap: onTap,
      minSize: SlushControl.bar,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: fill,
          shape: StadiumBorder(side: p.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: SlushControl.bar),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .3,
                      color: fg,
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
}

/// Tarjeta héroe: la única con sombra de color (menta) en oscuro.
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
  Widget build(BuildContext context) {
    final p = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.all(SlushSpacing.s12),
      decoration: BoxDecoration(
        color: Slush.lilac,
        borderRadius: BorderRadius.circular(SlushRadius.r32),
        border: Border.fromBorderSide(p.border),
        boxShadow: dark
            ? const [BoxShadow(color: Slush.mint, offset: Offset(3, 4))]
            : p.shadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.08,
            child: ExcludeSemantics(
              child: cover == null
                  ? const CustomPaint(painter: _CoverPainter())
                  : LayoutBuilder(
                      builder: (_, b) => ClipRRect(
                        // Concéntrico: 32 - 12 de padding.
                        borderRadius: BorderRadius.circular(20),
                        child: Artwork(
                          track: cover!,
                          size: b.maxWidth,
                          radius: 0,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: SlushSpacing.s12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MIX DEL DÍA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        letterSpacing: .3,
                        fontWeight: FontWeight.w800,
                        color: Slush.ink,
                      ),
                    ),
                    Text(
                      time == null
                          ? '$count canciones'
                          : '$count canciones · $time',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: Slush.ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: SlushSpacing.s8),
              Tooltip(
                message: 'Reproducir mix',
                child: SlushPressable(
                  onTap: onPlay,
                  radius: SlushRadius.pill,
                  elevation: SlushElevation.none,
                  semanticLabel: 'Reproducir mix',
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      color: Slush.ink,
                      shape: CircleBorder(),
                    ),
                    child: const SizedBox.square(
                      dimension: SlushControl.touch,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: _cream,
                        size: 28,
                      ),
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
      borderRadius: BorderRadius.circular(SlushRadius.r24),
      border: Border.fromBorderSide(context.slush.border),
      boxShadow: context.slush.shadowsFor(SlushElevation.control),
    ),
    child: track == null
        ? null
        : ClipRRect(
            borderRadius: BorderRadius.circular(SlushRadius.r12),
            child: Artwork(track: track!, size: width - 24, radius: 0),
          ),
  );
}

Paint _fill(Color c) => Paint()..color = c;
Paint _line(double w, [Color color = Slush.ink]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeJoin = StrokeJoin.round
  ..strokeCap = StrokeCap.round
  ..color = color;

/// Cinta azul con bordes de tinta y una línea clara en el centro, de lado a
/// lado. Estática.
class _RibbonPainter extends CustomPainter {
  const _RibbonPainter(this.thickness, this.line);
  final double thickness;
  final Color line;

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
    canvas.drawPath(path, stroke(t + 8, line));
    canvas.drawPath(path, stroke(t, Slush.blue));
    canvas.drawPath(path, stroke(t * .55, _cream));
    canvas.drawPath(path, stroke(t * .3, Slush.blue));
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.thickness != thickness || old.line != line;
}

class _HeartPainter extends CustomPainter {
  const _HeartPainter(this.line);
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Path()
      ..moveTo(w / 2, h * .95)
      ..cubicTo(-w * .2, h * .5, w * .1, -h * .1, w / 2, h * .3)
      ..cubicTo(w * .9, -h * .1, w * 1.2, h * .5, w / 2, h * .95)
      ..close();
    canvas.drawPath(p, _fill(Slush.orange));
    canvas.drawPath(p, _line(3, line));
    canvas.drawArc(
      Rect.fromLTWH(w * .16, h * .2, w * .2, h * .2),
      math.pi,
      math.pi * .6,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Slush.yellow,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => old.line != line;
}

/// Portada geométrica del mix: ojo concéntrico y sol amarillo.
class _CoverPainter extends CustomPainter {
  const _CoverPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(20),
    );
    canvas.drawRRect(r, _fill(Slush.blue));
    canvas.save();
    canvas.clipRRect(r);
    final s = size.shortestSide;
    final c = Offset(size.width * .55, size.height * .58);
    for (final (rad, color, ring) in [
      (.36, _cream, true),
      (.27, Slush.blue, true),
      (.2, _cream, true),
      (.1, Slush.ink, false),
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
