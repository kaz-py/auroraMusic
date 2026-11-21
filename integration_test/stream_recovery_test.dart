import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurora_music/audio/rust_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _toolsDirectory = String.fromEnvironment('AURORA_TOOLS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final seconds in [2, 130]) {
    testWidgets(
      'HTTP FFmpeg stream: ${seconds}s clean EOF completes naturally',
      (tester) async {
        final passed = await tester.runAsync(() async {
          final fixture = await _wavFixture(seconds: seconds);
          final server = await _LoopbackServer.start((request) async {
            request.response.headers.contentType = ContentType('audio', 'wav');
            request.response
              ..statusCode = HttpStatus.ok
              ..add(fixture.bytes);
            await request.response.close();
          });
          final audio = RustMusicAudio();
          try {
            await _initialize(audio);
            final completed = Completer<void>();
            var queueIndex = 0;
            final subscription = audio.completed.listen((_) {
              queueIndex++;
              if (!completed.isCompleted) completed.complete();
            });
            try {
              await audio.load(
                ResolvedAudio(
                  input: server.url,
                  duration: Duration(seconds: seconds),
                ),
              );
              await audio.play();
              if (seconds > 120) {
                await Future<void>.delayed(const Duration(seconds: 122));
                expect(queueIndex, 0);
                expect(audio.isPlaying, isTrue);
                expect(
                  audio.position,
                  greaterThan(const Duration(seconds: 120)),
                );
                expect(audio.lastError, isNull);
              }
              await completed.future.timeout(const Duration(seconds: 12));
              expect(queueIndex, 1);
              expect(audio.lastError, isNull);
              expect(audio.isPlaying, isFalse);
            } finally {
              await subscription.cancel();
            }
          } finally {
            await _dispose(audio);
            await server.close();
            await fixture.directory.delete(recursive: true);
          }
          return true;
        });
        expect(passed, isTrue);
      },
      timeout: const Timeout(Duration(seconds: 165)),
    );
  }

  testWidgets(
    'HTTP FFmpeg stream: truncated response errors without completion',
    (tester) async {
      final passed = await tester.runAsync(() async {
        // The WAV header advertises eight seconds, but the peer sends only two.
        final fixture = await _wavFixture(seconds: 2, declaredSeconds: 8);
        final server = await _LoopbackServer.start((request) async {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = fixture.bytes.length;
          request.response.add(fixture.bytes);
          await request.response.close();
        });
        final audio = RustMusicAudio();
        try {
          await _initialize(audio);
          var completions = 0;
          var queueIndex = 0;
          final subscription = audio.completed.listen((_) {
            completions++;
            queueIndex++;
          });
          try {
            await audio.load(
              ResolvedAudio(
                input: server.url,
                duration: const Duration(seconds: 8),
              ),
            );
            await audio.play();
            await _waitFor(() => audio.lastError != null, audio: audio);
            await Future<void>.delayed(const Duration(milliseconds: 350));
            expect(audio.lastError, isNotNull);
            expect(audio.isPlaying, isFalse);
            expect(completions, 0);
            expect(queueIndex, 0);
          } finally {
            await subscription.cancel();
          }
        } finally {
          await _dispose(audio);
          await server.close();
          await fixture.directory.delete(recursive: true);
        }
        return true;
      });
      expect(passed, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'HTTP FFmpeg stream: empty paused buffer does not complete',
    (tester) async {
      final passed = await tester.runAsync(() async {
        final fixture = await _wavFixture(seconds: 2);
        final release = Completer<void>();
        final server = await _LoopbackServer.start((request) async {
          request.response.headers.contentType = ContentType('audio', 'wav');
          request.response
            ..statusCode = HttpStatus.ok
            ..contentLength = fixture.bytes.length;
          await release.future;
          request.response.add(fixture.bytes);
          await request.response.close();
        });
        final audio = RustMusicAudio();
        try {
          await _initialize(audio);
          var completions = 0;
          final subscription = audio.completed.listen((_) => completions++);
          try {
            await audio.load(
              ResolvedAudio(
                input: server.url,
                duration: const Duration(seconds: 2),
              ),
            );
            await audio.play();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            await audio.pause();
            await Future<void>.delayed(const Duration(milliseconds: 400));
            expect(completions, 0);
            expect(audio.isPlaying, isFalse);
            expect(audio.lastError, isNull);
          } finally {
            if (!release.isCompleted) release.complete();
            await subscription.cancel();
          }
        } finally {
          if (!release.isCompleted) release.complete();
          await _dispose(audio);
          await server.close();
          await fixture.directory.delete(recursive: true);
        }
        return true;
      });
      expect(passed, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

Future<void> _initialize(RustMusicAudio audio) async {
  expect(
    _toolsDirectory,
    isNotEmpty,
    reason: 'Pass --dart-define=AURORA_TOOLS=<folder>',
  );
  await audio.initialize();
  audio.setVolume(0);
}

Future<void> _dispose(RustMusicAudio audio) async {
  await audio.stop();
  audio.dispose();
  await Future<void>.delayed(const Duration(milliseconds: 250));
}

Future<void> _waitFor(
  bool Function() condition, {
  required RustMusicAudio audio,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 12));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'Timed out waiting for native stream error; position=${audio.position}, playing=${audio.isPlaying}, buffering=${audio.isBuffering}, error=${audio.lastError}',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }
}

Future<_WavFixture> _wavFixture({
  required int seconds,
  int? declaredSeconds,
}) async {
  const rate = 48000, channels = 2;
  final actualFrames = rate * seconds;
  final declaredFrames = rate * (declaredSeconds ?? seconds);
  final bytes = ByteData(44 + actualFrames * channels * 2);
  void text(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  text(0, 'RIFF');
  bytes.setUint32(4, 36 + declaredFrames * channels * 2, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  text(36, 'data');
  bytes.setUint32(40, declaredFrames * channels * 2, Endian.little);
  for (var frame = 0; frame < actualFrames; frame++) {
    final sample = (math.sin(2 * math.pi * 375 * frame / rate) * 0.2 * 32767)
        .round();
    for (var channel = 0; channel < channels; channel++) {
      bytes.setInt16(
        44 + (frame * channels + channel) * 2,
        sample,
        Endian.little,
      );
    }
  }
  final directory = await Directory.systemTemp.createTemp(
    'aurora_stream_test_',
  );
  final wav = bytes.buffer.asUint8List();
  await File(
    '${directory.path}${Platform.pathSeparator}tone.wav',
  ).writeAsBytes(wav);
  return _WavFixture(directory, wav, 44 + declaredFrames * channels * 2);
}

class _WavFixture {
  const _WavFixture(this.directory, this.bytes, this.declaredLength);
  final Directory directory;
  final Uint8List bytes;
  final int declaredLength;
}

class _LoopbackServer {
  _LoopbackServer(this.server, this.handler);
  final HttpServer server;
  final Future<void> Function(HttpRequest) handler;
  final List<Future<void>> _handlers = [];
  String get url => 'http://127.0.0.1:${server.port}/tone.wav';

  static Future<_LoopbackServer> start(
    Future<void> Function(HttpRequest) handler,
  ) async {
    final wrapper = _LoopbackServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      handler,
    );
    wrapper.server.listen((request) {
      wrapper._handlers.add(wrapper.handler(request).catchError((Object _) {}));
    });
    return wrapper;
  }

  Future<void> close() async {
    await server.close(force: true);
    await Future.wait(_handlers, eagerError: false);
  }
}
