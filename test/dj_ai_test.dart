import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/ai_dj.dart';
import 'package:aurora_music/dj/coherence.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track song(
  String id, {
  String? title,
  String artist = 'North',
  String? album,
  List<String> genres = const [],
}) => Track(
  id: id,
  title: title ?? 'Song $id',
  artist: artist,
  album: album,
  genres: genres,
  pageUrl: 'https://youtu.be/$id',
);

Future<void> settle(bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue);
}

void main() {
  group('embeddings', () {
    test('hashing is deterministic and ignores video noise', () {
      final a = embedDjTrack(song('a', title: 'Night Drive'));
      final b = embedDjTrack(song('b', title: 'Night Drive (Official Video)'));
      expect(a, hasLength(djVectorDims));
      expect(embedDjTrack(song('a', title: 'Night Drive')), a);
      expect(djCosine(a, b), closeTo(1, 1e-6));
      expect(djArtists('Bad Bunny feat. Drake & Rosalía, J Balvin'), [
        'bad bunny',
        'drake',
        'rosalía',
        'j balvin',
      ]);
      expect(
        djTrackFeatures(song('f', title: 'Hit (feat. Guest)')),
        contains('a:guest'),
      );
    });

    test('cosine handles identical, orthogonal and empty vectors', () {
      expect(djCosine([1, 0], [2, 0]), closeTo(1, 1e-9));
      expect(djCosine([1, 0], [0, 3]), 0);
      expect(djCosine([1, 0], [-1, 0]), closeTo(-1, 1e-9));
      expect(djCosine([0, 0], [1, 0]), 0);
    });

    test('profile decays old events and skips count against a track', () {
      final now = DateTime(2026, 10, 15);
      final fresh = song('fresh', artist: 'Alpha', genres: ['rock']);
      final old = song('old', artist: 'Beta', genres: ['jazz']);
      final skipped = song('skipped', artist: 'Gamma', genres: ['trap']);
      final known = {
        for (final t in [fresh, old, skipped]) t.id: t,
      };
      final profile = buildTasteProfile(
        favorites: const [],
        playlistTracks: const [],
        history: const [],
        events: [
          DjEvent(DjSignal.complete, 'fresh', now),
          DjEvent(
            DjSignal.complete,
            'old',
            now.subtract(const Duration(days: 28)),
          ),
          DjEvent(DjSignal.skip, 'skipped', now),
        ],
        known: known,
        now: now,
      );
      final toFresh = djCosine(profile.vector, embedDjTrack(fresh));
      final toOld = djCosine(profile.vector, embedDjTrack(old));
      expect(toFresh, greaterThan(toOld));
      expect(toOld, greaterThan(0));
      expect(djCosine(profile.vector, embedDjTrack(skipped)), lessThan(0));
      expect(profile.features['a:gamma'], lessThan(0));
    });

    test('events encode compactly and reject garbage', () {
      final event = DjEvent(
        DjSignal.skip,
        'id|with|pipes',
        DateTime.fromMillisecondsSinceEpoch(42),
      );
      final decoded = DjEvent.decode(event.encode())!;
      expect(decoded.signal, DjSignal.skip);
      expect(decoded.trackId, 'id|with|pipes');
      expect(decoded.at.millisecondsSinceEpoch, 42);
      expect(DjEvent.decode('x|1|a'), isNull);
      expect(DjEvent.decode('c|nope|a'), isNull);
      expect(
        djIsSkip(const Duration(seconds: 10), const Duration(minutes: 3)),
        isTrue,
      );
      expect(
        djIsSkip(const Duration(seconds: 50), const Duration(minutes: 3)),
        isTrue,
      );
      expect(
        djIsSkip(const Duration(seconds: 90), const Duration(minutes: 3)),
        isFalse,
      );
    });

    test('events: 3 partes (antiguo) y 4 con artista', () {
      final old = DjEvent.decode('s|123|id')!;
      expect(old.trackId, 'id');
      expect(old.artist, '');
      final withArtist = DjEvent.decode('s|123|id|artista')!;
      expect(withArtist.trackId, 'id');
      expect(withArtist.artist, 'artista');
      final event = DjEvent(
        DjSignal.complete,
        'yt:x',
        DateTime.fromMillisecondsSinceEpoch(5),
        artist: 'a|b',
      );
      expect(DjEvent.decode(event.encode())!.artist, 'ab');
    });

    test('rankDjCandidates con coherencia: afín antes que sin relación', () {
      final related = song('rel', artist: 'B');
      final unrelated = song('unr', artist: 'Z');
      final picks = rankDjCandidates(
        candidates: [
          DjCandidate(unrelated, 'z', prior: 0.9),
          DjCandidate(related, 'b', prior: 0.1),
        ],
        profile: List.filled(djVectorDims, 0),
        limit: 2,
        coherence: CoherenceContext(artists: ['A'], neighbors: ['B']),
      );
      expect(picks.first.track.id, related.id);
      final strict = rankDjCandidates(
        candidates: [
          DjCandidate(unrelated, 'z', prior: 0.9),
          DjCandidate(related, 'b', prior: 0.1),
        ],
        profile: List.filled(djVectorDims, 0),
        limit: 1,
        coherence: CoherenceContext(artists: ['A'], neighbors: ['B']),
      );
      expect(strict.map((r) => r.track.id), [related.id]);
    });

    test('la puerta descuenta los artistas ya presentes en la cola', () {
      final picks = rankDjCandidates(
        candidates: [
          DjCandidate(song('b1', artist: 'B'), 'b', prior: 0.5),
          for (final z in ['Z1', 'Z2', 'Z3', 'Z4'])
            DjCandidate(song(z.toLowerCase(), artist: z), 'z', prior: 0.1),
        ],
        profile: List.filled(djVectorDims, 0),
        limit: 4,
        queueTail: [
          song('q1', artist: 'B'),
          song('q2', artist: 'Y1'),
          song('q3', artist: 'B'),
          song('q4', artist: 'Y2'),
        ],
        coherence: CoherenceContext(artists: ['A'], neighbors: ['B']),
      );
      expect(picks, hasLength(4));
      expect(picks.map((r) => r.track.artist), isNot(contains('B')));
    });

    test('discovery queries come from the profile and do not repeat', () {
      final profile = buildTasteProfile(
        favorites: [
          song('a', artist: 'Alpha', genres: ['rock']),
        ],
        playlistTracks: [song('b', artist: 'Beta')],
        history: const [],
        events: const [],
        known: const {},
        now: DateTime(2026),
      );
      final first = djDiscoveryQueries(profile);
      expect(first.map((q) => q.query), ['alpha songs', 'rock music']);
      final next = djDiscoveryQueries(
        profile,
        used: first.map((q) => q.query).toSet(),
      );
      expect(next.map((q) => q.query), ['beta songs']);
    });
  });

  group('ranking', () {
    test('MMR prefers a diverse pick over a near duplicate', () {
      final taste = song(
        'taste',
        title: 'Night Drive',
        artist: 'Zed',
        album: 'Neon',
        genres: ['synthwave'],
      );
      final c1 = song(
        'c1',
        title: 'Night Drive',
        artist: 'Ana',
        album: 'Neon',
        genres: ['synthwave'],
      );
      final c2 = song(
        'c2',
        title: 'Night Drive',
        artist: 'Bea',
        album: 'Neon',
        genres: ['synthwave'],
      );
      final c3 = song('c3', title: 'Morning Coffee', artist: 'Cid');
      final candidates = [
        DjCandidate(c1, 'r'),
        DjCandidate(c2, 'r'),
        DjCandidate(c3, 'r', prior: 1),
      ];
      List<String> rank(double lambda) => rankDjCandidates(
        candidates: candidates,
        profile: embedDjTrack(taste),
        limit: 3,
        lambda: lambda,
      ).map((r) => r.track.id).toList();
      expect(rank(1.0), ['c1', 'c2', 'c3']);
      expect(rank(djMmrLambda).take(2), ['c1', 'c3']);
    });

    test('artist cooldown: never back-to-back and at most two per ten', () {
      final candidates = [
        for (var i = 0; i < 6; i++) DjCandidate(song('a$i', artist: 'A'), 'r'),
        for (var i = 0; i < 3; i++) DjCandidate(song('b$i', artist: 'B'), 'r'),
        for (var i = 0; i < 3; i++) DjCandidate(song('c$i', artist: 'C'), 'r'),
      ];
      final picks = rankDjCandidates(
        candidates: candidates,
        profile: embedDjTrack(song('x', artist: 'A')),
        limit: 10,
      ).map((r) => r.track.artist).toList();
      expect(picks, hasLength(6));
      for (var i = 1; i < picks.length; i++) {
        expect(picks[i], isNot(picks[i - 1]));
      }
      for (final artist in ['A', 'B', 'C']) {
        expect(picks.where((a) => a == artist), hasLength(2));
      }
    });

    test('filters always exclude and queued aliases are deduplicated', () {
      final queued = song('queued');
      final alias = song(
        'alias',
        artist: 'Other',
      ).copyWith(pageUrl: 'https://www.youtube.com/watch?v=queued&si=x');
      final picks = rankDjCandidates(
        candidates: [
          DjCandidate(alias, 'r', prior: 1),
          DjCandidate(song('banned', artist: 'Banned'), 'r', prior: 1),
          DjCandidate(song('ok', artist: 'Fine'), 'r'),
        ],
        profile: embedDjTrack(song('p', artist: 'Banned')),
        limit: 5,
        blockedKeys: recommendationTrackKeys(queued),
        filters: const DjFilters(excludedArtists: ['banned']),
      );
      expect(picks.map((r) => r.track.id), ['ok']);
    });

    test('refill threshold fills to the target below five upcoming', () {
      expect(djRefillCount(4), djUpcomingTarget - 4);
      expect(djRefillCount(0), djUpcomingTarget);
      expect(djRefillCount(5), 0);
      expect(djRefillCount(12, force: true), djUpcomingTarget - 12);
      expect(djRefillCount(25, force: true), 0);
    });
  });

  group('vector store', () {
    test(
      'nearest neighbours are ordered by cosine and honour exclusions',
      () async {
        final db = LibraryDatabase.memory();
        addTearDown(db.close);
        Float32List v(List<double> values) => Float32List.fromList(values);
        await db.upsertTrackVectors([
          (track: song('east'), vector: v([1, 0, 0])),
          (track: song('north-east'), vector: v([1, 1, 0])),
          (track: song('up'), vector: v([0, 0, 1])),
        ]);
        final nearest = await db.nearestTracks([1, 0.1, 0], k: 2);
        expect(nearest.map((n) => n.track.id), ['east', 'north-east']);
        expect(nearest.first.track.pageUrl, 'https://youtu.be/east');
        final excluded = await db.nearestTracks(
          [1, 0.1, 0],
          k: 2,
          exclude: {'east'},
        );
        expect(excluded.map((n) => n.track.id), ['north-east', 'up']);
        await db.upsertTrackVectors([
          (track: song('east'), vector: v([0, 0, 1])),
        ]);
        expect(await db.countTrackVectors(), 3);
        expect(
          (await db.nearestTracks([0, 0, 1], k: 1)).single.score,
          closeTo(1, 1e-6),
        );

        expect(await db.readTasteProfile(), isNull);
        await db.saveTasteProfile(v([0.5, 0.25]));
        expect(await db.readTasteProfile(), [0.5, 0.25]);
      },
    );

    test('migration from schema 1 keeps data and adds vector tables', () async {
      final track = song('kept');
      final json = jsonEncode(track.toJson()).replaceAll("'", "''");
      final db = LibraryDatabase.memory(
        setupSql: [
          'CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          'CREATE TABLE favorites (track_id TEXT PRIMARY KEY)',
          'CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, tracks TEXT NOT NULL)',
          'CREATE TABLE history (track_id TEXT PRIMARY KEY, played_at INTEGER NOT NULL)',
          'CREATE TABLE downloads (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
          "INSERT INTO tracks VALUES ('${track.id}', '$json')",
          "INSERT INTO favorites VALUES ('kept')",
          'PRAGMA user_version = 1',
        ],
      );
      addTearDown(db.close);
      expect((await db.readTracks()).single.id, 'kept');
      expect(await db.readFavorites(), {'kept'});
      await db.upsertTrackVectors([
        (track: track, vector: embedDjTrack(track)),
      ]);
      expect(
        (await db.nearestTracks(embedDjTrack(track), k: 1)).single.track.id,
        'kept',
      );
    });
  });

  group('controller', () {
    test('records early next as skip and completion as complete', () async {
      final tracks = [for (var i = 0; i < 3; i++) song('t$i', artist: 'A$i')];
      final controller = await createTestController(tracks: tracks);
      addTearDown(() => closeTestController(controller));
      final audio = controller.audio as FakeAudio;
      await controller.playTrack(tracks[0], context: tracks);
      audio.position = const Duration(seconds: 5);
      await controller.next();
      audio.position = audio.duration;
      audio.completions.add(null);
      await settle(() => controller.djEvents.length == 2);
      expect(controller.djEvents.first.signal, DjSignal.skip);
      expect(controller.djEvents.first.trackId, 't0');
      expect(controller.djEvents.last.signal, DjSignal.complete);
      expect(controller.djEvents.last.trackId, 't1');
      expect(controller.preferences.getStringList('djEvents'), hasLength(2));
    });

    test('keeps about twenty upcoming and refills below five', () async {
      final tracks = [for (var i = 0; i < 60; i++) song('t$i', artist: 'A$i')];
      final controller = await createTestController(tracks: tracks);
      addTearDown(() => closeTestController(controller));
      await controller.startPersonalDj();
      await settle(() => controller.queue.length == djUpcomingTarget + 1);
      final reasons = controller.personalDjReasons;
      expect(reasons, isNotEmpty);
      for (var i = 0; i < djUpcomingTarget - djRefillThreshold; i++) {
        await controller.next();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.queue, hasLength(djUpcomingTarget + 1));
      await controller.next();
      await settle(
        () =>
            controller.queue.length - controller.queueIndex - 1 ==
            djUpcomingTarget,
      );
      expect(
        controller.queue.map((t) => t.id).toSet(),
        hasLength(controller.queue.length),
      );
    });

    test('offline discovery falls back to local recommendations', () async {
      final source = FakeSource()..searchError = StateError('offline');
      final tracks = [for (var i = 0; i < 10; i++) song('t$i', artist: 'A$i')];
      final controller = await createTestController(
        tracks: tracks,
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(tracks.first);
      await controller.startPersonalDj(includeDiscovery: true);
      await settle(() => controller.queue.length == 10);
      expect(controller.personalDjError, contains('offline'));
      expect(source.searchQueries.first, 'a0 songs');
    });

    test('results of a stale generation are discarded', () async {
      final source = FakeSource()..pendingSearch = Completer<List<Track>>();
      final tracks = [for (var i = 0; i < 3; i++) song('t$i', artist: 'A$i')];
      final controller = await createTestController(
        tracks: tracks,
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(tracks.first);
      await controller.startPersonalDj(includeDiscovery: true);
      await settle(() => source.searchQueries.isNotEmpty);
      final stale = source.pendingSearch!;
      // Later refills (new generation) wait on a fresh, unanswered search.
      source.pendingSearch = Completer<List<Track>>();
      await controller.setDjFilters(const DjFilters());
      stale.complete([song('late', artist: 'Fresh')]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(controller.queue.any((t) => t.id == 'late'), isFalse);
    });

    test('discovered tracks are embedded and ranked into the queue', () async {
      final source = FakeSource()
        ..searchMatches = [song('new', artist: 'Fresh')];
      final tracks = [for (var i = 0; i < 3; i++) song('t$i', artist: 'A$i')];
      final controller = await createTestController(
        tracks: tracks,
        source: source,
      );
      addTearDown(() => closeTestController(controller));
      await controller.toggleFavorite(tracks.first);
      await controller.startPersonalDj(includeDiscovery: true);
      await settle(() => controller.queue.any((t) => t.id == 'new'));
      expect(
        (await controller.database.nearestTracks(
          embedDjTrack(song('new', artist: 'Fresh')),
          k: 1,
        )).single.track.id,
        'new',
      );
      expect(controller.personalDjReasons['new'], 'Porque escuchas a a0');
    });
  });
}
