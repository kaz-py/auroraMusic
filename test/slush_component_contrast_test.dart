import 'dart:math' as math;

import 'package:aurora_music/theme/slush_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _ratio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (math.max(l1, l2) + .05) / (math.min(l1, l2) + .05);
}

void main() {
  for (final b in Brightness.values) {
    testWidgets('Slush $b: chips e IconButton rellenos son legibles', (
      t,
    ) async {
      final theme = slushTheme(b, Slush.lilac);
      final paper = theme.extension<SlushPalette>()!.paper;
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                ChoiceChip(
                  label: const Text('off'),
                  selected: false,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('fon'),
                  selected: true,
                  onSelected: (_) {},
                ),
                IconButton.filled(
                  key: const Key('filled'),
                  onPressed: () {},
                  icon: const Icon(Icons.add, key: Key('filled-i')),
                ),
                IconButton.filledTonal(
                  key: const Key('tonal'),
                  onPressed: () {},
                  icon: const Icon(Icons.add, key: Key('tonal-i')),
                ),
              ],
            ),
          ),
        ),
      );

      Color? labelColor(String s) => t
          .widget<RichText>(
            find.descendant(of: find.text(s), matching: find.byType(RichText)),
          )
          .text
          .style
          ?.color;
      expect(labelColor('off'), isNotNull, reason: 'etiqueta sin color');
      expect(_ratio(labelColor('off')!, paper), greaterThanOrEqualTo(4.5));
      expect(_ratio(labelColor('fon')!, Slush.mint), greaterThanOrEqualTo(4.5));

      Color bg(String key) => t
          .widget<Material>(
            find
                .descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(Material),
                )
                .first,
          )
          .color!;
      Color icon(String key) =>
          IconTheme.of(t.element(find.byKey(Key('$key-i')))).color!;
      for (final k in ['filled', 'tonal']) {
        expect(
          _ratio(icon(k), bg(k)),
          greaterThanOrEqualTo(4.5),
          reason: 'IconButton $k',
        );
      }
    });
  }
}
