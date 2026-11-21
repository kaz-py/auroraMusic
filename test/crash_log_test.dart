import 'dart:io';

import 'package:aurora_music/core/crash_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('aurora_crash_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('anota cada error una vez, por día UTC, sin perder los anteriores', () {
    var now = DateTime.utc(2026, 11, 17, 23, 59, 58);
    final logs = Directory('${root.path}/logs');
    final log = CrashLog(logs, version: '1.6.0+28', now: () => now);

    log.record('FlutterError', 'desbordamiento', StackTrace.fromString('#0 a'));
    log.record('FlutterError', 'desbordamiento'); // Repetido: se omite.
    log.record('Error no capturado', StateError('cola vacía'));
    now = now.add(const Duration(seconds: 5)); // Ya es 18 en UTC.
    log.record('Error de plataforma', 'canal cerrado');

    final first = File('${logs.path}/dart-2026-11-17.log').readAsStringSync();
    expect('desbordamiento'.allMatches(first), hasLength(1));
    expect(first, contains('[2026-11-17T23:59:58.000Z] FlutterError'));
    expect(first, contains('(Aurora 1.6.0+28)'));
    expect(first, contains('#0 a'));
    expect(first, contains('Bad state: cola vacía'));
    final second = File('${logs.path}/dart-2026-11-18.log').readAsStringSync();
    expect(second, contains('canal cerrado'));
    expect(second, isNot(contains('desbordamiento')));
  });
}
