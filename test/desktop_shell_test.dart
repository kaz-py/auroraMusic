import 'package:aurora_music/core/desktop_shell.dart';
import 'package:aurora_music/core/window_controls.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('la X minimiza a la bandeja por defecto y respeta el ajuste', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(CloseBehavior.read(prefs), isTrue);
    await prefs.setBool(CloseBehavior.key, false);
    expect(CloseBehavior.read(prefs), isFalse);
  });

  test('sin ventana nativa las llamadas fallan sin lanzar', () async {
    expect(await WindowControls.invoke('setCloseToTray', true), isFalse);
    expect(await WindowControls.query('getAutostart'), isFalse);
    expect(await WindowControls.requestHardExit(), isFalse);
  });

  test(
    'canal de ventana: envía el ajuste y la salida real detiene el audio',
    () async {
      const channel = MethodChannel('aurora/window');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      expect(await WindowControls.invoke('setCloseToTray', false), isTrue);
      expect(calls.single.method, 'setCloseToTray');
      expect(calls.single.arguments, false);

      // Cierre real (Alt+F4 / Salir): Dart pausa el audio; la X a la bandeja no.
      var stopped = 0;
      WindowControls.onRealExit = () async => stopped++;
      WindowControls.install();
      Future<Object?> native(Object? arg) async {
        final done = Completer<Object?>();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'aurora/window',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('confirmClose', arg),
              ),
              (data) => done.complete(
                const StandardMethodCodec().decodeEnvelope(data!),
              ),
            );
        return done.future;
      }

      expect(await native(true), true);
      expect(stopped, 1);
      expect(await native(false), true);
      expect(stopped, 1);
    },
    skip: !Platform.isWindows,
  );
}
