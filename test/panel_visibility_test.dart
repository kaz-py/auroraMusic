import 'package:aurora_music/shortcuts/shortcut_service.dart';
import 'package:aurora_music/ui/shell/panel_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Especificación: paneles laterales plegables (ShellPanels, PanelSeam) y
/// atajos Ctrl+B / Ctrl+Alt+B asociados (ShortcutService).
void main() {
  group('ShellPanels', () {
    test('claves de preferencia fijas', () {
      expect(ShellPanels.sidebarKey, 'shellSidebarCollapsed');
      expect(ShellPanels.asideKey, 'shellAsideHidden');
    });

    test('sin prefs: ambos paneles visibles (no plegados)', () {
      final panels = ShellPanels(null);
      expect(panels.sidebarCollapsed, isFalse);
      expect(panels.asideHidden, isFalse);
    });

    test('con prefs vacías: ambos paneles visibles', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final panels = ShellPanels(prefs);
      expect(panels.sidebarCollapsed, isFalse);
      expect(panels.asideHidden, isFalse);
    });

    test('lee los valores guardados al construirse', () async {
      SharedPreferences.setMockInitialValues({
        'shellSidebarCollapsed': true,
        'shellAsideHidden': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final panels = ShellPanels(prefs);
      expect(panels.sidebarCollapsed, isTrue);
      expect(panels.asideHidden, isTrue);
    });

    test(
      'toggle(left) invierte solo el izquierdo, persiste y notifica una vez',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final panels = ShellPanels(prefs);
        var notified = 0;
        panels.addListener(() => notified++);

        panels.toggle(PanelSide.left);

        expect(panels.sidebarCollapsed, isTrue);
        expect(panels.asideHidden, isFalse);
        expect(prefs.getBool('shellSidebarCollapsed'), isTrue);
        expect(notified, 1);

        panels.toggle(PanelSide.left);
        expect(panels.sidebarCollapsed, isFalse);
        expect(prefs.getBool('shellSidebarCollapsed'), isFalse);
        expect(notified, 2);
      },
    );

    test(
      'toggle(right) invierte solo el derecho, persiste y notifica una vez',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final panels = ShellPanels(prefs);
        var notified = 0;
        panels.addListener(() => notified++);

        panels.toggle(PanelSide.right);

        expect(panels.asideHidden, isTrue);
        expect(panels.sidebarCollapsed, isFalse);
        expect(prefs.getBool('shellAsideHidden'), isTrue);
        expect(notified, 1);

        panels.toggle(PanelSide.right);
        expect(panels.asideHidden, isFalse);
        expect(prefs.getBool('shellAsideHidden'), isFalse);
        expect(notified, 2);
      },
    );

    test('setSidebarCollapsed con el mismo valor no notifica', () async {
      SharedPreferences.setMockInitialValues({'shellSidebarCollapsed': true});
      final prefs = await SharedPreferences.getInstance();
      final panels = ShellPanels(prefs);
      var notified = 0;
      panels.addListener(() => notified++);

      panels.setSidebarCollapsed(true);
      expect(notified, 0);

      panels.setSidebarCollapsed(false);
      expect(notified, 1);
      expect(panels.sidebarCollapsed, isFalse);
    });

    test('setAsideHidden con el mismo valor no notifica', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final panels = ShellPanels(prefs);
      var notified = 0;
      panels.addListener(() => notified++);

      panels.setAsideHidden(false);
      expect(notified, 0);

      panels.setAsideHidden(true);
      expect(notified, 1);
      expect(panels.asideHidden, isTrue);
    });

    test('sin prefs, toggle funciona en memoria sin lanzar', () {
      final panels = ShellPanels(null);
      var notified = 0;
      panels.addListener(() => notified++);

      expect(() => panels.toggle(PanelSide.left), returnsNormally);
      expect(panels.sidebarCollapsed, isTrue);
      expect(() => panels.toggle(PanelSide.right), returnsNormally);
      expect(panels.asideHidden, isTrue);
      expect(notified, 2);
    });
  });

  group('PanelSeam', () {
    Future<void> pumpSeam(
      WidgetTester tester, {
      required PanelSide side,
      required bool open,
      required VoidCallback onToggle,
      String? shortcutLabel,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: Row(
                children: [
                  PanelSeam(
                    side: side,
                    open: open,
                    onToggle: onToggle,
                    shortcutLabel: shortcutLabel,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    test('ancho fijo de 14', () {
      expect(PanelSeam.width, 14);
    });

    testWidgets('tocarlo llama a onToggle exactamente una vez', (tester) async {
      var calls = 0;
      await pumpSeam(
        tester,
        side: PanelSide.left,
        open: true,
        onToggle: () => calls++,
      );
      await tester.tap(find.byType(PanelSeam));
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('etiquetas semánticas según lado y estado', (tester) async {
      final handle = tester.ensureSemantics();

      const cases = <(PanelSide, bool, String)>[
        (PanelSide.left, true, 'Plegar el panel izquierdo'),
        (PanelSide.left, false, 'Desplegar el panel izquierdo'),
        (PanelSide.right, true, 'Ocultar el panel derecho'),
        (PanelSide.right, false, 'Mostrar el panel derecho'),
      ];
      for (final (side, open, label) in cases) {
        await pumpSeam(tester, side: side, open: open, onToggle: () {});
        final node = tester.getSemantics(find.bySemanticsLabel(label));
        expect(node.label, label, reason: '$side open=$open');
        expect(
          node.getSemanticsData().flagsCollection.isButton,
          isTrue,
          reason: '$side open=$open debe ser botón',
        );
      }
      handle.dispose();
    });

    testWidgets('tooltip sin atajo: solo la etiqueta', (tester) async {
      await pumpSeam(tester, side: PanelSide.left, open: true, onToggle: () {});
      expect(find.byTooltip('Plegar el panel izquierdo'), findsOneWidget);
    });

    testWidgets('tooltip con atajo: etiqueta y atajo entre paréntesis', (
      tester,
    ) async {
      await pumpSeam(
        tester,
        side: PanelSide.left,
        open: true,
        onToggle: () {},
        shortcutLabel: 'Ctrl+B',
      );
      expect(
        find.byTooltip('Plegar el panel izquierdo (Ctrl+B)'),
        findsOneWidget,
      );
    });

    testWidgets('tooltip del lado derecho cerrado con atajo', (tester) async {
      await pumpSeam(
        tester,
        side: PanelSide.right,
        open: false,
        onToggle: () {},
        shortcutLabel: 'Ctrl+Alt+B',
      );
      expect(
        find.byTooltip('Mostrar el panel derecho (Ctrl+Alt+B)'),
        findsOneWidget,
      );
    });
  });

  group('Atajos de paneles (ShortcutService)', () {
    late ShortcutService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = ShortcutService(await SharedPreferences.getInstance());
    });

    test('toggleSidebar y toggleAside existen', () {
      expect(ShortcutId.values, contains(ShortcutId.toggleSidebar));
      expect(ShortcutId.values, contains(ShortcutId.toggleAside));
    });

    test('atajos por defecto: Ctrl+B y Ctrl+Alt+B', () {
      expect(service.labelOf(ShortcutId.toggleSidebar), 'Ctrl+B');
      expect(service.labelOf(ShortcutId.toggleAside), 'Ctrl+Alt+B');
    });

    test('no son combinaciones reservadas', () {
      expect(
        ShortcutService.isReserved(
          service.activatorOf(ShortcutId.toggleSidebar),
        ),
        isFalse,
      );
      expect(
        ShortcutService.isReserved(service.activatorOf(ShortcutId.toggleAside)),
        isFalse,
      );
    });

    test('no chocan con ninguna otra acción por defecto', () {
      for (final id in [ShortcutId.toggleSidebar, ShortcutId.toggleAside]) {
        expect(
          service.conflictOf(service.activatorOf(id), except: id),
          isNull,
          reason: '$id',
        );
      }
    });

    test('funcionan aunque haya un campo de texto enfocado', () {
      expect(
        ShortcutService.yieldsToTextField(
          service.activatorOf(ShortcutId.toggleSidebar),
        ),
        isFalse,
      );
      expect(
        ShortcutService.yieldsToTextField(
          service.activatorOf(ShortcutId.toggleAside),
        ),
        isFalse,
      );
    });

    test('la tecla de los atajos es B', () {
      expect(
        service.activatorOf(ShortcutId.toggleSidebar).trigger,
        LogicalKeyboardKey.keyB,
      );
      expect(
        service.activatorOf(ShortcutId.toggleAside).trigger,
        LogicalKeyboardKey.keyB,
      );
    });
  });
}
