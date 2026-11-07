import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_music/main.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/undo_snackbar.dart';

const _msg = 'Sonará a continuación';

/// Ancho de la tarjeta del aviso (el widget SnackBar ocupa todo el ancho).
double _snackWidth(WidgetTester tester) => tester
    .getSize(
      find.ancestor(of: find.text(_msg), matching: find.byType(Material)).first,
    )
    .width;

Future<void> _pump(WidgetTester tester, ThemeData theme, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => showUndoSnackBar(
                  ScaffoldMessenger.maybeOf(context),
                  const Text(_msg),
                  label: 'Deshacer',
                  onAction: () {},
                ),
                child: const Text('uno'),
              ),
              TextButton(
                onPressed: () => showUndoSnackBar(
                  ScaffoldMessenger.maybeOf(context),
                  const Text('segundo'),
                ),
                child: const Text('dos'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  final builders = <String, ThemeData Function(Brightness, Color)>{
    'atelier': auroraTheme,
    'modern': modernTheme,
    'brasa': brasaTheme,
    'slush': (b, c) => slushTheme(b, c),
  };
  for (final entry in builders.entries) {
    for (final b in Brightness.values) {
      final name = '${entry.key} ${b.name}';
      ThemeData theme() => entry.value(b, const Color(0xff4d7cff));

      testWidgets('$name: aviso con acción se cierra solo', (tester) async {
        await _pump(tester, theme(), const Size(1440, 900));
        await tester.tap(find.text('uno'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text(_msg), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text(_msg), findsNothing);
      });

      testWidgets('$name: ancho acotado y flotante', (tester) async {
        await _pump(tester, theme(), const Size(1440, 900));
        await tester.tap(find.text('uno'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_snackWidth(tester), lessThanOrEqualTo(420));

        await tester.pumpAndSettle(const Duration(seconds: 6));
        await _pump(tester, theme(), const Size(360, 640));
        await tester.tap(find.text('uno'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(_snackWidth(tester), lessThan(360));
      });

      testWidgets('$name: el segundo aviso sustituye al primero', (
        tester,
      ) async {
        await _pump(tester, theme(), const Size(1440, 900));
        await tester.tap(find.text('uno'));
        await tester.pump();
        await tester.tap(find.text('dos'));
        await tester.pumpAndSettle();
        expect(find.text(_msg), findsNothing);
        expect(find.text('segundo'), findsOneWidget);
      });
    }
  }
}
