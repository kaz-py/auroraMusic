import 'dart:io';

import 'package:aurora_music/sources/yt_dlp_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Linux/macOS: cancelling a yt-dlp job kills its children too and escalates
/// to SIGKILL when yt-dlp ignores SIGTERM. Uses a fake `yt-dlp` shell script.
void main() {
  // YtDlpSource registers a MethodChannel handler in its constructor.
  TestWidgetsFlutterBinding.ensureInitialized();
  final skip = Platform.isWindows ? 'POSIX process tree only' : null;

  late Directory dir;
  late YtDlpSource source;

  Future<void> writeFake({required bool ignoreTerm}) async {
    final script = File(p.join(dir.path, 'yt-dlp'));
    await script.writeAsString('''#!/bin/sh
echo \$\$ > "${dir.path}/parent.pid"
sleep 300 &
echo \$! > "${dir.path}/child.pid"
${ignoreTerm ? "trap '' TERM" : ''}
while true; do sleep 1; done
''');
    await Process.run('chmod', ['+x', script.path]);
  }

  bool alive(int pid) {
    final stat = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
    final state = (stat.stdout as String).trim();
    return state.isNotEmpty && !state.startsWith('Z');
  }

  bool zombie(int pid) {
    final stat = Process.runSync('ps', ['-o', 'stat=', '-p', '$pid']);
    return (stat.stdout as String).trim().startsWith('Z');
  }

  Future<int> pidFrom(String name) async {
    final file = File(p.join(dir.path, name));
    for (var i = 0; i < 100 && !await file.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // The child line is written right after the parent's.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return int.parse((await file.readAsString()).trim());
  }

  Future<void> gone(int pid) async {
    for (var i = 0; i < 40 && (alive(pid) || zombie(pid)); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(alive(pid), isFalse, reason: 'pid $pid still running');
    expect(zombie(pid), isFalse, reason: 'pid $pid left as a zombie');
  }

  setUp(() async {
    if (skip != null) return;
    dir = await Directory.systemTemp.createTemp('aurora-ytdlp-kill-');
    SharedPreferences.setMockInitialValues({'toolDirectory': dir.path});
    source = YtDlpSource(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    if (skip != null) return;
    source.dispose();
    for (final name in ['parent.pid', 'child.pid']) {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) {
        final pid = int.tryParse((await file.readAsString()).trim());
        if (pid != null) Process.killPid(pid, ProcessSignal.sigkill);
      }
    }
    await dir.delete(recursive: true);
  });

  Future<(int, int, Duration, Future<void>)> startAndCancel() async {
    final job = source.downloadVideo(
      Uri.parse('https://www.youtube.com/watch?v=abcdefghijk'),
      File(p.join(dir.path, 'out', 'clip.mp4')),
      jobId: 'job-kill',
    );
    final parent = await pidFrom('parent.pid');
    final child = await pidFrom('child.pid');
    expect(alive(parent), isTrue);
    expect(alive(child), isTrue);
    final watch = Stopwatch()..start();
    await source.cancel('job-kill');
    return (parent, child, watch.elapsed, job);
  }

  test('yt-dlp that obeys SIGTERM: it and its child die at once', () async {
    await writeFake(ignoreTerm: false);
    final (parent, child, took, job) = await startAndCancel();
    await expectLater(job, throwsA(isA<StateError>()));
    await gone(parent);
    await gone(child);
    expect(took, lessThan(const Duration(seconds: 1)));
  }, skip: skip);

  test(
    'yt-dlp that ignores SIGTERM: SIGKILL after ~2 s, child not orphaned',
    () async {
      await writeFake(ignoreTerm: true);
      final (parent, child, took, job) = await startAndCancel();
      await expectLater(job, throwsA(isA<StateError>()));
      await gone(parent);
      await gone(child);
      expect(took, greaterThanOrEqualTo(const Duration(milliseconds: 1900)));
      expect(took, lessThan(const Duration(seconds: 4)));
    },
    skip: skip,
  );
}
