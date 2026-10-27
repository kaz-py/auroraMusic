import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';

abstract final class StudioPalette {
  static const canvas = Color(0xff151312);
  static const well = Color(0xff100e0d);
  static const low = Color(0xff1d1b1a);
  static const panel = Color(0xff211f1e);
  static const high = Color(0xff2c2928);
  static const seam = Color(0xff373433);
  static const ink = Color(0xffe8e1df);
  static const muted = Color(0xffdfc0b3);
  static const parchment = Color(0xffa78b7f);
  static const orange = Color(0xffea6b29);
  static const peach = Color(0xffffb596);

  /// Radio de las fundas: asimétrico en Atelier, 16 en Modern.
  static BorderRadius of(BuildContext context) => isBrasa(context)
      ? BorderRadius.circular(6)
      : isModern(context)
      ? BorderRadius.circular(16)
      : sleeve;

  static const sleeve = BorderRadius.only(
    topLeft: Radius.circular(8),
    topRight: Radius.circular(2),
    bottomRight: Radius.circular(8),
    bottomLeft: Radius.circular(2),
  );
}

class StudioPanel extends StatelessWidget {
  const StudioPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.recessed = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool recessed;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final modern = isModern(context);
    final brasa = isBrasa(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        // Modern: tarjeta blanca radio 16 con sombra cálida; el hueco usa el lienzo.
        color: brasa
            ? (recessed ? colors.surface : Brasa.obsidian)
            : modern && recessed
            ? colors.surfaceContainer
            : recessed
            ? colors.surfaceContainerLowest
            : colors.surfaceContainerLow,
        borderRadius: StudioPalette.of(context),
        border: isSlush(context)
            ? Border.fromBorderSide(context.slush.border)
            : null,
        boxShadow: isSlush(context)
            ? context.slush.shadows
            : brasa
            ? (recessed ? null : Brasa.cardShadow)
            : modern
            ? Tracky.warmShadow
            : const [BoxShadow(color: Colors.black, offset: Offset(3, 4))],
      ),
      // Own Material so ink (hover/selected/focus) paints above the panel fill.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

class StudioStamp extends StatelessWidget {
  const StudioStamp(this.text, {super.key, this.color, this.filled = false});
  final String text;
  final Color? color;
  final bool filled;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brasa = isBrasa(context);
    final modern = isModern(context) || brasa;
    final label = Text(
      text,
      style: TextStyle(
        fontFamily: modern ? null : 'monospace',
        fontSize: modern ? 11 : 10,
        fontWeight: modern ? FontWeight.w500 : null,
        letterSpacing: modern ? 0 : .5,
        color: color ?? colors.onSurfaceVariant,
      ),
    );
    if (brasa && filled) {
      return DecoratedBox(
        decoration: ShapeDecoration(
          color: Brasa.graphite,
          shape: const StadiumBorder(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          child: label,
        ),
      );
    }
    if (modern && filled) return ModernBadge(text);
    return filled
        ? ColoredBox(
            color: colors.surfaceContainerLowest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: label,
            ),
          )
        : label;
  }
}

void showStudioPending(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$feature: función pendiente de implementar.')),
  );
}

String studioTime(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
