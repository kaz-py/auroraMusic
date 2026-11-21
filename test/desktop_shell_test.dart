import 'package:aurora_music/core/desktop_shell.dart';
import 'package:aurora_music/core/models.dart';
import 'support/fakes.dart';
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

  group('DesktopShell en Linux', () {
    const channel = MethodChannel('aurora/window');
    late List<MethodCall> calls;
    final a = Track(
      id: 'a',
      title: 'Uno',
      artist: 'Artista A',
      pageUrl: 'https://youtu.be/a',
    );
    final b = Track(
      id: 'b',
      title: 'Dos',
      artist: 'Artista B',
      pageUrl: 'https://youtu.be/b',
    );

    setUp(() {
      calls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (c) async {
            calls.add(c);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    });

    List<MethodCall> playbackCalls() =>
        calls.where((c) => c.method == 'setPlayback').toList();

    test('está soportado en Linux', () {
      expect(DesktopShell.supported, isTrue);
    });

    test(
      'start envía closeToTray (true por defecto) y la pista vacía',
      () async {
        final controller = await createTestController();
        addTearDown(() => closeTestController(controller));
        final shell = DesktopShell(controller)..start();
        addTearDown(shell.dispose);
        await pumpEventQueue();
        final close = calls.singleWhere((c) => c.method == 'setCloseToTray');
        expect(close.arguments, true);
        expect(playbackCalls().single.arguments, {
          'playing': false,
          'title': '',
          'artist': '',
        });
      },
    );

    test('start respeta una preferencia closeToTray guardada', () async {
      final controller = await createTestController(
        preferences: {'closeToTray': false},
      );
      addTearDown(() => closeTestController(controller));
      final shell = DesktopShell(controller)..start();
      addTearDown(shell.dispose);
      await pumpEventQueue();
      expect(
        calls.singleWhere((c) => c.method == 'setCloseToTray').arguments,
        false,
      );
      expect(shell.closeToTray, isFalse);
    });

    test(
      'setPlayback solo se reenvía si cambia título, artista o playing',
      () async {
        final controller = await createTestController();
        addTearDown(() => closeTestController(controller));
        final shell = DesktopShell(controller)..start();
        addTearDown(shell.dispose);
        await controller.playTrack(a, context: [a, b]);
        await pumpEventQueue();
        final afterPlay = playbackCalls().length;
        expect(playbackCalls().last.arguments, {
          'playing': true,
          'title': 'Uno',
          'artist': 'Artista A',
        });
        // Aviso sin cambios relevantes: no se reenvía.
        (controller.audio as FakeAudio).advanceTo(const Duration(seconds: 5));
        controller.notifyListeners();
        await pumpEventQueue();
        expect(playbackCalls().length, afterPlay);
        // Pausa: cambia playing.
        await controller.pausePlayback();
        await pumpEventQueue();
        expect(playbackCalls().length, afterPlay + 1);
        expect(playbackCalls().last.arguments['playing'], false);
        // Otra pista: cambia título y artista.
        await controller.playTrack(b, context: [a, b]);
        await pumpEventQueue();
        expect(playbackCalls().last.arguments, {
          'playing': true,
          'title': 'Dos',
          'artist': 'Artista B',
        });
      },
    );

    test('setCloseToTray guarda la preferencia y avisa al nativo', () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      final shell = DesktopShell(controller)..start();
      addTearDown(shell.dispose);
      await pumpEventQueue();
      calls.clear();
      await shell.setCloseToTray(false);
      expect(controller.preferences.getBool('closeToTray'), isFalse);
      expect(shell.closeToTray, isFalse);
      expect(calls.single.method, 'setCloseToTray');
      expect(calls.single.arguments, false);
    });

    test('acciones de bandeja: playPause, next y previous', () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      final audio = controller.audio as FakeAudio;
      final shell = DesktopShell(controller)..start();
      addTearDown(shell.dispose);
      await controller.playTrack(a, context: [a, b]);
      expect(audio.isPlaying, isTrue);

      WindowControls.onTrayAction!('playPause');
      await pumpEventQueue();
      expect(audio.isPlaying, isFalse, reason: 'sonando: pausa');

      WindowControls.onTrayAction!('playPause');
      await pumpEventQueue();
      expect(audio.isPlaying, isTrue, reason: 'en pausa: reanuda');

      WindowControls.onTrayAction!('next');
      await pumpEventQueue();
      expect(controller.currentTrack?.id, 'b');

      audio.position = Duration.zero;
      WindowControls.onTrayAction!('previous');
      await pumpEventQueue();
      expect(controller.currentTrack?.id, 'a');
    });

    test('dispose deja de escuchar y quita los manejadores', () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      final shell = DesktopShell(controller)..start();
      await pumpEventQueue();
      expect(WindowControls.onTrayAction, isNotNull);
      expect(WindowControls.onRealExit, isNotNull);
      shell.dispose();
      expect(WindowControls.onTrayAction, isNull);
      expect(WindowControls.onRealExit, isNull);
      calls.clear();
      await controller.playTrack(a, context: [a]);
      await pumpEventQueue();
      expect(playbackCalls(), isEmpty);
    });
  }, skip: !Platform.isLinux);
}
