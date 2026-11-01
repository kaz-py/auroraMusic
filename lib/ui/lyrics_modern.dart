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
  // Slush: tarjeta blanca de letras con contorno y sombra dura.
  if (isSlush(context)) {
    return BoxDecoration(
      color: context.slush.paper,
      borderRadius: BorderRadius.circular(24),
      border: Border.fromBorderSide(context.slush.border),
      boxShadow: context.slush.shadows,
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
  });
  final List<LyricLine> lines;
  final int active;
  final GlobalKey Function(int index) keyFor;
  final void Function(LyricLine line) onSeek;
  final String fontFamily;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final slush = isSlush(context);
    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: 28,
        vertical: MediaQuery.sizeOf(context).height * .18,
      ),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[i];
        final on = i == active;
        final distance = active < 0 ? 2 : (i - active).abs();
        final sigma = on ? 0.0 : (distance.clamp(1, 4) * .6);
        Widget text = AnimatedDefaultTextStyle(
          duration: animate ? const Duration(milliseconds: 220) : Duration.zero,
          curve: Curves.easeOut,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: slush ? (on ? 22 : 16) : (on ? 36 : 26),
            height: 1.25,
            letterSpacing: -.3,
            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            color: slush
                ? (on ? Slush.ink : context.slush.ink.withValues(alpha: .6))
                : on
                ? c.onSurface
                : c.onSurface.withValues(alpha: .42),
          ),
          // Slush: marcador lilac tras la línea activa.
          child: slush && on
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    color: Slush.lilac,
                    borderRadius: BorderRadius.circular(10),
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
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSeek(line),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: text,
            ),
          ),
        );
      },
    );
  }
}
