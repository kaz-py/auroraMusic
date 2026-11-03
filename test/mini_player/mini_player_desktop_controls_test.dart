import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/mini_player/mini_player_desktop_controls.dart';
import 'package:aurora_music/ui/mini_player/mini_player_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _a = Track(
  id: 'a',
  title: 'Uno',
  artist: 'Aurora',
  duration: Duration(minutes: 3),
);

class _Calls {
  final log = <String>[];
  double? volume;
  late final actions = MiniPlayerActions(
    openPlayer: () {},
    togglePlay: () {},
    next: () {},
    previous: () {},
    toggleLike: () {},
    setVolume: (v) {
      volume = v;
      log.add('volume');
    },
    toggleMute: () => log.add('mute'),
    openQueue: () => log.add('queue'),
    openEqualizer: () => log.add('eq'),
    openLyrics: () => log.add('lyrics'),
  );
}

MiniPlayerState _state({
  double volume = .5,
  bool eq = true,
  bool eqActive = false,
  bool lyrics = true,
  int queue = 3,
}) => MiniPlayerState(
  track: _a,
  isPlaying: true,
  progress: 0,
  buffering: false,
  hasError: false,
  liked: false,
  hasNext: true,
  hasPrevious: true,
  jamActive: false,
  canTogglePlay: true,
  volume: volume,
  queueLength: queue,
  equalizerAvailable: eq,
  equalizerActive: eqActive,
  lyricsAvailable: lyrics,
);

Widget _host(Widget controls, {double width = 400, double scale = 1}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: controls),
          ),
        ),
      ),
    );

MiniPlayerDesktopControls _controls(
  _Calls calls,
  MiniPlayerState state, {
  bool compact = false,
}) => MiniPlayerDesktopControls(
  state: state,
  actions: calls.actions,
  color: Colors.black,
  compact: compact,
);

void main() {
  testWidgets('completo: volumen, cola, EQ y letras de 44 px que actúan', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(_controls(calls, _state())));
    expect(find.byType(Slider), findsOneWidget);
    for (final tip in [
      'Silenciar',
      'Abrir cola (3)',
      'Ecualizador',
      'Letras',
    ]) {
      final box = find.byTooltip(tip);
      expect(box, findsOneWidget, reason: tip);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.byIcon(_iconOf(tester, tip)),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .shortestSide,
        greaterThanOrEqualTo(44),
      );
      await tester.tap(box);
    }
    expect(calls.log, ['mute', 'queue', 'eq', 'lyrics']);
    await tester.drag(find.byType(Slider), const Offset(20, 0));
    expect(calls.volume, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin slider si no cabe o con compact', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(_controls(calls, _state()), width: 200));
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Letras'), findsOneWidget);
    await tester.pumpWidget(
      _host(_controls(calls, _state(), compact: true), width: 600),
    );
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('estrecho: colapsa en el menú ⋯ y sus acciones funcionan', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_host(_controls(calls, _state()), width: 100));
    expect(find.byTooltip('Letras'), findsNothing);
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir cola (3)'));
    await tester.pumpAndSettle();
    expect(calls.log, ['queue']);
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letras'));
    await tester.pumpAndSettle();
    expect(calls.log, ['queue', 'lyrics']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EQ no disponible y sin letras: desactivados', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(_controls(calls, _state(eq: false, lyrics: false))),
    );
    await tester.tap(
      find.byTooltip('Ecualizador no disponible en este reproductor'),
    );
    await tester.tap(find.byTooltip('Letras'));
    expect(calls.log, isEmpty);
  });

  testWidgets('silenciado cambia tooltip e icono; EQ activo se anuncia', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(
      _host(_controls(calls, _state(volume: 0, eqActive: true))),
    );
    expect(find.byTooltip('Quitar silencio'), findsOneWidget);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
    expect(find.byTooltip('Ecualizador (activo)'), findsOneWidget);
  });

  testWidgets('semántica del slider y de los botones', (tester) async {
    final handle = tester.ensureSemantics();
    final calls = _Calls();
    await tester.pumpWidget(_host(_controls(calls, _state(volume: .5))));
    expect(find.bySemanticsLabel('Silenciar'), findsOneWidget);
    expect(find.bySemanticsLabel('Letras'), findsOneWidget);
    expect(find.semantics.byValue('Volumen 50 por ciento'), findsOneWidget);
    handle.dispose();
  });

  for (final width in [100.0, 200.0, 300.0, 700.0]) {
    testWidgets('texto ×2 sin desbordes a ${width.toInt()} px', (tester) async {
      final calls = _Calls();
      await tester.pumpWidget(
        _host(_controls(calls, _state()), width: width, scale: 2),
      );
      expect(tester.takeException(), isNull);
    });
  }

  group('estado desde el controlador', () {
    test('volumen, cola, EQ y letras', () async {
      final audio = FakeAudio();
      final c = await createTestController(tracks: [_a], audio: audio);
      addTearDown(() => closeTestController(c));
      var s = MiniPlayerState.fromController(c);
      expect(s.hasQueue, isFalse);
      expect(s.lyricsAvailable, isFalse);
      c.queue = [_a];
      c.queueIndex = 0;
      c.setVolume(.4);
      s = MiniPlayerState.fromController(c);
      expect(s.volume, closeTo(.4, 1e-9));
      expect(s.muted, isFalse);
      expect(s.queueLength, 1);
      expect(s.hasQueue, isTrue);
      expect(s.lyricsAvailable, isTrue);
      expect(s.equalizerAvailable, c.eq.supported);
      expect(s.canSetVolume, isTrue);
    });

    test(
      'setVolume y toggleMute usan el controlador y recuerdan el volumen',
      () async {
        final audio = FakeAudio();
        final c = await createTestController(audio: audio);
        addTearDown(() => closeTestController(c));
        final mute = MuteMemory();
        final actions = MiniPlayerActions.forController(
          c,
          openPlayer: () {},
          mute: mute,
        );
        actions.setVolume(.3);
        expect(audio.volume, closeTo(.3, 1e-9));
        actions.toggleMute();
        expect(audio.volume, 0);
        expect(MiniPlayerState.fromController(c).muted, isTrue);
        actions.toggleMute();
        expect(audio.volume, closeTo(.3, 1e-9));
      },
    );

    test('openQueue y openLyrics llegan tal cual', () async {
      final c = await createTestController();
      addTearDown(() => closeTestController(c));
      final log = <String>[];
      final actions = MiniPlayerActions.forController(
        c,
        openPlayer: () {},
        openQueue: () => log.add('q'),
        openLyrics: () => log.add('l'),
      );
      actions.openQueue();
      actions.openLyrics();
      actions.openEqualizer(); // sin callback: no hace nada
      expect(log, ['q', 'l']);
    });
  });
}

IconData _iconOf(WidgetTester tester, String tip) {
  final icon = find.descendant(
    of: find.byTooltip(tip),
    matching: find.byType(Icon),
  );
  return tester.widget<Icon>(icon.first).icon!;
}
