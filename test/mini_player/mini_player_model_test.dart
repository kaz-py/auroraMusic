import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/mini_player/mini_player_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _a = Track(
  id: 'a',
  title: 'Uno',
  artist: 'Aurora',
  duration: Duration(minutes: 3),
);
const _b = Track(
  id: 'b',
  title: 'Dos',
  artist: 'Aurora',
  duration: Duration(minutes: 3),
);

void main() {
  test('sin pista: estado vacío y sin saltos', () async {
    final c = await createTestController();
    addTearDown(() => closeTestController(c));
    final s = MiniPlayerState.fromController(c);
    expect(s.hasTrack, isFalse);
    expect(s.progress, 0);
    expect(s.hasNext, isFalse);
    expect(s.hasPrevious, isFalse);
    expect(s.canTogglePlay, isFalse);
    expect(s.jamActive, isFalse);
  });

  test('refleja pista, progreso, favorito y cola', () async {
    final audio = FakeAudio();
    final c = await createTestController(tracks: [_a, _b], audio: audio);
    addTearDown(() => closeTestController(c));
    c.queue = [_a, _b];
    c.queueIndex = 0;
    audio.advanceTo(const Duration(seconds: 90));
    c.favoriteIds = {'a'};

    var s = MiniPlayerState.fromController(c);
    expect(s.track?.id, 'a');
    expect(s.progress, closeTo(.5, 1e-9));
    expect(s.liked, isTrue);
    expect(s.hasNext, isTrue);
    expect(s.hasPrevious, isTrue);
    expect(s.canTogglePlay, isTrue);
    expect(s.isPlaying, isFalse);

    c.queueIndex = 1;
    s = MiniPlayerState.fromController(c);
    expect(s.hasNext, isFalse, reason: 'última de la cola, sin repetir');
    expect(s.liked, isFalse);

    c.repeat = RepeatMode.all;
    expect(MiniPlayerState.fromController(c).hasNext, isTrue);
    c.repeat = RepeatMode.off;
    c.shuffle = true;
    expect(MiniPlayerState.fromController(c).hasNext, isTrue);
  });

  test(
    'progreso acotado a 0..1 aunque la posición pase de la duración',
    () async {
      final audio = FakeAudio();
      final c = await createTestController(tracks: [_a], audio: audio);
      addTearDown(() => closeTestController(c));
      c.queue = [_a];
      c.queueIndex = 0;
      audio.advanceTo(const Duration(minutes: 9));
      expect(MiniPlayerState.fromController(c).progress, 1);
    },
  );

  test('las acciones usan los métodos del controlador', () async {
    final c = await createTestController(tracks: [_a, _b]);
    addTearDown(() => closeTestController(c));
    c.queue = [_a, _b];
    c.queueIndex = 0;
    var opened = 0;
    final actions = MiniPlayerActions.forController(
      c,
      openPlayer: () => opened++,
    );
    actions.openPlayer();
    expect(opened, 1);

    actions.toggleLike();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.favoriteIds, contains('a'));
    actions.toggleLike();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.favoriteIds, isNot(contains('a')));

    actions.next();
    expect(c.queueIndex, 1);
    actions.previous();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.queueIndex, 0);
  });

  test('togglePlay del shell sustituye al del controlador', () async {
    final c = await createTestController(tracks: [_a]);
    addTearDown(() => closeTestController(c));
    var toggled = 0;
    final actions = MiniPlayerActions.forController(
      c,
      openPlayer: () {},
      togglePlay: () => toggled++,
    );
    actions.togglePlay();
    expect(toggled, 1);
  });

  test(
    'con audio de Jam: pista de la sesión y sin saltar ni pausar a mano',
    () async {
      final c = await createTestController(tracks: [_a, _b]);
      addTearDown(() => closeTestController(c));
      c.queue = [_a, _b];
      c.queueIndex = 0;
      await c.beginJamPlayback();
      addTearDown(c.endJamPlayback);
      c.setJamNowPlaying(_b);
      final s = MiniPlayerState.fromController(c);
      expect(s.jamActive, isTrue);
      expect(s.track?.id, 'b');
      expect(s.hasPrevious, isFalse);
      expect(s.hasNext, isFalse);
      expect(s.canTogglePlay, isFalse);
    },
  );
}
