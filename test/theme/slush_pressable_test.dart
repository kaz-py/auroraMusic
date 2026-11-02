import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/theme/slush_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app({
  required Widget child,
  bool reduce = false,
  Brightness b = Brightness.light,
}) => MaterialApp(
  theme: slushTheme(b, Slush.lilac),
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
    child: c!,
  ),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('SlushPressable se hunde al pulsar y vuelve al soltar', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        child: SlushPressable(
          onTap: () => taps++,
          child: Container(
            key: const Key('face'),
            width: 120,
            height: 48,
            color: Slush.mint,
          ),
        ),
      ),
    );
    Matrix4 face() =>
        tester.widget<Transform>(find.byKey(SlushPressable.faceKey)).transform;
    expect(face().getTranslation().x, 0);
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('face'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    // Control: (2,3) - (1,1) = (1,2); escala .98.
    expect(face().getTranslation().x, closeTo(1, .01));
    expect(face().getTranslation().y, closeTo(2, .01));
    expect(face().storage[0], closeTo(.98, .001));
    await g.up();
    await tester.pumpAndSettle();
    expect(face().getTranslation().x, closeTo(0, .01));
    expect(taps, 1);
  });

  testWidgets('Movimiento reducido: sin traslación ni escala', (tester) async {
    await tester.pumpWidget(
      _app(
        reduce: true,
        child: SlushPressable(
          onTap: () {},
          child: Container(
            key: const Key('face'),
            width: 120,
            height: 48,
            color: Slush.mint,
          ),
        ),
      ),
    );
    final scope = find.byType(SlushPressable);
    expect(find.byKey(SlushPressable.faceKey), findsNothing);
    expect(
      find.descendant(of: scope, matching: find.byType(Transform)),
      findsNothing,
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('face'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.descendant(of: scope, matching: find.byType(Transform)),
      findsNothing,
    );
    final o = tester.widget<Opacity>(
      find.descendant(of: scope, matching: find.byType(Opacity)),
    );
    expect(o.opacity, lessThan(1));
    await g.up();
    await tester.pumpAndSettle();
  });

  testWidgets('Área táctil >= 44 aunque la cara sea menor', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        child: SlushPressable(
          onTap: () => taps++,
          child: const SizedBox(key: Key('face'), width: 20, height: 20),
        ),
      ),
    );
    final size = tester.getSize(find.byType(SlushPressable));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    // Fuera del dibujo pero dentro del área táctil.
    await tester.tapAt(
      tester.getCenter(find.byType(SlushPressable)) + const Offset(18, 18),
    );
    expect(taps, 1);
  });

  testWidgets('Teclado: Enter activa; el foco dibuja el anillo', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        child: SlushPressable(
          autofocus: true,
          onTap: () => taps++,
          child: Container(width: 100, height: 44, color: Slush.mint),
        ),
      ),
    );
    await tester.pump();
    final ring = find.descendant(
      of: find.byType(SlushPressable),
      matching: find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).border != null,
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
    expect(ring, findsOneWidget);
  });

  testWidgets('Sin onTap: deshabilitado, no se hunde', (tester) async {
    await tester.pumpWidget(
      _app(
        child: SlushPressable(
          child: Container(
            key: const Key('face'),
            width: 100,
            height: 44,
            color: Slush.mint,
          ),
        ),
      ),
    );
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('face'))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final m = tester
        .widget<Transform>(find.byKey(SlushPressable.faceKey))
        .transform;
    expect(m.getTranslation().x, 0);
    await g.up();
  });

  testWidgets('SlushPill: alto 24 y texto legible sobre cualquier relleno', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(
        _app(
          b: b,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SlushPill('a'),
              SlushPill('b', color: Slush.violet),
              Builder(builder: (c) => SlushPill('c', color: c.slush.paper)),
            ],
          ),
        ),
      );
      for (final pill in tester.widgetList<SlushPill>(find.byType(SlushPill))) {
        expect(tester.getSize(find.byWidget(pill)).height, 24);
      }
    }
  });

  group('Tema: objetivos y componentes', () {
    for (final b in Brightness.values) {
      test('Slush $b: 44 px, anillo de foco y transición de sección', () {
        final t = slushTheme(b, Slush.lilac);
        final p = t.extension<SlushPalette>()!;
        expect(t.materialTapTargetSize, MaterialTapTargetSize.padded);
        expect(t.visualDensity, VisualDensity.standard);
        for (final s in [
          t.filledButtonTheme.style!,
          t.outlinedButtonTheme.style!,
          t.textButtonTheme.style!,
        ]) {
          expect(s.minimumSize!.resolve({}), const Size(0, 44));
        }
        final side = t.filledButtonTheme.style!.side!;
        expect(side.resolve({WidgetState.focused}), p.focusRing);
        expect(side.resolve({WidgetState.disabled})!.color, p.disabledBorder);
        expect(side.resolve({}), p.border);
        expect(t.inputDecorationTheme.focusedBorder!.borderSide, p.focusRing);
        expect(t.inputDecorationTheme.enabledBorder!.borderSide, p.borderSoft);
        expect(t.inputDecorationTheme.errorBorder!.borderSide.color, p.error);
        expect(t.dialogTheme.backgroundColor, p.raised);
        expect(t.bottomSheetTheme.backgroundColor, p.raised);
        expect(t.popupMenuTheme.color, p.raised);
        expect(t.dividerTheme.thickness, 1.5);
        expect(t.sliderTheme.thumbColor, p.violetAccent);
        expect(
          t.pageTransitionsTheme.builders[TargetPlatform.windows],
          isA<SlushPageTransitionsBuilder>(),
        );
      });
    }

    test('Curvas y duraciones del motion', () {
      expect(SlushMotion.easeOut, const Cubic(.23, 1, .32, 1));
      expect(SlushMotion.easeInOut, const Cubic(.77, 0, .175, 1));
      expect(SlushMotion.drawer, const Cubic(.32, .72, 0, 1));
      expect(SlushMotion.pressDown.inMilliseconds, 90);
      expect(SlushMotion.pressUp.inMilliseconds, 160);
      expect(SlushMotion.sectionIn.inMilliseconds, 220);
      expect(SlushMotion.sectionOut.inMilliseconds, 140);
    });

    test('Escalas: margen y hueco por ancho', () {
      expect(SlushSpacing.margin(360), 16);
      expect(SlushSpacing.margin(700), 24);
      expect(SlushSpacing.margin(1200), 32);
      expect(SlushSpacing.sectionGap(500), 24);
      expect(SlushSpacing.sectionGap(700), 32);
      expect(SlushSpacing.sectionGap(1000), 48);
    });
  });

  testWidgets('Transición de sección: reducido solo opacidad', (tester) async {
    for (final reduce in [false, true]) {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          theme: slushTheme(Brightness.light, Slush.lilac),
          builder: (context, c) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
            child: c!,
          ),
          home: const Scaffold(body: Text('a')),
        ),
      );
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('b')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final hasSlide = find
          .descendant(
            of: find.byType(Navigator),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Transform &&
                  w.transform.getTranslation().y.abs() > 0 &&
                  w.transform.getTranslation().y.abs() <= 8,
            ),
          )
          .evaluate()
          .isNotEmpty;
      expect(hasSlide, !reduce, reason: 'reduce=$reduce');
      await tester.pumpAndSettle();
    }
  });
}
