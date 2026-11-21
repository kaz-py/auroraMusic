import 'package:flutter/material.dart';

import 'modern_theme.dart';
import 'slush_theme.dart';

/// Paleta Tracky (guía de estilo del usuario). Solo para el tema Modern.
abstract final class Tracky {
  static const navy = Color(0xff151b31);
  static const coral = Color(0xffff5858);
  static const mint = Color(0xff86e0c1);
  static const butter = Color(0xfffedf89);
  static const slate = Color(0xff6d6f75);
  static const canvas = Color(0xfff2f2f2);
  static const stone = Color(0xffe8e7e5);

  /// Sombra cálida de la guía: 1–4 px de desenfoque, <25 % de opacidad.
  static const warmShadow = [
    BoxShadow(color: Color(0x338a857d), offset: Offset(0, 1), blurRadius: 4),
  ];
}

/// Tarjeta Modern: 16 px (24 px si [feature]), sombra cálida, sin bordes
/// duros. [dark] = tarjeta de acento azul marino con texto claro. Con
/// [onTap] sube 2 px al pasar el ratón (respeta «reducir movimiento»).
class ModernCard extends StatefulWidget {
  const ModernCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.dark = false,
    this.feature = false,
    this.onTap,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool dark;
  final bool feature;
  final VoidCallback? onTap;
  final Color? color;

  @override
  State<ModernCard> createState() => _ModernCardState();
}

class _ModernCardState extends State<ModernCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(widget.feature ? 24 : 16);
    final still = MediaQuery.disableAnimationsOf(context);
    final fill =
        widget.color ??
        (widget.dark
            ? (isSlush(context)
                  ? Slush.violet
                  : isDarkTheme(context)
                  ? scheme.primaryContainer
                  : Tracky.navy)
            : scheme.surfaceContainerLow);
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: isSlush(context)
            ? Border.fromBorderSide(context.slush.border)
            : null,
        boxShadow: isSlush(context) ? context.slush.shadows : Tracky.warmShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: DefaultTextStyle.merge(
          style: TextStyle(color: widget.dark ? Colors.white : null),
          child: widget.onTap == null
              ? Padding(padding: widget.padding, child: widget.child)
              : InkWell(
                  onTap: widget.onTap,
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
        ),
      ),
    );
    if (widget.onTap == null) return card;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedSlide(
        offset: _hover && !still ? const Offset(0, -.015) : Offset.zero,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: card,
      ),
    );
  }
}

bool isDarkTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

enum ModernTone { mint, butter, coral, neutral }

/// Insignia de estado: 8 px de radio, Inter 12 / peso 500.
class ModernBadge extends StatelessWidget {
  const ModernBadge(this.label, {super.key, this.tone = ModernTone.neutral});
  final String label;
  final ModernTone tone;

  @override
  Widget build(BuildContext context) {
    final bg = switch (tone) {
      ModernTone.mint => Tracky.mint,
      ModernTone.butter => Tracky.butter,
      ModernTone.coral => Tracky.coral,
      ModernTone.neutral => Theme.of(context).colorScheme.surfaceContainerHigh,
    };
    final fg = tone == ModernTone.neutral
        ? Theme.of(context).colorScheme.onSurface
        : Tracky.navy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: fg,
            letterSpacing: -.12,
          ),
        ),
      ),
    );
  }
}

/// Titular de marca (Bagel Fat One, +0.03em) con UNA palabra en coral.
class ModernHeadline extends StatelessWidget {
  const ModernHeadline({
    super.key,
    required this.before,
    this.emphasis = '',
    this.after = '',
    this.size = 48,
    this.onDark = false,
    this.align = TextAlign.start,
  });
  final String before;
  final String emphasis;
  final String after;
  final double size;
  final bool onDark;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: isSlush(context) ? 'Bricolage Grotesque' : 'Bagel Fat One',
      fontWeight: isSlush(context) ? FontWeight.w800 : null,
      fontVariations: isSlush(context) ? [FontVariation('wght', 800)] : null,
      fontSize: size,
      height: isSlush(context) ? .95 : 1.1,
      letterSpacing: isSlush(context) ? -size * .02 : size * .03,
      color: onDark ? Colors.white : Theme.of(context).colorScheme.onSurface,
    );
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: before),
          if (emphasis.isNotEmpty)
            TextSpan(
              text: emphasis,
              style: TextStyle(
                color: isSlush(context) ? Slush.orange : Tracky.coral,
              ),
            ),
          TextSpan(text: after),
        ],
      ),
      textAlign: align,
    );
  }
}

/// Banner superior amarillo mantequilla (avisos temporales).
class ModernBanner extends StatelessWidget {
  const ModernBanner({super.key, required this.message, this.onClose});
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Tracky.butter,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      color: Tracky.navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Cerrar',
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 18, color: Tracky.navy),
              ),
          ],
        ),
      ),
    );
  }
}

/// Botón de reproducir/pausar circular menta (32–48 px) de la guía.
class ModernPlayButton extends StatelessWidget {
  const ModernPlayButton({
    super.key,
    required this.playing,
    required this.onPressed,
    this.size = 40,
    this.busy = false,
  });
  final bool playing;
  final VoidCallback? onPressed;
  final double size;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: playing ? 'Pausa' : 'Reproducir',
      child: SizedBox.square(
        dimension: size,
        child: Material(
          color: Tracky.mint,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Tracky.navy,
                    ),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Tracky.navy,
                    size: size * .6,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Atajo para ramas `if (isModern(context))` sin importar dos archivos.
bool modernOf(BuildContext context) => isModern(context);
