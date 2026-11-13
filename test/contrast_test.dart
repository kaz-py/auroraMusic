import 'dart:math';
import 'dart:ui' show PointerDeviceKind;

import 'package:aurora_music/theme/atelier_theme.dart';
import 'package:aurora_music/ui/aurora_states.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (max(x, y) + .05) / (min(x, y) + .05);
}

Color over(Color top, Color base) => Color.alphaBlend(top, base);

const accents = <Color>[
  Color(0xffe86927), // default orange
  Color(0xff3478c8),
  Color(0xff28734a),
  Color(0xff7047a3),
  Color(0xffc45c2b),
  Color(0xffa66b00),
  Color(0xffffff00),
  Color(0xff00ffff),
  Color(0xffffffff),
  Color(0xff202020),
];

/// Every (token, background, minimum ratio) pair that matters for states.
List<(String, double, double)> audit(Brightness b, Color accent) {
  final theme = auroraTheme(b, accent);
  final s = theme.colorScheme;
  final st = theme.extension<AuroraStates>()!;
  final out = <(String, double, double)>[];
  void add(String name, Color fg, Color bg, double min) =>
      out.add((name, ratio(fg, bg), min));
  final surfaces = {
    'surface': s.surface,
    'low': s.surfaceContainerLow,
    'mid': s.surfaceContainer,
    'high': s.surfaceContainerHigh,
  };
  surfaces.forEach((n, bg) {
    final hov = over(st.hover, bg), sel = over(st.selected, bg);
    final pre = over(st.pressed, bg);
    add('text/$n', s.onSurface, bg, 4.5);
    add('secondary/$n', s.onSurfaceVariant, bg, 4.5);
    add('outline/$n', s.outline, bg, 3);
    add('focusRing/$n', st.focusRing, bg, 3);
    add('disabled/$n', st.disabledText, bg, 3);
    add('hover-vs-rest/$n', hov, bg, 1.2);
    add('selected-vs-rest/$n', sel, bg, 1.3);
    add('pressed-vs-rest/$n', pre, bg, 1.4);
    add('secondary-on-hover/$n', s.onSurfaceVariant, hov, 4.5);
    add('text-on-selected/$n', st.onSelected, sel, 4.5);
    add('secondary-on-selected/$n', s.onSurfaceVariant, sel, 4.5);
    add('bar-on-selected/$n', st.selectedBar, sel, 3);
    add('icon-on-selected/$n', st.selectedBar, sel, 3);
  });
  add(
    'onPrimaryContainer/primaryContainer',
    s.onPrimaryContainer,
    s.primaryContainer,
    4.5,
  );
  return out;
}

void main() {
  test('state tokens meet contrast thresholds in both themes and accents', () {
    final fails = <String>[];
    for (final b in Brightness.values) {
      for (final a in accents) {
        for (final (name, r, min) in audit(b, a)) {
          if (r < min) {
            fails.add(
              '$b ${a.toARGB32().toRadixString(16)} $name '
              '${r.toStringAsFixed(2)} < $min',
            );
          }
        }
      }
    }
    expect(fails, isEmpty, reason: fails.take(40).join('\n'));
  });

  testWidgets('hover and selection change the row colour, focus shows ring', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      final theme = auroraTheme(b, const Color(0xffe86927));
      final st = theme.extension<AuroraStates>()!;
      final focus = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Column(
              children: [
                ListTile(
                  key: const Key('rest'),
                  title: const Text('a'),
                  onTap: () {},
                ),
                ListTile(
                  key: const Key('sel'),
                  selected: true,
                  title: const Text('b'),
                  onTap: () {},
                ),
                TextButton(
                  focusNode: focus,
                  onPressed: () {},
                  child: const Text('x'),
                ),
              ],
            ),
          ),
        ),
      );
      final rest = tester.getCenter(find.byKey(const Key('rest')));
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(rest);
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(find.byKey(const Key('rest')));
      expect(theme.hoverColor, st.hover);
      expect(tile.selected, isFalse);
      expect(theme.listTileTheme.selectedTileColor, st.selected);
      expect(
        ratio(
          over(st.selected, theme.colorScheme.surface),
          theme.colorScheme.surface,
        ),
        greaterThan(1.3),
      );
      // Keyboard focus: the text button receives the focus overlay.
      focus.requestFocus();
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpAndSettle();
      expect(focus.hasPrimaryFocus, isTrue);
      final overlay = theme.textButtonTheme.style!.overlayColor!.resolve({
        WidgetState.focused,
      });
      expect(overlay, isNotNull);
      expect(overlay!.a, greaterThan(.2));
      final outlined = theme.outlinedButtonTheme.style!.side!.resolve({
        WidgetState.focused,
      })!;
      expect(outlined.width, 2);
      expect(outlined.color, st.focusRing);
      await gesture.removePointer();
      focus.dispose();
    }
  });
}
