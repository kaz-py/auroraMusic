import 'dart:io';

import 'package:aurora_music/audio/eq_model.dart';
import 'package:aurora_music/audio/music_audio.dart';
import 'package:aurora_music/audio/rust_music_audio.dart';
import 'package:aurora_music/bridge/api/playback.dart' as rust;
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _media = 'rust/crates/aurora_audio/tests/fixtures/media';

/// Motor anterior simulado: registra lo que se le pide.
class _FakeLegacy extends MusicAudio {
  final calls = <String>[];
  @override
  Future<void> initialize() async => calls.add('initialize');
  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async => calls.add('load ${source.input} $start');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> stop() async => calls.add('stop');
  @override
  void setVolume(double volume) => calls.add('volume $volume');
  @override
  void setEqualizer(bool e, List<EqBand> b, {bool autoPreamp = true}) =>
      calls.add('eq $e');
  @override
  void setVisualizationEnabled(bool enabled) {}
  @override
  // ignore: must_call_super
  void dispose() {}
}

String _file(String name) => File('$_media/$name').absolute.path;

Future<void> _until(bool Function() done, {int seconds = 10}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  _bufferingAfterSeek();
  _deviceLoss();
  late RustMusicAudio audio;
  late _FakeLegacy legacy;

  setUp(() async {
    legacy = _FakeLegacy();
    audio = RustMusicAudio(
      legacy: legacy,
      engineFactory: () => rust.PlayerEngine.createSilent(sampleRate: 48000),
    );
    await audio.initialize();
  });
  tearDown(() => audio.dispose());

  test('plays a local file to the end and reports completion once', () async {
    var completed = 0;
    audio.completed.listen((_) => completed++);
    await audio.load(
      ResolvedAudio(input: _file('tone.wav'), duration: Duration.zero),
    );
    expect(audio.duration.inMilliseconds, closeTo(2000, 60));
    await audio.play();
    expect(audio.isPlaying, isTrue);
    await _until(() => completed > 0);
    expect(completed, 1);
    expect(audio.isPlaying, isFalse);
    expect(audio.lastError, isNull);
    expect(audio.position.inMilliseconds, closeTo(2000, 60));
    expect(legacy.calls, isEmpty, reason: 'no debe tocar el motor anterior');
  });

  test('pause holds the position and seek restarts from the target', () async {
    await audio.load(
      ResolvedAudio(input: _file('tone-opus.webm'), duration: Duration.zero),
    );
    await audio.play();
    await _until(() => audio.position > const Duration(milliseconds: 300));
    await audio.pause();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final held = audio.position;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(audio.position, held);
    expect(audio.isPlaying, isFalse);

    await audio.seek(const Duration(milliseconds: 1500));
    expect(audio.position.inMilliseconds, closeTo(1500, 100));
    await audio.play();
    await _until(() => !audio.isPlaying);
    expect(audio.position.inMilliseconds, closeTo(2000, 100));
  });

  test('a seek during play resumes playback', () async {
    await audio.load(
      ResolvedAudio(input: _file('tone.mp3'), duration: Duration.zero),
    );
    await audio.play();
    await audio.seek(const Duration(milliseconds: 500));
    expect(audio.isPlaying, isTrue);
  });

  test('unsupported inputs fall back to the previous engine', () async {
    await audio.load(
      ResolvedAudio(
        input: 'https://example.com/clip.mp3',
        duration: const Duration(minutes: 3),
      ),
    );
    expect(legacy.calls, contains('initialize'));
    expect(legacy.calls.any((c) => c.startsWith('load https://')), isTrue);
    await audio.play();
    expect(legacy.calls, contains('play'));
    // Volume and EQ reach the legacy engine once it exists.
    audio.setVolume(0.3);
    expect(legacy.calls, contains('volume 0.3'));
  });

  test(
    'a missing file reports the error and keeps the engine usable',
    () async {
      await expectLater(
        audio.load(
          ResolvedAudio(input: _file('nope.mp3'), duration: Duration.zero),
        ),
        throwsStateError,
      );
      expect(audio.lastError, isNotNull);
      await audio.load(
        ResolvedAudio(input: _file('tone.wav'), duration: Duration.zero),
      );
      expect(audio.lastError, isNull);
    },
  );

  test('raw YouTube URLs never reach the decoder', () {
    expect(
      () => audio.load(
        ResolvedAudio(
          input: 'https://rr1.googlevideo.com/videoplayback?x=1',
          duration: Duration.zero,
        ),
      ),
      throwsStateError,
    );
    expect(legacy.calls, isEmpty);
  });

  test(
    'without an output device everything goes to the previous engine',
    () async {
      final fallback = _FakeLegacy();
      final noDevice = RustMusicAudio(
        legacy: fallback,
        engineFactory: () => throw StateError('sin dispositivo'),
      );
      addTearDown(noDevice.dispose);
      await noDevice.initialize();
      expect(noDevice.rustUnavailableReason, contains('sin dispositivo'));
      await noDevice.load(
        ResolvedAudio(input: _file('tone.wav'), duration: Duration.zero),
      );
      expect(fallback.calls.any((c) => c.startsWith('load ')), isTrue);
    },
  );
}

