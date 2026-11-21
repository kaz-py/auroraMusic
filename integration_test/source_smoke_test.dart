import 'dart:io';
import 'package:aurora_music/audio/rust_music_audio.dart';
import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const online = bool.fromEnvironment('AURORA_ONLINE_SMOKE');
const tools = String.fromEnvironment('AURORA_TOOLS');
// Override when a public fixture becomes unavailable or restricted upstream.
const sample = String.fromEnvironment(
  'AURORA_SAMPLE_URL',
  defaultValue: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'YouTube extraction, actual streamed audio and offline MP3',
    (tester) async {
      final passed = await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        final source = YtDlpSource(await SharedPreferences.getInstance());
        final audio = RustMusicAudio();
        final directory = await (await getTemporaryDirectory()).createTemp(
          'aurora-source-smoke-',
        );
        try {
          if (Platform.isWindows) {
            expect(
              tools,
              isNotEmpty,
              reason: 'Pass --dart-define=AURORA_TOOLS=<verified tool folder>',
            );
            await source.configureToolDirectory(tools);
          }
          final tracks = await source.search(sample, limit: 1);
          expect(tracks, hasLength(1));
          final track = tracks.single;
          expect(track.title, isNotEmpty);
          expect(track.pageUrl, startsWith('https://www.youtube.com/'));
          final resolved = await source.resolve(track);
          expect(resolved.input, startsWith('https://'));
          await audio.initialize();
          audio.setVolume(0.02);
          await audio.load(resolved);
          await audio.play();
          await _wait(
            audio,
            () => audio.position > const Duration(milliseconds: 1600),
          );
          expect(audio.lastError, isNull);
          await audio.stop();

          final destination = File(p.join(directory.path, 'sample.mp3'));
          var progress = 0.0;
          await source.download(
            track,
            destination,
            jobId: 'smoke-${DateTime.now().microsecondsSinceEpoch}',
            onProgress: (value) => progress = value,
          );
          expect(await destination.length(), greaterThan(0));
          expect(progress, 1);
          final offline = await source.resolve(
            track.copyWith(localPath: destination.path),
          );
          expect(offline.input, destination.path);
          await audio.load(offline);
          await audio.play();
          await _wait(
            audio,
            () => audio.position > const Duration(milliseconds: 700),
          );
          expect(audio.lastError, isNull);
          await audio.seek(const Duration(seconds: 2));
          await _wait(
            audio,
            () => audio.position > const Duration(milliseconds: 2300),
          );
          return true;
        } finally {
          await audio.stop();
          audio.dispose();
          source.dispose();
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await directory.delete(recursive: true);
        }
      });
      expect(passed, isTrue);
    },
    skip: !online,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

Future<void> _wait(RustMusicAudio audio, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition()) {
    if (audio.lastError != null) {
      throw StateError(audio.lastError!);
    }
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Native audio clock did not advance.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
