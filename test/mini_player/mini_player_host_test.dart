import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _track = Track(
  id: 'a',
  title: 'Una canción con un título larguísimo para comprobar el recorte',
  artist: 'Un artista con un nombre igual de largo que el título anterior',
  artworkUrl: 'https://covers.test/a.jpg',
  duration: Duration(minutes: 3),
);

class _Seen {
  final kinds = <String>[];
  bool? wide;
  MiniPlayerState? state;
  MiniPlayerActions? actions;
  int builds = 0;
}

Map<String, MiniPlayerTheme> _themes(_Seen seen) => {
  for (final kind in const ['atelier', 'modern', 'brasa', 'slush'])
    kind: MiniPlayerTheme(
      build: (context, state, actions, {required wide}) {
        seen
          ..kinds.add(kind)
          ..wide = wide
          ..state = state
          ..actions = actions
          ..builds += 1;
        return SizedBox(
          key: const ValueKey('mini'),
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${state.track!.artist} — ${state.track!.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Reproducir',
                onPressed: actions.togglePlay,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        );
      },
    ),
};

class _Counts {
  int open = 0, toggle = 0, queue = 0, lyrics = 0;
}

void main() {
  group('reglas puras', () {
    test(
      'visible solo con pista, fuera de la sección 4 y de YouTube Music',
      () {
        bool v(bool track, int section, [bool official = false]) =>
            MiniPlayerHost.isVisible(
              hasTrack: track,
              section: section,
              officialMusicPage: official,
            );
        expect(v(true, 0), isTrue);
        expect(v(false, 0), isFalse);
        expect(v(true, 4), isFalse);
        expect(v(true, 6), isFalse); // Letras (modo artista): controles propios
        expect(v(true, 10, true), isFalse);
      },
    );

    test('Slush móvil lleva el mini en su barra, también con Jam', () {
      MiniPlayerPlacement p(bool slush, bool rail) =>
          MiniPlayerHost.placementFor(slush: slush, rail: rail);
      expect(p(true, false), MiniPlayerPlacement.bottomBar);
      expect(p(true, true), MiniPlayerPlacement.body);
      expect(p(false, false), MiniPlayerPlacement.body);
      expect(p(false, true), MiniPlayerPlacement.body);
    });

    test('el registro cubre los cuatro temas', () {
      expect(
        miniPlayerThemes.keys,
        unorderedEquals(['atelier', 'modern', 'brasa', 'slush']),
      );
    });
  });

  group('host', () {
    late AppController controller;
    late _Seen seen;
    late _Counts counts;

    Future<void> mount(
      WidgetTester tester, {
      int section = 0,
      bool rail = false,
      MiniPlayerPlacement placement = MiniPlayerPlacement.body,
      ThemeData? theme,
      double scale = 1,
      Size size = const Size(390, 800),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox()),
                  MiniPlayerHost(
                    controller: controller,
                    section: section,
                    rail: rail,
                    placement: placement,
                    themes: _themes(seen),
                    onOpenPlayer: () => counts.open++,
                    onTogglePlay: () => counts.toggle++,
                    onOpenQueue: () => counts.queue++,
                    onOpenLyrics: () => counts.lyrics++,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // El tema se interpola 200 ms: hasta asentarse el marcador no es fiable.
      await tester.pumpAndSettle();
    }

    setUp(() => seen = _Seen());
    setUp(() => counts = _Counts());

    Future<void> setup(WidgetTester tester, {bool playing = true}) async {
      controller = (await tester.runAsync(
        () => createTestController(tracks: [_track]),
      ))!;
      addTearDown(() => closeTestController(controller));
      if (playing) {
        controller.queue = [_track];
        controller.queueIndex = 0;
      }
    }

    testWidgets('sin pista no se construye el tema', (tester) async {
      await setup(tester, playing: false);
      await mount(tester);
      expect(find.byKey(const ValueKey('mini')), findsNothing);
      expect(seen.builds, 0);
    });

    testWidgets('en la sección 4 se oculta y fuera de ella aparece', (
      tester,
    ) async {
      await setup(tester);
      await mount(tester, section: 4);
      expect(find.byKey(const ValueKey('mini')), findsNothing);
      await mount(tester, section: 0);
      expect(find.byKey(const ValueKey('mini')), findsOneWidget);
    });

    testWidgets('solo dibuja el host de su ubicación', (tester) async {
      await setup(tester);
      await mount(tester, placement: MiniPlayerPlacement.bottomBar);
      expect(find.byKey(const ValueKey('mini')), findsNothing);
    });

    testWidgets('elige el tema por themeKind y pasa wide', (tester) async {
      await setup(tester);
      await mount(tester);
      expect(seen.kinds.last, 'atelier');
      expect(seen.wide, isFalse);
      await mount(tester, theme: brasaTheme(Brightness.dark, Colors.orange));
      expect(seen.kinds.last, 'brasa');
      await mount(tester, theme: modernTheme(Brightness.light, Colors.teal));
      expect(seen.kinds.last, 'modern');
      await mount(
        tester,
        theme: slushTheme(Brightness.light, Colors.teal),
        placement: MiniPlayerPlacement.bottomBar,
      );
      expect(seen.kinds.last, 'slush');
      expect(find.byKey(const ValueKey('mini')), findsOneWidget);

      await mount(tester, rail: true);
      await tester.pump();
      expect(seen.wide, isTrue);
    });

    testWidgets('con carril solo el tema recibe openMenu; en móvil no', (
      tester,
    ) async {
      await setup(tester);
      await mount(tester);
      expect(seen.actions!.openMenu, isNull);
      await mount(tester, rail: true);
      expect(seen.actions!.openMenu, isNotNull);
    });

    testWidgets('el host envuelve en gestos: toque abre, botón no', (
      tester,
    ) async {
      await setup(tester);
      await mount(tester);
      await tester.tapAt(
        tester.getTopLeft(find.byKey(const ValueKey('mini'))) +
            const Offset(20, 28),
      );
      expect(counts.open, 1);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(counts.toggle, 1);
      expect(counts.open, 1);
    });

    testWidgets('cola y letras las abre el shell; el EQ, una hoja propia', (
      tester,
    ) async {
      await setup(tester);
      await mount(tester);
      seen.actions!.openQueue();
      seen.actions!.openLyrics();
      expect((counts.queue, counts.lyrics), (1, 1));
      expect(seen.state!.equalizerAvailable, controller.eq.supported);
      seen.actions!.openEqualizer();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('estado y acciones salen del controlador', (tester) async {
      await setup(tester);
      controller.favoriteIds = {'a'};
      await mount(tester);
      expect(seen.state!.liked, isTrue);
      expect(seen.state!.track?.id, 'a');
      seen.actions!.openPlayer();
      expect(counts.open, 1);
    });

    for (final size in [
      const Size(320, 640),
      const Size(390, 844),
      const Size(1100, 700),
    ]) {
      testWidgets('sin desbordes a ${size.width.toInt()} px y texto ×2', (
        tester,
      ) async {
        await setup(tester);
        await mount(tester, size: size, scale: 2, rail: size.width >= 600);
        expect(find.byKey(const ValueKey('mini')), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(const ValueKey('mini'))).height,
          greaterThanOrEqualTo(44),
        );
      });
    }

    testWidgets('altura mínima crece con el texto', (tester) async {
      await setup(tester);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(MiniPlayerHost.heightFor(context, wide: false), 56 * 1.5);
      expect(MiniPlayerHost.heightFor(context, wide: true), 64 * 1.5);
    });
  });
}
