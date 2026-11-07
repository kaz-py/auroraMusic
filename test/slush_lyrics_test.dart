import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _track = Track(
  id: 's-track',
  artist: 'Artist',
  title: 'Song',
  duration: Duration(seconds: 180),
  pageUrl: 'https://example.test/s',
);

class _Lyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory supportDirectory, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => LyricsResult(
    LyricsKind.synced,
    lines: [
      for (var i = 1; i <= 30; i++)
        LyricLine(Duration(seconds: i), 'linea número $i de la canción'),
    ],
  );
}

void main() {
  testWidgets(
    'Letras Slush (panel y tarjeta): sin desborde 360-1920 px, texto x2',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final audio = FakeAudio();
      final controller = (await tester.runAsync(
        () => createTestController(audio: audio),
      ))!;
      addTearDown(() => tester.runAsync(() => closeTestController(controller)));
      controller.queue = [_track];
      controller.queueIndex = 0;
      await tester.runAsync(controller.togglePlayback);
      await audio.seek(const Duration(milliseconds: 12500));
      for (final brightness in Brightness.values) {
        for (final scale in const [1.0, 2.0]) {
          for (final width in const [
            360.0,
            412.0,
            600.0,
            900.0,
            1440.0,
            1920.0,
          ]) {
            await tester.binding.setSurfaceSize(Size(width, 800));
            final reason = '$brightness ${width}px x$scale';
            await tester.pumpWidget(
              MaterialApp(
                theme: slushTheme(brightness, const Color(0xff3b8bf2)),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 330,
                      height: 420,
                      child: SlushLyricsCard(
                        key: ValueKey(reason),
                        controller: controller,
                        service: _Lyrics(),
                      ),
                    ),
                  ),
                ),
              ),
            );
            controller.notifyListeners();
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            expect(tester.takeException(), isNull, reason: 'tarjeta $reason');
            expect(
              find.textContaining('linea número 12 '),
              findsOneWidget,
              reason: 'activa visible tarjeta $reason',
            );
          }
        }
      }
    },
  );
}
