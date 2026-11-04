import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart' show auroraTheme;
import 'package:aurora_music/ui/mini_player/cover_tone.dart' show coverContrast;
import 'package:aurora_music/ui/mini_player/atelier_mini_player.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/studio/studio_symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _plain = Track(
  id: 'p',
  title: 'Una canción con un título larguísimo para comprobar el recorte',
  artist: 'Un artista con un nombre igual de largo que el título anterior',
);

class _Calls {
  int open = 0, play = 0, next = 0, previous = 0, like = 0;
  int mute = 0, queue = 0, eq = 0, lyrics = 0;
  final seeks = <double>[];
  late final actions = MiniPlayerActions(
    openPlayer: () => open++,
    togglePlay: () => play++,
    next: () => next++,
    previous: () => previous++,
    toggleLike: () => like++,
    seek: seeks.add,
    toggleMute: () => mute++,
    openQueue: () => queue++,
    openEqualizer: () => eq++,
    openLyrics: () => lyrics++,
  );
}

MiniPlayerState _state({
  Track? track = _plain,
  bool playing = false,
  double progress = .4,
  bool buffering = false,
  bool error = false,
  bool liked = false,
  bool hasNext = true,
  bool hasPrevious = true,
  bool canTogglePlay = true,
  bool seek = false,
  int queue = 0,
  bool eq = false,
  bool lyrics = false,
  String? jamHost,
  bool ad = false,
  bool jam = false,
}) => MiniPlayerState(
  track: track,
  isPlaying: playing,
  progress: progress,
  buffering: buffering,
  hasError: error,
  liked: liked,
  hasNext: hasNext,
  hasPrevious: hasPrevious,
  jamActive: false,
  canTogglePlay: canTogglePlay,
  canSeek: seek,
  queueLength: queue,
  equalizerAvailable: eq,
  lyricsAvailable: lyrics,
  jamHostName: jamHost,
  adPlaying: ad,
  jamAudio: jam,
);

final _light = auroraTheme(Brightness.light, const Color(0xffe86927));
final _dark = auroraTheme(Brightness.dark, const Color(0xffe86927));

