import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _first = Track(
  id: 'one',
  title: 'Uno',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/abcdefghijk',
);
const _second = Track(
  id: 'two',
  title: 'Dos',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/lmnopqrstuv',
);

class _FailingAudio extends FakeAudio {
  int failedLoadsRemaining = 0;

  @override
  Future<void> load(
    ResolvedAudio source, {
    Duration start = Duration.zero,
  }) async {
    if (failedLoadsRemaining > 0) {
      failedLoadsRemaining--;
      throw Exception('socket timeout');
    }
    await super.load(source, start: start);
  }
}

class _PendingAudio extends FakeAudio {
  final loadStarted = Completer<void>();
  final loadGate = Completer<void>();

  @override
  Future<void> load(
    ResolvedAudio source, {
    Duration start = Duration.zero,
  }) async {
    if (!loadStarted.isCompleted) loadStarted.complete();
    await loadGate.future;
    await super.load(source, start: start);
  }
}

Future<void> _settle(AppController controller) async {
  while (controller.busy) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

class _PrefetchSource extends FakeSource {
  final prefetched = <String>[];
  Completer<void>? gate;
  @override
  Future<void> prefetch(Track track) async {
    prefetched.add(track.id);
    await gate?.future;
  }
}

Future<void> _tick(FakeAudio audio, int seconds) async {
  audio.position = Duration(seconds: seconds);
  audio.notifyListeners();
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

void main() {
  test('preloads next track once after 10 s', () async {
    final source = _PrefetchSource();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    await _tick(audio, 5);
    expect(source.prefetched, isEmpty);
    await _tick(audio, 11);
    await _tick(audio, 12);
    expect(source.prefetched, ['two']);
  });

  test('preload skips shuffle, repeat one and local next', () async {
    final source = _PrefetchSource();
    final audio = FakeAudio();
    const local = Track(
      id: 'loc',
      title: 'L',
      artist: 'A',
      localPath: 'C:/x.mp3',
    );
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second, local],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_second, context: [_second, local]);
    await _tick(audio, 20);
    expect(source.prefetched, isEmpty);
    await controller.playTrack(_first, context: [_first, _second]);
    controller.shuffle = true;
    await _tick(audio, 20);
    controller.shuffle = false;
    controller.repeat = RepeatMode.one;
    await _tick(audio, 21);
    expect(source.prefetched, isEmpty);
  });

  test('queue change during preload allows a fresh preload', () async {
    final source = _PrefetchSource()..gate = Completer<void>();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    await _tick(audio, 11);
    await _tick(audio, 12);
    expect(source.prefetched, ['two']);
    await controller.playTrack(_first, context: [_first, _second]);
    source.gate!.complete();
    await _tick(audio, 11);
    await _tick(audio, 12);
    expect(source.prefetched, ['two', 'two']);
  });

  test('premature EOF refreshes once at position and does not loop', () async {
    final source = FakeSource();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
      preferences: {
        'queue': ['one', 'one', 'two'],
        'queueIndex': 1,
      },
    );
    addTearDown(() => closeTestController(controller));
    await controller.playQueueAt(1);
    audio.position = const Duration(seconds: 37);
    audio.lastError = 'El audio terminó antes de completar la reproducción.';
    audio.notifyListeners();
    await _settle(controller);

    expect(controller.queueIndex, 1);
    expect(controller.currentTrack?.id, 'one');
    expect(source.resolved, ['one', 'one']);
    expect(audio.position, const Duration(seconds: 37));
    expect(audio.isPlaying, isTrue);
    expect(controller.error, isNull);
    audio.lastError = 'El audio terminó antes de completar la reproducción.';
    audio.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _settle(controller);
    expect(source.resolved, ['one', 'one']);
    expect(controller.error, isNotNull);
  });

  for (final message in [
    'HTTP 410',
    'Source error: Response code: 410',
    'Connection closed unexpectedly',
    '[in#0 @ 000001] Error opening input: Server returned 4XX Client Error, '
        'but not one of 40{0,1,3,4}',
    'premature EOF',
  ]) {
    test('proxy-surfaced "$message" refreshes the stream', () async {
      final source = FakeSource();
      final audio = FakeAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(_first);
      audio.lastError = message;
      audio.notifyListeners();
      await _settle(controller);
      expect(source.resolved, ['one', 'one']);
    });
  }

  const open4xx =
      '[in#0 @ 000001] Error opening input: Server returned 4XX Client Error, '
      'but not one of 40{0,1,3,4}';

  test('a stream that never opens advances after its refresh failed', () async {
    final source = FakeSource();
    final audio = _FailingAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    audio.failedLoadsRemaining = 1;
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _settle(controller);
    expect(source.resolved, ['one', 'one', 'two']);
    expect(controller.currentTrack?.id, 'two');
  });

  test('a second 4XX right after the refresh advances, not loops', () async {
    final source = FakeSource();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    expect(source.resolved, ['one', 'one']);
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(source.resolved, ['one', 'one', 'two']);
    expect(controller.currentTrack?.id, 'two');
  });

  test('a 4XX after real playback is not skipped', () async {
    final source = FakeSource();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    audio.position = const Duration(seconds: 40);
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(controller.currentTrack?.id, 'one');
  });

  test('failed refresh is not retried; 60 s of progress re-arms it', () async {
    final source = FakeSource();
    final audio = _FailingAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    audio.position = const Duration(seconds: 24);
    audio.failedLoadsRemaining = 1;
    audio.lastError = 'SocketException: connection timed out';
    audio.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _settle(controller);
    expect(source.resolved, ['one', 'one']);
    expect(controller.error, isNotNull);

    audio.lastError = 'SocketException: connection timed out';
    audio.notifyListeners();
    await _settle(controller);
    expect(source.resolved, ['one', 'one']);

    // Playing 60 more seconds opens a new failure window.
    audio.isPlaying = true;
    audio.position = const Duration(seconds: 90);
    audio.notifyListeners();
    audio.lastError = 'SocketException: connection timed out';
    audio.notifyListeners();
    await _settle(controller);
    expect(source.resolved, ['one', 'one', 'one']);
    expect(controller.error, isNull);
  });

  test('queue change while URL refresh is pending wins', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 18);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await controller.playQueueAt(1);
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await _settle(controller);

    expect(controller.queueIndex, 1);
    expect(controller.currentTrack?.id, 'two');
    expect(audio.loaded?.input, 'https://example.test/two');
  });

  test('stop cancels in-flight refresh', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 12);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    while (source.resolved.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await controller.stopPlayback();
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await _settle(controller);
    expect(audio.isPlaying, isFalse);
    expect(audio.position, Duration.zero);
    expect(source.resolved, ['one', 'one']);
  });

  test('pause cancels a refresh while source resolution is pending', () async {
    final source = FakeSource();
    final pending = Completer<ResolvedAudio>();
    final audio = FakeAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first);
    source.pendingResolves['one'] = pending;
    audio.position = const Duration(seconds: 12);
    audio.lastError = 'premature EOF';
    audio.notifyListeners();
    while (source.resolved.length < 2) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    await controller.togglePlayback();
    pending.complete(const ResolvedAudio(input: 'https://example.test/one'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(audio.isPlaying, isFalse);
    expect(source.resolved, ['one', 'one']);
  });

  test('toggle pauses an initial load that is still busy', () async {
    final audio = _PendingAudio();
    final controller = await createTestController(audio: audio);
    addTearDown(() => closeTestController(controller));
    final starting = controller.playTrack(_first);
    await audio.loadStarted.future;

    await controller.togglePlayback();
    audio.loadGate.complete();
    await starting;

    expect(audio.isPlaying, isFalse);
    expect(audio.loadCount, 1);
  });
  test('a track that fails to open is never recorded as played', () async {
    final source = FakeSource();
    final audio = _FailingAudio();
    final controller = await createTestController(
      source: source,
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    expect(controller.recentTracks, isEmpty);
    audio.failedLoadsRemaining = 1;
    audio.lastError = open4xx;
    audio.notifyListeners();
    await _settle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _settle(controller);
    expect(controller.currentTrack?.id, 'two');
    expect(controller.recentTracks, isEmpty);
    expect(await controller.database.readHistory(), isEmpty);
  });

  test('playback is recorded once, after 5 s of real progress', () async {
    final audio = FakeAudio();
    final controller = await createTestController(
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    await _tick(audio, 3);
    expect(controller.recentTracks, isEmpty);
    await _tick(audio, 6);
    await _tick(audio, 7);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.recentTracks.map((t) => t.id), ['one']);
    expect(await controller.database.readHistory(), ['one']);
  });

  test('next before the 5 s threshold leaves no history behind', () async {
    final audio = FakeAudio();
    final controller = await createTestController(
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    await _tick(audio, 2);
    await controller.next();
    await _tick(audio, 6);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(controller.recentTracks.map((t) => t.id), ['two']);
  });
  test('sleep at track end pauses when that track completes', () async {
    final audio = FakeAudio();
    final controller = await createTestController(
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    controller.setSleepAtTrackEnd();
    await controller.next();
    expect(controller.currentTrack?.id, 'two');
    expect(controller.sleepRemaining, isNotNull);
    audio.position = audio.duration;
    audio.completions.add(null);
    await _settle(controller);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(audio.isPlaying, isFalse);
    expect(controller.currentTrack?.id, 'two');
    expect(controller.sleepRemaining, isNull);
  });

  test('stop cancels sleep at track end', () async {
    final audio = FakeAudio();
    final controller = await createTestController(
      audio: audio,
      tracks: [_first, _second],
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(_first, context: [_first, _second]);
    controller.setSleepAtTrackEnd();
    await controller.stopPlayback();
    expect(controller.sleepRemaining, isNull);
  });
}
