import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _mine = Track(
  id: 'mine',
  title: 'Mine',
  artist: 'A',
  pageUrl: 'https://youtu.be/mine',
);
const _jam = Track(
  id: 'jam1',
  title: 'Jam Song',
  artist: 'B',
  pageUrl: 'https://youtu.be/jam1',
);

class _RecordingLyrics extends LyricsService {
  final asked = <String>[];
  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async {
    asked.add(track.id);
    return const LyricsResult(LyricsKind.notFound);
  }
}

void main() {
  testWidgets('en Jam nowTrack es la pista de la Jam y la letra la sigue', (
    tester,
  ) async {
    final app = (await tester.runAsync(
      () => createTestController(audio: FakeAudio()),
    ))!;
    addTearDown(() => closeTestController(app));
    app.queue = [_mine];
    app.queueIndex = 0;
    expect(app.nowTrack?.id, 'mine');
    final service = _RecordingLyrics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArtistModePage(
            controller: app,
            service: service,
            onClose: () {},
            onTogglePlay: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(app.beginJamPlayback);
    expect(app.nowTrack, isNull);
    app.setJamNowPlaying(_jam);
    await tester.pump();
    expect(app.nowTrack?.id, 'jam1');
    expect(service.asked, contains('jam1'));
    await tester.runAsync(app.endJamPlayback);
    expect(app.nowTrack?.id, 'mine');
  });

  test('noteJamPlay registra historial sin tocar la cola personal', () async {
    final app = await createTestController(audio: FakeAudio());
    addTearDown(() => closeTestController(app));
    app.queue = [_mine];
    app.queueIndex = 0;
    await app.beginJamPlayback();
    await app.noteJamPlay(_jam);
    expect(app.recentTracks.first.id, 'jam1');
    expect(app.queue.map((t) => t.id), ['mine']);
  });
}
