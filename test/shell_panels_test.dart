import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/shell/panel_visibility.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'support/fakes.dart';

/// Especificación: paneles laterales plegables integrados en la app completa
/// (escritorio). Atajos Ctrl+B (izquierdo) y Ctrl+Alt+B (derecho), persistencia
/// y ausencia de paneles en móvil.
const _themes = ['atelier', 'modern', 'brasa', 'slush'];
const _desktopSizes = [Size(1200, 800), Size(1920, 1080)];

const _tracks = [
  Track(
    id: 'a',
    title: 'Primera pista',
    artist: 'Aurora',
    pageUrl: 'https://www.youtube.com/watch?v=a',
    duration: Duration(minutes: 3),
  ),
];

Finder _seam(PanelSide side) =>
    find.byWidgetPredicate((w) => w is PanelSeam && w.side == side);

PanelSeam _seamWidget(WidgetTester tester, PanelSide side) =>
    tester.widget<PanelSeam>(_seam(side));

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

  Future<AppController> pump(
    WidgetTester tester, {
    required String theme,
    required Size size,
    Map<String, Object> extra = const {},
  }) async {
    final controller = (await tester.runAsync(
      () => createTestController(
        tracks: _tracks,
        audio: FakeAudio(),
        preferences: {'themeKind': theme, ...extra},
      ),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await controller.closed;
        if (await controller.supportDirectory.exists()) {
          await controller.supportDirectory.delete(recursive: true);
        }
      }),
    );
    // Desmontar (el proveedor libera el controlador) aunque la prueba falle.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    // Escritorio: sin padding de notch.
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [controllerProvider.overrideWith((ref) => controller)],
        child: const AuroraApp(),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> sendCtrlB(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> sendCtrlAltB(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  for (final theme in _themes) {
    for (final size in _desktopSizes) {
      final label = '$theme ${size.width.toInt()}x${size.height.toInt()}';
      group(label, () {
        testWidgets('Inicio: seam izquierdo y derecho abiertos al arrancar', (
          tester,
        ) async {
          await pump(tester, theme: theme, size: size);
          expect(_seam(PanelSide.left), findsOneWidget);
          expect(_seamWidget(tester, PanelSide.left).open, isTrue);
          if (_seam(PanelSide.right).evaluate().isNotEmpty) {
            expect(_seamWidget(tester, PanelSide.right).open, isTrue);
          }
        });

        testWidgets('tocar el seam izquierdo pliega y despliega sin overflow', (
          tester,
        ) async {
          final controller = await pump(tester, theme: theme, size: size);

          await tester.tap(_seam(PanelSide.left));
          await tester.pumpAndSettle();
          expect(
            controller.preferences.getBool('shellSidebarCollapsed'),
            isTrue,
          );
          expect(_seamWidget(tester, PanelSide.left).open, isFalse);
          expect(tester.takeException(), isNull);

          await tester.tap(_seam(PanelSide.left));
          await tester.pumpAndSettle();
          expect(
            controller.preferences.getBool('shellSidebarCollapsed'),
            isFalse,
          );
          expect(_seamWidget(tester, PanelSide.left).open, isTrue);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Ctrl+B pliega y despliega la barra izquierda', (
          tester,
        ) async {
          final controller = await pump(tester, theme: theme, size: size);

          await sendCtrlB(tester);
          expect(
            controller.preferences.getBool('shellSidebarCollapsed'),
            isTrue,
          );
          expect(tester.takeException(), isNull);

          await sendCtrlB(tester);
          expect(
            controller.preferences.getBool('shellSidebarCollapsed'),
            isFalse,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('Ctrl+Alt+B oculta y muestra el panel derecho', (
          tester,
        ) async {
          final controller = await pump(tester, theme: theme, size: size);

          await sendCtrlAltB(tester);
          expect(controller.preferences.getBool('shellAsideHidden'), isTrue);
          if (_seam(PanelSide.right).evaluate().isNotEmpty) {
            expect(_seamWidget(tester, PanelSide.right).open, isFalse);
          }
          expect(tester.takeException(), isNull);

          await sendCtrlAltB(tester);
          expect(controller.preferences.getBool('shellAsideHidden'), isFalse);
          if (_seam(PanelSide.right).evaluate().isNotEmpty) {
            expect(_seamWidget(tester, PanelSide.right).open, isTrue);
          }
          expect(tester.takeException(), isNull);
        });

        testWidgets(
          'persistencia: arranca con ambos paneles plegados/ocultos',
          (tester) async {
            await pump(
              tester,
              theme: theme,
              size: size,
              extra: const {
                'shellSidebarCollapsed': true,
                'shellAsideHidden': true,
              },
            );
            expect(_seam(PanelSide.left), findsOneWidget);
            expect(_seamWidget(tester, PanelSide.left).open, isFalse);
            if (_seam(PanelSide.right).evaluate().isNotEmpty) {
              expect(_seamWidget(tester, PanelSide.right).open, isFalse);
            }
            expect(tester.takeException(), isNull);
          },
        );
      });
    }
  }

  for (final theme in _themes) {
    testWidgets('móvil 390x844 ($theme): no hay PanelSeam', (tester) async {
      await pump(tester, theme: theme, size: const Size(390, 844));
      expect(_seam(PanelSide.left), findsNothing);
      expect(_seam(PanelSide.right), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
