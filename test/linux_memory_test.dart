import 'dart:io';

import 'package:aurora_music/core/linux_memory.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime clock;
  late int trims;
  late List<int> skia;
  late List<VoidCallback> idle;

  setUp(() {
    clock = DateTime(2026, 11, 20, 12);
    trims = 0;
    skia = [];
    idle = [];
  });

  LinuxMemoryTuning tuning({bool enabled = true}) => LinuxMemoryTuning(
    enabled: enabled,
    trim: () => ++trims,
    setSkiaCacheBytes: (bytes) async => skia.add(bytes),
    runWhenIdle: idle.add,
    now: () => clock,
    idleInterval: const Duration(minutes: 2),
    settleDelay: const Duration(seconds: 2),
    minGap: const Duration(seconds: 20),
  );

  testWidgets('fuera de Linux no hace nada', (tester) async {
    final t = tuning(enabled: false)..start();
    t.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pump(const Duration(minutes: 5));
    expect(t.trimNow(), isFalse);
    expect(trims, 0);
    expect(skia, isEmpty);
    expect(idle, isEmpty);
    t.dispose();
  });

  testWidgets('al arrancar pone techo a la caché de Skia una vez', (
    tester,
  ) async {
    final t = tuning()..start();
    t.start();
    await tester.pump();
    expect(skia, [LinuxMemoryTuning.defaultSkiaCacheBytes]);
    t.dispose();
  });

  testWidgets('ocultar la ventana recorta tras la espera, una sola vez', (
    tester,
  ) async {
    final t = tuning()..start();
    t.didChangeAppLifecycleState(AppLifecycleState.inactive);
    t.didChangeAppLifecycleState(AppLifecycleState.hidden);
    t.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 1));
    expect(trims, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(trims, 1);
    expect(t.trims, 1);
    t.dispose();
  });

  testWidgets('volver al primer plano no recorta', (tester) async {
    final t = tuning()..start();
    t.didChangeAppLifecycleState(AppLifecycleState.resumed);
    t.didChangeAppLifecycleState(AppLifecycleState.detached);
    await tester.pump(const Duration(seconds: 5));
    expect(trims, 0);
    t.dispose();
  });

  testWidgets('respeta la distancia mínima entre recortes', (tester) async {
    final t = tuning()..start();
    expect(t.trimNow(), isTrue);
    clock = clock.add(const Duration(seconds: 19));
    expect(t.trimNow(), isFalse);
    clock = clock.add(const Duration(seconds: 1));
    expect(t.trimNow(), isTrue);
    expect(trims, 2);
    t.dispose();
  });

  testWidgets('el recorte periódico espera al reposo y no se acumula', (
    tester,
  ) async {
    final t = tuning()..start();
    await tester.pump(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2));
    // Dos ticks sin reposo: una sola tarea en cola.
    expect(idle, hasLength(1));
    expect(trims, 0);
    idle.removeAt(0)();
    expect(trims, 1);
    await tester.pump(const Duration(minutes: 2));
    expect(idle, hasLength(1));
    t.dispose();
  });

  testWidgets('dispose cancela los temporizadores pendientes', (tester) async {
    final t = tuning()..start();
    t.trimSoon();
    t.dispose();
    await tester.pump(const Duration(minutes: 5));
    expect(trims, 0);
    expect(idle, isEmpty);
  });

  testWidgets('por defecto usa el canal flutter/skia del motor', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.skia,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.skia,
        null,
      ),
    );
    final t = LinuxMemoryTuning(enabled: true, trim: () => 0)..start();
    await tester.pump();
    expect(calls, hasLength(1));
    expect(calls.single.method, 'Skia.setResourceCacheMaxBytes');
    expect(calls.single.arguments, LinuxMemoryTuning.defaultSkiaCacheBytes);
    t.dispose();
  });

  testWidgets('sin canal Skia (Impeller) sigue funcionando', (tester) async {
    final t = LinuxMemoryTuning(
      enabled: true,
      trim: () => ++trims,
      setSkiaCacheBytes: (_) async => throw MissingPluginException(),
      runWhenIdle: idle.add,
      now: () => clock,
    )..start();
    await tester.pump();
    expect(t.trimNow(), isTrue);
    t.dispose();
  });

  test(
    'malloc_trim de glibc existe y se puede llamar',
    () {
      final trim = LinuxMemoryTuning.lookupMallocTrim();
      expect(trim, isNotNull);
      expect(trim!(), anyOf(0, 1));
    },
    skip: Platform.isLinux ? false : 'solo en Linux con glibc',
  );
}
