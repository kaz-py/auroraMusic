import 'dart:typed_data';

import 'package:aurora_music/account/account_service.dart';
import 'package:aurora_music/account/sync_service.dart';
import 'package:aurora_music/account/sync_store.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAvatarStorage implements AvatarStorage {
  final files = <String>{};
  final calls = <String>[];
  bool failProfile = false;
  @override
  Future<void> upload(String path, Uint8List png) async {
    files.add(path);
    calls.add('upload $path');
  }

  @override
  Future<void> remove(String path) async {
    files.remove(path);
    calls.add('remove $path');
  }

  @override
  Future<void> setProfilePath(String? path) async {
    if (failProfile) throw Exception('db');
    calls.add('profile $path');
  }
}

/// Servidor en memoria: updated_at lo pone él (reloj creciente), como el trigger.
class FakeRemote implements SyncRemote {
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  int clock = 1000000;
  int pullCalls = 0;
  final pushedRows = <String, int>{};
  String _key(String t) => t == 'user_taste'
      ? 'user_id'
      : t == 'user_playlists'
      ? 'id'
      : 'track_id';

  @override
  Future<List<Map<String, dynamic>>> pull(
    String table,
    String? since,
    int limit,
  ) async {
    pullCalls++;
    final rows =
        (tables[table]?.values ?? [])
            .where(
              (r) =>
                  since == null ||
                  (r['updated_at'] as String).compareTo(since) >= 0,
            )
            .toList()
          ..sort(
            (a, b) => (a['updated_at'] as String).compareTo(
              b['updated_at'] as String,
            ),
          );
    return rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> push(
    String table,
    String conflict,
    List<Map<String, dynamic>> rows,
  ) async {
    final stamp = DateTime.fromMillisecondsSinceEpoch(
      clock += 1000,
      isUtc: true,
    ).toIso8601String();
    final out = <Map<String, dynamic>>[];
    pushedRows[table] = (pushedRows[table] ?? 0) + rows.length;
    for (final r in rows) {
      final key = table == 'user_taste' ? '1' : r[_key(table)] as String;
      tables.putIfAbsent(table, () => {})[key] = {
        ...r,
        'user_id': 'u1',
        'updated_at': stamp,
        'deleted': r['deleted'] ?? false,
      };
      out.add({
        _key(table): table == 'user_taste' ? 'u1' : key,
        'updated_at': stamp,
      });
    }
    return out;
  }
}

const trackA = Track(id: 'a', title: 'A', artist: 'X');
const trackB = Track(id: 'b', title: 'B', artist: 'Y');

Future<(LibraryDatabase, SyncService, FakeRemote, List<int>)> device(
  FakeRemote remote, {
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({});
  final db = LibraryDatabase.memory();
  addTearDown(db.close);
  final pulled = <int>[];
  final sync = SyncService(
    accounts: AccountService(config: null),
    database: db,
    preferences: await SharedPreferences.getInstance(),
    onPulled: () async => pulled.add(1),
    remote: remote,
    clock: clock,
  );
  return (db, sync, remote, pulled);
}

void main() {
  group('validators', () {
    test('email', () {
      expect(validateEmail('a@b.co'), isNull);
      expect(validateEmail('a@b'), isNotNull);
      expect(validateEmail('sin arroba'), isNotNull);
    });
    test('username', () {
      expect(validateUsername('juan_1.x'), isNull);
      expect(validateUsername('ab'), isNotNull);
      expect(validateUsername('Mayus'), isNotNull);
      expect(validateUsername('con espacio'), isNotNull);
      expect(validateUsername('a' * 25), isNotNull);
    });
    test('password min 8', () {
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('12345678'), isNull);
    });
    test('error mapping', () {
      expect(
        mapAccountError(Exception('user_already_exists')).message,
        contains('correo'),
      );
      expect(
        mapAccountError(Exception('invalid_credentials')).message,
        contains('incorrectos'),
      );
      expect(
        mapAccountError(Exception('SocketException')).message,
        contains('conexión'),
      );
      expect(
        mapAccountError(Exception('Database error saving new user')).message,
        contains('usuario'),
      );
    });
  });

  group('avatar', () {
    final png = Uint8List.fromList([1, 2, 3]);
    test('replace uploads, repoints, then deletes previous', () async {
      final s = FakeAvatarStorage()..files.add('u/1.png');
      final path = await replaceAvatar(
        storage: s,
        uid: 'u',
        previous: 'u/1.png',
        png: png,
        millis: 2,
      );
      expect(path, 'u/2.png');
      expect(s.files, {'u/2.png'});
      expect(s.calls, ['upload u/2.png', 'profile u/2.png', 'remove u/1.png']);
    });
    test(
      'failed profile update keeps old file and drops the new one',
      () async {
        final s = FakeAvatarStorage()
          ..files.add('u/1.png')
          ..failProfile = true;
        await expectLater(
          replaceAvatar(
            storage: s,
            uid: 'u',
            previous: 'u/1.png',
            png: png,
            millis: 2,
          ),
          throwsException,
        );
        expect(s.files, {'u/1.png'});
      },
    );
  });

  group('merge', () {
    test('remote wins when absent locally or newer; local wins ties/newer', () {
      final local = {
        'old': const SyncMeta(10, false, true),
        'new': const SyncMeta(50, false, true),
        'tie': const SyncMeta(30, false, false),
      };
      expect(
        remoteWinners(local, {'old': 20, 'new': 20, 'tie': 30, 'only': 5}),
        {'old', 'only'},
      );
    });
  });

  group('sync: menos peticiones al servidor', () {
    test(
      'tras un cambio local solo se sube: no se vuelve a bajar todo',
      () async {
        final remote = FakeRemote();
        final (db, sync, _, _) = await device(remote);
        await db.saveTrack(trackA);
        await db.setFavorite('a', true);
        await sync.runSync('u1'); // ciclo completo: baja (4 tablas) y sube
        final pullsAfterFull = remote.pullCalls;
        expect(pullsAfterFull, greaterThan(0));

        await db.saveTrack(trackB);
        await db.setFavorite('b', true);
        await sync.runSync(
          'u1',
          pull: false,
        ); // lo que hace el aplazamiento de 30 s
        expect(
          remote.pullCalls,
          pullsAfterFull,
          reason: 'sin GET innecesarios',
        );
        expect(remote.tables['user_favorites']!.keys, containsAll(['a', 'b']));
      },
    );

    test(
      'el historial no se sube en cada reproducción, solo cada 10 min',
      () async {
        var now = DateTime(2026, 1, 1, 12);
        final remote = FakeRemote();
        final (db, sync, _, _) = await device(remote, clock: () => now);
        await db.saveTrack(trackA);
        await db.recordPlay('a');
        await sync.runSync('u1'); // completo: sube el historial
        final first = remote.pushedRows['user_history'] ?? 0;
        expect(first, 1);

        await db.saveTrack(trackB);
        await db.recordPlay('b');
        now = now.add(const Duration(minutes: 1));
        await sync.runSync('u1', pull: false);
        expect(remote.pushedRows['user_history'], first, reason: 'aún no toca');

        now = now.add(const Duration(minutes: 11));
        await sync.runSync('u1', pull: false);
        expect(remote.pushedRows['user_history'], greaterThan(first));
      },
    );
  });

  group('sync', () {
    test(
      'first sign-in unions local and remote without wiping either',
      () async {
        final remote = FakeRemote();
        // Otro dispositivo ya subió el favorito b.
        final (db2, sync2, _, _) = await device(remote);
        await db2.saveTrack(trackB);
        await db2.setFavorite('b', true);
        await sync2.runSync('u1');

        final (db1, sync1, _, pulled) = await device(remote);
        await db1.saveTrack(trackA);
        await db1.setFavorite('a', true); // local previo a la cuenta
        await sync1.runSync('u1');

        expect(await db1.readFavorites(), {'a', 'b'});
        expect(pulled, isNotEmpty);
        expect(remote.tables['user_favorites']!.keys.toSet(), {'a', 'b'});
        // Segundo ciclo sin cambios: nada que subir ni recargar.
        pulled.clear();
        await sync1.runSync('u1');
        expect(pulled, isEmpty);
      },
    );

    test('tombstone propagates a delete to another device', () async {
      final remote = FakeRemote();
      final (db1, sync1, _, _) = await device(remote);
      await db1.saveTrack(trackA);
      await db1.setFavorite('a', true);
      await db1.savePlaylist(
        const MusicPlaylist(id: 'p', name: 'Mix', trackIds: ['a']),
      );
      await sync1.runSync('u1');

      final (db2, sync2, _, _) = await device(remote);
      await sync2.runSync('u1');
      expect(await db2.readFavorites(), {'a'});
      expect((await db2.readPlaylists()).single.name, 'Mix');

      await db1.setFavorite('a', false);
      await db1.deletePlaylist('p');
      await sync1.runSync('u1');
      expect(remote.tables['user_favorites']!['a']!['deleted'], true);

      await sync2.runSync('u1');
      expect(await db2.readFavorites(), isEmpty);
      expect(await db2.readPlaylists(), isEmpty);
    });

    test('last write wins on playlist rename', () async {
      final remote = FakeRemote();
      final (db1, sync1, _, _) = await device(remote);
      await db1.savePlaylist(const MusicPlaylist(id: 'p', name: 'Uno'));
      await sync1.runSync('u1');
      final (db2, sync2, _, _) = await device(remote);
      await sync2.runSync('u1');

      await db1.savePlaylist(const MusicPlaylist(id: 'p', name: 'Dos'));
      await sync1.runSync('u1');
      await sync2.runSync('u1');
      expect((await db2.readPlaylists()).single.name, 'Dos');
    });
  });
}
