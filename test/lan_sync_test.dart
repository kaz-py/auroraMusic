import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/account/lan_sync.dart';
import 'package:aurora_music/account/sync_store.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _a = Track(id: 'a', title: 'A', artist: 'X');
const _b = Track(id: 'b', title: 'B', artist: 'Y');
const _c = Track(id: 'c', title: 'C', artist: 'Z');

class _Device {
  _Device(this.db, this.prefs);
  final LibraryDatabase db;
  final SharedPreferences prefs;
}

Future<_Device> _device() async {
  SharedPreferences.setMockInitialValues({});
  final db = LibraryDatabase.memory();
  addTearDown(db.close);
  return _Device(db, await SharedPreferences.getInstance());
}

Future<void> _favorite(LibraryDatabase db, Track t) async {
  await db.saveTrack(t);
  await db.setFavorite(t.id, true);
}

void main() {
  late _Device source, target;
  late LanSyncServer server;
  late LanSyncClient client;

  setUp(() async {
    source = await _device();
    target = await _device();
    await source.db.seedSyncMeta();
    server = LanSyncServer(source.db, deviceId: 'origen', allowLoopback: true);
    addTearDown(server.stop);
    client = LanSyncClient(target.db, target.prefs);
  });

  test(
    'transfiere favoritos y listas, y la segunda vez no manda nada',
    () async {
      await _favorite(source.db, _a);
      await _favorite(source.db, _b);
      await source.db.savePlaylist(
        MusicPlaylist(id: 'p1', name: 'Mi lista', trackIds: const ['a', 'b']),
      );
      final invite = await server.start('127.0.0.1');

      final first = await client.receive(invite);
      expect(first.applied['favorites'], 2);
      expect(first.applied['playlists'], 1);
      expect(await target.db.readFavorites(), containsAll(['a', 'b']));
      expect((await target.db.readPlaylists()).single.name, 'Mi lista');

      // Nada nuevo: no se vuelve a enviar ni aplicar nada.
      final second = await client.receive(invite);
      expect(second.total, 0);

      // Un favorito nuevo: viaja solo ese.
      await _favorite(source.db, _c);
      final third = await client.receive(invite);
      expect(third.applied['favorites'], 1);
      expect(third.applied['playlists'], 0);
      expect(await target.db.readFavorites(), contains('c'));
    },
  );

  test('lo quitado en el origen también se quita en el destino', () async {
    await _favorite(source.db, _a);
    final invite = await server.start('127.0.0.1');
    await client.receive(invite);
    expect(await target.db.readFavorites(), contains('a'));

    await source.db.setFavorite('a', false);
    await client.receive(invite);
    expect(await target.db.readFavorites(), isNot(contains('a')));
  });

  test(
    'lo más reciente gana: un cambio posterior en el destino se conserva',
    () async {
      await _favorite(source.db, _a);
      final invite = await server.start('127.0.0.1');
      await client.receive(invite);

      // El destino quita el favorito después; el origen no cambió: no lo repone.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await target.db.setFavorite('a', false);
      final again = await client.receive(invite);
      expect(again.total, 0);
      expect(await target.db.readFavorites(), isNot(contains('a')));
    },
  );

  test(
    'sin la clave correcta el servidor responde 401 y no entrega nada',
    () async {
      await _favorite(source.db, _a);
      final invite = await server.start('127.0.0.1');
      final http = HttpClient();
      addTearDown(() => http.close(force: true));

      Future<int> status(String? token) async {
        final request = await http.getUrl(
          Uri.http('127.0.0.1:${invite.port}', '/lan/favorites', {
            'since': '0',
          }),
        );
        if (token != null) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        }
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      expect(await status(null), 401);
      expect(await status('x' * invite.token.length), 401);
      expect(await status(invite.token), 200);
    },
  );

  test('el código caduca y entonces el servidor deja de entregar', () async {
    var now = DateTime(2026, 1, 1, 10);
    final timed = LanSyncServer(
      source.db,
      deviceId: 'origen',
      allowLoopback: true,
      clock: () => now,
    );
    addTearDown(timed.stop);
    await _favorite(source.db, _a);
    final invite = await timed.start('127.0.0.1');

    now = now.add(const Duration(minutes: 6));
    await expectLater(
      client.receive(invite),
      throwsA(
        isA<LanSyncException>().having(
          (e) => e.message,
          'm',
          contains('caducó'),
        ),
      ),
    );
  });

  test('el servidor rechaza direcciones que no son de red local', () async {
    expect(
      () => LanSyncServer(source.db, deviceId: 'x').start('8.8.8.8'),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => LanSyncServer(source.db, deviceId: 'x').start('127.0.0.1'),
      throwsA(isA<FormatException>()),
      reason: 'el bucle local solo se permite en pruebas',
    );
  });

  group('código QR', () {
    test('ida y vuelta', () async {
      final invite = await server.start('127.0.0.1');
      final back = LanSyncInvite.decode(invite.encode(), allowLoopback: true);
      expect(back.address, '127.0.0.1');
      expect(back.port, invite.port);
      expect(back.token, invite.token);
      expect(back.deviceId, 'origen');
    });

    test('rechaza un código que apunta a internet, caducado o dañado', () {
      String code(Map<String, Object?> o) =>
          lanSyncPrefix +
          base64Url
              .encode(utf8.encode(jsonEncode({'v': 1, ...o})))
              .replaceAll('=', '');
      final soon = DateTime.now()
          .add(const Duration(minutes: 4))
          .millisecondsSinceEpoch;
      final good = {
        'a': '192.168.1.5',
        'p': 40000,
        't': 'x' * 40,
        'd': 'o',
        'e': soon,
      };

      expect(LanSyncInvite.decode(code(good)).address, '192.168.1.5');
      for (final bad in [
        {...good, 'a': '8.8.8.8'},
        {...good, 'a': 'ejemplo.com'},
        {...good, 'e': 1000},
        {...good, 'p': 80},
        {...good, 't': 'corto'},
      ]) {
        expect(
          () => LanSyncInvite.decode(code(bad)),
          throwsA(isA<FormatException>()),
        );
      }
      expect(
        () => LanSyncInvite.decode('hola'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => LanSyncInvite.decode('${lanSyncPrefix}no-es-base64!!'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
