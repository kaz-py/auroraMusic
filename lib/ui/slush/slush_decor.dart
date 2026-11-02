import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';

/// Banda de color plano a todo el ancho: borde negro 2 px y esquinas grandes.
/// [tone] se mezcla con el fondo (teñido por la portada) y el texto es negro.
class SlushBand extends StatelessWidget {
  const SlushBand({
    super.key,
    required this.tone,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Color tone;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Tonos de las bandas alternadas.
  static const tones = [
    Slush.mint,
    Slush.lilac,
    Slush.yellow,
    Color(0xffa9d2ff),
  ];

  static Color tint(BuildContext context, Color tone) =>
      Color.lerp(tone, Theme.of(context).scaffoldBackgroundColor, .25)!;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: tint(context, tone),
        borderRadius: BorderRadius.circular(SlushRadius.r32),
        border: Border.fromBorderSide(p.borderSoft),
        boxShadow: p.shadowsFor(SlushElevation.card),
      ),
      child: slushOnVivid(
        context,
        DefaultTextStyle.merge(
          style: const TextStyle(color: Slush.ink),
          child: child,
        ),
      ),
    );
  }
}

/// Chip de filtro tocable: contorno de control, color vivo; seleccionado =
/// tinta. Objetivo táctil de 44 (32 con puntero fino, >= 900), hundido al
/// pulsar, anillo de foco, 1 línea con elipsis. Sin sombra por defecto: vive
/// dentro de tarjetas y bandas.
class SlushChip extends StatelessWidget {
  const SlushChip(
    this.label, {
    super.key,
    this.icon,
    this.color = Slush.yellow,
    this.selected = false,
    this.elevation = SlushElevation.none,
    required this.onTap,
  });
  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;
  final SlushElevation elevation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final fill = selected ? p.ink : color;
    final fg = selected ? p.paper : slushOnColor(context, color);
    final dense = MediaQuery.sizeOf(context).width >= Breakpoints.medium;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.5,
        child: SlushPressable(
          onTap: onTap,
          elevation: elevation,
          minSize: dense ? SlushControl.dense : SlushControl.touch,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: AnimatedContainer(
              duration: SlushMotion.reduce(context)
                  ? Duration.zero
                  : SlushMotion.select,
              curve: SlushMotion.easeOut,
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: dense ? 6 : 10,
              ),
              decoration: ShapeDecoration(
                color: fill,
                shape: StadiumBorder(side: p.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        letterSpacing: .2,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum SlushShape { star, bolt, dots }

/// Pegatina decorativa pequeña (estrella, rayo, puntos). Ignora el puntero.
class SlushDecor extends StatelessWidget {
  const SlushDecor(
    this.shape, {
    super.key,
    this.size = 36,
    this.color = Slush.yellow,
    this.angle = 0,
  });
  final SlushShape shape;
  final double size;
  final Color color;
  final double angle;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: Transform.rotate(
        angle: angle,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _DecorPainter(shape, color, context.slush.line),
          ),
        ),
      ),
    ),
  );
}

class _DecorPainter extends CustomPainter {
  const _DecorPainter(this.shape, this.color, this.ink);
  final SlushShape shape;
  final Color color;
  final Color ink;

  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..color = ink;
    final fill = Paint()..color = color;
    final w = s.width, h = s.height;
    if (shape == SlushShape.dots) {
      for (var i = 0; i < 9; i++) {
        canvas.drawCircle(
          Offset(w * (.15 + .35 * (i % 3)), h * (.15 + .35 * (i ~/ 3))),
          w * .06,
          Paint()..color = ink,
        );
      }
      return;
    }
    final p = Path();
    if (shape == SlushShape.star) {
      for (var i = 0; i < 8; i++) {
        final r = w / 2 * (i.isEven ? 1 : .38);
        final a = -math.pi / 2 + math.pi * i / 4;
        final o = Offset(w / 2 + r * math.cos(a), h / 2 + r * math.sin(a));
        i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
      }
    } else {
      p
        ..moveTo(w * .62, 0)
        ..lineTo(w * .1, h * .58)
        ..lineTo(w * .46, h * .58)
        ..lineTo(w * .34, h)
        ..lineTo(w * .92, h * .38)
        ..lineTo(w * .55, h * .38)
        ..close();
    }
    p.close();
    canvas.drawPath(p, fill);
    canvas.drawPath(p, line);
  }

  @override
  bool shouldRepaint(_DecorPainter old) =>
      old.shape != shape || old.color != color || old.ink != ink;
}
