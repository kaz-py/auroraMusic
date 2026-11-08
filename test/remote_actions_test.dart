import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/remote/aurora_remote_actions.dart';
import 'package:aurora_music/remote/remote_control_server.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _a = Track(
  id: 'a',
  title: 'Uno',
  artist: 'Ana',
  pageUrl: 'https://music.youtube.com/watch?v=aaaaaaaaaaa',
);
const _b = Track(
  id: 'b',
  title: 'Dos',
  artist: 'Beto',
  pageUrl: 'https://music.youtube.com/watch?v=bbbbbbbbbbb',
);

void main() {
  late AppController app;
  late FakeAudio audio;
  JamController? jam;
  late AuroraRemoteActions actions;

  setUp(() async {
    audio = FakeAudio();
    app = await createTestController(tracks: [_a, _b], audio: audio);
    jam = null;
    actions = AuroraRemoteActions(
      app,
      currentJam: () => jam,
      ensureJam: () => jam ??= JamController(app: app),
    );
  });
  tearDown(() => closeTestController(app));

  test(
    'without a Jam, commands drive the player and status reflects it',
    () async {
      await app.playTrack(_a, context: [_a, _b]);
      expect(actions.status()['track'], containsPair('title', 'Uno'));
      expect(actions.status()['jam'], isNull);
      expect(actions.status()['queueLength'], 2);

      await actions.pause();
      expect(audio.isPlaying, isFalse);
      expect(actions.status()['playing'], isFalse);
      await actions.play();
      expect(audio.isPlaying, isTrue);
      await actions.toggle();
      expect(audio.isPlaying, isFalse);

      await actions.next();
      expect(app.currentTrack?.id, 'b');
      await actions.previous();
      expect(app.currentTrack?.id, 'a');
    },
  );

  test('starting a Jam on a server-less build fails with the reason', () async {
    await expectLater(
      actions.startJam(mode: 'online'),
      throwsA(
        isA<RemoteControlException>().having((e) => e.status, 'status', 409),
      ),
    );
  });

  test(
    'in a Jam, controls go through its permissions and previous is refused',
    () async {
      await app.playTrack(_a, context: [_a, _b]);
      final guest = JamController(app: app);
      guest.service
        ..connection = JamConnection.connected
        ..participantId = 'guest'
        ..participants = [
          const JamParticipant(
            id: 'host',
            name: 'Lucía',
            role: JamRole.host,
            permissions: JamPermissions.all,
          ),
          const JamParticipant(id: 'guest', name: 'Beto'),
        ];
      jam = guest;
      expect(actions.status()['jam'], containsPair('host', false));

      // Sin permiso de pausa ni de salto: la Jam responde, la API no lo esquiva.
      await expectLater(
        actions.toggle(),
        throwsA(
          isA<RemoteControlException>()
              .having((e) => e.status, 'status', 409)
              .having((e) => e.message, 'message', contains('Lucía')),
        ),
      );
      await expectLater(actions.next(), throwsA(isA<RemoteControlException>()));
      await expectLater(
        actions.previous(),
        throwsA(isA<RemoteControlException>()),
      );
      expect(app.currentTrack?.id, 'a');

      // Iniciar una Jam con otra ya activa no crea una segunda.
      final again = await actions.startJam();
      expect(again['alreadyActive'], isTrue);
    },
  );
}
