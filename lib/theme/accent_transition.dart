import 'package:flutter/widgets.dart';

/// Duración única de la transición de color al cambiar de canción.
const accentTransitionDuration = Duration(milliseconds: 800);

/// Mezcla dos acentos en HSL por el camino más corto del tono: nunca pasa por
/// gris, blanco ni negro (el RGB directo entre naranja y azul sí lo hacía).
Color lerpAccent(Color a, Color b, double t) {
  if (t <= 0) return a;
  if (t >= 1) return b;
  final x = HSLColor.fromColor(a), y = HSLColor.fromColor(b);
  // Sin saturación el tono no significa nada: se toma el del otro extremo.
  final hx = x.saturation < .05 ? y.hue : x.hue;
  final hy = y.saturation < .05 ? x.hue : y.hue;
  final delta = ((hy - hx + 540) % 360) - 180;
  return HSLColor.fromAHSL(
    1,
    (hx + delta * t) % 360,
    x.saturation + (y.saturation - x.saturation) * t,
    x.lightness + (y.lightness - x.lightness) * t,
  ).toColor();
}

/// Acento animado vigente, para widgets que lo leen directamente en vez de
/// pasar por el tema (así no saltan mientras el tema se mueve).
class AccentScope extends InheritedWidget {
  const AccentScope({super.key, required this.accent, required super.child});

  final Color accent;

  static Color of(BuildContext context, Color fallback) =>
      context.dependOnInheritedWidgetOfExactType<AccentScope>()?.accent ??
      fallback;

  @override
  bool updateShouldNotify(AccentScope old) => accent != old.accent;
}

/// Un solo controlador para todos los temas: cuando [accent] cambia, entrega a
/// [builder] el color intermedio en cada fotograma (la app construye su tema
/// con él, así que tema y widgets sueltos se mueven a la vez). Si cambia a mitad
/// de camino, parte del color mostrado en ese momento. Sin animación al
/// montar ni con [instant] (movimiento reducido).
class AccentTransition extends StatefulWidget {
  const AccentTransition({
    super.key,
    required this.accent,
    required this.builder,
    this.instant = false,
    this.duration = accentTransitionDuration,
  });

  final Color accent;
  final bool instant;
  final Duration duration;

  /// `moving` es verdadero mientras dura la transición.
  final Widget Function(BuildContext context, Color accent, bool moving)
  builder;

  @override
  State<AccentTransition> createState() => _AccentTransitionState();
}

class _AccentTransitionState extends State<AccentTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late Color _from = widget.accent;
  late Color _to = widget.accent;

  Color get _now => _controller.isAnimating
      ? lerpAccent(_from, _to, Curves.easeInOut.transform(_controller.value))
      : _to;

  @override
  void didUpdateWidget(AccentTransition old) {
    super.didUpdateWidget(old);
    final target = widget.accent;
    final reduced = WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations;
    if (widget.instant || reduced) {
      _controller.stop();
      _from = _to = target;
    } else if (target != _to) {
      _from = _now;
      _to = target;
      _controller.duration = widget.duration;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) =>
        widget.builder(context, _now, _controller.isAnimating),
  );
}
