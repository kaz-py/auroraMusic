import 'package:aurora_music/core/online_status.dart';
import 'package:aurora_music/online/online_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'el interruptor pasa a modo local y «comprobar» detecta el servidor',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var up = false;
      final status = OnlineStatus(
        preferences: prefs,
        enabled: true,
        probe: (_) async => up,
      );
      addTearDown(status.dispose);
      String statusText() => tester
          .widget<Text>(find.byKey(const ValueKey('online-status')))
          .data!;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OnlineSettings(status: status)),
        ),
      );
      await tester.runAsync(() => status.available());
      await tester.pump();
      expect(statusText(), contains('no responde'));

      up = true;
      await tester.tap(find.byKey(const ValueKey('online-check')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(statusText(), contains('El servidor responde'));

      await tester.tap(find.byKey(const ValueKey('online-switch')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      expect(status.mode, OnlineMode.off);
      expect(statusText(), contains('Modo local'));
      expect(find.byKey(const ValueKey('online-check')), findsNothing);
    },
  );
}
