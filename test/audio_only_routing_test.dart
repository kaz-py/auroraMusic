import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/sources/web_music_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

class _InitializationAudio extends FakeAudio {
  int initializeCalls = 0;
  int pauseCalls = 0;
  bool initialized = false;
  bool failInitialization = false;
  Track? metadata;
  @override
  Track? currentTrackMetadata;

  void emitMetadata(Track track) {
    currentTrackMetadata = track;
    notifyListeners();
  }

  @override
  Future<void> updateTrackMetadata(Track track) async => metadata = track;

  @override
  Future<void> initialize() async {
    initializeCalls++;
    if (failInitialization) throw StateError('Synthetic audio startup failure');
    initialized = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    if (!initialized) throw StateError('Synthetic audio not initialized');
    await super.pause();
  }
}

class _FailingLibraryDatabase extends LibraryDatabase {
  _FailingLibraryDatabase() : super.memory();
  bool failReads = true;
  int saveCalls = 0;

  @override
  Future<void> saveTrack(Track track) {
    saveCalls++;
    return super.saveTrack(track);
  }

  @override
  Future<List<Track>> readTracks() async {
    if (failReads) throw StateError('Synthetic library read failure');
    return super.readTracks();
  }
}

Future<AppController> _controller(
  _InitializationAudio audio, {
  bool audioOnly = false,
  FakeSource? utility,
  LibraryDatabase? database,
  Future<List<Track>> Function(String query, {int limit})? metadataSearch,
}) async {
  SharedPreferences.setMockInitialValues({'autoRefill': false});
  final app = AppController(
    audio: audio,
    source: WebMusicSource(
      utility ?? FakeSource(),
      audioOnly: audioOnly,
      metadataSearch: metadataSearch,
    ),
    database: database ?? LibraryDatabase.memory(),
    preferences: await SharedPreferences.getInstance(),
    supportDirectory: await Directory.systemTemp.createTemp('audio_routing_'),
  );
  addTearDown(() => closeTestController(app));
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('official source still initializes native audio at startup', () async {
    final audio = _InitializationAudio();
    final app = await _controller(audio);
    await app.initialize(mediaControls: false);

    expect(audio.initializeCalls, 1);
    expect(audio.initialized, isTrue);
    expect(app.ready, isTrue);
    expect(app.error, isNull);
  });

  test(
    'opening official viewer before native startup does not pause idle audio',
    () async {
      final audio = _InitializationAudio();
      final app = await _controller(audio);

      app.openYouTubeMusic();
      await Future<void>.delayed(Duration.zero);

      expect(audio.pauseCalls, 0);
      expect(audio.initializeCalls, 0);
      expect(app.youtubeMusicActive, isTrue);
      expect(app.error, isNull);
    },
  );

  test('official viewer pauses active or buffering native audio', () async {
    final audio = _InitializationAudio();
    final app = await _controller(audio);
    await app.initialize(mediaControls: false);

    audio.isPlaying = true;
    app.openYouTubeMusic();
    await Future<void>.delayed(Duration.zero);
    expect(audio.pauseCalls, 1);
    expect(audio.isPlaying, isFalse);

    app.closeYouTubeMusic();
    audio.isBuffering = true;
    app.openYouTubeMusic();
    await Future<void>.delayed(Duration.zero);
    expect(audio.pauseCalls, 2);
    expect(app.error, isNull);
  });

  test(
    'download directory failure still initializes native audio; retry is safe',
    () async {
      final audio = _InitializationAudio();
      final app = await _controller(audio);
      final obstruction = await File(
        '${app.supportDirectory.path}/downloads',
      ).writeAsString('Synthetic directory obstruction');

      await app.initialize(mediaControls: false);

      expect(app.ready, isTrue);
      expect(app.error, isNotNull);
      expect(audio.initializeCalls, 1);
      expect(audio.initialized, isTrue);
      final startupError = app.error;
      app.openYouTubeMusic();
      await Future<void>.delayed(Duration.zero);
      expect(audio.pauseCalls, 0);
      expect(app.error, startupError);

      await obstruction.delete();
      app.clearError();
      await app.initialize(mediaControls: false);
      expect(audio.initializeCalls, 1);
      expect(audio.initialized, isTrue);
      expect(app.error, isNull);
    },
  );

  test(
    'native initialization failure is reported without idle viewer pause',
    () async {
      final audio = _InitializationAudio()..failInitialization = true;
      final app = await _controller(audio);
      await app.initialize(mediaControls: false);

      expect(audio.initializeCalls, 1);
      expect(audio.initialized, isFalse);
      expect(app.ready, isFalse);
      expect(app.error, contains('Synthetic audio startup failure'));
      app.openYouTubeMusic();
      await Future<void>.delayed(Duration.zero);
      expect(audio.pauseCalls, 0);
      expect(app.error, contains('Synthetic audio startup failure'));
      await app.playTrack(
        const Track(
          id: 'radio',
          title: 'Radio',
          artist: 'Station',
          pageUrl: 'https://radio.example.test/song.mp3',
        ),
      );
      expect(audio.loadCount, 0);
      expect(app.error, contains('audio no está preparado'));
      audio.failInitialization = false;
      await app.initialize(mediaControls: false);
      expect(audio.initializeCalls, 2);
      expect(app.ready, isTrue);
      expect(app.error, isNull);
    },
  );

  test(
    'database read failure cannot skip native startup; restoration retries',
    () async {
      final audio = _InitializationAudio();
      final database = _FailingLibraryDatabase();
      final app = await _controller(audio, database: database);
      await app.initialize(mediaControls: false);
      expect(audio.initializeCalls, 1);
      expect(audio.initialized, isTrue);
      expect(app.ready, isTrue);
      expect(app.error, contains('Synthetic library read failure'));
      database.failReads = false;
      await app.initialize(mediaControls: false);
      expect(audio.initializeCalls, 1);
      expect(app.error, isNull);
    },
  );

  test(
    'audio mode uses one queue across official watch pages and local files',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final app = await _controller(audio, audioOnly: true, utility: utility);
      final file = await File(
        '${app.supportDirectory.path}/song.mp3',
      ).writeAsBytes([1, 2, 3]);
      final local = Track(
        id: 'local',
        title: 'Local',
        artist: 'Artist',
        localPath: file.path,
      );
      const web = Track(
        id: 'yt:abcdefghijk',
        title: 'Online',
        artist: 'Artist',
        pageUrl: 'https://youtu.be/abcdefghijk?si=discarded',
      );
      await app.initialize(mediaControls: false);
      await app.playTrack(web, context: [web, local]);
      expect(app.usesOfficialYouTubeMusic, isFalse);
      expect(app.usesYouTubeWebAudio, isTrue);
      expect(app.youtubeMusicRequest, isNull);
      expect(app.youtubeMusicActive, isFalse);
      expect(app.queue.map((track) => track.id), [web.id, local.id]);
      expect(
        audio.loaded?.input,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
      await app.next();
      expect(app.currentTrack?.id, local.id);
      expect(audio.loaded?.input, file.path);
      await app.previous();
      expect(app.currentTrack?.id, web.id);
      expect(
        audio.loaded?.input,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
      expect(utility.resolved, isEmpty);
      audio.advanceTo(const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);
      expect(app.recentTracks.map((track) => track.id), [web.id]);
      expect(app.preferences.getStringList('queue'), [web.id, local.id]);
      expect(audio.metadata?.id, web.id);
    },
  );

  test(
    'audio mode resolves legacy YouTube ids without an extracted URL',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final app = await _controller(audio, audioOnly: true, utility: utility);
      await app.initialize(mediaControls: false);
      const legacy = Track(
        id: 'yt:abcdefghijk',
        title: 'Legacy',
        artist: 'Artist',
      );
      await app.playTrack(legacy);
      expect(
        audio.loaded?.input,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
      expect(app.error, isNull);
      expect(utility.resolved, isEmpty);
    },
  );

  test('Spotify matching offers only real saved playback candidates', () async {
    final audio = _InitializationAudio(), utility = FakeSource();
    final app = await _controller(audio, audioOnly: true, utility: utility);
    const web = Track(
      id: 'yt:abcdefghijk',
      title: 'Known Song',
      artist: 'Known Artist',
      pageUrl: 'https://youtu.be/abcdefghijk',
    );
    const spotify = Track(
      id: 'spotify:synthetic',
      title: 'Known Song',
      artist: 'Known Artist',
      spotifyMatchPending: true,
    );
    await app.database.saveTrack(web);
    await app.database.saveTrack(spotify);
    await app.initialize(mediaControls: false);
    expect((await app.findSpotifyMatches(spotify)).single.id, web.id);
    expect(await app.matchSpotifyTrack(spotify.id, web, play: true), isTrue);
    expect(app.currentTrack?.id, spotify.id);
    expect(
      audio.loaded?.input,
      'https://music.youtube.com/watch?v=abcdefghijk',
    );
    expect(app.youtubeMusicRequest, isNull);
    expect(utility.searchQueries, isEmpty);
    expect(utility.resolved, isEmpty);
  });

  test(
    'web audio completion advances Aurora queue and honors repeat one',
    () async {
      final audio = _InitializationAudio();
      final app = await _controller(audio, audioOnly: true);
      const first = Track(
        id: 'yt:abcdefghijk',
        title: 'First',
        artist: 'Artist',
      );
      const second = Track(
        id: 'yt:lmnopqrstuv',
        title: 'Second',
        artist: 'Artist',
      );
      await app.initialize(mediaControls: false);
      await app.playTrack(first, context: [first, second]);
      audio.position = audio.duration;
      audio.completions.add(null);
      for (var attempt = 0; attempt < 100 && audio.loadCount < 2; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(app.currentTrack?.id, second.id);
      expect(audio.loadCount, 2);
      // Allow the controller's async persistence to complete before the next end.
      for (var attempt = 0; attempt < 100 && app.busy; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      app.repeat = RepeatMode.one;
      audio.position = audio.duration;
      audio.completions.add(null);
      for (var attempt = 0; attempt < 100 && audio.loadCount < 3; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(app.currentTrack?.id, second.id);
      expect(audio.loadCount, 3);
    },
  );

  test(
    'Spotify can match an existing local file without an online page',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final app = await _controller(audio, audioOnly: true, utility: utility);
      final file = await File(
        '${app.supportDirectory.path}/local.mp3',
      ).writeAsBytes([1]);
      final local = Track(
        id: 'local',
        title: 'Saved Song',
        artist: 'Saved Artist',
        localPath: file.path,
      );
      const spotify = Track(
        id: 'spotify:synthetic',
        title: 'Saved Song',
        artist: 'Saved Artist',
        spotifyMatchPending: true,
      );
      await app.database.saveTrack(local);
      await app.database.saveTrack(spotify);
      await app.initialize(mediaControls: false);
      expect((await app.findSpotifyMatches(spotify)).single.id, local.id);
      expect(
        await app.matchSpotifyTrack(spotify.id, local, play: true),
        isTrue,
      );
      expect(audio.loaded?.input, file.path);
      expect(app.currentTrack?.isLocal, isTrue);
      expect(app.currentTrack?.isPendingSpotifyMatch, isFalse);
      expect(utility.resolved, isEmpty);
      expect(app.youtubeMusicRequest, isNull);
    },
  );

  test(
    'audio mode search uses remembered metadata or an explicit watch link',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final app = await _controller(audio, audioOnly: true, utility: utility);
      const saved = Track(
        id: 'yt:abcdefghijk',
        title: 'Known Song',
        artist: 'Known Artist',
        pageUrl: 'https://music.youtube.com/watch?v=abcdefghijk',
      );
      await app.database.saveTrack(saved);
      await app.initialize(mediaControls: false);
      await app.search('Known');
      expect(app.searchResults.single.id, saved.id);
      await app.search('https://youtu.be/lmnopqrstuv?si=discarded');
      expect(app.searchResults.single.id, 'yt:lmnopqrstuv');
      expect(
        app.searchResults.single.pageUrl,
        'https://music.youtube.com/watch?v=lmnopqrstuv',
      );
      await app.search('Unknown Artist');
      expect(app.searchResults, isEmpty);
      expect(app.canDiscoverRecommendations, isFalse);
      await app.discoverRecommendations();
      expect(utility.searchQueries, isEmpty);
      expect(utility.resolved, isEmpty);
    },
  );

  test('audio mode refuses media URLs and playlist extraction', () async {
    final source = WebMusicSource(FakeSource(), audioOnly: true);
    addTearDown(source.dispose);
    await expectLater(
      source.resolve(
        const Track(
          id: 'signed-media',
          title: 'Media',
          artist: 'Artist',
          pageUrl: 'https://rr1.googlevideo.com/videoplayback?token=synthetic',
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      source.search(
        'https://name:synthetic@music.youtube.com/watch?v=abcdefghijk',
      ),
      throwsArgumentError,
    );
    await expectLater(
      source.importPlaylist(
        Uri.https('music.youtube.com', '/playlist', {'list': 'PLsynthetic'}),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'download availability rejects web, missing web files and pending Spotify',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final app = await _controller(audio, audioOnly: true, utility: utility);
      await app.initialize(mediaControls: false);
      const web = Track(
        id: 'yt:abcdefghijk',
        title: 'Online',
        artist: 'Artist',
        pageUrl: 'https://youtu.be/abcdefghijk',
      );
      final missing = web.copyWith(
        localPath: '${app.supportDirectory.path}/missing.mp3',
      );
      expect(app.canDownloadTrack(web), isFalse);
      expect(app.canDownloadTrack(missing), isFalse);
      expect(
        app.canDownloadTrack(
          const Track(
            id: 'spotify:synthetic',
            title: 'Pending',
            artist: 'Artist',
            spotifyMatchPending: true,
          ),
        ),
        isFalse,
      );
      expect(
        app.canDownloadTrack(
          const Track(
            id: 'radio',
            title: 'Radio',
            artist: 'Station',
            pageUrl: 'https://radio.example.test/song.mp3',
          ),
        ),
        isTrue,
      );
      await app.downloadTrack(missing);
      expect(app.error, contains('solo de video'));
      expect(app.downloads, isEmpty);
      expect(utility.maxActiveDownloads, 0);
    },
  );

  test(
    'current web metadata replaces link placeholder once and rejects stale ids',
    () async {
      final audio = _InitializationAudio();
      final database = _FailingLibraryDatabase()..failReads = false;
      final app = await _controller(audio, audioOnly: true, database: database);
      await app.initialize(mediaControls: false);
      await app.search('https://youtu.be/abcdefghijk');
      final linked = app.searchResults.single;
      await app.playTrack(linked);
      final writes = database.saveCalls;
      audio.emitMetadata(
        const Track(
          id: 'yt:lmnopqrstuv',
          title: 'Stale Song',
          artist: 'Other Artist',
        ),
      );
      expect(app.currentTrack?.title, 'YouTube Music');
      const observed = Track(
        id: 'yt:abcdefghijk',
        title: 'Observed Song',
        artist: 'Observed Artist',
      );
      audio.emitMetadata(observed);
      audio.emitMetadata(observed);
      expect(app.currentTrack?.title, observed.title);
      expect(app.currentTrack?.artist, observed.artist);
      expect(app.currentTrack?.pageUrl, linked.pageUrl);
      expect(app.currentTrack?.id, linked.id);
      expect(database.saveCalls, writes + 1);
      expect((await database.readTracks()).single.title, observed.title);
    },
  );

  test(
    'a larger observed cover updates the current song without repeated writes',
    () async {
      final audio = _InitializationAudio();
      final database = _FailingLibraryDatabase()..failReads = false;
      final app = await _controller(audio, audioOnly: true, database: database);
      await app.initialize(mediaControls: false);
      await app.search('https://youtu.be/abcdefghijk');
      await app.playTrack(app.searchResults.single);
      const observed = Track(
        id: 'yt:abcdefghijk',
        title: 'Observed Song',
        artist: 'Artist',
        artworkUrl: 'https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg',
      );
      audio.emitMetadata(observed);
      final writes = database.saveCalls;
      final improved = observed.copyWith(
        artworkUrl: 'https://i.ytimg.com/vi/abcdefghijk/maxresdefault.jpg',
      );
      audio.emitMetadata(improved);
      audio.emitMetadata(improved);
      audio.emitMetadata(observed);
      audio.emitMetadata(improved);
      audio.emitMetadata(observed);
      expect(app.currentTrack?.artworkUrl, improved.artworkUrl);
      expect(app.currentTrack?.title, observed.title);
      expect(database.saveCalls, writes + 1);
      audio.emitMetadata(
        observed.copyWith(artworkUrl: 'https://secret@i.ytimg.com/private.jpg'),
      );
      expect(app.currentTrack?.artworkUrl, improved.artworkUrl);
      expect(database.saveCalls, writes + 1);
    },
  );

  test(
    'optional website metadata merges with library without yt-dlp listing',
    () async {
      final audio = _InitializationAudio(), utility = FakeSource();
      final queries = <String>[];
      const saved = Track(
        id: 'yt:abcdefghijk',
        title: 'Known Song',
        artist: 'Known Artist',
        pageUrl: 'https://youtu.be/abcdefghijk',
      );
      const remote = Track(
        id: 'website-result',
        title: 'Known New Song',
        artist: 'Known Artist',
        pageUrl: 'https://youtu.be/lmnopqrstuv?si=discarded',
      );
      final app = await _controller(
        audio,
        audioOnly: true,
        utility: utility,
        metadataSearch: (String query, {int limit = 20}) async {
          queries.add(query);
          return [saved, remote];
        },
      );
      await app.database.saveTrack(saved);
      await app.initialize(mediaControls: false);
      await app.search('Known');
      expect(app.searchResults.map((track) => track.id), [
        saved.id,
        'yt:lmnopqrstuv',
      ]);
      expect(
        app.searchResults.last.pageUrl,
        'https://music.youtube.com/watch?v=lmnopqrstuv',
      );
      expect(queries, ['Known']);
      expect(app.canDiscoverRecommendations, isTrue);
      await app.search('https://youtu.be/wxyz1234567');
      expect(queries, ['Known']);
      expect(app.searchResults.single.id, 'yt:wxyz1234567');
      expect(utility.searchQueries, isEmpty);
      expect(utility.resolved, isEmpty);
    },
  );

  test(
    'website metadata failure keeps matching library results and reports error',
    () async {
      final app = await _controller(
        _InitializationAudio(),
        audioOnly: true,
        metadataSearch: (String query, {int limit = 20}) async =>
            throw StateError('Synthetic website search unavailable'),
      );
      const saved = Track(
        id: 'yt:abcdefghijk',
        title: 'Known Song',
        artist: 'Known Artist',
      );
      await app.database.saveTrack(saved);
      await app.initialize(mediaControls: false);
      await app.search('Known');
      expect(app.searchResults.single.id, saved.id);
      expect(app.error, contains('Synthetic website search unavailable'));
      expect(app.searching, isFalse);
    },
  );

  test(
    'website results cannot inject local files or signed media URLs',
    () async {
      final source = WebMusicSource(
        FakeSource(),
        audioOnly: true,
        metadataSearch: (String query, {int limit = 20}) async => const [
          Track(
            id: 'local-injected',
            title: 'Invalid',
            artist: 'Artist',
            localPath: 'synthetic.mp3',
          ),
          Track(
            id: 'signed-media',
            title: 'Invalid',
            artist: 'Artist',
            pageUrl:
                'https://rr1.googlevideo.com/videoplayback?token=synthetic',
          ),
          Track(
            id: 'public-watch',
            title: 'Real Public Metadata',
            artist: 'Real Artist',
            pageUrl: 'https://youtu.be/abcdefghijk',
          ),
        ],
      );
      addTearDown(source.dispose);
      final result = await source.search('Song');
      expect(result.single.id, 'yt:abcdefghijk');
      expect(result.single.localPath, isNull);
      expect(
        result.single.pageUrl,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
    },
  );
}
