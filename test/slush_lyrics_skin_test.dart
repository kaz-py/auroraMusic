import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(
    id: 'a',
    title: 'Ok Alright',
    artist: 'Travis Scott',
    duration: Duration(minutes: 3),
  ),
];

class _Lyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration.zero, 'Primera línea'),
      LyricLine(Duration(seconds: 30), 'Segunda línea'),
    ],
  );
}

void main() {
  for (final (width, scale) in const [(1440.0, 1.0), (360.0, 2.0)]) {
    testWidgets('modo letra Slush ${width}px x$scale: salir, Play lima, sin '
        'desborde', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(tracks: _songs),
      ))!;
      c.queue = [..._songs];
      await tester.runAsync(() => c.playQueueAt(0));
      await c.audio.pause();
      addTearDown(() => tester.runAsync(() => closeTestController(c)));
      await tester.pumpWidget(
        MaterialApp(
          theme: slushTheme(Brightness.light, const Color(0xff3b8bf2)),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ArtistModePage(
              controller: c,
              service: _Lyrics(),
              onClose: () {},
              onTogglePlay: () {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Salir del modo letra'), findsOneWidget);
      final play = find.byKey(const ValueKey('slush-lyrics-play'));
      expect(play, findsOneWidget);
      final limeFace = find.descendant(
        of: play,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == Slush.lime,
        ),
      );
      expect(limeFace, findsOneWidget);
    });
  }
}