void _bufferingAfterSeek() {
  late RustMusicAudio audio;
  setUp(() async {
    audio = RustMusicAudio(
      legacy: _FakeLegacy(),
      engineFactory: () => rust.PlayerEngine.createSilent(sampleRate: 48000),
    );
    await audio.initialize();
  });
  tearDown(() => audio.dispose());

  test('the loading flag clears after seeking over the local proxy', () async {
    final bytes = File('$_media/tone-opus.webm').readAsBytesSync();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final range = request.headers.value('range');
      final start = range == null
          ? 0
          : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      final body = bytes.sublist(start);
      request.response
        ..statusCode = start > 0 ? 206 : 200
        ..headers.set('Accept-Ranges', 'bytes')
        ..headers.contentLength = body.length;
      if (start > 0) {
        request.response.headers.set(
          'Content-Range',
          'bytes $start-${bytes.length - 1}/${bytes.length}',
        );
      }
      request.response.add(body);
      await request.response.close();
    });
    await audio.load(
      ResolvedAudio(
        input: 'http://127.0.0.1:${server.port}/audio',
        duration: const Duration(seconds: 2),
      ),
    );
    await audio.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final target in [900, 400, 1300]) {
      await audio.seek(Duration(milliseconds: target));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(audio.isPlaying, isTrue);
      expect(audio.isBuffering, isFalse, reason: 'tras saltar a $target ms');
    }
  });

  test('the loading flag clears after seeking while playing', () async {
    await audio.load(
      ResolvedAudio(input: _file('tone-opus.webm'), duration: Duration.zero),
    );
    await audio.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final target in [900, 400, 1300]) {
      await audio.seek(Duration(milliseconds: target));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(audio.isPlaying, isTrue);
      expect(audio.isBuffering, isFalse, reason: 'tras saltar a $target ms');
    }
  });
}

void _deviceLoss() {
  test('a lost output device is reopened and playback continues', () async {
    final engines = <rust.PlayerEngine>[];
    final audio = RustMusicAudio(
      legacy: _FakeLegacy(),
      engineFactory: () {
        final engine = rust.PlayerEngine.createSilent(sampleRate: 48000);
        engines.add(engine);
        return engine;
      },
    );
    addTearDown(audio.dispose);
    await audio.initialize();
    await audio.load(
      ResolvedAudio(input: _file('tone-opus.webm'), duration: Duration.zero),
    );
    await audio.play();
    await _until(() => audio.position > const Duration(milliseconds: 400));
    final before = audio.position;
    engines.first.simulateDeviceLoss();
    await _until(() => engines.length == 2);
    expect(engines, hasLength(2));
    await _until(
      () =>
          audio.isPlaying &&
          audio.position > before + const Duration(milliseconds: 200),
    );
    expect(audio.isPlaying, isTrue);
    expect(audio.position, greaterThan(before));
    expect(audio.lastError, isNull);
  });

  test(
    'losing the device with no replacement falls back to the old engine',
    () async {
      var created = 0;
      final engines = <rust.PlayerEngine>[];
      final legacy = _FakeLegacy();
      final audio = RustMusicAudio(
        legacy: legacy,
        engineFactory: () {
          if (created++ > 0) throw StateError('sin dispositivo');
          final engine = rust.PlayerEngine.createSilent(sampleRate: 48000);
          engines.add(engine);
          return engine;
        },
      );
      addTearDown(audio.dispose);
      await audio.initialize();
      await audio.load(
        ResolvedAudio(input: _file('tone-opus.webm'), duration: Duration.zero),
      );
      await audio.play();
      await _until(() => audio.position > const Duration(milliseconds: 300));
      engines.single.simulateDeviceLoss();
      await _until(() => legacy.calls.any((c) => c.startsWith('load ')));
      expect(legacy.calls.any((c) => c.startsWith('load ')), isTrue);
    },
  );
}
