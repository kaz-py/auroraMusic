import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  testWidgets(
    'Ajustes > Apariencia: el interruptor activa el modo y lo guarda',
    (tester) async {
      final controller = (await tester.runAsync(createTestController))!;
      final container = ProviderContainer(
        overrides: [controllerProvider.overrideWith((ref) => controller)],
      );
      addTearDown(() async {
        container.dispose();
        await tester.runAsync(() => closeTestController(controller));
      });
      tester.view.physicalSize = const Size(800, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AuroraApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tune).last);
      await tester.pumpAndSettle();

      final label = find.text('Fondo difuminado de la portada');
      await tester.ensureVisible(label);
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: label,
        matching: find.byType(SwitchListTile),
      );
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.tap(label);
      await tester.pumpAndSettle();
      expect(controller.blurredCoverMode, isTrue);
      expect(controller.preferences.getBool('blurredCoverMode'), isTrue);
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
