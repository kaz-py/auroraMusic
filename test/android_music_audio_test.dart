import 'dart:async';

import 'package:aurora_music/audio/android_music_audio.dart';
import 'package:aurora_music/audio/eq_model.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('aurora/audio');
  const events = EventChannel('aurora/audio/events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late AndroidMusicAudio audio;

  Future<void> emit(Map<String, Object?> event) async {
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      events.name,
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() async {
    calls.clear();
    messenger.setMockMethodCallHandler(methods, (call) async {
      calls.add(call);
      if (call.method == 'initialize') {
        return {
          'type': 'state',
          'generation': 0,
          'playing': false,
          'buffering': false,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(
      MethodChannel(events.name),
      (_) async => null,
    );
    audio = AndroidMusicAudio();
    await audio.initialize();
  });
  tearDown(() async {
    audio.dispose();
    await Future<void>.delayed(Duration.zero);
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(MethodChannel(events.name), null);
  });

  test('maps metadata for the system session', () async {
    await audio.updateMetadata(
      id: 'a',
      title: 'T',
      artist: 'A',
      album: 'Al',
      duration: const Duration(seconds: 90),
      artworkUrl: 'https://example.com/a.jpg',
    );
    expect(calls.last.method, 'metadata');
    expect(calls.last.arguments, {
      'id': 'a',
      'title': 'T',
      'artist': 'A',
      'album': 'Al',
      'durationMs': 90000,
      'artworkUrl': 'https://example.com/a.jpg',
    });
  });

  test('forwards each system action once and drops unknown ones', () async {
    final seen = <String>[];
    final sub = audio.mediaActions.listen(seen.add);
    for (final action in ['play', 'next', 'previous', 'pause', 'bogus']) {
      await emit({'type': 'action', 'generation': 0, 'action': action});
    }
    expect(seen, ['play', 'next', 'previous', 'pause']);
    await sub.cancel();
  });

  test(
    'passes stream headers, load offset and controls to the single player',
    () async {
      await audio.load(
        const ResolvedAudio(
          input: 'https://example.com/audio',
          headers: {'Referer': 'https://example.com'},
          duration: Duration(minutes: 3),
        ),
        start: const Duration(seconds: 4),
      );
      final args = calls.last.arguments as Map;
      expect(args['headers'], {'Referer': 'https://example.com'});
      expect(args['startMs'], 4000);
      expect(args['generation'], 1);
      await audio.play();
      await audio.pause();
      await audio.seek(const Duration(minutes: 5));
      expect(calls.last.arguments, {'positionMs': 180000});
      audio.setVolume(2);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, {'volume': 1.0});
      expect(audio.supportsEqualizer, false);
      expect(audio.supportsVisualization, false);
    },
  );

  test(
    'ignores stale state/errors/completion after replacement and stop',
    () async {
      await audio.load(const ResolvedAudio(input: '/first.mp3'));
      await audio.load(const ResolvedAudio(input: '/second.mp3'));
      var completed = 0;
      final subscription = audio.completed.listen((_) => completed++);
      await emit({'type': 'state', 'generation': 1, 'playing': true});
      await emit({'type': 'error', 'generation': 1, 'message': 'old error'});
      await emit({'type': 'completed', 'generation': 1});
      expect(audio.isPlaying, false);
      expect(audio.lastError, null);
      expect(completed, 0);
      await emit({
        'type': 'state',
        'generation': 2,
        'playing': true,
        'positionMs': 42000,
        'durationMs': 90000,
      });
      expect(audio.isPlaying, true);
      expect(audio.position, const Duration(seconds: 42));
      await audio.stop();
      await emit({'type': 'completed', 'generation': 2});
      expect(completed, 0);
      expect(audio.position, Duration.zero);
      await subscription.cancel();
    },
  );

  test('interrupt keeps the system session; stop releases it', () async {
    await audio.load(const ResolvedAudio(input: '/first.mp3'));
    await audio.interrupt();
    expect(calls.last.method, 'stop');
    expect(calls.last.arguments, {'generation': 2, 'keepSession': true});
    expect(audio.position, Duration.zero);
    await audio.stop();
    expect(calls.last.method, 'stop');
    expect(calls.last.arguments, {'generation': 3});
  });

  test(
    'validates EOF once and rejects failed or superseded validation',
    () async {
      final validation = Completer<void>();
      var validationCalls = 0, completions = 0;
      final subscription = audio.completed.listen((_) => completions++);
      await audio.load(
        ResolvedAudio(
          input: '/growing.webm',
          validateCompletion: () {
            validationCalls++;
            return validation.future;
          },
        ),
      );
      await emit({'type': 'completed', 'generation': 1});
      await emit({'type': 'completed', 'generation': 1});
      expect(validationCalls, 1);
      expect(completions, 0);
      await audio.load(const ResolvedAudio(input: '/replacement.mp3'));
      validation.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completions, 0);
      await emit({'type': 'completed', 'generation': 2});
      await emit({'type': 'completed', 'generation': 2});
      expect(completions, 1);
      await audio.load(
        ResolvedAudio(
          input: '/failed.webm',
          validateCompletion: () async {
            throw StateError('incomplete audio');
          },
        ),
      );
      await emit({'type': 'completed', 'generation': 3});
      expect(completions, 1);
      expect(audio.lastError, contains('incomplete audio'));
      await subscription.cancel();
    },
  );

  test(
    'routes native next and previous to Flutter and publishes metadata',
    () async {
      await audio.load(const ResolvedAudio(input: '/track.mp3'));
      final actions = <String>[];
      final subscription = audio.mediaActions.listen(actions.add);
      await emit({'type': 'action', 'generation': 1, 'action': 'next'});
      await emit({'type': 'action', 'generation': 1, 'action': 'previous'});
      await emit({'type': 'action', 'generation': 1, 'action': 'play'});
      await emit({'type': 'action', 'generation': 1, 'action': 'pause'});
      await emit({'type': 'action', 'generation': 1, 'action': 'stop'});
      await emit({'type': 'action', 'generation': 0, 'action': 'next'});
      expect(actions, ['next', 'previous', 'play', 'pause', 'stop']);
      await audio.updateMetadata(id: 'track', title: 'Song', artist: 'Artist');
      expect(calls.last.method, 'metadata');
      expect(calls.last.arguments, containsPair('title', 'Song'));
      await subscription.cancel();
    },
  );

  test(
    'reports a native command failure instead of remaining buffering',
    () async {
      messenger.setMockMethodCallHandler(methods, (_) async {
        throw PlatformException(
          code: 'AUDIO_ERROR',
          message: 'network failure',
        );
      });
      await expectLater(
        audio.load(const ResolvedAudio(input: 'https://example.com/audio')),
        throwsA(isA<PlatformException>()),
      );
      expect(audio.isBuffering, false);
      expect(audio.isPlaying, false);
      expect(audio.lastError, contains('network failure'));
    },
  );

  test(
    'exposes native EQ availability and passes eight bounded parametric bands',
    () async {
      audio.setEqualizer(true, [EqBand(60, 5)]);
      expect(calls.last.method, 'initialize');
      await emit({'type': 'state', 'generation': 0, 'supportsEqualizer': true});
      expect(audio.supportsEqualizer, true);
      audio.setEqualizer(true, [
        EqBand(60, 20),
        EqBand(170, -20, double.nan),
        EqBand(310, 3, 2),
      ], autoPreamp: false);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.method, 'equalizer');
      final args = calls.last.arguments as Map;
      expect(args['enabled'], true);
      expect(args['autoPreamp'], false);
      final bands = (args['bands'] as List).cast<Map>();
      expect(bands.length, 8);
      expect(bands[0], {'frequency': 60.0, 'gainDb': 12.0, 'q': 1.0});
      expect(bands[1]['gainDb'], -12.0);
      expect(bands[1]['q'], 1.0);
      expect(bands[2], {'frequency': 310.0, 'gainDb': 3.0, 'q': 2.0});
      expect(bands[3]['frequency'], eqDefaultFrequencies[3]);
      await emit({
        'type': 'state',
        'generation': 0,
        'supportsEqualizer': false,
      });
      expect(audio.supportsEqualizer, false);
      expect(audio.lastError, null);
    },
  );
}
