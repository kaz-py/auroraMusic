import 'dart:io';

import 'package:aurora_music/audio/rust_music_audio.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'YouTube stream stays on the same song beyond two minutes',
    (tester) async {
      final passed = await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final source = YtDlpSource(await SharedPreferences.getInstance());
        final audio = RustMusicAudio();
        var completions = 0;
        final subscription = audio.completed.listen((_) => completions++);
        try {
          if (Platform.isWindows) {
            await source.configureToolDirectory(
              const String.fromEnvironment('AURORA_TOOLS'),
            );
          }
          source.setExperimentalProgressivePlayback(
            const bool.fromEnvironment('AURORA_PROGRESSIVE'),
          );
          final tracks = await source.search(
            const String.fromEnvironment('AURORA_SAMPLE_URL'),
            limit: 1,
          );
          final found = tracks.single;
          final track = const bool.fromEnvironment('AURORA_AS_IMPORTED_TRACK')
              ? Track(
                  id: 'spotify-native-fixture',
                  title: found.title,
                  artist: found.artist,
                  duration: found.duration,
                  pageUrl: found.pageUrl,
                )
              : found;
          final resolved = await source.resolve(track);
          if (!const bool.fromEnvironment('AURORA_PROGRESSIVE')) {
            expect(File(resolved.input).existsSync(), isTrue);
            expect(File(resolved.input).lengthSync(), greaterThan(0));
          }
          expect(resolved.duration, greaterThan(const Duration(seconds: 150)));
          await audio.initialize();
          audio.setVolume(0);
          const initialPosition = Duration(
            milliseconds: int.fromEnvironment('AURORA_INITIAL_POSITION_MS'),
          );
          await audio.load(resolved, start: initialPosition);
          await audio.play();
          const fullTrack = bool.fromEnvironment('AURORA_FULL_TRACK');
          const minimumPlayback = Duration(
            seconds: int.fromEnvironment(
              'AURORA_PLAY_SECONDS',
              defaultValue: 130,
            ),
          );
          final deadline = DateTime.now().add(
            fullTrack
                ? resolved.duration + const Duration(seconds: 30)
                : const Duration(seconds: 160),
          );
          while (audio.position < initialPosition + minimumPlayback ||
              (fullTrack && completions == 0)) {
            expect(audio.lastError, isNull);
            if (completions == 0) expect(audio.isPlaying, isTrue);
            if (DateTime.now().isAfter(deadline)) {
              fail('Playback did not reach its expected endpoint');
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(completions, fullTrack ? 1 : 0);
          expect(audio.lastError, isNull);
          if (!fullTrack && const bool.fromEnvironment('AURORA_CHECK_EOF')) {
            final ended = audio.completed.first;
            await audio.seek(resolved.duration - const Duration(seconds: 3));
            await ended.timeout(const Duration(seconds: 20));
            expect(completions, 1);
            expect(audio.lastError, isNull);
          }
          if (fullTrack) {
            // Repeat pointer-like seek bursts on the same resolved song. Pause
            // while a seek is outstanding must win over its asynchronous load.
            await audio.load(resolved);
            await audio.play();
            await Future.wait([
              audio.seek(const Duration(seconds: 35)),
              audio.seek(const Duration(seconds: 65)),
              audio.seek(const Duration(seconds: 125)),
            ]);
            await Future<void>.delayed(const Duration(milliseconds: 400));
            expect(audio.isPlaying, isTrue);
            expect(audio.position.inSeconds, closeTo(125, 2));
            expect(audio.lastError, isNull);
            final seek = audio.seek(const Duration(seconds: 45));
            await audio.pause();
            await seek;
            expect(audio.isPlaying, isFalse);
            expect(completions, 1);
          }
          return true;
        } finally {
          await subscription.cancel();
          await audio.stop();
          audio.dispose();
          source.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      });
      expect(passed, isTrue);
    },
    skip: !const bool.fromEnvironment('AURORA_ONLINE_SMOKE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
