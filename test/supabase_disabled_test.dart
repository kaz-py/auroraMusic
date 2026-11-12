import 'package:aurora_music/account/account_wiring.dart';
import 'package:aurora_music/core/feature_flags.dart';
import 'package:aurora_music/core/online_status.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'jam_sync_test.dart' show peer;
import 'support/fake_jam_backend.dart';
import 'support/fakes.dart';

void main() {
  // Aquí se prueba el comportamiento real de producción: apagado.
  setUp(() => supabaseServicesOverride = false);
  tearDown(() => supabaseServicesOverride = true);

  test('el interruptor general de producción está apagado', () {
    // Si se vuelve a activar Supabase, este test recuerda revisar lo demás.
    expect(kSupabaseEnabled, isFalse);
  });

  test('apagado, ni se prueba el servidor ni se crea la cuenta', () async {
    final c = await createTestController();
    addTearDown(() => closeTestController(c));
    var probes = 0;
    c.online = OnlineStatus(
      preferences: c.preferences,
      enabled: false,
      probe: (_) async {
        probes++;
        return true;
      },
    );

    expect(await c.online.available(force: true), isFalse);
    await connectAccount(c);

    expect(probes, 0);
    expect(c.accounts, isNull, reason: 'no se creó el cliente de Supabase');
    expect(c.sync, isNull);
  });

  test(
    'apagado, la Jam funciona en red local y explica lo de internet',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      host.app.online = OnlineStatus(
        preferences: host.app.preferences,
        enabled: false,
      );

      expect(host.jam.remoteAvailable, isFalse);
      expect(host.jam.remoteProblem, contains('red local'));

      expect(await host.jam.startHosting(name: 'Ana'), isTrue);
      expect(
        host.jam.service.invite!.isRemote,
        isFalse,
        reason: 'va por la LAN',
      );
      expect(backend.rooms, isEmpty);
      await host.jam.service.disconnect();

      expect(
        await host.jam.startHosting(name: 'Ana', mode: JamHostMode.online),
        isFalse,
      );
      expect(host.jam.error, contains('desactivada temporalmente'));
    },
  );
}
