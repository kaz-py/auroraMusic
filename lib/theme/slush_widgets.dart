import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';

import 'slush_theme.dart';

/// Pegatina de estrella dentada con texto («NUEVO», «EN VIVO»), girada.
class SlushSticker extends StatelessWidget {
  const SlushSticker(
    this.label, {
    super.key,
    this.color = Slush.yellow,
    this.size = 84,
    this.angle = -.2,
  });
  final String label;
  final Color color;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: angle,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BurstPainter(color, context.slush.line),
        child: Center(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Bagel Fat One',
              fontSize: size * .17,
              color: Slush.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter(this.color, this.line);
  final Color color;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final path = Path();
    const points = 14;
    for (var i = 0; i < points * 2; i++) {
      final r = size.width / 2 * (i.isEven ? 1 : .82);
      final a = math.pi * i / points;
      final p = c + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.color != color || old.line != line;
}

/// Píldora informativa (no tocable): relleno de color, contorno de control y
/// texto `micro` (11, w700, +2 %, mayúsculas). Alto 24; el texto sigue al
/// relleno ([slushOnColor]): tinta sobre vivos, crema sobre papel oscuro,
/// blanco sobre violeta.
class SlushPill extends StatelessWidget {
  const SlushPill(this.label, {super.key, this.color = Slush.mint});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: SlushControl.pill),
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: color,
        shape: StadiumBorder(side: context.slush.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              letterSpacing: .22,
              fontWeight: FontWeight.w700,
              color: slushOnColor(context, color),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pulsable con relieve de pegatina: al bajar el dedo la cara se hunde sobre
/// la sombra dura (translate + scale, solo `transform`), 90 ms al bajar y
/// 160 ms al soltar con [SlushMotion.easeOut]. Hover (solo puntero) y anillo
/// de foco de teclado van como capa propia; activar con teclado no anima.
///
/// Con movimiento reducido (`MediaQuery.disableAnimations`) no hay
/// traslación ni escala: solo baja la opacidad, 120 ms.
///
/// La cara debe ser opaca (la sombra queda detrás). El área táctil mide al
/// menos [minSize] aunque el dibujo sea menor.
class SlushPressable extends StatefulWidget {
  const SlushPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = SlushRadius.pill,
    this.elevation = SlushElevation.control,
    this.pressedScale = .98,
    this.minSize = SlushControl.touch,
    this.autofocus = false,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Radio de la cara (sombra, hover y anillo lo siguen).
  final double radius;

  /// Sombra dura de reposo; [SlushElevation.none] no dibuja sombra ni
  /// traslada, solo escala.
  final SlushElevation elevation;

  /// Escala al pulsar (0,98 en controles táctiles; 1 para no escalar).
  final double pressedScale;
  final double minSize;
  final bool autofocus;
  final String? semanticLabel;

  /// Clave de la cara animada (`Transform`), para pruebas.
  static const faceKey = ValueKey('slush-pressable-face');

  @override
  State<SlushPressable> createState() => _SlushPressableState();
}

class _SlushPressableState extends State<SlushPressable>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this);
  bool _hover = false;
  bool _focus = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset? _downAt;

  // Feedback en pointer-down (onTapDown espera 100 ms).
  void _down(PointerDownEvent e) {
    if (!_enabled) return;
    _downAt = e.position;
    _c.forward();
  }

  void _up() {
    _downAt = null;
    _c.reverse();
  }

  // Si el dedo se arrastra (scroll), la cara se suelta.
  void _move(PointerMoveEvent e) {
    final d = _downAt;
    if (d != null && (e.position - d).distance > kTouchSlop) _up();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = SlushMotion.reduce(context);
    _c.duration = reduce ? SlushMotion.reduced : SlushMotion.pressDown;
    _c.reverseDuration = reduce ? SlushMotion.reduced : SlushMotion.pressUp;
    final p = context.slush;
    final r = BorderRadius.circular(widget.radius);
    final e = widget.elevation;
    final sink = e.offset - const Offset(1, 1);

    Widget face = Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: reduce ? Duration.zero : SlushMotion.hover,
              curve: SlushMotion.easeOut,
              decoration: BoxDecoration(
                borderRadius: r,
                color: _hover && _enabled ? p.hover : Colors.transparent,
              ),
            ),
          ),
        ),
        if (_focus)
          Positioned(
            left: -5,
            top: -5,
            right: -5,
            bottom: -5,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius + 5),
                  border: Border.fromBorderSide(p.focusRing),
                ),
              ),
            ),
          ),
      ],
    );

    face = reduce
        ? AnimatedBuilder(
            animation: _c,
            child: face,
            builder: (_, c) => Opacity(
              opacity: 1 - .15 * SlushMotion.easeOut.transform(_c.value),
              child: c,
            ),
          )
        : AnimatedBuilder(
            animation: _c,
            child: face,
            builder: (_, c) {
              final t = SlushMotion.easeOut.transform(_c.value);
              final s = 1 + (widget.pressedScale - 1) * t;
              return Transform(
                key: SlushPressable.faceKey,
                alignment: Alignment.center,
                transform: Matrix4.translationValues(
                  sink.dx * t,
                  sink.dy * t,
                  0,
                )..scaleByDouble(s, s, 1, 1),
                child: c,
              );
            },
          );

    // Sombra fija detrás: la cara se hunde sobre ella (sin Transform: vale
    // igual con movimiento reducido).
    final shadow = e == SlushElevation.none
        ? null
        : Positioned(
            left: e.offset.dx,
            top: e.offset.dy,
            right: -e.offset.dx,
            bottom: -e.offset.dy,
            child: DecoratedBox(
              decoration: BoxDecoration(color: p.shadow, borderRadius: r),
            ),
          );

    Widget body = Stack(clipBehavior: Clip.none, children: [?shadow, face]);
    if (widget.minSize > 0) {
      body = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize,
          minHeight: widget.minSize,
        ),
        child: Align(widthFactor: 1, heightFactor: 1, child: body),
      );
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        autofocus: widget.autofocus,
        mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (_) => _up(),
          onPointerCancel: (_) => _up(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapCancel: _up,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// Pantalla Slush: fondo de color plano propio y titular gigante («COLA»,
/// «JAM»). El contenido ocupa el resto.
class SlushScreen extends StatelessWidget {
  const SlushScreen({
    super.key,
    required this.color,
    required this.title,
    required this.child,
  });
  final Color color;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.displayLarge?.copyWith(fontSize: 96, height: .9),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

/// Onda azul decorativa con borde negro, para fondos de cabecera.
class SlushWave extends StatelessWidget {
  const SlushWave({super.key, this.height = 140});
  final double height;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _WavePainter(context.slush.line)),
    ),
  );
}

class _WavePainter extends CustomPainter {
  const _WavePainter(this.line);
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(0, h * .7);
    path.cubicTo(w * .25, h * 1.1, w * .4, -h * .1, w * .65, h * .4);
    path.cubicTo(w * .8, h * .7, w * .92, h * .2, w, h * .3);
    final stroke = h * .3;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke + 6
        ..color = line,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Slush.blue,
    );
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.line != line;
}