void main() {
  Future<_Calls> mount(
    WidgetTester tester, {
    MiniPlayerState? state,
    bool wide = false,
    double width = 412,
    double scale = 1,
    bool dark = false,
    bool reduced = false,
    bool gestures = false,
  }) async {
    final calls = _Calls();
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? _dark : _light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduced,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              Builder(
                builder: (context) {
                  Widget bar = ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MiniPlayerHost.heightFor(context, wide: wide),
                    ),
                    child: AtelierMiniPlayer(
                      state: state ?? _state(),
                      actions: calls.actions,
                      wide: wide,
                    ),
                  );
                  if (gestures) {
                    bar = MiniPlayerGestures(
                      actions: calls.actions,
                      hasNext: state?.hasNext ?? true,
                      hasPrevious: state?.hasPrevious ?? true,
                      child: bar,
                    );
                  }
                  return bar;
                },
              ),
            ],
          ),
        ),
      ),
    );
    // El tema se interpola 200 ms al cambiar entre claro y oscuro.
    await tester.pump(const Duration(milliseconds: 300));
    return calls;
  }

  Finder text(String s) => find.text(s);
  TextStyle style(WidgetTester tester, String s) =>
      tester.widget<Text>(text(s)).style!;
  Finder button(String tooltip) => find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(IconButton),
  );

  test('el registro usa el diseño nuevo, no la barra anterior', () {
    expect(miniPlayerThemes['atelier'], same(atelierMiniPlayer));
  });

  group('sin desbordes', () {
    for (final (name, width, wide) in const [
      ('360', 360.0, false),
      ('412', 412.0, false),
      ('600 con carril', 600.0, true),
      ('900', 900.0, true),
      ('1440', 1440.0, true),
    ]) {
      for (final scale in const [1.0, 2.0]) {
        for (final dark in const [false, true]) {
          testWidgets(
            '$name · texto ×${scale.toInt()} · ${dark ? 'oscuro' : 'claro'}',
            (tester) async {
              await mount(
                tester,
                width: width,
                wide: wide,
                scale: scale,
                dark: dark,
                state: _state(playing: true, liked: true),
              );
              expect(tester.takeException(), isNull);
              final size = tester.getSize(find.byType(AtelierMiniPlayer));
              expect(size.width, width);
              final min = (wide ? 64.0 : 56.0) * scale.clamp(1.0, 1.5);
              expect(size.height, greaterThanOrEqualTo(min));
              // Ningún botón se sale de la barra.
              final bar = tester.getRect(find.byType(AtelierMiniPlayer));
              for (final b in find.byType(IconButton).evaluate()) {
                final r = tester.getRect(find.byWidget(b.widget));
                expect(bar.contains(r.topLeft), isTrue);
                expect(
                  bar.contains(r.bottomRight - const Offset(1, 1)),
                  isTrue,
                );
              }
            },
          );
        }
      }
    }

    testWidgets('320 px con texto ×2 prescinde del corazón y no desborda', (
      tester,
    ) async {
      await mount(tester, width: 320, scale: 2, state: _state(playing: true));
      expect(tester.takeException(), isNull);
      expect(button('Añadir a favoritos'), findsNothing);
      expect(button('Pausar'), findsOneWidget);
    });
  });

  group('táctil y semántica', () {
    testWidgets('todos los botones miden al menos 44 × 44', (tester) async {
      for (final wide in const [false, true]) {
        await mount(tester, wide: wide, width: wide ? 900 : 360);
        final buttons = find.byType(IconButton).evaluate().toList();
        expect(buttons.length, wide ? 4 : 3);
        for (final b in buttons) {
          final size = tester.getSize(find.byWidget(b.widget));
          expect(size.width, greaterThanOrEqualTo(44));
          expect(size.height, greaterThanOrEqualTo(44));
        }
      }
    });

    testWidgets('móvil: corazón, play y siguiente; ancho: añade anterior', (
      tester,
    ) async {
      await mount(tester);
      expect(button('Añadir a favoritos'), findsOneWidget);
      expect(button('Reproducir'), findsOneWidget);
      expect(button('Siguiente'), findsOneWidget);
      expect(button('Anterior'), findsNothing);
      await mount(tester, wide: true, width: 900);
      expect(button('Anterior'), findsOneWidget);
    });

    testWidgets('la línea de tiempo expone su valor', (tester) async {
      final handle = tester.ensureSemantics();
      await mount(tester, state: _state(progress: .5));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Progreso de la pista')),
        matchesSemantics(label: 'Progreso de la pista', value: '50 %'),
      );
      handle.dispose();
    });
  });

  group('contraste (claro y oscuro)', () {
    for (final dark in const [false, true]) {
      testWidgets('texto y botón de play, ${dark ? 'oscuro' : 'claro'}', (
        tester,
      ) async {
        await mount(tester, dark: dark, state: _state(liked: true));
        final scheme = (dark ? _dark : _light).colorScheme;
        final paper = scheme.surfaceContainerLow;
        expect(
          coverContrast(style(tester, _plain.title).color!, paper),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          coverContrast(style(tester, _plain.artist).color!, paper),
          greaterThanOrEqualTo(4.5),
        );
        final play = tester.widget<IconButton>(button('Reproducir')).style!;
        final bg = play.backgroundColor!.resolve({})!;
        final fg = play.foregroundColor!.resolve({})!;
        expect(coverContrast(fg, bg), greaterThanOrEqualTo(4.5));
        expect(coverContrast(bg, paper), greaterThanOrEqualTo(3));
        final heart = tester.widget<IconButton>(button('Quitar de favoritos'));
        expect(
          coverContrast(heart.style!.foregroundColor!.resolve({})!, paper),
          greaterThanOrEqualTo(3),
        );
      });
    }
  });

  group('jerarquía', () {
    testWidgets('normal: título en display, artista en cursiva más pequeño', (
      tester,
    ) async {
      await mount(tester);
      final title = style(tester, _plain.title);
      final artist = style(tester, _plain.artist);
      expect(title.fontFamily, _light.textTheme.titleLarge!.fontFamily);
      expect(title.fontSize, greaterThan(artist.fontSize!));
      expect(artist.fontStyle, FontStyle.italic);
      expect(
        tester.getTopLeft(text(_plain.title)).dy,
        lessThan(tester.getTopLeft(text(_plain.artist)).dy),
      );
    });

    testWidgets('sin pista no pinta nada', (tester) async {
      await mount(tester, state: _state(track: null));
      expect(find.byType(IconButton), findsNothing);
      expect(tester.getSize(find.byType(AtelierMiniPlayer)).height, 56);
    });
  });

  group('estados', () {
    testWidgets('sonando: pausa; en pausa: reproducir', (tester) async {
      await mount(tester, state: _state(playing: true));
      expect(button('Pausar'), findsOneWidget);
      expect(find.byIcon(StudioSymbols.pause), findsOneWidget);
      await mount(tester, state: _state(playing: false));
      expect(button('Reproducir'), findsOneWidget);
      expect(find.byIcon(StudioSymbols.playArrow), findsOneWidget);
    });

    testWidgets('buffering: anillo; con movimiento reducido, reloj quieto', (
      tester,
    ) async {
      await mount(tester, state: _state(buffering: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await mount(tester, state: _state(buffering: true), reduced: true);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(StudioSymbols.hourglassEmpty), findsOneWidget);
    });

    testWidgets('error: aviso en lugar del artista, con contraste', (
      tester,
    ) async {
      await mount(tester, state: _state(error: true));
      expect(text('No se pudo reproducir'), findsOneWidget);
      expect(text(_plain.artist), findsNothing);
      expect(
        coverContrast(
          style(tester, 'No se pudo reproducir').color!,
          _light.colorScheme.surfaceContainerLow,
        ),
        greaterThanOrEqualTo(4.5),
      );
      await mount(tester, dark: true, state: _state(error: true));
      expect(
        coverContrast(
          style(tester, 'No se pudo reproducir').color!,
          _dark.colorScheme.surfaceContainerLow,
        ),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('Jam sin permiso: play, siguiente y anterior desactivados', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        width: 900,
        state: _state(
          canTogglePlay: false,
          hasNext: false,
          hasPrevious: false,
          jamHost: 'Lucía',
        ),
      );
      expect(
        tester.widget<IconButton>(button('Lo controla Lucía')).onPressed,
        isNull,
      );
      expect(tester.widget<IconButton>(button('Siguiente')).onPressed, isNull);
      expect(tester.widget<IconButton>(button('Anterior')).onPressed, isNull);
    });

    testWidgets('favorito marcado usa corazón lleno', (tester) async {
      await mount(tester, state: _state(liked: true));
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      await mount(tester, state: _state(liked: false));
      expect(find.byIcon(Icons.favorite), findsNothing);
      expect(find.byIcon(StudioSymbols.favorite), findsOneWidget);
    });
  });

  group('vinilo', () {
    double turns(WidgetTester tester) => tester
        .widget<RotationTransition>(
          find.byWidgetPredicate(
            (w) => w is RotationTransition && w.turns is AnimationController,
          ),
        )
        .turns
        .value;

    testWidgets('gira solo con la pista sonando', (tester) async {
      await mount(tester, state: _state(playing: true));
      await tester.pump(const Duration(seconds: 2));
      expect(turns(tester), greaterThan(.1));
      await mount(tester, state: _state(playing: false));
      final rest = turns(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(turns(tester), rest);
    });

    testWidgets('no gira mientras carga ni con error', (tester) async {
      await mount(tester, state: _state(playing: true, buffering: true));
      await tester.pump(const Duration(seconds: 2));
      expect(turns(tester), 0);
      await mount(tester, state: _state(playing: true, error: true));
      await tester.pump(const Duration(seconds: 2));
      expect(turns(tester), 0);
    });

    testWidgets('con movimiento reducido no gira', (tester) async {
      await mount(tester, state: _state(playing: true), reduced: true);
      await tester.pump(const Duration(seconds: 2));
      expect(turns(tester), 0);
    });
  });

  group('gestos y botones', () {
    testWidgets('los botones llaman a su acción y no abren el reproductor', (
      tester,
    ) async {
      final calls = await mount(tester, wide: true, width: 900, gestures: true);
      await tester.tap(button('Reproducir'));
      await tester.tap(button('Siguiente'));
      await tester.tap(button('Anterior'));
      await tester.tap(button('Añadir a favoritos'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        [calls.play, calls.next, calls.previous, calls.like, calls.open],
        [1, 1, 1, 1, 0],
      );
    });

    testWidgets('tocar la barra abre el reproductor', (tester) async {
      final calls = await mount(tester, gestures: true);
      await tester.tap(text(_plain.title));
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.open, 1);
    });

    testWidgets('arrastrar arriba abre; a los lados salta de pista', (
      tester,
    ) async {
      final calls = await mount(tester, gestures: true);
      final bar = find.byType(AtelierMiniPlayer);
      await tester.fling(bar, const Offset(0, -120), 900);
      await tester.pumpAndSettle();
      expect(calls.open, 1);
      await tester.fling(bar, const Offset(-220, 0), 1200);
      await tester.pumpAndSettle();
      expect(calls.next, 1);
      await tester.fling(bar, const Offset(220, 0), 1200);
      await tester.pumpAndSettle();
      expect(calls.previous, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con movimiento reducido los mismos umbrales valen', (
      tester,
    ) async {
      final calls = await mount(tester, gestures: true, reduced: true);
      final bar = find.byType(AtelierMiniPlayer);
      await tester.fling(bar, const Offset(-220, 0), 1200);
      await tester.pumpAndSettle();
      await tester.fling(bar, const Offset(0, -120), 900);
      await tester.pumpAndSettle();
      expect((calls.next, calls.open), (1, 1));
    });
  });

  group('escritorio: controles y posición', () {
    testWidgets('el carril muestra volumen, cola, EQ y letras que actúan', (
      tester,
    ) async {
      final calls = await mount(
        tester,
        wide: true,
        width: 1440,
        state: _state(seek: true, queue: 3, eq: true, lyrics: true),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byTooltip('Silenciar'));
      await tester.tap(find.byTooltip('Abrir cola (3)'));
      await tester.tap(find.byTooltip('Ecualizador'));
      await tester.tap(find.byTooltip('Letras'));
      expect([calls.mute, calls.queue, calls.eq, calls.lyrics], [1, 1, 1, 1]);
    });

    testWidgets('el móvil no lleva controles de escritorio', (tester) async {
      await mount(tester, state: _state(queue: 3));
      expect(find.byTooltip('Silenciar'), findsNothing);
      expect(find.byType(Slider), findsNothing);
    });

    testWidgets('a 600 px los controles se pliegan sin desbordar', (
      tester,
    ) async {
      await mount(tester, wide: true, width: 600, scale: 2, state: _state());
      expect(tester.takeException(), isNull);
    });

    testWidgets('arrastrar la regla mueve la marca y confirma solo al soltar', (
      tester,
    ) async {
      final calls = await mount(
        tester,
        wide: true,
        width: 900,
        gestures: true,
        state: _state(seek: true),
      );
      final top = tester.getTopLeft(find.byType(AtelierMiniPlayer));
      final g = await tester.startGesture(top + const Offset(90, 6));
      await g.moveBy(const Offset(180, 0));
      await g.moveBy(const Offset(180, 0));
      await tester.pump();
      expect(calls.seeks, isEmpty);
      expect(calls.next + calls.previous, 0);
      await g.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(calls.seeks, hasLength(1));
      expect(calls.seeks.single, closeTo(.5, .02));
      expect(calls.next + calls.previous, 0);
    });

    testWidgets('tocar la regla salta a ese punto y anuncia «Posición»', (
      tester,
    ) async {
      final calls = await mount(
        tester,
        wide: true,
        width: 900,
        state: _state(seek: true),
      );
      // La tarjeta (760 px a 900) empieza en x = 70; un cuarto son 190 px.
      final top = tester.getTopLeft(find.byType(AtelierMiniPlayer));
      await tester.tapAt(top + const Offset(70 + 190, 6 + 6));
      expect(calls.seeks.single, closeTo(.25, .01));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Posición')),
        matchesSemantics(
          label: 'Posición',
          value: '40 %',
          increasedValue: '40 %',
          decreasedValue: '40 %',
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
    });

    testWidgets('sin permiso de posición la regla no responde', (tester) async {
      final calls = await mount(
        tester,
        wide: true,
        width: 900,
        state: _state(),
      );
      final top = tester.getTopLeft(find.byType(AtelierMiniPlayer));
      await tester.tapAt(top + const Offset(225, 6));
      expect(calls.seeks, isEmpty);
    });
  });

  group('anuncio y Jam en el subtítulo', () {
    const plain = Track(id: 's', title: 'Luz de luna', artist: 'Mare Sol');
    for (final scale in const [1.0, 2.0]) {
      final tag = '360 · ×${scale.toInt()}';
      Future<void> pump(WidgetTester tester, MiniPlayerState state) =>
          mount(tester, width: 360, scale: scale, state: state);

      testWidgets('anuncio · $tag', (tester) async {
        await pump(tester, _state(track: plain, ad: true, playing: true));
        expect(tester.takeException(), isNull);
        expect(text('Anuncio · tu canción sigue después'), findsOneWidget);
        expect(text('Mare Sol'), findsNothing);
      });

      testWidgets('Jam · $tag', (tester) async {
        await pump(tester, _state(track: plain, jam: true, playing: true));
        expect(tester.takeException(), isNull);
        expect(text('Mare Sol · Jam'), findsOneWidget);
      });
    }
  });
}
