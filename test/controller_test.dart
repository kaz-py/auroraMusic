import 'dart:async';
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _ProgressiveSource extends FakeSource {
  bool supported = true;
  bool? applied;
  int setCalls = 0;

  @override
  bool get supportsExperimentalProgressivePlayback => supported;

  @override
  void setExperimentalProgressivePlayback(bool enabled) {
    applied = enabled;
    setCalls++;
  }
}

class _PlaybackTrackingAudio extends FakeAudio {
  int pauseCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> pause() {
    pauseCalls++;
    return super.pause();
  }

  @override
  Future<void> seek(Duration value) {
    seekCalls++;
    return super.seek(value);
  }
}

const first = Track(
  id: 'one',
  title: 'Uno',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/abcdefghijk',
);
const second = Track(
  id: 'two',
  title: 'Dos',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/lmnopqrstuv',
);
const third = Track(
  id: 'three',
  title: 'Tres',
  artist: 'Artista',
  pageUrl: 'https://youtu.be/wxyz1234567',
);

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue);
}

List<Track> _djLibrary([int count = 8]) => [
  for (var i = 0; i < count; i++)
    Track(
      id: 'dj-$i',
      title: 'DJ $i',
      artist: 'Artist $i',
      pageUrl: 'https://youtu.be/dj-$i',
    ),
];

Future<(AppController, List<Track>)> _controllerWithQueuedRecommendations({
  required bool paused,
}) async {
  final tracks = _djLibrary();
  final controller = await createTestController(tracks: tracks);
  await controller.toggleFavorite(tracks.first);
  final queue = [
    tracks.first,
    ...controller.recommendations.map((item) => item.track),
  ];
  await controller.playTrack(tracks.first, context: queue);
  if (paused) await controller.pausePlayback();
  return (controller, queue);
}

