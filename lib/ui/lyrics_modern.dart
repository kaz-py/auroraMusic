import 'dart:ui';

import 'package:flutter/material.dart';

import '../lyrics/lyrics_service.dart';
import '../theme/slush_theme.dart';

String _t(Duration d) =>
    '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Fondo del tema Modern: degradado con el color de la portada (el acento
/// del tema) que se funde con la superficie.
BoxDecoration modernLyricsBackdrop(BuildContext context) {
  final c = Theme.of(context).colorScheme;
  // Slush: panel `raised` con contorno suave y sombra dura de la paleta.
  if (isSlush(context)) {
    final p = context.slush;
    return BoxDecoration(
      color: p.raised,
      borderRadius: BorderRadius.circular(SlushRadius.r24),
      border: Border.fromBorderSide(p.borderSoft),
      boxShadow: p.shadows,
    );
  }
  return BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(c.primary.withValues(alpha: .38), c.surface),
        Color.alphaBlend(c.secondary.withValues(alpha: .14), c.surface),
        c.surface,
      ],
    ),
  );
}

/// Letras sincronizadas grandes: línea activa enorme y las demás se
/// desenfocan suavemente según su distancia.
class ModernLyricsList extends StatelessWidget {
  const ModernLyricsList({
    super.key,
    required this.lines,
    required this.active,
    required this.keyFor,
    required this.onSeek,
    required this.fontFamily,
    this.animate = true,
    this.controller,
  });
  final List<LyricLine> lines;
  final int active;
  final GlobalKey Function(int index) keyFor;
  final void Function(LyricLine line) onSeek;
  final String fontFamily;
  final bool animate;

  /// Slush: permite saltar a la zona de una línea aún no construida.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final slush = isSlush(context);
    final p = context.slush;
    final list = LayoutBuilder(
      builder: (context, box) => ListView.builder(
        controller: controller,
        padding: EdgeInsets.symmetric(
          horizontal: 28,
          // Slush: 40 % arriba y abajo para que cualquier línea pueda centrarse.
          vertical:
              (slush && box.hasBoundedHeight
                  ? box.maxHeight
                  : MediaQuery.sizeOf(context).height) *
              (slush ? .4 : .18),
        ),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final on = i == active;
          final distance = active < 0 ? 2 : (i - active).abs();
          final sigma = on ? 0.0 : (distance.clamp(1, 4) * .6);
          Widget text = AnimatedDefaultTextStyle(
            duration: animate
                ? const Duration(milliseconds: 220)
                : Duration.zero,
            curve: slush ? SlushMotion.easeOut : Curves.easeOut,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: slush ? (on ? 26 : 18) : (on ? 36 : 26),
              height: 1.25,
              letterSpacing: -.3,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: slush
                  ? (on ? Slush.ink : p.ink3)
                  : on
                  ? c.onSurface
                  : c.onSurface.withValues(alpha: .42),
            ),
            // Slush: marcador lilac tras la línea activa.
            child: slush && on
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Slush.lilac,
                      borderRadius: BorderRadius.circular(SlushRadius.r12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(line.text),
                    ),
                  )
                : Text(line.text),
          );
          if (sigma > 0 && !slush) {
            text = ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: text,
            );
          }
          return Semantics(
            key: keyFor(i),
            liveRegion: on,
            label: '${_t(line.at)} ${line.text}',
            child: InkWell(
              borderRadius: BorderRadius.circular(slush ? SlushRadius.r16 : 16),
              onTap: () => onSeek(line),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: slush ? SlushControl.touch : 0,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 6,
                  ),
                  child: text,
                ),
              ),
            ),
          );
        },
      ),
    );
    // Sin salto con texto grande: la letra no escala más de 1,5.
    return slush
        ? MediaQuery.withClampedTextScaling(maxScaleFactor: 1.5, child: list)
        : list;
  }
}
