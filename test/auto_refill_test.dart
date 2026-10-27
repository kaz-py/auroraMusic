import 'dart:convert';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/artist_graph.dart';
import 'package:aurora_music/dj/suggestions_api.dart';
import 'package:aurora_music/core/queue_policy.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/fakes.dart';

/// Radio de YouTube simulada; el audio lo resuelve el FakeSource.
class _RadioSource extends InnerTubeSource {
  _RadioSource(this.radio) : super(FakeSource(), post: (_, _) async => {});
  final List<Track> radio;
  @override
  Future<List<Track>> related(String videoId, {int limit = 25}) async => radio;
  @override
  Future<ResolvedAudio> resolve(Track track) => delegate.resolve(track);
}

class _BrokenEngine extends SuggestionsApi {
  @override
  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async =>
      throw 'motor caído';
}

Track song(int n) => Track(
  id: 'yt:refill${n.toString().padLeft(6, '0')}',
  title: 'Song $n',
  artist: 'Artist $n',
  pageUrl:
      'https://music.youtube.com/watch?v=refill${n.toString().padLeft(6, '0')}',
  duration: const Duration(minutes: 3),
);

Future<void> eventually(bool Function() ok) async {
  for (var i = 0; i < 200; i++) {
    if (ok()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TestFailure('timeout');
}

void main() {
  final library = [for (var i = 0; i < 12; i++) song(i)];
  late FakeAudio audio;

  Future<AppController> make({Map<String, Object> prefs = const {}}) async {
    audio = FakeAudio();
    final app = await createTestController(
      tracks: library,
      audio: audio,
      preferences: {'autoRefill': true, ...prefs},
    );
    addTearDown(() => closeTestController(app));
    return app;
  }

  test('cola que se agota: se rellena y la siguiente suena sola', () async {
    final app = await make();
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    expect(
      app.queue.length - app.queueIndex - 1,
      greaterThanOrEqualTo(kQueueLookahead),
    );
    expect(app.autoAddedIds, isNotEmpty);
    expect(app.autoAddedIds.contains(library[0].id), isFalse);
    final first = app.queue[1];
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(() => app.currentTrack?.id == first.id);
  });

  test('sin red: usa la biblioteca, sin repetir artista seguido', () async {
    final app = await make();
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    for (var i = 1; i < app.queue.length; i++) {
      expect(app.queue[i].artist, isNot(app.queue[i - 1].artist));
    }
  });

  test('repeat-one no rellena', () async {
    final app = await make();
    app.cycleRepeat();
    app.cycleRepeat();
    expect(app.repeat, RepeatMode.one);
    await app.playTrack(library[0], context: [library[0]]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, 1);
  });

  // La cola nunca termina: con shuffle una pista suelta también se continúa.
  test('shuffle con una sola pista: se rellena y continúa', () async {
    final app = await make();
    app.setShuffle(true);
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    final before = app.queue.length;
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(() => app.currentTrack?.id != library[0].id);
    expect(app.queue.length, greaterThanOrEqualTo(before));
  });

  test('pista de búsqueda (replaceQueue false) continúa al terminar', () async {
    final app = await make();
    await app.playTrack(library[0], replaceQueue: false);
    await eventually(() => app.queue.length >= 1 + kQueueLookahead);
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(() => app.currentTrack?.id != library[0].id);
  });

  test('motor caído: sigue con la biblioteca', () async {
    final app = await make();
    app.suggestionsApi = SuggestionsApi(
      fetchCandidates: (_) async => throw 'offline',
    );
    await app.playTrack(library[0], context: [library[0]]);
    await eventually(() => app.queue.length > 1);
    audio.position = audio.duration;
    audio.completions.add(null);
    await eventually(() => app.currentTrack?.id != library[0].id);
  });

  test('motor caído: de la radio solo entra lo afín a la semilla', () async {
    Track yt(String id, String artist) => Track(
      id: 'yt:${id.padRight(11, '0')}',
      title: 'Tema $id',
      artist: artist,
      pageUrl: 'https://music.youtube.com/watch?v=${id.padRight(11, '0')}',
      duration: const Duration(minutes: 3),
    );
    final a1 = yt('a1', 'A'), a2 = yt('a2', 'A');
    final z1 = yt('z1', 'Z'), b1 = yt('b1', 'B');
    audio = FakeAudio();
    final app = await createTestController(
      tracks: [a1],
      audio: audio,
      source: _RadioSource([a2, z1, b1]),
      preferences: {
        'autoRefill': true,
        ArtistGraph.prefsKey: jsonEncode({
          'a': {
            't': DateTime.now().millisecondsSinceEpoch,
            'ok': true,
            'n': ['b'],
            'g': <String>[],
          },
        }),
      },
    );
    addTearDown(() => closeTestController(app));
    app.suggestionsApi = _BrokenEngine();
    await app.playTrack(a1, context: [a1]);
    await eventually(
      () =>
          app.queue.any((t) => t.id == a2.id) &&
          app.queue.any((t) => t.id == b1.id),
    );
    expect(app.queue.map((t) => t.id), isNot(contains(z1.id)));
  });

  test('ajuste apagado no rellena', () async {
    final app = await make(prefs: {'autoRefill': false});
    expect(app.autoRefill, isFalse);
    await app.playTrack(library[0], context: [library[0]]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, 1);
    expect(app.autoAddedIds, isEmpty);
  });

  test('una cola larga armada a mano no se toca', () async {
    final app = await make();
    await app.playTrack(library[0], context: library);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.queue.length, library.length);
    expect(app.autoAddedIds, isEmpty);
  });
}
