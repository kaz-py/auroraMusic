import 'package:flutter/semantics.dart' show CustomSemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'mini_player_model.dart';

/// Distancia (px) o velocidad (px/s) a partir de las cuales se confirma el gesto.
/// Con movimiento reducido valen igual: solo desaparece el seguimiento visual.
const double kMiniOpenDistance = 40;
const double kMiniOpenVelocity = 600;
const double kMiniSwipeDistance = 64;
const double kMiniSwipeVelocity = 700;

/// Desplazamiento mínimo para que un gesto rápido cuente (histéresis).
const double _flickMinimum = 12;

/// Gestos de la barra del mini reproductor, iguales en todos los temas:
///
/// - toque: [MiniPlayerActions.openPlayer];
/// - arrastre vertical hacia arriba: abre el reproductor (la barra sigue al
///   dedo con resistencia y vuelve con un muelle; solo `transform`);
/// - arrastre horizontal: izquierda = siguiente, derecha = anterior (el muelle
///   hereda la velocidad del dedo);
/// - movimiento reducido (`MediaQuery.disableAnimationsOf`): sin seguimiento
///   ni muelle, mismos umbrales.
///
/// La barra no se desplaza, así que no compite con el scroll de la página. Los
/// botones del hijo ganan el toque; arrastrar sobre ellos mueve la barra.
/// [hasNext]/[hasPrevious] en falso: el gesto no confirma y la barra solo
/// «rebota». Semántica: un solo nodo con acciones personalizadas (abrir,
/// siguiente, anterior); los botones del hijo conservan su nodo.
class MiniPlayerGestures extends StatefulWidget {
  const MiniPlayerGestures({
    super.key,
    required this.child,
    required this.actions,
    this.hasNext = true,
    this.hasPrevious = true,
    this.semanticsLabel = 'Mini reproductor',
    this.tapOpens = true,
    this.onLongPress,
  });

  final Widget child;
  final MiniPlayerActions actions;
  final bool hasNext, hasPrevious;
  final String semanticsLabel;

  /// Con false, tocar la barra no hace nada (en escritorio el clic va solo a
  /// la portada y el título, `MiniPlayerInfoTap`); los arrastres siguen.
  final bool tapOpens;

  /// Pulsación larga sobre la barra (móvil): recibe la esquina superior
  /// izquierda de la barra en pantalla. Null: sin pulsación larga.
  final ValueChanged<Offset>? onLongPress;

  @override
  State<MiniPlayerGestures> createState() => _MiniPlayerGesturesState();
}

class _MiniPlayerGesturesState extends State<MiniPlayerGestures>
    with TickerProviderStateMixin {
  // Desplazamiento mostrado de cada eje; sin límites: lo mueve el dedo o un muelle.
  late final _x = AnimationController.unbounded(vsync: this);
  late final _y = AnimationController.unbounded(vsync: this);
  double _rawX = 0, _rawY = 0, _grabX = 0, _grabY = 0;
  bool _pressed = false;

  bool get _still => MediaQuery.disableAnimationsOf(context);

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  /// Resistencia progresiva: cuanto más se arrastra, menos sigue la barra.
  static double _rubber(double distance, double dimension) =>
      distance.sign *
      (distance.abs() * dimension * .55) /
      (dimension + .55 * distance.abs());

  void _spring(
    AnimationController c, {
    double velocity = 0,
    bool bounce = false,
  }) {
    if (_still || (c.value == 0 && velocity == 0)) {
      c.value = 0;
      return;
    }
    c.animateWith(
      SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1,
          stiffness: 322, // respuesta ~0,35 s
          ratio: bounce ? .8 : 1,
        ),
        c.value,
        0,
        velocity,
      ),
    );
  }

  void _hStart(DragStartDetails _) {
    _x.stop();
    _rawX = 0;
    _grabX = _x.value;
  }

  void _vStart(DragStartDetails _) {
    _y.stop();
    _rawY = 0;
    _grabY = _y.value;
  }

  // --- horizontal ---
  void _hUpdate(DragUpdateDetails d) {
    _rawX += d.primaryDelta ?? 0;
    if (_still) return;
    final blocked = _rawX < 0 ? !widget.hasNext : !widget.hasPrevious;
    _x.value = _grabX + _rubber(_rawX, blocked ? 40 : 120);
  }

  void _hEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final flick = v.abs() >= kMiniSwipeVelocity && _rawX.abs() >= _flickMinimum;
    final direction = flick ? v.sign : _rawX.sign;
    final far = _rawX.abs() >= kMiniSwipeDistance;
    final allowed = direction < 0 ? widget.hasNext : widget.hasPrevious;
    final commit = (far || flick) && direction != 0 && allowed;
    if (commit) {
      (direction < 0 ? widget.actions.next : widget.actions.previous)();
    }
    _spring(_x, velocity: v * .4, bounce: commit);
    _rawX = 0;
  }

  // --- vertical ---
  void _vUpdate(DragUpdateDetails d) {
    _rawY += d.primaryDelta ?? 0;
    if (_still) return;
    _y.value = _grabY + _rubber(_rawY, _rawY < 0 ? 96 : 24);
  }

  void _vEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final flick = v <= -kMiniOpenVelocity && _rawY <= -_flickMinimum;
    final commit = flick || _rawY <= -kMiniOpenDistance;
    if (commit) widget.actions.openPlayer();
    _spring(_y, velocity: v * .4, bounce: commit);
    _rawY = 0;
  }

  void _setPressed(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  // Ancla: la esquina superior izquierda de la barra (la tarjeta se abre encima).
  void _longPress() {
    final box = context.findRenderObject() as RenderBox;
    widget.onLongPress!(box.localToGlobal(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.actions;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: widget.semanticsLabel,
      hint: widget.tapOpens ? 'Toca para abrir el reproductor' : null,
      onTap: widget.tapOpens ? a.openPlayer : null,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Abrir reproductor'): a.openPlayer,
        if (widget.hasNext)
          const CustomSemanticsAction(label: 'Pista siguiente'): a.next,
        if (widget.hasPrevious)
          const CustomSemanticsAction(label: 'Pista anterior'): a.previous,
        if (widget.onLongPress != null)
          const CustomSemanticsAction(label: 'Más acciones'): _longPress,
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.tapOpens ? a.openPlayer : null,
          onLongPressStart: widget.onLongPress == null
              ? null
              : (_) => _longPress(),
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          onHorizontalDragStart: _hStart,
          onHorizontalDragUpdate: _hUpdate,
          onHorizontalDragEnd: _hEnd,
          onHorizontalDragCancel: () => _spring(_x),
          onVerticalDragStart: _vStart,
          onVerticalDragUpdate: _vUpdate,
          onVerticalDragEnd: _vEnd,
          onVerticalDragCancel: () => _spring(_y),
          child: AnimatedBuilder(
            animation: Listenable.merge([_x, _y]),
            child: widget.child,
            builder: (context, child) => Transform.translate(
              offset: Offset(_x.value, _y.value),
              child: AnimatedScale(
                scale: _pressed && !_still ? .985 : 1,
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
