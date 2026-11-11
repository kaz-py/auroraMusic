import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/jam/jam_playback_bridge.dart';
import 'support/fakes.dart';

const song = Track(
  id: 'yt:abcdefghijk',
  title: 'Song',
  artist: 'Artist',
  pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
);

class _EngineSource extends FakeSource {
  _EngineSource(this.audio);
  final ResolvedAudio audio;
  @override
  Future<ResolvedAudio> resolve(Track track) async => audio;
}

void main() {
  {
    const audio = ResolvedAudio(input: 'http://127.0.0.1:4000/t/a/i');
    test('Jam plays resolved audio', () async {
      final now = DateTime.utc(2026, 10, 12);
      final out = FakeAudio();
      final app = await createTestController(
        audio: out,
        source: _EngineSource(audio),
      );
      final service = JamService(clock: () => now);
      service.queue = [
        JamQueueEntry(
          id: 'entry',
          track: JamTrack.fromTrack(song),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(
        app: app,
        service: service,
        clock: () => now,
      );
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
        await closeTestController(app);
      });
      await bridge.enable();
      await bridge.apply(
        JamPlayback(
          sequence: 1,
          serverTimeMs: now.millisecondsSinceEpoch,
          entryId: 'entry',
          isPlaying: true,
          positionMs: 1000,
        ),
      );
      expect(out.loaded?.input, audio.input);
    });
  }

  test(
    'clock offset projects host position with bounded stale frame extrapolation',
    () {
      const state = JamPlayback(
        sequence: 1,
        serverTimeMs: 10000,
        positionMs: 3000,
        isPlaying: true,
      );
      expect(jamTargetPosition(state, 10500, 200), 3700);
      expect(jamTargetPosition(state, 30000, 0), 8000);
      expect(jamTargetPosition(state, 10500, 200, durationMs: 3500), 3500);
      expect(
        jamTargetPosition(
          const JamPlayback(sequence: 2, serverTimeMs: 10000, positionMs: 3000),
          30000,
          200,
        ),
        3000,
      );
    },
  );
  test(
    'drift correction uses a 1.5 s deadband, one jump (max 3 s) and a five second cooldown',
    () {
      expect(
        jamDriftCorrection(
          currentMs: 1000,
          targetMs: 2400,
          nowMs: 10000,
          lastSeekMs: null,
        ),
        isNull,
      );
      expect(
        jamDriftCorrection(
          currentMs: 1000,
          targetMs: 6000,
          nowMs: 10000,
          lastSeekMs: null,
        ),
        4000,
      );
      expect(
        jamDriftCorrection(
          currentMs: 6000,
          targetMs: 1000,
          nowMs: 10000,
          lastSeekMs: null,
        ),
        3000,
      );
      expect(
        jamDriftCorrection(
          currentMs: 1000,
          targetMs: 6000,
          nowMs: 10000,
          lastSeekMs: 8000,
        ),
        isNull,
      );
    },
  );
  test(
    'own audio resolves canonical YouTube and repeated states do not reload',
    () async {
      var now = DateTime.utc(2026, 10, 12);
      final audio = FakeAudio(), source = FakeSource();
      final app = await createTestController(audio: audio, source: source);
      final service = JamService(clock: () => now);
      service.queue = [
        JamQueueEntry(
          id: 'entry',
          track: JamTrack.fromTrack(song),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(
        app: app,
        service: service,
        clock: () => now,
      );
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
        await closeTestController(app);
      });
      await bridge.enable();
      var state = JamPlayback(
        sequence: 1,
        serverTimeMs: now.millisecondsSinceEpoch,
        entryId: 'entry',
        isPlaying: true,
        positionMs: 2000,
      );
      await bridge.apply(state);
      expect(source.resolved, ['yt:abcdefghijk']);
      expect(audio.loadCount, 1);
      expect(audio.position.inMilliseconds, 2000);
      expect(app.queue, isEmpty);
      expect(app.jamPlaybackActive, isTrue);
      now = now.add(const Duration(seconds: 6));
      state = JamPlayback(
        sequence: 2,
        serverTimeMs: now.millisecondsSinceEpoch,
        entryId: 'entry',
        isPlaying: true,
        positionMs: 8000,
      );
      await bridge.apply(state);
      expect(audio.loadCount, 1);
      expect(audio.position.inMilliseconds, 5000);
      now = now.add(const Duration(seconds: 1));
      await bridge.apply(state);
      expect(audio.position.inMilliseconds, 5000);
      await bridge.apply(
        JamPlayback(
          sequence: 3,
          serverTimeMs: now.millisecondsSinceEpoch,
          entryId: 'entry',
          isPlaying: false,
          positionMs: 3000,
        ),
      );
      expect(audio.isPlaying, isFalse);
    },
  );
  test(
    'unavailable local song warns without stopping the shared session',
    () async {
      final app = await createTestController();
      final service = JamService();
      service.connection = JamConnection.connected;
      service.queue = [
        JamQueueEntry(
          id: 'local',
          track: JamTrack.fromTrack(
            const Track(
              id: 'private',
              title: 'Missing local',
              artist: 'Artist',
              localPath: 'does-not-exist.mp3',
            ),
          ),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(app: app, service: service);
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
        await closeTestController(app);
      });
      await bridge.enable();
      await bridge.apply(
        JamPlayback(
          sequence: 1,
          serverTimeMs: DateTime.now().millisecondsSinceEpoch,
          entryId: 'local',
          isPlaying: true,
        ),
      );
      expect(bridge.warning, isNotNull);
      expect(bridge.loading, isFalse);
      expect(service.queue, hasLength(1));
      expect(service.connection, JamConnection.connected);
      expect((app.audio as FakeAudio).loadCount, 0);
    },
  );
  test('late source resolution cannot load a superseded track', () async {
    final source = FakeSource(), audio = FakeAudio();
    final app = await createTestController(source: source, audio: audio);
    final old = Completer<ResolvedAudio>();
    source.pendingResolves[song.id] = old;
    final service = JamService();
    service.queue = [
      JamQueueEntry(
        id: 'first',
        track: JamTrack.fromTrack(song),
        addedBy: 'host',
      ),
      JamQueueEntry(
        id: 'second',
        track: JamTrack.fromTrack(
          const Track(
            id: 'yt:lmnopqrstuv',
            title: 'Second',
            artist: 'Artist',
            pageUrl: 'https://www.youtube.com/watch?v=lmnopqrstuv',
          ),
        ),
        addedBy: 'host',
      ),
    ];
    final bridge = JamPlaybackBridge(app: app, service: service);
    addTearDown(() async {
      await bridge.disable();
      bridge.dispose();
      service.dispose();
      await closeTestController(app);
    });
    await bridge.enable();
    final first = bridge.apply(
      JamPlayback(
        sequence: 1,
        serverTimeMs: DateTime.now().millisecondsSinceEpoch,
        entryId: 'first',
        isPlaying: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final second = bridge.apply(
      JamPlayback(
        sequence: 2,
        serverTimeMs: DateTime.now().millisecondsSinceEpoch,
        entryId: 'second',
        isPlaying: true,
      ),
    );
    old.complete(const ResolvedAudio(input: 'offline-old'));
    await Future.wait([first, second]);
    expect(audio.loadCount, 1);
    expect(bridge.currentEntryId, 'second');
    expect(audio.loaded!.input.contains('lmnopqrstuv'), isTrue);
  });
  test(
    'leaving restores personal playback and preserves queue edits during Jam',
    () async {
      final audio = FakeAudio();
      final app = await createTestController(audio: audio, tracks: [song]);
      await app.playTrack(song);
      audio.position = const Duration(seconds: 42);
      final service = JamService();
      service.queue = [
        JamQueueEntry(
          id: 'entry',
          track: JamTrack.fromTrack(
            const Track(
              id: 'yt:lmnopqrstuv',
              title: 'Jam song',
              artist: 'Artist',
              pageUrl: 'https://www.youtube.com/watch?v=lmnopqrstuv',
            ),
          ),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(app: app, service: service);
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
        await closeTestController(app);
      });
      await bridge.enable();
      await bridge.apply(
        JamPlayback(
          sequence: 1,
          serverTimeMs: DateTime.now().millisecondsSinceEpoch,
          entryId: 'entry',
          isPlaying: true,
        ),
      );
      await app.addToQueue(
        const Track(
          id: 'yt:12345678901',
          title: 'Personal addition',
          artist: 'Artist',
          pageUrl: 'https://www.youtube.com/watch?v=12345678901',
        ),
      );
      await bridge.disable();
      expect(app.queue, hasLength(2));
      expect(app.currentTrack!.id, song.id);
      expect(app.jamPlaybackActive, isFalse);
      expect(audio.position.inSeconds, 42);
      expect(audio.isPlaying, isTrue);
    },
  );
  test(
    'leaving does not resurrect a personal track removed during Jam',
    () async {
      final audio = FakeAudio();
      final app = await createTestController(audio: audio, tracks: [song]);
      await app.playTrack(song);
      final service = JamService();
      final bridge = JamPlaybackBridge(app: app, service: service);
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
        await closeTestController(app);
      });
      await bridge.enable();
      await app.removeFromQueue(0);
      await bridge.disable();
      expect(app.queue, isEmpty);
      expect(audio.isPlaying, isFalse);
    },
  );
  test('paused unloaded personal queue is not played when leaving', () async {
    final audio = FakeAudio();
    final app = await createTestController(audio: audio, tracks: [song]);
    await app.addToQueue(song);
    final service = JamService();
    final bridge = JamPlaybackBridge(app: app, service: service);
    addTearDown(() async {
      await bridge.disable();
      bridge.dispose();
      service.dispose();
      await closeTestController(app);
    });
    await bridge.enable();
    await bridge.disable();
    expect(audio.loadCount, 0);
    expect(audio.isPlaying, isFalse);
  });
}
