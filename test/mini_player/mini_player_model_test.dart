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

  test('canSeek y seek(fracción) usan la duración y el controlador', () async {
    final audio = FakeAudio();
    final c = await createTestController(audio: audio);
    addTearDown(() => closeTestController(c));
    expect(MiniPlayerState.fromController(c).canSeek, isFalse);
    await c.playTrack(
      const Track(
        id: 'a',
        title: 'Uno',
        artist: 'Aurora',
        pageUrl: 'https://www.youtube.com/watch?v=a',
        duration: Duration(minutes: 3),
      ),
    );
    expect(MiniPlayerState.fromController(c).canSeek, isTrue);
    final actions = MiniPlayerActions.forController(c, openPlayer: () {});
    actions.seek(.5);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(audio.position, const Duration(seconds: 90));
    actions.seek(2);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(audio.position, const Duration(minutes: 3));
  });

  group('miniSubtitle', () {
    MiniPlayerState state({
      bool ad = false,
      bool jam = false,
      bool error = false,
    }) => MiniPlayerState(
      track: _a,
      isPlaying: true,
      progress: 0,
      buffering: false,
      hasError: error,
      liked: false,
      hasNext: false,
      hasPrevious: false,
      jamActive: jam,
      adPlaying: ad,
      jamAudio: jam,
      canTogglePlay: true,
    );

    test('artista por defecto; con artista de titular, la pista', () {
      expect(miniSubtitle(state()), 'Aurora');
      expect(miniSubtitle(state(), artistProminent: true), 'Uno');
    });

    test('anuncio, Jam y fallo con su prioridad', () {
      expect(miniSubtitle(state(ad: true, error: true)), miniAdNotice);
      expect(
        miniSubtitle(state(ad: true), artistProminent: true),
        miniAdNotice,
      );
      // El anuncio no cuenta con audio de Jam.
      expect(miniSubtitle(state(ad: true, jam: true)), 'Aurora · Jam');
      expect(
        miniSubtitle(state(jam: true), artistProminent: true),
        'Uno · Jam',
      );
      expect(miniSubtitle(state(error: true)), miniErrorNotice);
      expect(miniSubtitleIsError(state(error: true)), isTrue);
      expect(miniSubtitleIsError(state(ad: true, error: true)), isFalse);
      expect(miniSubtitleIsError(state(jam: true, error: true)), isFalse);
    });
  });

  test('miniClock: m:ss, h:mm:ss y negativos a cero', () {
    expect(miniClock(Duration.zero), '0:00');
    expect(miniClock(const Duration(seconds: 65)), '1:05');
    expect(miniClock(const Duration(seconds: 3605)), '1:00:05');
    expect(miniClock(const Duration(seconds: -3)), '0:00');
  });

  group('etiquetas de siguiente y anterior', () {
    MiniPlayerState state({
      String? skipHost,
      bool vote = false,
      bool jam = false,
    }) => MiniPlayerState(
      track: _a,
      isPlaying: true,
      progress: 0,
      buffering: false,
      hasError: false,
      liked: false,
      hasNext: true,
      hasPrevious: true,
      jamActive: jam,
      canTogglePlay: true,
      jamSkipHost: skipHost,
      jamVoteSkip: vote,
    );

    test('siguiente: normal, lo controla el anfitrión o votar', () {
      expect(state().nextLabel(), 'Siguiente');
      expect(state().nextLabel('Pista siguiente'), 'Pista siguiente');
      expect(state(skipHost: 'Ana').nextLabel(), 'Lo controla Ana');
      expect(
        state(skipHost: 'Ana', vote: true).nextLabel(),
        'Votar para saltar',
      );
    });

    test('anterior: no disponible con la Jam activa', () {
      expect(state().previousLabel(), 'Anterior');
      expect(state(jam: true).previousLabel(), 'No disponible en una Jam');
    });
  });
}
