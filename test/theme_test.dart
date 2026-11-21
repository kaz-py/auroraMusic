import 'dart:math';

import 'package:aurora_music/theme/atelier_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color first, Color second) {
  final a = first.computeLuminance(), b = second.computeLuminance();
  return (max(a, b) + 0.05) / (min(a, b) + 0.05);
}

void main() {
  test(
    'all artwork hue buckets preserve readable text and action contrast',
    () {
      for (final brightness in Brightness.values) {
        for (var hue = 0; hue < 360; hue += 15) {
          final scheme = auroraTheme(
            brightness,
            HSLColor.fromAHSL(1, hue + 7.5, .65, .65).toColor(),
          ).colorScheme;
          expect(
            contrast(scheme.onSurface, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onPrimary, scheme.primary),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness hue $hue button',
          );
          expect(
            contrast(scheme.primary, scheme.surface),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness hue $hue accent text',
          );
        }
      }
    },
  );

  test(
    'dark studio surfaces stay neutral while both themes keep accessible accents',
    () {
      final accents = <Color>[
        const Color(0xffe86927), // orange
        const Color(0xff3478c8), // blue
        const Color(0xff28734a), // forest
        const Color(0xffc45c2b), // terracotta
        const Color(0xffa66b00), // amber
        const Color(0xff7047a3), // purple
      ];
      for (final brightness in Brightness.values) {
        final themes = accents
            .map((accent) => auroraTheme(brightness, accent))
            .toList();
        final schemes = themes.map((theme) => theme.colorScheme).toList();
        for (final scheme in schemes) {
          expect(scheme.surface, isNot(scheme.surfaceContainerLow));
          expect(scheme.surfaceContainerLow, isNot(scheme.surfaceContainer));
          expect(scheme.surfaceContainer, isNot(scheme.surfaceContainerHigh));
          expect(
            contrast(scheme.onSurface, scheme.surfaceContainerLow),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurface, scheme.surfaceContainer),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurface, scheme.surfaceContainerLowest),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurfaceVariant, scheme.surfaceContainerHigh),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: '$brightness selected navigation text',
          );
        }
        // Atelier: papel y tinta fijos, el acento no tiñe las superficies.
        const surfaceVariants = 1;
        expect(
          schemes.map((scheme) => scheme.surface).toSet(),
          hasLength(surfaceVariants),
        );
        expect(
          schemes.map((scheme) => scheme.surfaceContainer).toSet(),
          hasLength(surfaceVariants),
        );
        expect(schemes.map((scheme) => scheme.primary).toSet(), hasLength(6));
        double surfaceTintDistance(Color a, Color b) =>
            ((a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs()) * 255;
        expect(
          surfaceTintDistance(schemes.first.surface, schemes.last.surface),
          equals(0),
          reason:
              '$brightness artwork palettes should retain neutral studio surfaces',
        );
        expect(themes[0].cardTheme.color, schemes[0].surfaceContainerLow);
        // Atelier: los campos solo llevan subrayado de tinta, sin relleno.
        expect(themes[0].inputDecorationTheme.fillColor, isNull);
        expect(
          themes[0].dialogTheme.backgroundColor,
          schemes[0].surfaceContainerHigh,
        );
        expect(themes[0].popupMenuTheme.color, schemes[0].surfaceContainerHigh);
        expect(themes[0].listTileTheme.selectedColor, schemes[0].onSurface);
      }
    },
  );
}
