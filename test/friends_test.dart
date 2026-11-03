import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/friends/friends_providers.dart';
import 'package:aurora_music/friends/friends_service.dart';
import 'package:aurora_music/ui/friends_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/friends_fakes.dart';

void main() {
  late FakeAuth auth;
  late FakeData data;
  FriendsService make() => FriendsService(
    auth: auth,
    currentUid: () => auth.uid,
    dataFor: (uid) => data,
    avatarUrl: (_) => null,
  );

  setUp(() {
    auth = FakeAuth();
    data = FakeData('me');
  });

  test('sin sesión no carga nada; al iniciar sesión sí', () async {
    final f = make();
    expect(f.signedIn, isFalse);
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    auth.set('me');
    await settle();
    expect(f.signedIn, isTrue);
    expect(f.friends.map((u) => u.username), ['ana']);
    auth.set(null);
    expect(f.friends, isEmpty);
    expect(data.unsubscribed, isTrue);
    f.dispose();
  });

  test(
    'transiciones de solicitud: enviar, aceptar, rechazar, borrar',
    () async {
      data.requests
        ..add(req('in1', 'u1', 'me', 'pending'))
        ..add(req('in2', 'u2', 'me', 'pending'));
      auth.set('me');
      final f = make();
      await settle();
      expect(f.incoming.length, 2);
      expect(await f.accept('in1'), isNull);
      expect(await f.decline('in2'), isNull);
      expect(f.friends.map((u) => u.username), ['ana']);
      expect(f.incoming, isEmpty);
      expect(await f.sendRequest('u3'), isNull);
      expect(f.outgoing.single.user.username, 'carla');
      expect(f.relationTo('u3'), 'sent');
      expect(await f.removeFriend('u1'), isNull);
      expect(f.friends, isEmpty);
      expect(await f.sendRequest('me'), isNotNull);
      f.dispose();
    },
  );

  test('búsqueda: mínimo 3 letras y excluye al propio usuario', () async {
    data.profiles['me'] = {'id': 'me', 'username': 'yo_mismo'};
    auth.set('me');
    final f = make();
    await settle();
    expect(await f.searchUsers('yo'), isEmpty);
    expect(await f.searchUsers('yo_'), isEmpty);
    data.profiles['u4'] = {'id': 'u4', 'username': 'yoli'};
    expect((await f.searchUsers('yol')).single.username, 'yoli');
    f.dispose();
  });

  test(
    'mensajes: dos sentidos, ventana de 100 y anteriores por amigo',
    () async {
      for (var i = 0; i < 130; i++) {
        data.shares.add(share(i));
      }
      // Dos enviados a ana, los más nuevos de todos.
      for (var i = 0; i < 2; i++) {
        data.shares.add({
          'id': 'out$i',
          'from_id': 'me',
          'to_id': 'u1',
          'kind': 'track',
          'track': {'id': 'o$i', 'title': 'Enviada $i', 'artist': 'Yo'},
          'note': null,
          'created_at': DateTime.utc(2026, 1, 1, 5, i).toIso8601String(),
          'seen': false,
        });
      }
      auth.set('me');
      final f = make();
      await settle();
      expect(f.messages.length, 100);
      expect(f.threadWith('u1').first.track.title, 'Enviada 1');
      expect(f.threadWith('u1').first.mine, isTrue);
      expect(f.threadWith('u1').where((i) => i.mine).length, 2);
      expect(f.hasOlderWith('u1'), isTrue);
      // Los enviados no cuentan como sin ver.
      expect(f.unseenCount, 130);
      await f.loadOlderWith('u1');
      expect(f.threadWith('u1').length, 120);
      expect(f.hasOlderWith('u1'), isTrue);
      await f.loadOlderWith('u1');
      expect(f.threadWith('u1').length, 132);
      expect(f.hasOlderWith('u1'), isFalse);
      await f.markSeen(['s129', 's128', 'out0']);
      expect(f.unseenCount, 128);
      expect(data.shares.where((s) => s['seen'] == true).length, 2);
      // Un refresh no pierde las páginas anteriores ya cargadas.
      await f.refresh();
      expect(f.threadWith('u1').length, 132);
      f.dispose();
    },
  );

  test('chats: orden por último envío y amigos sin envíos al final', () async {
    data.requests
      ..add(req('a', 'u1', 'me', 'accepted'))
      ..add(req('b', 'u2', 'me', 'accepted'))
      ..add(req('c', 'u3', 'me', 'accepted'));
    final now = DateTime.now();
    String ago(int m) =>
        now.subtract(Duration(minutes: m)).toUtc().toIso8601String();
    data.shares
      ..add({...share(1), 'created_at': ago(30), 'seen': true})
      ..add({...share(2), 'created_at': ago(20)})
      ..add({...share(3, from: 'u2'), 'created_at': ago(2)})
      ..add({...share(4, from: 'u2'), 'created_at': ago(5)});
    auth.set('me');
    final f = make();
    await settle();
    final chats = f.chats;
    expect(chats.map((c) => c.peer.username), ['beto', 'ana', 'carla']);
    expect(chats.map((c) => c.unseen), [2, 1, 0]);
    expect(chats.last.last, isNull);
    expect(chats.first.last!.id, 's3');
    f.dispose();
  });

  test('tiempo real: nueva canción y solicitud avisan y suman', () async {
    auth.set('me');
    final f = make();
    await settle();
    final notices = <FriendsNotice>[];
    f.notices.listen(notices.add);
    data.onShare!(share(1));
    await settle();
    expect(f.unseenCount, 1);
    expect(f.messages.single.peer.username, 'ana');
    expect(f.messages.single.mine, isFalse);
    data.requests.add(req('x', 'u2', 'me', 'pending'));
    data.onRequest!('insert', req('x', 'u2', 'me', 'pending'));
    await settle();
    expect(f.incoming.single.user.username, 'beto');
    expect(notices.map((n) => n.kind), [
      FriendsNoticeKind.share,
      FriendsNoticeKind.request,
    ]);
    expect(notices.map((n) => n.peerId), ['u1', null]);
    f.dispose();
  });

  test(
    'enviar: solo amigos, sin locales y sin ruta local en el JSON',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      const t = Track(id: 'abc', title: 'T', artist: 'A', pageUrl: 'file:///x');
      expect(await f.shareTrack('u2', t), isNotNull);
      expect(
        await f.shareTrack(
          'u1',
          const Track(id: 'l', title: 'L', artist: 'A', localPath: 'C:/m.mp3'),
        ),
        isNotNull,
      );
      expect(await f.shareTrack('u1', t, note: 'hola'), isNull);
      expect(data.lastTrack!.containsKey('localPath'), isFalse);
      expect(data.lastTrack!.containsKey('pageUrl'), isFalse);
      f.dispose();
    },
  );

  test('pista recibida no confiable se valida', () {
    expect(trackFromShared('x'), isNull);
    expect(trackFromShared({'id': 1, 'title': 't', 'artist': 'a'}), isNull);
    final t = trackFromShared({
      'id': 'v',
      'title': 't',
      'artist': 'a',
      'localPath': 'C:/secreto',
      'artworkUrl': 'javascript:alert(1)',
    })!;
    expect(t.localPath, isNull);
    expect(t.artworkUrl, isNull);
  });

  test(
    'listas: se filtran locales, se recorta y se valida al recibir',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      final many = [
        for (var i = 0; i < 600; i++)
          Track(id: 'v$i', title: 'T$i', artist: 'A'),
        const Track(id: 'loc', title: 'L', artist: 'A', localPath: 'C:/m.mp3'),
      ];
      expect(await f.sharePlaylist('u2', 'Mix', many), isNotNull);
      expect(await f.sharePlaylist('u1', 'Mix', many.sublist(600)), isNotNull);
      expect(await f.sharePlaylist('u1', 'Mix', many, note: 'toma'), isNull);
      expect(data.lastKind, 'playlist');
      final sent = data.lastTrack!['tracks'] as List;
      expect(sent.length, maxSharedPlaylistTracks);
      expect(sent.any((t) => (t as Map).containsKey('localPath')), isFalse);
      final back = playlistFromShared(data.lastTrack)!;
      expect(back.tracks.length, maxSharedPlaylistTracks);
      expect(playlistFromShared({'name': 'x', 'tracks': 'no'}), isNull);
      expect(playlistFromShared({'name': '', 'tracks': []}), isNull);
      f.dispose();
    },
  );

  test(
    'invitación a Jam: solo amigos, código válido, caduca a las 2 h',
    () async {
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      auth.set('me');
      final f = make();
      await settle();
      expect(await f.shareJamInvite('u1', 'no es un código'), isNotNull);
      expect(await f.shareJamInvite('u2', 'ABCD2345'), isNotNull);
      expect(await f.shareJamInvite('u1', 'abcd-2345'), isNull);
      expect(data.lastKind, 'jam');
      expect(data.lastTrack, {'code': 'ABCD2345'});
      expect(jamCodeFromShared({'code': 'abcd2345'}), 'ABCD2345');
      expect(jamCodeFromShared({'code': 'aurora://x'}), isNull);
      expect(jamCodeFromShared({'code': 5}), isNull);
      final item = SharedItem(
        id: 'j',
        peer: f.friends.first,
        mine: false,
        track: const Track(id: '-', title: '', artist: ''),
        createdAt: DateTime(2026, 1, 1, 10),
        seen: false,
        kind: SharedKind.jam,
        jamCode: 'ABCD2345',
      );
      expect(item.jamExpired(DateTime(2026, 1, 1, 11, 59)), isFalse);
      expect(item.jamExpired(DateTime(2026, 1, 1, 12, 1)), isTrue);
      f.dispose();
    },
  );

  test('bandeja con los tres tipos; los inválidos se descartan', () async {
    final now = DateTime.now().toUtc().toIso8601String();
    data.shares
      ..add({...share(1), 'created_at': now})
      ..add({
        ...share(2),
        'kind': 'playlist',
        'created_at': now,
        'track': {
          'name': 'Mix',
          'tracks': [
            {'id': 'a', 'title': 'T', 'artist': 'A'},
          ],
        },
      })
      ..add({
        ...share(3),
        'kind': 'jam',
        'created_at': now,
        'track': {'code': 'ABCD2345'},
      })
      ..add({
        ...share(4),
        'kind': 'jam',
        'track': {'code': '<x>'},
      })
      ..add({...share(5), 'kind': 'otro'})
      ..add({
        ...share(6),
        'kind': 'jam',
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'track': {'code': 'ABCD2345'},
      });
    auth.set('me');
    final f = make();
    await settle();
    expect(f.messages.map((i) => i.kind).toSet(), {
      SharedKind.track,
      SharedKind.playlist,
      SharedKind.jam,
    });
    // La Jam de hace 3 h llega en los datos (el falso no aplica RLS) pero el
    // hilo no la enseña.
    expect(f.messages.length, 4);
    expect(f.threadWith('u1').length, 3);
    expect(f.threadWith('u1').any((i) => i.jamExpired()), isFalse);
    final notices = <FriendsNoticeKind>[];
    f.notices.map((n) => n.kind).listen(notices.add);
    data.onShare!({
      ...share(9),
      'kind': 'jam',
      'created_at': now,
      'track': {'code': 'ZZZZ2345'},
    });
    await settle();
    expect(notices, [FriendsNoticeKind.jam]);
    f.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    required bool signedIn,
    Size? size,
    Future<void> Function(String)? onJoinJam,
    ValueNotifier<String?>? openChat,
    Track? playing,
  }) async {
    final controller = await createTestController();
    if (playing != null) {
      controller.queue = [playing];
      await controller.playQueueAt(0);
    }
    auth.uid = signedIn ? 'me' : null;
    final f = make();
    addTearDown(() {
      auth.dispose();
    });
    if (size != null) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [friendsServiceProvider.overrideWith((ref) => f)],
        child: MaterialApp(
          home: Scaffold(
            body: FriendsPage(
              controller: controller,
              onJoinJam: onJoinJam,
              openChat: openChat ?? ValueNotifier<String?>(null),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('página sin sesión invita a Ajustes → Cuenta', (tester) async {
    await tester.runAsync(() => pump(tester, signedIn: false));
    expect(find.byKey(const ValueKey('friends-signin-hint')), findsOneWidget);
    expect(find.textContaining('Ajustes → Cuenta'), findsOneWidget);
  });

  for (final size in [const Size(1000, 800), const Size(320, 640)]) {
    testWidgets('chat: lista, hilo, unirse y volver ${size.width.toInt()}px', (
      tester,
    ) async {
      final now = DateTime.now();
      String ago(int m) =>
          now.subtract(Duration(minutes: m)).toUtc().toIso8601String();
      data.requests.add(req('a', 'u1', 'me', 'accepted'));
      data.shares
        ..add({
          'id': 'out0',
          'from_id': 'me',
          'to_id': 'u1',
          'kind': 'track',
          'track': {'id': 'o0', 'title': 'Enviada por mí', 'artist': 'Yo'},
          'note': null,
          'created_at': ago(5),
          'seen': false,
        })
        ..add({
          ...share(2),
          'kind': 'playlist',
          'created_at': ago(3),
          'track': {
            'name': 'Mix de ana',
            'tracks': [
              {'id': 'a', 'title': 'T', 'artist': 'A'},
            ],
          },
        })
        ..add({
          ...share(3),
          'kind': 'jam',
          'created_at': ago(1),
          'track': {'code': 'ABCD2345'},
        });
      String? joined;
      final openChat = ValueNotifier<String?>(null);
      await tester.runAsync(
        () => pump(
          tester,
          signedIn: true,
          size: size,
          openChat: openChat,
          onJoinJam: (c) async => joined = c,
        ),
      );
      await tester.runAsync(settle);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
      await tester.pump();
      expect(find.byKey(const ValueKey('friends-chat-u1')), findsOneWidget);
      expect(find.text('Te invita a su Jam'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('friends-chat-u1')));
      await tester.pump();
      expect(openChat.value, 'u1');
      expect(find.text('ana te invita a su Jam'), findsOneWidget);
      expect(find.text('Mix de ana'), findsOneWidget);
      expect(find.text('1 canciones'), findsOneWidget);
      expect(find.byTooltip('Guardar en mi biblioteca'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-join-s3')));
      expect(joined, 'ABCD2345');
      // Lo enviado por mí está en lo alto del hilo; puede quedar fuera.
      await tester.drag(find.byType(ListView).first, const Offset(0, 400));
      await tester.pump();
      expect(find.text('Enviada por mí'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-back')));
      await tester.pump();
      expect(openChat.value, isNull);
      expect(find.byKey(const ValueKey('friends-chat-u1')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chat: enviar lo que suena añade el mensaje al hilo', (
    tester,
  ) async {
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    final openChat = ValueNotifier<String?>('u1');
    await tester.runAsync(
      () => pump(
        tester,
        signedIn: true,
        openChat: openChat,
        playing: const Track(id: 'v9', title: 'Nueva', artist: 'X'),
      ),
    );
    await tester.runAsync(settle);
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-empty')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chat-note')), 'hola');
    await tester.tap(find.byKey(const ValueKey('chat-send-now')));
    await tester.runAsync(settle);
    await tester.pump();
    expect(data.lastKind, 'track');
    expect(find.text('Nueva'), findsOneWidget);
    // La nota viaja en el mensaje y el campo se vacía.
    expect(find.text('«hola»'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('chat-note')),
    );
    expect(field.controller!.text, isEmpty);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('chat: invitación a Jam caducada no aparece', (tester) async {
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    data.shares
      ..add({
        ...share(1),
        'kind': 'jam',
        'created_at': DateTime.now()
            .subtract(const Duration(hours: 3))
            .toUtc()
            .toIso8601String(),
        'track': {'code': 'ABCD2345'},
      })
      ..add({
        ...share(2),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    final openChat = ValueNotifier<String?>('u1');
    await tester.runAsync(
      () => pump(tester, signedIn: true, openChat: openChat),
    );
    await tester.runAsync(settle);
    await tester.pump();
    expect(find.text('ana te invita a su Jam'), findsNothing);
    expect(find.text('Canción 2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('menú de canción: «Enviar a un amigo» sigue a la sesión', (
    tester,
  ) async {
    final controller = await tester.runAsync(createTestController);
    final f = make();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [friendsServiceProvider.overrideWith((ref) => f)],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SendToFriendButton(
                  track: const Track(id: 'x', title: 'T', artist: 'A'),
                ),
                SendToFriendButton(
                  track: const Track(
                    id: 'y',
                    title: 'L',
                    artist: 'A',
                    localPath: 'C:/m.mp3',
                  ),
                ),
                Text('${controller != null}'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('send-to-friend')), findsNothing);
    data.requests.add(req('a', 'u1', 'me', 'accepted'));
    auth.set('me');
    await tester.runAsync(settle);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-to-friend')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('send-to-friend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-to-u1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('share-to-u1')));
    await tester.pumpAndSettle();
    expect(data.lastKind, 'track');
    auth.set(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('send-to-friend')), findsNothing);
  });

  for (final size in [const Size(1000, 800), const Size(320, 640)]) {
    testWidgets('página con datos ${size.width.toInt()}px', (tester) async {
      data.requests
        ..add(req('a', 'u1', 'me', 'accepted'))
        ..add(req('b', 'u2', 'me', 'pending'));
      data.shares.add(share(0));
      await tester.runAsync(() => pump(tester, signedIn: true, size: size));
      await tester.runAsync(settle);
      await tester.pump();
      expect(find.text('ana'), findsOneWidget);
      expect(find.text('Solicitudes · 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friends-tab-1')));
      await tester.pump();
      expect(find.text('beto'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('friends-chat-u1')));
      await tester.pump();
      expect(find.text('Canción 0'), findsOneWidget);
      expect(find.textContaining('Escúchala'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });
  }
}
