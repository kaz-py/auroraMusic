import 'dart:async';
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_playback_bridge.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/sources/web_music_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const webTrack = Track(
  id: 'yt:abcdefghijk',
  title: 'Web Song',
  artist: 'Artist',
  pageUrl: 'https://youtu.be/abcdefghijk?si=secret',
);
const radioTrack = Track(
  id: 'radio',
  title: 'Radio Song',
  artist: 'Artist',
  pageUrl: 'https://radio.example.test/song.mp3',
);

class _DelayedPlayAudio extends FakeAudio {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> play() async {
    started.complete();
    await release.future;
    await super.play();
  }
}

Future<AppController> _controller({
  List<Track> tracks = const [],
  FakeSource? utility,
  FakeAudio? audio,
  Directory? directory,
  Map<String, Object> preferences = const {},
}) async {
  SharedPreferences.setMockInitialValues({'autoRefill': false, ...preferences});
  final prefs = await SharedPreferences.getInstance();
  final database = LibraryDatabase.memory();
  for (final track in tracks) {
    await database.saveTrack(track);
  }
  final app = AppController(
    audio: audio ?? FakeAudio(),
    source: WebMusicSource(utility ?? FakeSource()),
    database: database,
    preferences: prefs,
    supportDirectory:
        directory ?? await Directory.systemTemp.createTemp('web_routing_'),
  );
  await app.initialize(mediaControls: false);
  addTearDown(() => closeTestController(app));
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'web navigation preserves stored queue and ignores native transport and completion',
    () async {
      final utility = FakeSource(), audio = FakeAudio();
      final app = await _controller(
        tracks: [radioTrack, webTrack],
        utility: utility,
        audio: audio,
        preferences: {
          'queue': [radioTrack.id, webTrack.id],
          'queueIndex': 0,
        },
      );
      final originalIds = app.queue.map((track) => track.id).toList();
      await app.playTrack(webTrack, context: [webTrack, radioTrack]);
      expect(
        app.youtubeMusicRequest.toString(),
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
      expect(app.youtubeMusicActive, isTrue);
      expect(app.queue.map((track) => track.id), originalIds);
      expect(app.queueIndex, 0);
      expect(audio.loadCount, 0);
      app.clearYouTubeMusicRequest();
      expect(app.youtubeMusicRequest, isNull);
      expect(app.youtubeMusicActive, isTrue);
      await app.next();
      await app.previous();
      await app.resumePlayback();
      await app.playQueueAt(1);
      await app.addToQueue(webTrack);
      audio.completions.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(audio.loadCount, 0);
      expect(utility.resolved, isEmpty);
      expect(app.queue.map((track) => track.id), originalIds);
      expect(app.preferences.getStringList('queue'), originalIds);
      expect(app.queueIndex, 0);
      expect(app.recentTracks, isEmpty);
    },
  );

  test(
    'existing local YouTube file stays native and wins over its online alias',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'web_historical_',
      );
      final file = await File(
        '${directory.path}/song.mp3',
      ).writeAsBytes([1, 2, 3]);
      final local = webTrack.copyWith(localPath: file.path);
      final utility = FakeSource(), audio = FakeAudio();
      final app = await _controller(
        tracks: [local, radioTrack],
        utility: utility,
        audio: audio,
        directory: directory,
      );
      app.openYouTubeMusic();
      await app.playTrack(webTrack, context: [webTrack, radioTrack]);
      expect(audio.loaded?.input, file.path);
      expect(audio.isPlaying, isTrue);
      expect(app.youtubeMusicActive, isFalse);
      expect(app.youtubeMusicRequest, isNull);
      expect(utility.resolved, isEmpty);
      expect(app.currentTrack?.isLocal, isTrue);
      expect(app.recentTracks, isEmpty);
      audio.advanceTo(const Duration(seconds: 6));
      await Future<void>.delayed(Duration.zero);
      expect(app.recentTracks.single.id, local.id);
      await app.next();
      expect(audio.loaded?.input, radioTrack.pageUrl);
      expect(app.currentTrack?.id, radioTrack.id);
    },
  );

  test(
    'missing historical local file routes to official player without offline extraction',
    () async {
      final utility = FakeSource(), audio = FakeAudio();
      final directory = await Directory.systemTemp.createTemp('web_missing_');
      final missing = webTrack.copyWith(
        localPath: '${directory.path}/missing.mp3',
      );
      final app = await _controller(
        tracks: [missing],
        utility: utility,
        audio: audio,
        directory: directory,
        preferences: {
          'queue': [missing.id],
          'queueIndex': 0,
        },
      );
      await app.resumePlayback();
      expect(app.youtubeMusicRequest?.host, 'music.youtube.com');
      expect(audio.loadCount, 0);
      expect(utility.resolved, isEmpty);
      expect(app.tracks.single.localPath, missing.localPath);
    },
  );

  test(
    'restored native queue skips online YouTube entries on next and previous',
    () async {
      final next = const Track(
        id: 'next-radio',
        title: 'Next',
        artist: 'Station',
        pageUrl: 'https://radio.example.test/next.mp3',
      );
      final audio = FakeAudio();
      final app = await _controller(
        tracks: [radioTrack, webTrack, next],
        audio: audio,
        preferences: {
          'queue': [radioTrack.id, webTrack.id, next.id],
          'queueIndex': 0,
        },
      );
      await app.resumePlayback();
      await app.next();
      expect(app.currentTrack?.id, next.id);
      expect(app.youtubeMusicRequest, isNull);
      await app.previous();
      expect(app.currentTrack?.id, radioTrack.id);
      await app.next();
      await app.next();
      expect(audio.isPlaying, isFalse);
      expect(audio.loadCount, 4);
      expect(app.queue.length, 3);
    },
  );

  test(
    'new native contexts exclude web entries and adding web never extends local queue',
    () async {
      final app = await _controller(tracks: [radioTrack, webTrack]);
      await app.playTrack(radioTrack, context: [radioTrack, webTrack]);
      expect(app.queue.map((track) => track.id), [radioTrack.id]);
      await app.addToQueue(webTrack);
      expect(app.queue.map((track) => track.id), [radioTrack.id]);
      expect(app.youtubeMusicRequest?.host, 'music.youtube.com');
    },
  );

  test(
    'shared search and DJ use actual native library without network discovery',
    () async {
      final directory = await Directory.systemTemp.createTemp('web_search_');
      final file = await File('${directory.path}/saved.mp3').writeAsBytes([1]);
      final local = const Track(
        id: 'local',
        title: 'Saved Song',
        artist: 'Artist',
      ).copyWith(localPath: file.path);
      final missing = const Track(
        id: 'missing',
        title: 'Missing Song',
        artist: 'Artist',
      ).copyWith(localPath: '${directory.path}/absent');
      final utility = FakeSource();
      final app = await _controller(
        tracks: [webTrack, radioTrack, local, missing],
        utility: utility,
        directory: directory,
      );
      await app.search('Song');
      expect(
        app.searchResults.map((track) => track.id),
        unorderedEquals([radioTrack.id, local.id]),
      );
      expect(app.canDiscoverRecommendations, isFalse);
      await app.discoverRecommendations();
      app.setPersonalDjIncludeDiscovery(true);
      expect(app.personalDjIncludeDiscovery, isFalse);
      expect(
        app.recommendations.every((item) => app.isNativePlayable(item.track)),
        isTrue,
      );
      await app.startPersonalDj(includeDiscovery: true);
      expect(app.personalDjIncludeDiscovery, isFalse);
      expect(app.queue.every(app.isNativePlayable), isTrue);
      expect(utility.searchQueries, isEmpty);
      expect(utility.resolved, isEmpty);
    },
  );

  test(
    'audio download rejects web tracks and playlist import navigates without listing',
    () async {
      final utility = FakeSource();
      final app = await _controller(tracks: [webTrack], utility: utility);
      await app.downloadTrack(webTrack);
      expect(app.downloads, isEmpty);
      expect(utility.maxActiveDownloads, 0);
      expect(app.error, contains('solo de video'));
      await app.importPlaylist(
        'https://www.youtube.com/playlist?list=PLabc&token=secret',
      );
      expect(
        app.youtubeMusicRequest.toString(),
        'https://music.youtube.com/playlist?list=PLabc',
      );
      expect(app.playlists, isEmpty);
      expect(utility.searchQueries, isEmpty);
    },
  );

  test(
    'Spotify matching routes official playback and keeps native queue isolated',
    () async {
      const spotify = Track(
        id: 'spotify:one',
        title: 'Web Song',
        artist: 'Artist',
        spotifyUri: 'spotify:track:one',
        spotifyMatchPending: true,
      );
      final utility = FakeSource(), audio = FakeAudio();
      final app = await _controller(
        tracks: [spotify, radioTrack],
        utility: utility,
        audio: audio,
      );
      await app.playTrack(radioTrack);
      expect(await app.findSpotifyMatches(spotify), isEmpty);
      expect(
        await app.matchSpotifyTrack(spotify.id, webTrack, play: true),
        isTrue,
      );
      expect(app.youtubeMusicRequest?.queryParameters['v'], 'abcdefghijk');
      expect(app.queue.map((track) => track.id), [radioTrack.id]);
      expect(utility.searchQueries, isEmpty);
      expect(utility.resolved, isEmpty);
      expect(audio.loadCount, 1);
      expect(
        await app.importSpotifyMetadataMatch(spotify, webTrack, play: true),
        isTrue,
      );
      expect(audio.loadCount, 1);
      expect(app.queue.map((track) => track.id), [radioTrack.id]);
    },
  );

  test(
    'Jam web track opens official player once without native resolution or synchronization',
    () async {
      final utility = FakeSource(), audio = FakeAudio();
      final app = await _controller(utility: utility, audio: audio);
      final service = JamService();
      service.queue = [
        JamQueueEntry(
          id: 'web-entry',
          track: JamTrack.fromTrack(webTrack),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(app: app, service: service);
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
      });
      await bridge.enable();
      const state = JamPlayback(
        sequence: 1,
        entryId: 'web-entry',
        serverTimeMs: 1000,
        positionMs: 3000,
        isPlaying: true,
      );
      await bridge.apply(state);
      expect(app.youtubeMusicRequest?.queryParameters['v'], 'abcdefghijk');
      expect(bridge.warning, contains('no se sincronizan'));
      expect(audio.loadCount, 0);
      expect(audio.isPlaying, isFalse);
      app.clearYouTubeMusicRequest();
      await bridge.apply(state);
      expect(app.youtubeMusicRequest, isNull);
      expect(utility.resolved, isEmpty);
      expect(utility.searchQueries, isEmpty);
      expect(app.queue, isEmpty);
    },
  );

  test('Jam uses historical local file before online alias', () async {
    final directory = await Directory.systemTemp.createTemp('web_jam_local_');
    final file = await File('${directory.path}/saved.mp3').writeAsBytes([1]);
    final local = webTrack.copyWith(localPath: file.path);
    final utility = FakeSource(), audio = FakeAudio();
    final app = await _controller(
      tracks: [local],
      utility: utility,
      audio: audio,
      directory: directory,
    );
    final service = JamService();
    service.queue = [
      JamQueueEntry(
        id: 'local-entry',
        track: JamTrack.fromTrack(webTrack),
        addedBy: 'host',
      ),
    ];
    final bridge = JamPlaybackBridge(app: app, service: service)
      ..remember(webTrack);
    addTearDown(() async {
      await bridge.disable();
      bridge.dispose();
      service.dispose();
    });
    await bridge.enable();
    await bridge.apply(
      const JamPlayback(
        sequence: 1,
        entryId: 'local-entry',
        serverTimeMs: 1000,
        isPlaying: true,
      ),
    );
    expect(audio.loaded?.input, file.path);
    expect(audio.isPlaying, isTrue);
    expect(app.youtubeMusicRequest, isNull);
    expect(utility.resolved, isEmpty);
  });

  test(
    'unsafe web navigation cannot forward credentials or replace a valid request',
    () async {
      final app = await _controller();
      app.openYouTubeMusic(Uri.parse(webTrack.pageUrl!));
      final valid = app.youtubeMusicRequest;
      app.openYouTubeMusic(
        Uri.parse('https://name:secret@music.youtube.com/watch?v=abcdefghijk'),
      );
      expect(app.youtubeMusicRequest, valid);
      expect(app.error, isNotNull);
    },
  );

  test(
    'closing web leaves native playback paused until explicit resume',
    () async {
      final audio = FakeAudio();
      final app = await _controller(tracks: [radioTrack], audio: audio);
      await app.playTrack(radioTrack);
      app.openYouTubeMusic();
      await Future<void>.delayed(Duration.zero);
      expect(audio.isPlaying, isFalse);
      await app.removeFromQueue(0);
      expect(audio.isPlaying, isFalse);
      expect(app.youtubeMusicActive, isTrue);
      app.closeYouTubeMusic();
      expect(app.youtubeMusicActive, isFalse);
      expect(app.youtubeMusicRequest, isNull);
      expect(audio.isPlaying, isFalse);
      audio.completions.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(audio.loadCount, 1);
      await app.playTrack(radioTrack);
      expect(audio.isPlaying, isTrue);
    },
  );

  test(
    'web navigation wins over native play already awaiting completion',
    () async {
      final audio = _DelayedPlayAudio();
      final app = await _controller(tracks: [radioTrack], audio: audio);
      final playing = app.playTrack(radioTrack);
      await audio.started.future;
      app.openYouTubeMusic();
      audio.release.complete();
      await playing;
      expect(app.youtubeMusicActive, isTrue);
      expect(audio.isPlaying, isFalse);
      expect(app.recentTracks, isEmpty);
    },
  );

  test(
    'Jam frames and disabling Jam cannot restore native audio during web playback',
    () async {
      final audio = FakeAudio(), utility = FakeSource();
      final app = await _controller(
        tracks: [radioTrack],
        audio: audio,
        utility: utility,
      );
      await app.playTrack(radioTrack);
      final service = JamService();
      service.queue = [
        JamQueueEntry(
          id: 'native-entry',
          track: JamTrack.fromTrack(radioTrack),
          addedBy: 'host',
        ),
      ];
      final bridge = JamPlaybackBridge(app: app, service: service)
        ..remember(radioTrack);
      addTearDown(() async {
        await bridge.disable();
        bridge.dispose();
        service.dispose();
      });
      await bridge.enable();
      app.openYouTubeMusic();
      await bridge.apply(
        const JamPlayback(
          sequence: 1,
          entryId: 'native-entry',
          serverTimeMs: 1000,
          isPlaying: true,
        ),
      );
      expect(bridge.warning, contains('suspendida'));
      expect(audio.loadCount, 1);
      expect(audio.isPlaying, isFalse);
      await bridge.disable();
      expect(audio.loadCount, 1);
      expect(app.youtubeMusicActive, isTrue);
      expect(app.queue.single.id, radioTrack.id);
      expect(utility.resolved, isEmpty);
    },
  );
}
