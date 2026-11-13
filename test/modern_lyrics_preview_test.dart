import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/player/modern_player_parts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _track = Track(
  id: 'natural',
  title: 'Natural',
  artist: 'Imagine Dragons',
  pageUrl: 'https://example.test/natural',
);

class _Lyrics extends LyricsService {
  _Lyrics(this.result);
  final LyricsResult result;

  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => result;

  @override
  Future<LyricsResult?> upgradeToSynced(Track track, Directory root) async =>
      null;
}

class _Audio extends FakeAudio {
  void tick(Duration at) {
    position = at;
    notifyListeners();
  }
}

void main() {
  late AppController controller;
  late _Audio audio;

  setUp(() async {
    audio = _Audio();
    controller = await createTestController(audio: audio);
    controller.queue = [_track];
    await controller.playQueueAt(0);
    await audio.pause();
    addTearDown(() => closeTestController(controller));
  });

  Future<void> mount(WidgetTester tester, LyricsResult result) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: modernTheme(Brightness.dark, const Color(0xff6ea8ff)),
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(width: 360),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 40),
                  child: ModernLyricsPreview(
                    controller: controller,
                    onOpen: () {},
                    service: _Lyrics(result),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    addTearDown(() async {
      await settleLyricsIo(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    await settleLyricsIo(tester);
    await tester.pump();
  }

  testWidgets('muestra la línea actual de la letra en el panel de escritorio '
      'de Modern', (tester) async {
    await mount(
      tester,
      const LyricsResult(
        LyricsKind.synced,
        lines: [
          LyricLine(Duration.zero, 'Will you hold the line'),
          LyricLine(Duration(seconds: 10), 'When every one of them'),
          LyricLine(Duration(seconds: 20), 'Has given up and given in'),
        ],
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Will you hold the line'), findsOneWidget);
    audio.tick(const Duration(seconds: 12));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(find.text('When every one of them'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('letra sin sincronizar en el panel de escritorio de Modern', (
    tester,
  ) async {
    await mount(
      tester,
      const LyricsResult(LyricsKind.plain, text: 'Uno\nDos\nTres\nCuatro'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Uno'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
