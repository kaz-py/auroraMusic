import 'package:flutter/material.dart';

import 'brasa_theme.dart';

/// Resplandor radial de brasa detrás de [child] (la portada que suena).
/// Es un degradado radial estático (sin blur ni `BackdropFilter`) dentro de su
/// propio `RepaintBoundary`: se pinta una vez y no se repinta con el progreso.
/// Se extiende [spread] veces el tamaño del hijo sin ocupar espacio extra.
class BrasaGlow extends StatelessWidget {
  const BrasaGlow({
    super.key,
    required this.child,
    this.spread = 1.7,
    this.intensity = .36,
    this.color = Brasa.ember,
  });

  final Widget child;
  final double spread;
  final double intensity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final glow = RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: intensity),
              color.withValues(alpha: intensity * .35),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .45, 1],
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.hasBoundedWidth ? box.maxWidth : 0.0;
        final h = box.hasBoundedHeight ? box.maxHeight : 0.0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (w > 0 && h > 0)
              Positioned(
                left: -w * (spread - 1) / 2,
                top: -h * (spread - 1) / 2,
                width: w * spread,
                height: h * spread,
                child: IgnorePointer(child: glow),
              ),
            child,
          ],
        );
      },
    );
  }
}

/// Seek «filamento»: línea incandescente (degradado brasa `#B3401F → #FF7A3D →
/// #E8A24A`, brillo y cabeza con halo). Con [onChanged] es un seek táctil; sin
/// él es solo un indicador de progreso. [height] es el grosor de la línea; la
/// zona táctil mide al menos [hitHeight].
class BrasaFilament extends StatelessWidget {
  const BrasaFilament({
    super.key,
    required this.value,
    this.height = 4,
    this.hitHeight = 24,
    this.head = true,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel = 'Progreso',
  });

  final double value;
  final double height;
  final double hitHeight;
  final bool head;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final line = RepaintBoundary(
      child: CustomPaint(
        painter: _FilamentPainter(v, height, head),
        child: SizedBox(height: hitHeight, width: double.infinity),
      ),
    );
    if (onChanged == null) return ExcludeSemantics(child: line);
    return LayoutBuilder(
      builder: (context, box) {
        double at(Offset p) =>
            box.maxWidth <= 0 ? 0 : (p.dx / box.maxWidth).clamp(0.0, 1.0);
        return Semantics(
          label: semanticLabel,
          slider: true,
          value: '${(v * 100).round()} %',
          increasedValue: '${((v + .05).clamp(0.0, 1.0) * 100).round()} %',
          decreasedValue: '${((v - .05).clamp(0.0, 1.0) * 100).round()} %',
          onIncrease: () => onChangeEnd?.call((v + .05).clamp(0.0, 1.0)),
          onDecrease: () => onChangeEnd?.call((v - .05).clamp(0.0, 1.0)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => onChanged!(at(d.localPosition)),
            onTapUp: (d) => onChangeEnd?.call(at(d.localPosition)),
            onHorizontalDragUpdate: (d) => onChanged!(at(d.localPosition)),
            onHorizontalDragEnd: (_) => onChangeEnd?.call(v),
            child: line,
          ),
        );
      },
    );
  }
}

class _FilamentPainter extends CustomPainter {
  _FilamentPainter(this.v, this.height, this.head);
  final double v;
  final double height;
  final bool head;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final r = Radius.circular(height / 2);
    final track = RRect.fromLTRBR(
      0,
      cy - height / 2,
      size.width,
      cy + height / 2,
      r,
    );
    canvas.drawRRect(track, Paint()..color = Brasa.surface3);
    final x = size.width * v;
    if (x <= 0) return;
    final fill = RRect.fromLTRBR(0, cy - height / 2, x, cy + height / 2, r);
    canvas.drawRRect(
      fill.inflate(height * .5),
      Paint()
        ..color = Brasa.ember.withValues(alpha: .35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, height),
    );
    canvas.drawRRect(
      fill,
      Paint()
        ..shader = Brasa.filament.createShader(
          Rect.fromLTWH(0, 0, x < 1 ? 1 : x, size.height),
        ),
    );
    if (head) {
      final hr = height * 1.5 + 2;
      canvas.drawCircle(
        Offset(x, cy),
        hr * 1.7,
        Paint()..color = Brasa.ember.withValues(alpha: .28),
      );
      canvas.drawCircle(
        Offset(x, cy),
        hr,
        Paint()..color = const Color(0xffffd9b5),
      );
    }
  }

  @override
  bool shouldRepaint(_FilamentPainter old) =>
      old.v != v || old.height != height || old.head != head;
}

/// Etiqueta de sección: DM Mono en versalitas con punto de brasa.
class BrasaSectionLabel extends StatelessWidget {
  const BrasaSectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 18, 6, 6),
    child: Row(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(color: Brasa.ember, shape: BoxShape.circle),
          child: SizedBox.square(dimension: 6),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Brasa.mono(11, color: Brasa.cloud),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
