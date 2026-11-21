import 'package:aurora_music/core/online_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<OnlineStatus> _status(
  Future<bool> Function(Duration) probe, {
  Map<String, Object> prefs = const {},
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  return OnlineStatus(
    preferences: await SharedPreferences.getInstance(),
    enabled: true,
    probe: probe,
    clock: clock,
  );
}

void main() {
  test('un servidor caído se prueba una vez y se recuerda un rato', () async {
    var calls = 0;
    var now = DateTime(2026, 1, 1);
    final status = await _status((_) async {
      calls++;
      return false;
    }, clock: () => now);
    addTearDown(status.dispose);

    expect(await status.available(), isFalse);
    expect(await status.available(), isFalse);
    expect(calls, 1, reason: 'la segunda respuesta sale de la caché');
    expect(status.lastKnown, isFalse);

    now = now.add(const Duration(minutes: 3));
    expect(await status.available(), isFalse);
    expect(calls, 2, reason: 'caducó la caché negativa y se vuelve a probar');
  });

  test('cuando el servidor vuelve se detecta y se avisa una vez', () async {
    var up = false;
    var recovered = 0;
    final status = await _status((_) async => up);
    addTearDown(status.dispose);
    status.onRecovered(() => recovered++);

    expect(await status.available(), isFalse);
    up = true;
    expect(await status.available(force: true), isTrue);
    expect(recovered, 1);
    expect(await status.available(force: true), isTrue);
    expect(recovered, 1, reason: 'seguir arriba no es una recuperación');
  });

  test('un fallo del sondeo cuenta como sin servidor, no como error', () async {
    final status = await _status((_) async => throw StateError('dns'));
    addTearDown(status.dispose);
    expect(await status.available(), isFalse);
  });

  test('en modo solo local no se contacta con el servidor', () async {
    var calls = 0;
    final status = await _status((_) async {
      calls++;
      return true;
    }, prefs: {OnlineStatus.modeKey: 'off'});
    addTearDown(status.dispose);
    expect(status.mode, OnlineMode.off);
    expect(await status.available(), isFalse);
    expect(calls, 0);
  });

  test('el modo se guarda y al volver a «auto» se prueba de nuevo', () async {
    var up = true;
    final status = await _status((_) async => up);
    addTearDown(status.dispose);
    await status.setMode(OnlineMode.off);
    expect(status.mode, OnlineMode.off);
    expect(status.lastKnown, isFalse);

    await status.setMode(OnlineMode.auto);
    expect(await status.available(), isTrue);
    expect(status.mode, OnlineMode.auto);
  });

  test('si está caído reintenta solo y avisa al volver', () async {
    var up = false;
    var recovered = 0;
    final status = await _status((_) async => up);
    addTearDown(status.dispose);
    // Reintento rápido para la prueba.
    SharedPreferences.setMockInitialValues({});
    final quick = OnlineStatus(
      preferences: await SharedPreferences.getInstance(),
      enabled: true,
      probe: (_) async => up,
      downTtl: const Duration(milliseconds: 30),
    )..onRecovered(() => recovered++);
    addTearDown(quick.dispose);

    expect(await quick.available(), isFalse);
    up = true;
    for (var i = 0; i < 50 && recovered == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(recovered, 1);
    expect(quick.lastKnown, isTrue);
  });
}
