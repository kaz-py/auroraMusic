import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_decor.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + .05) / (math.min(la, lb) + .05);
}

void main() {
  testWidgets('SlushBand en oscuro: texto del tema con contraste >= 4.5', (
    tester,
  ) async {
    late Color tint;
    late Color variant;
    late Color small;
    await tester.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.dark, Slush.lilac),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final tone = SlushBand.tones.first;
              tint = SlushBand.tint(context, tone);
              return SlushBand(
                tone: tone,
                child: Builder(
                  builder: (context) {
                    final t = Theme.of(context);
                    variant = t.colorScheme.onSurfaceVariant;
                    small = t.textTheme.bodySmall!.color!;
                    return Text('x', style: TextStyle(color: variant));
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(_contrast(variant, tint), greaterThanOrEqualTo(4.5));
    expect(_contrast(small, tint), greaterThanOrEqualTo(4.5));
  });
}
