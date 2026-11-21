// ModernAura: el fundido de colores solo corre al cambiar de pista; reconstruir
// con la misma pista (varias veces por segundo al reproducir) no anima nada.
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/modern_cristal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

const _track = Track(id: 'a', title: 'Tema', artist: 'Artista');

Widget _host({
  required Track? track,
  required int n,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: ModernAura(track: track, child: Text('pos $n')),
    ),
  );
}

Future<void> _rebuildMany(
  WidgetTester tester,
  Track? track, {
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    _host(track: track, n: 0, disableAnimations: disableAnimations),
  );
  await tester.pump(const Duration(milliseconds: 800));
  expect(tester.hasRunningAnimations, isFalse);
  for (var i = 1; i <= 10; i++) {
    await tester.pumpWidget(
      _host(track: track, n: i, disableAnimations: disableAnimations),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isFalse, reason: 'rebuild $i');
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  }
  expect(find.text('pos 10'), findsOneWidget);
}

void main() {
  testWidgets('misma pista reconstruida varias veces no anima', (tester) async {
    await _rebuildMany(tester, _track);
  });

  testWidgets('track null reconstruido varias veces no anima', (tester) async {
    await _rebuildMany(tester, null);
  });

  testWidgets('con disableAnimations tampoco anima al reconstruir', (
    tester,
  ) async {
    await _rebuildMany(tester, _track, disableAnimations: true);
  });

  testWidgets('pista distinta con mismos colores no anima', (tester) async {
    await tester.pumpWidget(_host(track: _track, n: 0));
    await tester.pump(const Duration(milliseconds: 800));
    const other = Track(id: 'b', title: 'Otro', artist: 'Artista');
    await tester.pumpWidget(_host(track: other, n: 1));
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
