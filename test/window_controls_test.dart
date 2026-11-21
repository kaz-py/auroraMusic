import 'dart:async';
import 'dart:io';

import 'package:aurora_music/core/window_controls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('aurora/window');

TestDefaultBinaryMessenger get _messenger =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

/// Simula una llamada del nativo hacia Dart y devuelve la respuesta decodificada.
Future<Object?> _fromNative(String method, Object? arguments) async {
  final done = Completer<Object?>();
  await _messenger.handlePlatformMessage(
    'aurora/window',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    (data) => done.complete(
      data == null ? null : const StandardMethodCodec().decodeEnvelope(data),
    ),
  );
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _messenger.setMockMethodCallHandler(_channel, null);
    WindowControls.onTrayAction = null;
    WindowControls.onRealExit = null;
    WindowControls.onArguments = null;
  });

  group('plataforma Linux', () {
    test('la bandeja está soportada y la barra propia no', () {
      expect(WindowControls.traySupported, isTrue);
      expect(WindowControls.supported, isFalse);
    });

    test('invoke devuelve true si el nativo responde con éxito', () async {
      final calls = <MethodCall>[];
      _messenger.setMockMethodCallHandler(_channel, (c) async {
        calls.add(c);
        return 'ok';
      });
      expect(await WindowControls.invoke('setCloseToTray', true), isTrue);
      expect(calls.single.method, 'setCloseToTray');
      expect(calls.single.arguments, true);
    });

    test('invoke da false sin lanzar si no hay manejador nativo', () async {
      for (final op in [
        'setMini',
        'setFullscreen',
        'setBackground',
        'getAutostart',
      ]) {
        expect(await WindowControls.invoke(op), isFalse, reason: op);
      }
    });

    test(
      'invoke da false sin lanzar si el nativo no implementa el método',
      () async {
        _messenger.setMockMethodCallHandler(_channel, (c) async {
          throw MissingPluginException();
        });
        expect(
          await WindowControls.invoke('setMini', {'enabled': true}),
          isFalse,
        );
        expect(
          await WindowControls.invoke('setFullscreen', {'enabled': true}),
          isFalse,
        );
      },
    );

    test(
      'invoke da false sin lanzar si el nativo responde PlatformException',
      () async {
        _messenger.setMockMethodCallHandler(_channel, (c) async {
          throw PlatformException(code: 'boom', message: 'fallo nativo');
        });
        expect(await WindowControls.invoke('setBackground', 0xFFFFFF), isFalse);
      },
    );

    test('query devuelve el booleano del nativo', () async {
      var answer = true;
      _messenger.setMockMethodCallHandler(_channel, (c) async {
        expect(c.method, 'trayAvailable');
        return answer;
      });
      expect(await WindowControls.query('trayAvailable'), isTrue);
      answer = false;
      expect(await WindowControls.query('trayAvailable'), isFalse);
    });

    test('query da false si no está implementado o falla', () async {
      expect(await WindowControls.query('getAutostart'), isFalse);
      _messenger.setMockMethodCallHandler(_channel, (c) async => null);
      expect(await WindowControls.query('getAutostart'), isFalse);
      _messenger.setMockMethodCallHandler(_channel, (c) async {
        throw PlatformException(code: 'x');
      });
      expect(await WindowControls.query('trayAvailable'), isFalse);
    });
  }, skip: !Platform.isLinux);

  group(
    'llamadas del nativo hacia Dart',
    () {
      setUp(WindowControls.install);

      test('trayAction reenvía playPause, next y previous', () async {
        final actions = <String>[];
        WindowControls.onTrayAction = actions.add;
        for (final a in ['playPause', 'next', 'previous']) {
          await _fromNative('trayAction', a);
        }
        expect(actions, ['playPause', 'next', 'previous']);
      });

      test(
        'confirmClose con true llama a onRealExit y responde true',
        () async {
          var exits = 0;
          WindowControls.onRealExit = () async => exits++;
          expect(await _fromNative('confirmClose', true), true);
          expect(exits, 1);
        },
      );

      test('confirmClose con false no sale pero responde true', () async {
        var exits = 0;
        WindowControls.onRealExit = () async => exits++;
        expect(await _fromNative('confirmClose', false), true);
        expect(exits, 0);
      });

      test('arguments entrega el texto a onArguments', () async {
        String? got;
        WindowControls.onArguments = (a) => got = a;
        await _fromNative('arguments', 'aurora://jam/ABC123');
        expect(got, 'aurora://jam/ABC123');
      });
    },
    skip: !Platform.isLinux && !Platform.isWindows,
  );
}