void main() {
  test(
    'experimental progressive playback defaults off and configures source',
    () async {
      final source = _ProgressiveSource();
      final controller = await createTestController(source: source);
      addTearDown(() => closeTestController(controller));

      expect(controller.experimentalProgressivePlayback, isFalse);
      expect(
        controller.preferences.getBool('experimentalProgressivePlayback'),
        isNull,
      );
      expect(source.applied, isFalse);
      expect(source.setCalls, 1);
    },
  );

  test(
    'saved experimental progressive playback is restored on startup',
    () async {
      final source = _ProgressiveSource();
      final controller = await createTestController(
        source: source,
        preferences: const {'experimentalProgressivePlayback': true},
      );
      addTearDown(() => closeTestController(controller));

      expect(controller.experimentalProgressivePlayback, isTrue);
      expect(source.applied, isTrue);
    },
  );

  test('audio quality is saved, restored and applied to InnerTube', () async {
    final source = InnerTubeSource(FakeSource());
    final controller = await createTestController(
      source: source,
      preferences: const {'audioQuality': 'normal'},
    );
    addTearDown(() => closeTestController(controller));

    expect(controller.audioQuality, AudioQuality.normal);
    expect(source.audioQuality, AudioQuality.normal);
    controller.setAudioQuality(AudioQuality.saver);
    expect(controller.preferences.getString('audioQuality'), 'saver');
    expect(source.audioQuality, AudioQuality.saver);
  });

  test('changing progressive playback only configures next tracks', () async {
    final source = _ProgressiveSource();
    final audio = _PlaybackTrackingAudio();
    final controller = await createTestController(
      tracks: [first, second],
      source: source,
      audio: audio,
    );
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(first);
    audio.position = const Duration(seconds: 42);
    final loads = audio.loadCount;
    final pauses = audio.pauseCalls;
    final seeks = audio.seekCalls;

    controller.setExperimentalProgressivePlayback(true);
    await Future<void>.delayed(Duration.zero);

    expect(
      controller.preferences.getBool('experimentalProgressivePlayback'),
      isTrue,
    );
    expect(source.applied, isTrue);
    expect(audio.loadCount, loads);
    expect(audio.pauseCalls, pauses);
    expect(audio.seekCalls, seeks);
    expect(audio.position, const Duration(seconds: 42));
    expect(audio.isPlaying, isTrue);
  });

  test(
    'session import copies privately, replaces and clears without deleting the original',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      final original = File('${controller.supportDirectory.path}/original.txt');
      await original.writeAsString(
        '# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\ttest-value\n',
      );
      await controller.configureYouTubeSession(original);
      final firstCopy = File(controller.source.cookieFile!);
      expect(firstCopy.path, isNot(original.path));
      expect(await firstCopy.readAsString(), await original.readAsString());
      await controller.configureYouTubeSession(original);
      expect(await firstCopy.exists(), isFalse);
      final secondCopy = File(controller.source.cookieFile!);
      await controller.clearYouTubeSession();
      expect(controller.hasYouTubeSession, isFalse);
      expect(await secondCopy.exists(), isFalse);
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'failed session validation preserves the previous session and cleans the rejected copy',
    () async {
      final source = FakeSource();
      final controller = await createTestController(source: source);
      addTearDown(() => closeTestController(controller));
      final original = File('${controller.supportDirectory.path}/original.txt');
      await original.writeAsString('test session');
      await controller.configureYouTubeSession(original);
      final previous = source.cookieFile;
      source.cookieError = ArgumentError('Invalid cookie format');
      await controller.configureYouTubeSession(original);
      expect(source.cookieFile, previous);
      expect(
        await Directory(
          '${controller.supportDirectory.path}/session',
        ).list().length,
        1,
      );
      expect(controller.sessionBusy, isFalse);
      expect(controller.error, contains('Invalid cookie format'));
      // An old preference must never cause removal of a user-owned file.
      source.cookieFile = original.path;
      await controller.clearYouTubeSession();
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'queue advances, previous restarts, and reorder preserves playing item',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first, context: [first, second, third]);
      await controller.next();
      expect(controller.currentTrack?.id, second.id);
      await controller.reorderQueue(1, 3);
      expect(controller.queueIndex, 2);
      expect(controller.currentTrack?.id, second.id);
      (controller.audio as FakeAudio).position = const Duration(seconds: 15);
      await controller.previous();
      expect(controller.audio.position, Duration.zero);
      expect(controller.currentTrack?.id, second.id);
      await controller.next();
      expect(controller.audio.isPlaying, isFalse);
    },
  );

  test('clearing search invalidates an in-flight result', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(source: source);
    addTearDown(() => closeTestController(controller));
    final searching = controller.search('consulta');
    await controller.search('');
    source.pendingSearch!.complete([first]);
    await searching;
    expect(controller.searchResults, isEmpty);
    expect(controller.searching, isFalse);
  });

  test(
    'requested discovery is bounded, deduplicated, and library-neutral',
    () async {
      final source = FakeSource();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      source.searchMatches = [
        first,
        const Track(
          id: 'new-one',
          title: 'Nuevo uno',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/new-one',
        ),
        const Track(
          id: 'new-one',
          title: 'Duplicado',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/new-one',
        ),
        const Track(
          id: 'url-copy',
          title: 'Mismo video con otro ID',
          artist: 'Artista',
          pageUrl: 'https://www.youtube.com/watch?v=new-one&feature=share',
        ),
        const Track(id: 'unplayable', title: 'Sin enlace', artist: 'Artista'),
        const Track(
          id: 'pending',
          title: 'Pendiente',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/pending',
          spotifyMatchPending: true,
        ),
        for (var i = 2; i <= 8; i++)
          Track(
            id: 'new-$i',
            title: 'Nuevo $i',
            artist: 'Artista',
            pageUrl: 'https://youtu.be/new-$i',
          ),
      ];

      await controller.discoverRecommendations();

      expect(source.searchQueries, ['Artista songs']);
      expect(source.searchLimits, [12]);
      expect(controller.discoveredRecommendations, hasLength(6));
      expect(
        controller.discoveredRecommendations.map((track) => track.id).toSet(),
        hasLength(6),
      );
      expect(controller.tracks.map((track) => track.id).toSet(), {
        'one',
        'two',
        'three',
      });
      expect(
        (await controller.database.readTracks())
            .map((track) => track.id)
            .toSet(),
        {'one', 'two', 'three'},
      );

      source.searchMatches = [
        for (var i = 9; i <= 14; i++)
          Track(
            id: 'refresh-$i',
            title: 'Refresco $i',
            artist: 'Otra',
            pageUrl: 'https://youtu.be/refresh-$i',
          ),
      ];
      await controller.discoverRecommendations();
      expect(
        controller.discoveredRecommendations.map((track) => track.id).toSet(),
        {
          'refresh-9',
          'refresh-10',
          'refresh-11',
          'refresh-12',
          'refresh-13',
          'refresh-14',
        },
      );
    },
  );

  test('cancelled discovery ignores its late source result', () async {
    final source = FakeSource()..pendingSearch = Completer<List<Track>>();
    final controller = await createTestController(
      tracks: [first, second],
      source: source,
    );
    addTearDown(() => closeTestController(controller));
    final discovery = controller.discoverRecommendations();
    controller.cancelRecommendationDiscovery();
    source.pendingSearch!.complete([third]);
    await discovery;

    expect(controller.discoveredRecommendations, isEmpty);
    expect(controller.discoveringRecommendations, isFalse);
  });

  test('discovery failure stays separate from the main search error', () async {
    final source = FakeSource()..searchError = StateError('offline');
    final controller = await createTestController(
      tracks: [first, second],
      source: source,
    );
    addTearDown(() => closeTestController(controller));

    await controller.discoverRecommendations();

    expect(controller.recommendationDiscoveryError, contains('offline'));
    expect(controller.error, isNull);
    expect(controller.searching, isFalse);
  });

  test(
    'stale discovery results are discarded after favorite taste changes',
    () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      final discovery = controller.discoverRecommendations();
      await _waitFor(() => source.searchQueries.isNotEmpty);
      await controller.toggleFavorite(first);
      source.pendingSearch!.complete([
        third.copyWith(pageUrl: 'https://youtu.be/fresh'),
      ]);
      await discovery;

      expect(controller.discoveredRecommendations, isEmpty);
      expect(controller.discoveringRecommendations, isFalse);
    },
  );

  test(
    'personal DJ refills its queue before the current track finishes',
    () async {
      final tracks = _djLibrary();
      final controller = await createTestController(tracks: tracks);
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(tracks.first);
      controller.repeat = RepeatMode.all;
      controller.shuffle = true;
      await controller.startPersonalDj();
      final initialQueue = List.of(controller.queue);
      expect(controller.personalDjActive, isTrue);
      expect(controller.queue.length, 6);

      for (var completion = 0; completion < 4; completion++) {
        final before = controller.currentTrack?.id;
        (controller.audio as FakeAudio).position = controller.audio.duration;
        (controller.audio as FakeAudio).completions.add(null);
        await _waitFor(() => controller.currentTrack?.id != before);
      }
      await _waitFor(() => controller.queue.length > initialQueue.length);

      // The whole eight-track library becomes reachable, without duplicates.
      expect(controller.queue.length, 8);
      expect(controller.queue.map((t) => t.id).toSet(), hasLength(8));
      expect(controller.repeat, RepeatMode.all);
      expect(controller.shuffle, isTrue);
      expect(controller.audio.isPlaying, isTrue);
    },
  );

  test(
    'starting DJ on a paused track queues recommendations without resuming',
    () async {
      final tracks = _djLibrary();
      final controller = await createTestController(tracks: tracks);
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(tracks[0]);
      await controller.pausePlayback();
      final currentId = controller.currentTrack?.id;
      final audio = controller.audio as FakeAudio;
      final loaded = audio.loadCount;

      await controller.startPersonalDj();

      expect(controller.personalDjActive, isTrue);
      expect(controller.currentTrack?.id, currentId);
      expect(controller.audio.isPlaying, isFalse);
      expect(audio.loadCount, loaded);
      expect(controller.queueIndex, 0);
    },
  );

  test('DJ starts over already queued recommendations while playing', () async {
    final (controller, queue) = await _controllerWithQueuedRecommendations(
      paused: false,
    );
    addTearDown(() => closeTestController(controller));
    final audio = controller.audio as FakeAudio;
    final loads = audio.loadCount;
    final currentIndex = controller.queueIndex;
    final currentTrack = controller.currentTrack;

    expect(controller.recommendations, isNotEmpty);
    expect(
      controller.recommendations.every(
        (item) => queue.any((track) => track.id == item.track.id),
      ),
      isTrue,
    );
    expect(controller.canStartPersonalDj, isTrue);
    await controller.startPersonalDj();

    expect(controller.personalDjActive, isTrue);
    expect(controller.currentTrack, currentTrack);
    expect(controller.queueIndex, currentIndex);
    expect(
      controller.queue.map((track) => track.id),
      queue.map((track) => track.id),
    );
    expect(audio.loadCount, loads);
    expect(audio.isPlaying, isTrue);
  });

  test('DJ starts over already queued recommendations while paused', () async {
    final (controller, queue) = await _controllerWithQueuedRecommendations(
      paused: true,
    );
    addTearDown(() => closeTestController(controller));
    final audio = controller.audio as FakeAudio;
    audio.position = const Duration(seconds: 37);
    final loads = audio.loadCount;
    final currentIndex = controller.queueIndex;
    final currentTrack = controller.currentTrack;

    expect(controller.canStartPersonalDj, isTrue);
    await controller.startPersonalDj();

    expect(controller.personalDjActive, isTrue);
    expect(controller.currentTrack, currentTrack);
    expect(controller.queueIndex, currentIndex);
    expect(
      controller.queue.map((track) => track.id),
      queue.map((track) => track.id),
    );
    expect(audio.loadCount, loads);
    expect(audio.position, const Duration(seconds: 37));
    expect(audio.isPlaying, isFalse);
  });

  test(
    'pausing during a DJ refill keeps it paused after results arrive',
    () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(first);
      await controller.startPersonalDj(includeDiscovery: true);
      await _waitFor(() => source.searchQueries.isNotEmpty);
      await controller.pausePlayback();
      source.pendingSearch!.complete([
        const Track(
          id: 'dj-found',
          title: 'Found',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/dj-found',
        ),
      ]);
      await _waitFor(() => controller.queue.length > 2);

      expect(controller.personalDjActive, isTrue);
      expect(controller.audio.isPlaying, isFalse);
      expect(controller.currentTrack?.id, isNotNull);
    },
  );

  test(
    'pause during completion waiting for refill cannot advance or resume',
    () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(first);
      await controller.startPersonalDj(includeDiscovery: true);
      await _waitFor(() => source.searchQueries.isNotEmpty);
      await controller.next();
      final currentId = controller.currentTrack?.id;
      final audio = controller.audio as FakeAudio;
      audio.position = audio.duration;
      audio.completions.add(null);
      await controller.pausePlayback();
      source.pendingSearch!.complete([
        const Track(
          id: 'dj-waiting',
          title: 'Waiting result',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/dj-waiting',
        ),
      ]);
      await _waitFor(() => controller.queue.length > 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.currentTrack?.id, currentId);
      expect(controller.audio.isPlaying, isFalse);
      expect(controller.queueIndex, 1);
    },
  );

  test(
    'stopping DJ during a refill preserves current playback and ignores results',
    () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final controller = await createTestController(
        tracks: [first, second, third],
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(first);
      await controller.startPersonalDj(includeDiscovery: true);
      await _waitFor(() => source.searchQueries.isNotEmpty);
      final queueBefore = List.of(controller.queue);
      final currentBefore = controller.currentTrack?.id;
      controller.stopPersonalDj();
      source.pendingSearch!.complete([
        const Track(
          id: 'dj-found',
          title: 'Found',
          artist: 'Artista',
          pageUrl: 'https://youtu.be/dj-found',
        ),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.personalDjActive, isFalse);
      expect(controller.audio.isPlaying, isTrue);
      expect(controller.currentTrack?.id, currentBefore);
      expect(
        controller.queue.map((track) => track.id),
        queueBefore.map((track) => track.id),
      );
    },
  );

  test('DJ search errors are contained', () async {
    final source = FakeSource()..searchError = StateError('offline');
    final controller = await createTestController(
      tracks: [first, second, third],
      source: source,
    );
    addTearDown(() => closeTestController(controller));
    await controller.toggleFavorite(first);
    await controller.startPersonalDj(includeDiscovery: true);
    await _waitFor(() => controller.personalDjError != null);
    expect(controller.audio.isPlaying, isTrue);
    expect(controller.error, isNull);
  });

  test(
    'DJ discovery never repeats a query and uses bounded searches',
    () async {
      final source = FakeSource()
        ..searchMatches = [
          for (var i = 0; i < 6; i++)
            Track(
              id: 'remote-$i',
              title: 'Remote $i',
              artist: 'Remote artist $i',
              pageUrl: 'https://youtu.be/remote-$i',
            ),
        ];
      final tracks = _djLibrary();
      final controller = await createTestController(
        tracks: tracks,
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(tracks.first);
      await controller.startPersonalDj(includeDiscovery: true);
      final audio = controller.audio as FakeAudio;

      for (var completion = 0; completion < 12; completion++) {
        if (!controller.audio.isPlaying) break;
        final loadCount = audio.loadCount;
        audio.position = audio.duration;
        audio.completions.add(null);
        await _waitFor(
          () => audio.loadCount > loadCount || !controller.audio.isPlaying,
        );
      }

      expect(source.searchQueries.first, 'artist 0 songs');
      expect(
        source.searchQueries.toSet(),
        hasLength(source.searchQueries.length),
      );
      expect(source.searchLimits, everyElement(12));
    },
  );

  test('empty library has no DJ or discovery action', () async {
    final empty = await createTestController();
    addTearDown(() => closeTestController(empty));
    await empty.startPersonalDj();
    await empty.discoverRecommendations();
    expect(empty.canStartPersonalDj, isFalse);
    expect(empty.audio.isPlaying, isFalse);
    expect((empty.source as FakeSource).searchQueries, isEmpty);
  });

  test(
    'early completion after seeking or a truncated stream does not advance',
    () async {
      final controller = await createTestController(tracks: [first, second]);
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first, context: [first, second]);
      final audio = controller.audio as FakeAudio;
      audio.position = const Duration(seconds: 30);
      audio.completions.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.currentTrack?.id, first.id);

      audio.position = audio.duration;
      audio.completions.add(null);
      await _waitFor(() => controller.currentTrack?.id == second.id);
    },
  );

  test('completion within the engine tolerance still advances', () async {
    final controller = await createTestController(tracks: [first, second]);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(first, context: [first, second]);
    final audio = controller.audio as FakeAudio;
    audio.position = audio.duration - const Duration(milliseconds: 900);
    audio.completions.add(null);
    await _waitFor(() => controller.currentTrack?.id == second.id);
  });

  test(
    'shuffle keeps skipping failing tracks while some remain unplayed',
    () async {
      Completer<ResolvedAudio> failing() => Completer<ResolvedAudio>()
        ..future.ignore()
        ..completeError(StateError('boom'));
      final source = FakeSource()
        ..pendingResolves['two'] = failing()
        ..pendingResolves['three'] = failing();
      final controller = await createTestController(
        source: source,
        tracks: [first, second, third],
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first, context: [first, second, third]);
      controller.shuffle = true;
      final audio = controller.audio as FakeAudio;
      audio.position = audio.duration;
      audio.completions.add(null);
      // Whichever fails first (even at the last index), the other is tried.
      await _waitFor(
        () =>
            source.resolved.contains('two') &&
            source.resolved.contains('three'),
      );
    },
  );

  test('older extraction cannot replace a newer selected track', () async {
    final source = FakeSource();
    source.pendingResolves['one'] = Completer<ResolvedAudio>();
    final controller = await createTestController(source: source);
    addTearDown(() => closeTestController(controller));
    final original = controller.playTrack(first);
    while (!source.resolved.contains('one')) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.playTrack(second);
    source.pendingResolves['one']!.complete(
      const ResolvedAudio(input: 'https://example.test/old'),
    );
    await original;
    expect(controller.currentTrack?.id, second.id);
    expect((controller.audio as FakeAudio).loaded?.input, contains('two'));
  });

  test(
    'favorites and playlist ordering are persisted, stale playlist edits merge',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(first);
      await controller.createPlaylist('Viaje');
      final stale = controller.playlists.single;
      await controller.addToPlaylist(stale, first);
      await controller.addToPlaylist(stale, second);
      await controller.reorderPlaylist(stale, 0, 2);
      expect((await controller.database.readPlaylists()).single.trackIds, [
        'two',
        'one',
      ]);
      expect(await controller.database.readFavorites(), {'one'});
    },
  );

  test(
    'downloads run serially and become playable local library files',
    () async {
      final source = FakeSource()..downloadGate = Completer<void>();
      final controller = await createTestController(source: source);
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      await controller.downloadTrack(second);
      while (source.activeDownloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      source.downloadGate!.complete();
      while (controller.downloads.any(
        (job) =>
            job.status == DownloadStatus.queued ||
            job.status == DownloadStatus.downloading,
      )) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(source.maxActiveDownloads, 1);
      expect(
        controller.tracks.every((track) => track.localPath != null),
        isTrue,
      );
      await controller.playTrack(controller.tracks.first);
      expect(source.resolved, isEmpty);
    },
  );

  test(
    'concurrent playlist additions and stale rename preserve every item',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.createPlaylist('Primera');
      final stale = controller.playlists.single;
      await Future.wait([
        controller.addToPlaylist(stale, first),
        controller.addToPlaylist(stale, second),
        controller.addToPlaylist(stale, third),
      ]);
      await controller.renamePlaylist(stale, 'Final');
      final saved = (await controller.database.readPlaylists()).single;
      expect(saved.name, 'Final');
      expect(saved.trackIds.toSet(), {'one', 'two', 'three'});
    },
  );

  test(
    'session restores paused with saved position and no network access',
    () async {
      final source = FakeSource();
      final controller = await createTestController(
        source: source,
        tracks: [first, second],
        preferences: {
          'queue': ['one', 'two'],
          'queueIndex': 1,
          'position': 42000,
        },
      );
      addTearDown(() => closeTestController(controller));
      expect(controller.currentTrack?.id, 'two');
      expect(controller.audio.isPlaying, isFalse);
      expect(source.resolved, isEmpty);
      await controller.persistSession();
      expect(controller.preferences.getInt('position'), 42000);
      await controller.togglePlayback();
      expect(controller.audio.position, const Duration(seconds: 42));
    },
  );

  test(
    'stale favorites preserve offline files and deletion retains library metadata',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final file = File(controller.tracks.single.localPath!);
      await controller.toggleFavorite(first);
      expect(controller.tracks.single.localPath, file.path);
      await controller.createPlaylist('Offline');
      await controller.addToPlaylist(controller.playlists.single, first);
      await controller.removeDownload(controller.downloads.single);
      expect(await file.exists(), isFalse);
      expect(controller.tracks.single.localPath, isNull);
      expect(controller.downloads, isEmpty);
      expect(await controller.database.readDownloads(), isEmpty);
      expect(await controller.database.readFavorites(), {'one'});
      expect(controller.playlists.single.trackIds, ['one']);
    },
  );

  test(
    'Windows download deletion accepts equivalent drive casing',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final job = controller.downloads.single;
      final original = File(job.localPath!);
      final path = original.absolute.path;
      expect(path[1], ':');
      final drive = path[0] == path[0].toUpperCase()
          ? path[0].toLowerCase()
          : path[0].toUpperCase();
      job.localPath = '$drive${path.substring(1)}';
      await controller.removeDownload(job);
      expect(controller.error, isNull);
      expect(await original.exists(), isFalse);
      expect(controller.downloads, isEmpty);
    },
    skip: !Platform.isWindows,
  );

  test('download deletion rejects files outside app storage', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    final directory = Directory(
      '${controller.supportDirectory.path}/downloads',
    );
    await directory.create();
    final outside = File('${controller.supportDirectory.path}/keep.mp3');
    await outside.writeAsBytes([1, 2, 3]);
    final job = DownloadJob(id: 'outside', track: first)
      ..status = DownloadStatus.completed
      ..localPath = outside.path;
    controller.downloads.add(job);
    await controller.removeDownload(job);
    expect(await outside.exists(), isTrue);
    expect(controller.downloads, contains(job));
    expect(controller.error, contains('fuera'));
  });

  test(
    'download jobs retain their destination root and never overwrite files',
    () async {
      final controller = await createTestController();
      addTearDown(() => closeTestController(controller));
      await controller.downloadTrack(first);
      while (controller.downloads.single.status != DownloadStatus.completed) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final job = controller.downloads.single;
      final original = File(job.localPath!);
      expect(
        job.destinationRoot,
        await Directory(original.parent.path).resolveSymbolicLinks(),
      );
      await controller.preferences.setString(
        'downloadsDirectory',
        '${controller.supportDirectory.path}/another-folder',
      );
      await controller.removeDownload(job);
      expect(await original.exists(), isFalse);
    },
  );

  test(
    'expired remote audio is re-extracted once and resumes position',
    () async {
      final source = FakeSource()..expiredStream = true;
      final audio = FakeAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first);
      audio.position = const Duration(seconds: 27);
      audio.lastError = 'HTTP 403 Forbidden';
      audio.notifyListeners();
      while (controller.busy) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(source.resolved, ['one', 'one']);
      expect(audio.position, const Duration(seconds: 27));
      audio.lastError = 'HTTP 403 Forbidden';
      audio.notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.resolved.length, 2);
    },
  );
  test(
    '429 stops playback recovery even when the cached URL expired',
    () async {
      final source = FakeSource()..expiredStream = true;
      final audio = FakeAudio();
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first);
      audio.lastError = 'HTTP 429 Too Many Requests';
      audio.notifyListeners();
      expect(source.resolved, ['one']);
      expect(source.playbackFailures, ['HTTP 429 Too Many Requests']);
      expect(controller.busy, false);
    },
  );
  test(
    'a proxy 410 while opening the stream re-resolves once and plays',
    () async {
      final source = FakeSource();
      final audio = FakeAudio()
        ..loadErrors.add(
          StateError(
            '[in#0 @ 000001] Error opening input: Server returned 4XX Client '
            'Error, but not one of 40{0,1,3,4}',
          ),
        );
      final controller = await createTestController(
        source: source,
        audio: audio,
      );
      addTearDown(() => closeTestController(controller));
      await controller.playTrack(first);
      expect(source.resolved, ['one', 'one']);
      expect(audio.loadCount, 1);
      expect(controller.error, isNull);
      expect(audio.isPlaying, true);
    },
  );
  test('the open retry happens once and only for stream errors', () async {
    final source = FakeSource();
    final audio = FakeAudio()
      ..loadErrors.addAll([
        StateError(
          'Server returned 4XX Client Error, but not one of 40{0,1,3,4}',
        ),
        StateError(
          'Server returned 4XX Client Error, but not one of 40{0,1,3,4}',
        ),
      ]);
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(first);
    expect(source.resolved, ['one', 'one']);
    expect(controller.error, contains('4XX'));
    audio.loadErrors.add(StateError('Formato de audio no compatible'));
    await controller.playTrack(first);
    expect(source.resolved, ['one', 'one', 'one']);
  });
  test('status digits in an audio path never report a YouTube block', () async {
    final source = FakeSource();
    final audio = FakeAudio();
    final controller = await createTestController(source: source, audio: audio);
    addTearDown(() => closeTestController(controller));
    await controller.playTrack(first);
    audio.lastError = 'Cannot inspect audio403.webm';
    audio.notifyListeners();
    expect(source.playbackFailures, isEmpty);
    expect(source.resolved, ['one']);
    expect(controller.error, 'Cannot inspect audio403.webm');
  });

  test(
    'reordering duplicate queue entries preserves the selected occurrence',
    () async {
      final controller = await createTestController(
        tracks: [first, second],
        preferences: {
          'queue': ['one', 'one', 'two'],
          'queueIndex': 1,
          'position': 42000,
        },
      );
      addTearDown(() => closeTestController(controller));
      await controller.reorderQueue(2, 0);
      expect(controller.queueIndex, 2);
      expect(controller.currentTrack?.id, 'one');
      await controller.playQueueAt(2);
      expect(controller.queueIndex, 2);
      expect(controller.audio.position, Duration.zero);
      await controller.removeFromQueue(2);
      expect(controller.audio.position, Duration.zero);
    },
  );

  test(
    'shutdown waits for an active download before closing its database',
    () async {
      final source = FakeSource()..downloadGate = Completer<void>();
      final controller = await createTestController(source: source);
      await controller.downloadTrack(first);
      while (source.activeDownloads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.dispose();
      source.downloadGate!.complete();
      await controller.closed;
      await controller.supportDirectory.delete(recursive: true);
      expect(source.activeDownloads, 0);
    },
  );
}
