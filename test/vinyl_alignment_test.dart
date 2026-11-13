import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/vinyl_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('vinyl layers share a center on desktop and narrow layouts', (
    tester,
  ) async {
    final controller = (await tester.runAsync(createTestController))!;
    final disc = find.byKey(const ValueKey('vinyl-disc'));
    final label = find.byKey(const ValueKey('vinyl-label'));
    final hole = find.byKey(const ValueKey('vinyl-hole'));

    Future<void> pumpAt(Size size, double textScale) async {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        // Atelier solo pinta la portada; Modern pinta el disco (sin pista, siempre).
        MaterialApp(
          theme: modernTheme(Brightness.dark, const Color(0xff6ea8ff)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: VinylPlayer(controller: controller)),
        ),
      );
      await tester.pump();

      final discCenter = tester.getCenter(disc);
      for (final layer in [label, hole]) {
        final center = tester.getCenter(layer);
        expect((center.dx - discCenter.dx).abs(), lessThanOrEqualTo(1));
        expect((center.dy - discCenter.dy).abs(), lessThanOrEqualTo(1));
      }
      expect(tester.takeException(), isNull);
    }

    try {
      await pumpAt(const Size(1440, 900), 1);
      await pumpAt(const Size(320, 800), 2);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() => closeTestController(controller));
      await tester.binding.setSurfaceSize(null);
    }
  });
}
