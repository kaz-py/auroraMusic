import 'package:aurora_music/core/online_status.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jam_sync_test.dart' show eventually, input, peer, song;
import 'support/fake_jam_backend.dart';

/// Servidor en línea controlable: `up` decide si «responde».
class _Server {
  bool up = false;
  int probes = 0;
}

Future<OnlineStatus> _online(_Server server) async => OnlineStatus(
  preferences: await SharedPreferences.getInstance(),
  enabled: true,
  probe: (_) async {
    server.probes++;
    return server.up;
  },
  downTtl: const Duration(milliseconds: 1),
  upTtl: const Duration(milliseconds: 1),
);

void main() {
  test(
    'con el servidor caído la Jam automática se crea en red local',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      final server = _Server();
      host.app.online = await _online(server);

      final connected = await host.jam.startHosting(name: 'Ana');

      expect(connected, isTrue);
      expect(host.jam.error, isNull);
      expect(
        host.jam.service.invite!.isRemote,
        isFalse,
        reason: 'va por la LAN',
      );
      expect(backend.rooms, isEmpty, reason: 'no se creó nada en el servidor');
    },
  );

  test(
    'al volver el servidor, la siguiente Jam automática es en línea',
    () async {
      final backend = FakeJamBackend();
      final server = _Server();
      final host = await peer(backend);
      host.app.online = await _online(server);

      await host.jam.startHosting(name: 'Ana');
      expect(host.jam.service.invite!.isRemote, isFalse);
      await host.jam.service.disconnect();

      server.up = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final connected = await host.jam.startHosting(name: 'Ana');

      expect(connected, isTrue);
      expect(host.jam.service.invite!.isRemote, isTrue);
      expect(backend.rooms, hasLength(1));
    },
  );

  test('pedir «en línea» con el servidor caído explica el motivo', () async {
    final backend = FakeJamBackend();
    final host = await peer(backend);
    host.app.online = await _online(_Server());

    final connected = await host.jam.startHosting(
      name: 'Ana',
      mode: JamHostMode.online,
    );

    expect(connected, isFalse);
    expect(host.jam.error, contains('no responde'));
    expect(host.jam.error, contains('red local'));
  });

  test(
    'unirse con un código en línea sin servidor avisa y no se cuelga',
    () async {
      final backend = FakeJamBackend();
      final server = _Server()..up = true;
      final host = await peer(backend);
      host.app.online = await _online(server);
      await host.jam.startHosting(name: 'Ana');
      final code = host.jam.service.invite!.code;

      final guest = await peer(backend);
      final down = _Server();
      guest.app.online = await _online(down);
      await guest.jam.join(code, 'Beto');
      expect(guest.jam.active, isFalse);
      expect(guest.jam.error, contains('no responde'));

      // Cuando el servidor vuelve, el mismo código funciona.
      down.up = true;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await guest.jam.join(code, 'Beto');
      expect(guest.jam.active, isTrue);
    },
  );

  test('en modo «solo local» ni siquiera se sondea el servidor', () async {
    final backend = FakeJamBackend();
    final host = await peer(backend);
    await host.app.preferences.setString(OnlineStatus.modeKey, 'off');
    final server = _Server()..up = true;
    host.app.online = await _online(server);

    await host.jam.startHosting(name: 'Ana');

    expect(host.jam.service.invite!.isRemote, isFalse);
    expect(server.probes, 0);
  });

  test(
    'en línea el anfitrión no repite lo que los invitados ya calculan',
    () async {
      final backend = FakeJamBackend();
      final host = await peer(backend);
      host.app.online = await _online(_Server()..up = true);
      await host.jam.startHosting(name: 'Ana');
      final guest = await peer(backend);
      guest.app.online = await _online(_Server()..up = true);
      await guest.jam.join(host.jam.service.invite!.code, 'Beto');
      host.jam.add(song(1));
      await eventually(() => input(guest) != null && guest.audio.isPlaying);

      final before = host.jam.service.playback!.sequence;
      // El audio falso no avanza solo: se simula una reproducción real.
      for (var i = 0; i < 35; i++) {
        host.audio.position += const Duration(milliseconds: 100);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final steady = host.jam.service.playback!.sequence - before;
      // Antes se publicaba cada segundo (3–4 veces); ahora solo al cambiar algo
      // o en el fotograma clave de 10 s.
      expect(
        steady,
        lessThanOrEqualTo(1),
        reason: '$steady publicaciones sin cambios',
      );
      expect(
        guest.audio.isPlaying,
        isTrue,
        reason: 'el invitado sigue sonando',
      );

      // Pausar sí se publica enseguida.
      await host.jam.togglePlayback();
      await eventually(
        () => !guest.audio.isPlaying,
        'la pausa llega al invitado',
      );
    },
  );
}
