import 'dart:async';
import 'dart:io';

import 'package:aurora_music/bridge/api/voice.dart' as rust;
import 'package:aurora_music/remote/remote_control_server.dart';
import 'package:aurora_music/voice/voice_command_service.dart';
import 'package:aurora_music/voice/voice_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    Future<void> Function(File, VoiceDownloadProgress)? download,
    bool supported = true,
    bool cpu = true,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    return VoiceCommandService(
      await SharedPreferences.getInstance(),
      actions,
      supportDirectory: dir,
      supported: supported,
      cpuSupported: () => cpu,
      pollEvery: const Duration(milliseconds: 10),
      silentAfter: const Duration(milliseconds: 150),
      modelReady: (_) => installed,
      download:
          download ??
          (file, progress) async {
            log.add('descarga');
            progress(0.5);
            installed = true;
            progress(1);
          },
      startListener: (model) async {
        log.add('escucha:${p.basename(model)}');
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
    expect(log, ['descarga', 'escucha:${VoiceModel.name}']);
    // Con el modelo ya descargado no vuelve a descargar.
    await service.setEnabled(false);
    log.clear();
    await service.setEnabled(true);
    expect(log, ['escucha:${VoiceModel.name}']);
    service.dispose();
  });

  test('diagnostics is opt-in and restarts the listening to apply', () async {
    installed = true;
    final service = await create();
    expect(service.diagnosticsEnabled, isFalse);
    await service.setEnabled(true);
    await service.setDiagnostics(true);
    expect(service.diagnosticsEnabled, isTrue);
    expect(log, ['escucha:${VoiceModel.name}', 'escucha:${VoiceModel.name}']);
    expect(
      p.isWithin(dir.path, service.diagnosticsDirectory.path),
      isTrue,
      reason: 'solo escribe dentro de su carpeta de datos',
    );
    service.dispose();
  });

  test('a download that leaves no valid model is an error', () async {
    final service = await create(download: (_, _) async {});
    await service.setEnabled(true);
    expect(service.state, VoiceState.error);
    expect(service.error, contains('modelo'));
    expect(log, isEmpty);
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

  test('what Whisper heard is exposed, command or not', () async {
    installed = true;
    final service = await create();
    await service.setEnabled(true);
    expect(service.lastHeard, isNull);
    listener.queue.add(const rust.VoiceEvent(wake: false, heard: ' hola '));
    await settle();
    expect(service.lastHeard, 'hola');
    expect(service.lastHeardAt, isNotNull);
    expect(actions.calls, isEmpty);
    listener.queue.add(
      const rust.VoiceEvent(
        intent: rust.VoiceIntent.next,
        wake: false,
        heard: 'aurora siguiente',
      ),
    );
    await settle();
    expect(service.lastHeard, 'aurora siguiente');
    expect(actions.calls, ['next']);
    await service.setEnabled(false);
    expect(service.lastHeard, isNull);
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

  test('download failures become readable errors', () async {
    final failing = await create(
      download: (_, _) async =>
          throw const VoiceModelException('Sin conexión.'),
    );
    await failing.setEnabled(true);
    expect(failing.state, VoiceState.error);
    expect(failing.error, 'Sin conexión.');
    expect(log, isEmpty);
    failing.dispose();
  });

  test('a CPU without AVX2 refuses to listen, download or analyse', () async {
    final service = await create(cpu: false);
    await service.setEnabled(true);
    expect(service.state, VoiceState.error);
    expect(service.error, contains('AVX2'));
    expect(log, isEmpty);
    expect(service.analysisReady, isFalse);

    await service.setLyricsSync(true);
    expect(service.modelError, contains('AVX2'));
    expect(log, isEmpty);
    service.dispose();
  });

  test('lyrics sync downloads the model without listening', () async {
    final service = await create();
    expect(service.analysisReady, isFalse);
    await service.setLyricsSync(true);
    expect(log, ['descarga']);
    expect(service.modelBusy, isFalse);
    expect(service.modelError, isNull);
    expect(service.analysisReady, isTrue);
    expect(service.modelPath, endsWith(VoiceModel.name));
    service.dispose();
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

  group('downloadVerified', () {
    final payload = List<int>.generate(1000, (i) => i % 251);
    final good = sha256.convert(payload).toString();

    Future<void> run(
      Uri url,
      File target, {
      String? sha,
      List<int>? body,
      int status = 200,
    }) => downloadVerified(
      url,
      target,
      expectedBytes: payload.length,
      expectedSha256: sha ?? good,
      clientFactory: () => _FakeClient(body ?? payload, status),
    );

    test('refuses plain http without touching the disk', () async {
      final target = File('${dir.path}/voice/m.bin');
      await expectLater(
        run(Uri.parse('http://example.com/m.bin'), target),
        throwsA(
          isA<VoiceModelException>().having(
            (e) => e.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
      expect(target.existsSync(), isFalse);
      expect(File('${target.path}.part').existsSync(), isFalse);
      expect(target.parent.existsSync(), isFalse);
    });

    test('writes .part and renames to the final name once verified', () async {
      final target = File('${dir.path}/voice/m.bin');
      await run(Uri.parse('https://example.com/m.bin'), target);
      expect(target.readAsBytesSync(), payload);
      expect(File('${target.path}.part').existsSync(), isFalse);
    });

    test(
      'a corrupt, short or oversized body never becomes the model',
      () async {
        final target = File('${dir.path}/voice/m.bin');
        final url = Uri.parse('https://example.com/m.bin');
        // Uno tras otro: comparten el mismo archivo de destino.
        for (final bad in <Future<void> Function()>[
          () => run(url, target, sha: '0' * 64),
          () => run(url, target, body: payload.sublist(0, 10)),
          () => run(url, target, body: [...payload, 1]),
          () => run(url, target, status: 404),
        ]) {
          await expectLater(bad(), throwsA(isA<VoiceModelException>()));
          expect(target.existsSync(), isFalse);
          expect(File('${target.path}.part').existsSync(), isFalse);
        }
      },
    );
  });
}

class _FakeClient implements HttpClient {
  _FakeClient(this.body, this.status);
  final List<int> body;
  final int status;

  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeRequest(_FakeResponse(body, status));
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.response);
  final HttpClientResponse response;
  @override
  Future<HttpClientResponse> close() async => response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.body, this.statusCode);
  final List<int> body;
  @override
  final int statusCode;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.fromIterable([
        body.sublist(0, body.length ~/ 2),
        body.sublist(body.length ~/ 2),
      ]).listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
