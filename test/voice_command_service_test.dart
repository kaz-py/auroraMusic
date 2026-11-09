import 'dart:io';

import 'package:aurora_music/bridge/api/voice.dart' as rust;
import 'package:aurora_music/remote/remote_control_server.dart';
import 'package:aurora_music/voice/voice_command_service.dart';
import 'package:aurora_music/voice/voice_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Actions implements RemoteControlActions {
  final calls = <String>[];
  Object? failure;
  Future<void> _r(String n) async {
    calls.add(n);
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<void> play() => _r('play');
  @override
  Future<void> pause() => _r('pause');
  @override
  Future<void> toggle() => _r('toggle');
  @override
  Future<void> next() => _r('next');
  @override
  Future<void> previous() => _r('previous');
  @override
  Future<Map<String, Object?>> startJam({String mode = 'auto'}) async => {};
  @override
  Map<String, Object?> status() => {};
}

class _Listener implements VoiceListenerPort {
  final queue = <rust.VoiceEvent>[];
  bool stopped = false;
  @override
  List<rust.VoiceEvent> poll() {
    final out = List.of(queue);
    queue.clear();
    return out;
  }

  double micLevel = 0.1;
  @override
  double get level => micLevel;
  @override
  bool get isRunning => !stopped;
  @override
  void stop() => stopped = true;
}

rust.VoiceEvent _command(rust.VoiceIntent i) =>
    rust.VoiceEvent(intent: i, wake: false);
const _wake = rust.VoiceEvent(wake: true);

void main() {
  late Directory dir;
  late _Actions actions;
  late _Listener listener;
  late List<String> log;
  var installed = false;

  Future<VoiceCommandService> create({
    Map<String, Object> prefs = const {},
    String? Function()? library,
    Future<void> Function(File, VoiceDownloadProgress)? download,
    bool supported = true,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return VoiceCommandService(
      await SharedPreferences.getInstance(),
      actions,
      supportDirectory: dir,
      supported: supported,
      pollEvery: const Duration(milliseconds: 10),
      silentAfter: const Duration(milliseconds: 150),
      libraryPath: library ?? () => 'libvosk.fake',
      modelInstalled: (_) => installed,
      download:
          download ??
          (file, progress) async {
            log.add('descarga');
            progress(0.5);
            await file.parent.create(recursive: true);
            await file.writeAsString('zip');
            progress(1);
          },
      installModel: (archive, dest) async {
        log.add('instala');
        installed = true;
      },
      startListener: (lib, model) async {
        log.add('escucha:$lib');
        return listener;
      },
    );
  }

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 60));

  setUp(() {
    dir = Directory.systemTemp.createTempSync('aurora_voice_');
    actions = _Actions();
    listener = _Listener();
    log = [];
    installed = false;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('is off by default and never touches the microphone', () async {
    final service = await create();
    await service.start();
    expect(service.enabled, isFalse);
    expect(service.state, VoiceState.off);
    expect(log, isEmpty);
    service.dispose();
  });

  test('enabling downloads the model once, then listens', () async {
    final service = await create();
    await service.setEnabled(true);
    expect(service.state, VoiceState.listening);
    expect(log, ['descarga', 'instala', 'escucha:libvosk.fake']);
    expect(
      File('${dir.path}/voice/${VoiceModel.name}.zip').existsSync(),
      isFalse,
      reason: 'el ZIP se borra tras instalar',
    );
    // Con el modelo ya instalado no vuelve a descargar.
    await service.setEnabled(false);
    log.clear();
    await service.setEnabled(true);
    expect(log, ['escucha:libvosk.fake']);
    service.dispose();
  });

  test('each spoken intent runs its action; wake alone runs nothing', () async {
    installed = true;
    final service = await create();
    await service.setEnabled(true);
    listener.queue.addAll([_wake]);
    await settle();
    expect(service.awaitingCommand, isTrue);
    expect(actions.calls, isEmpty);
    listener.queue.addAll([
      _command(rust.VoiceIntent.pause),
      _command(rust.VoiceIntent.resume),
      _command(rust.VoiceIntent.play),
      _command(rust.VoiceIntent.next),
      _command(rust.VoiceIntent.previous),
    ]);
    await settle();
    expect(actions.calls, ['pause', 'play', 'play', 'next', 'previous']);
    expect(service.awaitingCommand, isFalse);
    expect(service.lastCommand, 'Anterior');
    service.dispose();
  });

  test('a refused action is reported without stopping the listening', () async {
    installed = true;
    final service = await create();
    await service.setEnabled(true);
    actions.failure = const RemoteControlException(409, 'Lo controla Ana.');
    listener.queue.add(_command(rust.VoiceIntent.next));
    await settle();
    expect(service.error, 'Lo controla Ana.');
    expect(service.state, VoiceState.listening);
    service.dispose();
  });

  test(
    'a microphone that only delivers silence is flagged, and recovers',
    () async {
      installed = true;
      final service = await create();
      await service.setEnabled(true);
      listener.micLevel = 0;
      await settle();
      expect(service.microphoneSilent, isFalse, reason: 'aún es pronto');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(service.microphoneSilent, isTrue);
      listener.micLevel = 0.2;
      await settle();
      expect(service.microphoneSilent, isFalse);
      service.dispose();
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a lost microphone stops listening and says why', () async {
    installed = true;
    final service = await create();
    await service.setEnabled(true);
    listener.queue.add(
      const rust.VoiceEvent(wake: false, stopped: 'Sin micrófono.'),
    );
    await settle();
    expect(service.state, VoiceState.error);
    expect(service.error, 'Sin micrófono.');
    expect(listener.stopped, isTrue);
    service.dispose();
  });

  test('disabling releases the microphone and ignores later events', () async {
    installed = true;
    final service = await create();
    await service.setEnabled(true);
    await service.setEnabled(false);
    expect(listener.stopped, isTrue);
    expect(service.state, VoiceState.off);
    listener.queue.add(_command(rust.VoiceIntent.next));
    await settle();
    expect(actions.calls, isEmpty);
    service.dispose();
  });

  test('download and library failures become readable errors', () async {
    final failing = await create(
      download: (_, _) async =>
          throw const VoiceModelException('Sin conexión.'),
    );
    await failing.setEnabled(true);
    expect(failing.state, VoiceState.error);
    expect(failing.error, 'Sin conexión.');
    expect(log, isNot(contains(startsWith('escucha'))));
    failing.dispose();

    final noLibrary = await create(library: () => null);
    await noLibrary.setEnabled(true);
    expect(noLibrary.state, VoiceState.error);
    expect(noLibrary.error, contains('libvosk'));
    noLibrary.dispose();
  });

  test(
    'a saved enabled flag resumes listening on launch; unsupported never does',
    () async {
      installed = true;
      final resumed = await create(
        prefs: {VoiceCommandService.enabledKey: true},
      );
      await resumed.start();
      expect(resumed.state, VoiceState.listening);
      resumed.dispose();

      log.clear();
      final unsupported = await create(
        prefs: {VoiceCommandService.enabledKey: true},
        supported: false,
      );
      await unsupported.start();
      await unsupported.setEnabled(true);
      expect(unsupported.enabled, isFalse);
      expect(log, isEmpty);
      unsupported.dispose();
    },
  );
}
