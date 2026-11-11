import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_service.dart';
import 'package:aurora_music/jam/jam_suggestions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'jam_remote_test.dart' show guest, newRoom, until;

JamTrack tk(String tag, int n, String artist) {
  final id = '$tag${n.toString().padLeft(11 - tag.length, '0')}';
  return JamTrack.fromTrack(
    Track(
      id: 'yt:$id',
      title: '$tag $n',
      artist: artist,
      pageUrl: 'https://music.youtube.com/watch?v=$id',
    ),
  );
}

JamSuggestion sg(JamTrack t) => JamSuggestion(t, 'Radio de YouTube');

void main() {
  group('autoplay', () {
    test(
      '3 gustos: intercalado justo, sin duplicados ni artista seguido',
      () async {
        final room = await newRoom();
        final (g1, _) = await guest(room, 'Beto');
        final (g2, _) = await guest(room, 'Cris');
        await until(room.host, () => room.host.participants.length == 3);
        final dup = tk('dup', 1, 'Shared');
        room.host.publishSuggestions([
          sg(tk('rock', 1, 'Rock A')),
          sg(dup),
          sg(tk('rock', 2, 'Shared')),
          sg(tk('rock', 3, 'Rock B')),
        ]);
        g1.publishSuggestions([
          sg(tk('jazz', 1, 'Jazz A')),
          sg(dup),
          sg(tk('jazz', 2, 'Shared')),
          sg(tk('jazz', 3, 'Jazz B')),
        ]);
        g2.publishSuggestions([
          sg(tk('pop', 1, 'Pop A')),
          sg(tk('pop', 2, 'Pop B')),
          sg(tk('pop', 3, 'Shared')),
        ]);
        await until(room.host, () => room.host.groupSuggestions.length >= 9);
        expect(room.host.upcomingQueued, 0);

        expect(room.host.promoteSuggested(target: 6), 6);
        expect(room.host.upcomingQueued, 6);
        final promoted = room.host.queue
            .where((e) => e.status == JamEntryStatus.queued)
            .toList();
        final keys = promoted.expand((e) => e.track.keys).toList();
        expect(keys.toSet().length, keys.length, reason: 'sin duplicados');
        final artists = [for (final e in promoted) e.track.artist];
        for (var i = 1; i < artists.length; i++) {
          expect(artists[i], isNot(artists[i - 1]));
        }
        final perPerson = <String, int>{};
        for (final e in promoted) {
          expect(e.suggestedFor, isNotNull);
          perPerson[e.suggestedFor!] = (perPerson[e.suggestedFor!] ?? 0) + 1;
        }
        expect(perPerson.length, 3);
        expect(perPerson.values.every((c) => c == 2), isTrue);
        expect(room.host.promoteSuggested(target: 6), 0);
        await until(
          g1,
          () => g1.queue.where((e) => e.suggestedFor != null).length >= 6,
        );
        expect(g1.participantName(promoted.first.suggestedFor!), isNotEmpty);
      },
    );

    test('las pendientes de aprobación no se promueven', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      await room.host.setRules(const JamRules(approve: true));
      g1.publishSuggestions([sg(tk('jazz', 1, 'Jazz A'))]);
      await until(room.host, () => room.host.queue.length == 1);
      expect(room.host.queue.single.status, JamEntryStatus.pending);
      expect(room.host.promoteSuggested(), 0);
    });

    test('autoplay viaja en las reglas y está apagado por defecto', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      expect(room.host.rules.autoplay, isFalse);
      expect(g1.rules.autoplay, isFalse);
      await room.host.setRules(room.host.rules.copyWith(autoplay: true));
      await until(g1, () => g1.rules.autoplay);
    });
  });

  group('añadir en lote', () {
    test('anfitrión: tope de 200 e informa lo descartado', () async {
      final room = await newRoom();
      final all = [for (var i = 0; i < 230; i++) tk('big', i, 'A$i')];
      final r = await room.host.addMany([...all, all.first]);
      expect(room.host.queue.length, 200);
      expect(r.added, 200);
      expect(r.dropped, 31);
      expect(r.message, contains('descartadas'));
    });

    test('anfitrión: modos siguiente y mezclar', () async {
      final room = await newRoom();
      await room.host.addMany([tk('a', 1, 'X'), tk('a', 2, 'Y')]);
      final r = await room.host.addMany([
        tk('b', 1, 'P'),
        tk('b', 2, 'Q'),
      ], mode: JamAddMode.playNext);
      expect(room.host.queue.first.track.title, 'b 1');
      expect(r.firstEntryId, room.host.queue.first.id);
      final s = await room.host.addMany([
        for (var i = 0; i < 20; i++) tk('c', i, 'Z$i'),
      ], mode: JamAddMode.shuffle);
      expect(s.added, 20);
      expect(
        room.host.queue.skip(4).map((e) => e.track.title).join(),
        isNot([for (var i = 0; i < 20; i++) 'c $i'].join()),
      );
    });

    test('invitado: lotes con espera, tope y orden al final', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      await room.host.setRules(const JamRules(maxPerGuest: 7));
      await until(g1, () => g1.rules.maxPerGuest == 7);
      final waits = <Duration>[];
      final progress = <JamAddProgress>[];
      final r = await g1.addMany(
        [for (var i = 0; i < 10; i++) tk('g', i, 'G$i')],
        mode: JamAddMode.playNow,
        wait: (d) async => waits.add(d),
        onProgress: progress.add,
      );
      expect(r.added, 7);
      expect(r.message, contains('tope por invitado'));
      expect(r.message, contains('solo el anfitrión'));
      expect(waits.length, 1);
      expect(waits.first, jamRemoteBatchWait);
      expect(progress.any((p) => p.running), isTrue);
      expect(progress.last.running, isFalse);
      await until(room.host, () => room.host.queue.length == 7);
      expect(room.host.queue.first.track.title, 'g 0');
    });

    test('permisos: sin permiso o silenciado falla con mensaje', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      room.host.setPermissions(
        g1.participantId,
        const JamPermissions(add: false),
      );
      await until(g1, () => g1.me?.permissions.add == false);
      await expectLater(
        g1.addMany([tk('n', 1, 'N')]),
        throwsA(
          isA<JamException>().having(
            (e) => e.message,
            'mensaje',
            contains('no permite'),
          ),
        ),
      );
      room.host.setPermissions(g1.participantId, const JamPermissions());
      await room.host.setMuted(g1.participantId, true);
      await until(g1, () => g1.me?.muted == true);
      await expectLater(
        g1.addMany([tk('n', 2, 'N')]),
        throwsA(isA<JamException>()),
      );
    });

    test('añadir una sugerida desde un invitado la sube a la cola', () async {
      final room = await newRoom();
      final (g1, _) = await guest(room, 'Beto');
      await until(room.host, () => room.host.participants.length == 2);
      g1.publishSuggestions([sg(tk('jazz', 1, 'Jazz A'))]);
      await until(g1, () => g1.groupSuggestions.length == 1);
      final s = g1.groupSuggestions.single;
      expect(s.forName, 'Beto');
      g1.addTrack(s.track);
      await until(
        g1,
        () => g1.groupSuggestions.isEmpty && g1.queue.length == 1,
      );
      expect(g1.queue.single.status, JamEntryStatus.queued);
    });
  });

  test('sin red ni YouTube las sugerencias salen de lo local', () async {
    final out = await JamSuggestionAdapter(
      related: (_) async => throw Exception('sin red'),
      seeds: () => [const Track(id: 'yt:abcdefghijk', title: 'S', artist: 'A')],
      local: () => [
        const Track(id: 'yt:zzzzzzzzzzz', title: 'Local', artist: 'L'),
      ],
    ).build();
    expect(out.single.reason, 'De tu biblioteca');
  });
}
