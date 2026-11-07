import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/mini_player/cover_tone.dart' show coverContrast;
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/mini_player/modern_mini_player.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _track = Track(
  id: 'a',
  title: 'Noches de neón',
  artist: 'Aurora Boreal',
  duration: Duration(minutes: 3),
);

const _long = Track(
  id: 'l',
  title:
      'Una canción con un título larguísimo para comprobar el recorte limpio',
  artist: 'Un artista con un nombre igual de largo que el título anterior',
  duration: Duration(minutes: 3),
);

class _Calls {
  int open = 0, play = 0, next = 0, previous = 0, like = 0, shuffles = 0;
  int queue = 0, eq = 0, lyrics = 0, mute = 0;
  final volumes = <double>[];
  final seeks = <double>[];
  late final actions = MiniPlayerActions(
    openPlayer: () => open++,
    togglePlay: () => play++,
    next: () => next++,
    previous: () => previous++,
    toggleLike: () => like++,
    toggleShuffle: () => shuffles++,
    seek: seeks.add,
    setVolume: volumes.add,
    toggleMute: () => mute++,
    openQueue: () => queue++,
    openEqualizer: () => eq++,
    openLyrics: () => lyrics++,
  );
}

MiniPlayerState _state({
  Track? track = _track,
  bool playing = false,
  double progress = .4,
  bool buffering = false,
  bool error = false,
  bool liked = false,
  bool canTogglePlay = true,
  bool canSeek = true,
  bool hasNext = true,
  bool hasPrevious = true,
  String? jamHost,
  bool ad = false,
  bool jam = false,
  int queueLength = 3,
  bool eqAvailable = true,
  bool lyricsAvailable = true,
  bool shuffle = false,
  bool canShuffle = false,
}) => MiniPlayerState(
  track: track,
  isPlaying: playing,
  progress: progress,
  buffering: buffering,
  hasError: error,
  liked: liked,
  hasNext: hasNext,
  hasPrevious: hasPrevious,
  jamActive: jamHost != null,
  canTogglePlay: canTogglePlay,
  canSeek: canSeek,
  jamHostName: jamHost,
  adPlaying: ad,
  jamAudio: jam,
  queueLength: queueLength,
  equalizerAvailable: eqAvailable,
  lyricsAvailable: lyricsAvailable,
  shuffle: shuffle,
  canShuffle: canShuffle,
);

const _accents = [
  Color(0xffff5858),
  Color(0xff86e0c1),
  Color(0xfffedf89),
  Color(0xff151b31),
  Color(0xffffffff),
  Color(0xff000000),
];

void main() {
  setUpAll(() async {
    for (final font in {
      'Inter': 'assets/fonts/inter/Inter-Variable.ttf',
      'Bagel Fat One': 'assets/fonts/bagel_fat_one/BagelFatOne-Regular.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  Future<_Calls> mount(
    WidgetTester tester, {
    MiniPlayerState? state,
    double width = 390,
    double scale = 1,
    bool? wide,
    bool dark = false,
    bool reduced = false,
    Color accent = const Color(0xffff5858),
    _Calls? calls,
  }) async {
    final c = calls ?? _Calls();
    final isWide = wide ?? width >= 600;
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: modernTheme(dark ? Brightness.dark : Brightness.light, accent),
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
                  final s = state ?? _state();
                  return MiniPlayerGestures(
                    actions: c.actions,
                    hasNext: s.hasNext,
                    hasPrevious: s.hasPrevious,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MiniPlayerHost.heightFor(
                          context,
                          wide: isWide,
                        ),
                      ),
                      child: ModernMiniPlayer(
                        state: s,
                        actions: c.actions,
                        wide: isWide,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
    // El indicador de carga no deja de animar: un fotograma basta.
    if (state?.buffering ?? false) {
      await tester.pump(const Duration(milliseconds: 300));
    } else {
      await tester.pumpAndSettle();
    }
    return c;
  }

  Offset textSpot(WidgetTester tester, String text) =>
      tester.getCenter(find.text(text));

  Rect scrubRect(WidgetTester tester) => tester.getRect(
    find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Posición',
    ),
  );

  group('Aspecto y tamaño', () {
    testWidgets('sin pista no pinta nada', (tester) async {
      await mount(tester, state: _state(track: null));
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('Aurora Boreal'), findsNothing);
    });

    testWidgets(
      'móvil: tarjeta de 60 px con título, artista, corazón, play y siguiente',
      (tester) async {
        await mount(tester);
        expect(find.text('Noches de neón'), findsOneWidget);
        expect(find.text('Aurora Boreal'), findsOneWidget);
        expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
        expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
        // Desde 330 px interiores el móvil también muestra «siguiente».
        expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
        final card = tester.getSize(find.byType(ModernMiniPlayer));
        // 60 px de tarjeta + 4 y 8 de margen.
        expect(card.height, closeTo(72, .01));
        expect(card.width, 390);
        // Título arriba, artista debajo.
        expect(
          tester.getTopLeft(find.text('Noches de neón')).dy,
          lessThan(tester.getTopLeft(find.text('Aurora Boreal')).dy),
        );
      },
    );

    testWidgets('ancho: tarjeta centrada de 960 con anterior/siguiente', (
      tester,
    ) async {
      await mount(tester, width: 1440);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      final play = tester.getCenter(find.byIcon(Icons.play_arrow_rounded));
      expect(
        tester.getSize(find.byType(ModernMiniPlayer)).width,
        1440,
        reason: 'ocupa el ancho; la tarjeta se centra dentro',
      );
      final scrub = scrubRect(tester);
      expect(scrub.width, closeTo(960 - 28, 1));
      expect(scrub.center.dx, closeTo(720, 1));
      expect(play.dx, greaterThan(720));
    });

    for (final width in [360.0, 412.0, 600.0, 900.0, 1440.0, 1920.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          testWidgets(
            'sin desbordes ni toques < 44: ${width.toInt()} px x$scale '
            '${dark ? 'oscuro' : 'claro'}',
            (tester) async {
              await mount(
                tester,
                state: _state(track: _long, error: scale == 2, liked: dark),
                width: width,
                scale: scale,
                dark: dark,
              );
              expect(tester.takeException(), isNull);
              for (final element in find.byType(IconButton).evaluate()) {
                final size = element.size!;
                expect(size.width, greaterThanOrEqualTo(44));
                expect(size.height, greaterThanOrEqualTo(44));
              }
              // Cabe en el ancho.
              expect(
                tester.getRect(find.byType(ModernMiniPlayer)).right,
                lessThanOrEqualTo(width),
              );
            },
          );
        }
      }
    }
  });

  group('Estados', () {
    testWidgets('reproduciendo muestra pausa; pausado, play', (tester) async {
      await mount(tester, state: _state(playing: true));
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      await mount(tester, state: _state(playing: false));
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('cargando: indicador en lugar del icono, sigue pulsable', (
      tester,
    ) async {
      final calls = await mount(tester, state: _state(buffering: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
      await tester.tap(find.byTooltip('Cargando'));
      expect(calls.play, 1);
    });

    testWidgets('error: aviso con contraste y sin romper la barra', (
      tester,
    ) async {
      await mount(tester, state: _state(error: true));
      expect(find.text('No se pudo reproducir'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.text('Aurora Boreal'), findsNothing);
    });

    testWidgets('Jam sin permiso: play desactivado y quién controla', (
      tester,
    ) async {
      final calls = await mount(
        tester,
        state: _state(canTogglePlay: false, jamHost: 'Marta'),
      );
      expect(find.text('Lo controla Marta'), findsOneWidget);
      await tester.tap(find.byTooltip('Reproducir'), warnIfMissed: false);
      expect(calls.play, 0);
    });

    testWidgets('corazón lleno cuando es favorito', (tester) async {
      await mount(tester, state: _state(liked: true));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byTooltip('Quitar de favoritos'), findsOneWidget);
    });
  });

  group('Acciones y gestos', () {
    testWidgets('play y corazón llaman a sus acciones sin abrir', (
      tester,
    ) async {
      final calls = await mount(tester);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.tap(find.byTooltip('Añadir a favoritos'));
      expect((calls.play, calls.like, calls.open), (1, 1, 0));
    });

    testWidgets('ancho: anterior y siguiente', (tester) async {
      final calls = await mount(tester, width: 900);
      await tester.tap(find.byTooltip('Siguiente'));
      await tester.tap(find.byTooltip('Anterior'));
      expect((calls.next, calls.previous), (1, 1));
    });

    testWidgets('ancho: aleatorio solo con canShuffle; móvil sin botón', (
      tester,
    ) async {
      var calls = await mount(
        tester,
        width: 900,
        state: _state(canShuffle: true),
      );
      expect(find.byTooltip('Aleatorio'), findsOneWidget);
      await tester.tap(find.byTooltip('Aleatorio'));
      expect(calls.shuffles, 1);
      calls = await mount(tester, width: 900, state: _state());
      await tester.tap(find.byTooltip('Aleatorio'), warnIfMissed: false);
      expect(calls.shuffles, 0);
      await mount(tester, state: _state(canShuffle: true));
      expect(find.byTooltip('Aleatorio'), findsNothing);
    });

    testWidgets('ancho: sin siguiente el botón queda desactivado', (
      tester,
    ) async {
      final calls = await mount(
        tester,
        width: 900,
        state: _state(hasNext: false),
      );
      await tester.tap(find.byTooltip('Siguiente'), warnIfMissed: false);
      expect(calls.next, 0);
    });

    testWidgets('ancho: controles de escritorio y acciones', (tester) async {
      final calls = await mount(tester, width: 1440);
      expect(find.byType(MiniPlayerDesktopControls), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byTooltip('Silenciar'));
      await tester.tap(find.byTooltip('Abrir cola (3)'));
      await tester.tap(find.byTooltip('Ecualizador'));
      await tester.tap(find.byTooltip('Letras'));
      await tester.tap(find.byType(Slider));
      expect(
        (calls.mute, calls.queue, calls.eq, calls.lyrics, calls.open),
        (1, 1, 1, 1, 0),
      );
      expect(calls.volumes, hasLength(1));
      // La tarjeta crece a 960 px en >= 1100.
      expect(scrubRect(tester).width, closeTo(960 - 28, 1));
    });

    testWidgets('600 y 900: tarjeta < 640 sin slider, 900 de 760 con él', (
      tester,
    ) async {
      await mount(tester, width: 600);
      expect(find.byType(MiniPlayerDesktopControls), findsOneWidget);
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Silenciar'), findsOneWidget);
      await mount(tester, width: 900);
      expect(find.byType(Slider), findsOneWidget);
      expect(scrubRect(tester).width, closeTo(760 - 28, 1));
    });

    testWidgets('móvil: sin controles de escritorio', (tester) async {
      await mount(tester);
      expect(find.byType(MiniPlayerDesktopControls), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byTooltip('Silenciar'), findsNothing);
    });

    testWidgets('ancho: sin EQ ni letras se desactivan', (tester) async {
      final calls = await mount(
        tester,
        width: 1440,
        state: _state(eqAvailable: false, lyricsAvailable: false),
      );
      await tester.tap(find.byTooltip('Letras'), warnIfMissed: false);
      await tester.tap(
        find.byTooltip('Ecualizador no disponible en este reproductor'),
        warnIfMissed: false,
      );
      expect((calls.eq, calls.lyrics), (0, 0));
    });

    testWidgets('tocar la tarjeta abre el reproductor', (tester) async {
      final calls = await mount(tester);
      await tester.tapAt(textSpot(tester, 'Noches de neón'));
      expect(calls.open, 1);
    });

    testWidgets('arrastrar arriba abre; a los lados cambia de pista', (
      tester,
    ) async {
      final calls = await mount(tester);
      final spot = textSpot(tester, 'Noches de neón');
      await tester.dragFrom(spot, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect(calls.open, 1);
      await tester.dragFrom(spot, const Offset(-110, 0));
      await tester.pumpAndSettle();
      expect((calls.next, calls.previous), (1, 0));
      await tester.dragFrom(spot, const Offset(110, 0));
      await tester.pumpAndSettle();
      expect((calls.next, calls.previous), (1, 1));
    });

    testWidgets('movimiento reducido: mismos umbrales', (tester) async {
      final calls = await mount(tester, reduced: true);
      final spot = textSpot(tester, 'Noches de neón');
      await tester.dragFrom(spot, const Offset(-30, 0));
      await tester.pumpAndSettle();
      expect((calls.next, calls.previous), (0, 0));
      await tester.dragFrom(spot, const Offset(-110, 0));
      await tester.dragFrom(spot, const Offset(0, -80));
      await tester.pumpAndSettle();
      expect((calls.next, calls.open), (1, 1));
      expect(tester.takeException(), isNull);
    });
  });

  group('Progreso', () {
    testWidgets('tocar la línea busca sin abrir', (tester) async {
      final calls = await mount(tester);
      final r = scrubRect(tester);
      await tester.tapAt(Offset(r.left + r.width * .75, r.center.dy));
      expect(calls.seeks, hasLength(1));
      expect(calls.seeks.single, closeTo(.75, .02));
      expect(calls.open, 0);
    });

    testWidgets(
      'con el ratón encima la zona crece a 24 px y la línea engorda',
      (tester) async {
        final calls = await mount(tester);
        expect(scrubRect(tester).height, 10);
        double grow() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .where((p) => p.runtimeType.toString() == '_LinePainter')
            .map((p) => (p! as dynamic).grow as double)
            .single;
        expect(grow(), 0);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(
          Offset(scrubRect(tester).center.dx, scrubRect(tester).bottom - 5),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final r = scrubRect(tester);
        expect(r.height, 24);
        expect(grow(), 1);
        // La línea está a 5 px del borde inferior: 12 px por encima ya es zona.
        await tester.tapAt(Offset(r.left + r.width * .5, r.bottom - 5 - 12));
        expect(calls.seeks, hasLength(1));
        expect(calls.open, 0);

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(scrubRect(tester).height, 10);
        expect(grow(), 0);
      },
    );

    testWidgets('arrastrar la línea confirma al soltar y no cambia de pista', (
      tester,
    ) async {
      final calls = await mount(tester);
      final r = scrubRect(tester);
      final gesture = await tester.startGesture(
        Offset(r.left + r.width * .2, r.center.dy),
      );
      await gesture.moveBy(Offset(r.width * .1, 0));
      await gesture.moveBy(Offset(r.width * .2, 0));
      await tester.pump();
      expect(calls.seeks, isEmpty, reason: 'solo al soltar');
      await gesture.up();
      await tester.pumpAndSettle();
      expect(calls.seeks, hasLength(1));
      expect(calls.seeks.single, closeTo(.5, .03));
      expect((calls.next, calls.previous), (0, 0));
    });

    testWidgets('sin permiso de búsqueda es solo visual', (tester) async {
      final calls = await mount(tester, state: _state(canSeek: false));
      final r = scrubRect(tester);
      await tester.tapAt(Offset(r.left + r.width * .75, r.center.dy));
      expect(calls.seeks, isEmpty);
    });

    testWidgets('semántica de posición con acciones de ajuste', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = await mount(tester, state: _state(progress: .4));
      final node = tester.getSemantics(find.bySemanticsLabel('Posición'));
      expect(node.value, '40 %');
      tester.semantics.increase(find.semantics.byLabel('Posición'));
      expect(calls.seeks.single, closeTo(.45, .001));
      handle.dispose();
    });
  });

  group('Contraste', () {
    double ratio(Color a, Color b) => coverContrast(a, b);

    for (final dark in [false, true]) {
      for (final accent in _accents) {
        testWidgets('tarjeta normal ${dark ? 'oscura' : 'clara'} con acento '
            '#${accent.toARGB32().toRadixString(16)}', (tester) async {
          await mount(tester, dark: dark, accent: accent);
          final context = tester.element(find.byType(ModernMiniPlayer));
          final scheme = Theme.of(context).colorScheme;
          final card = tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(ModernMiniPlayer),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .map((d) => d.decoration)
              .whereType<BoxDecoration>()
              .firstWhere((d) => d.boxShadow != null && d.color != null)
              .color!;
          Color ink(String text) =>
              tester.widget<Text>(find.text(text)).style!.color!;
          expect(ratio(ink('Noches de neón'), card), greaterThanOrEqualTo(4.5));
          expect(ratio(ink('Aurora Boreal'), card), greaterThanOrEqualTo(4.5));
          final play = tester
              .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.play_arrow_rounded),
              )
              .style!;
          final fill = play.backgroundColor!.resolve({})!;
          expect(ratio(fill, card), greaterThanOrEqualTo(3));
          expect(
            ratio(play.foregroundColor!.resolve({})!, fill),
            greaterThanOrEqualTo(4.5),
          );
          final line = tester.widget<CustomPaint>(
            find.descendant(
              of: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == 'Posición',
              ),
              matching: find.byType(CustomPaint),
            ),
          );
          expect(
            ratio((line.painter! as dynamic).color as Color, card),
            greaterThanOrEqualTo(3),
          );
          // Corazón de contorno (onSurfaceVariant) como control: >= 3.
          expect(ratio(scheme.onSurfaceVariant, card), greaterThanOrEqualTo(3));
        });
      }
    }

    for (final dark in [false, true]) {
      testWidgets('controles de escritorio con contraste >= 3 '
          '${dark ? 'oscuro' : 'claro'}', (tester) async {
        await mount(tester, width: 1440, dark: dark);
        final context = tester.element(find.byType(ModernMiniPlayer));
        final card = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(ModernMiniPlayer),
                matching: find.byType(DecoratedBox),
              ),
            )
            .map((d) => d.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.boxShadow != null && d.color != null)
            .color!;
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byTooltip('Letras'),
            matching: find.byType(Icon),
          ),
        );
        expect(icon.color, Theme.of(context).colorScheme.onSurfaceVariant);
        expect(ratio(icon.color!, card), greaterThanOrEqualTo(3));
      });
    }
  });

  group('Registro en el host', () {
    test('Modern está registrado', () {
      expect(miniPlayerThemes['modern'], same(modernMiniPlayer));
    });

    testWidgets('el host lo oculta sin pista y lo pinta con pista', (
      tester,
    ) async {
      final controller = (await tester.runAsync(
        () => createTestController(
          tracks: [_track],
          preferences: {'themeKind': 'modern'},
        ),
      ))!;
      addTearDown(() => closeTestController(controller));
      Future<void> host() async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: modernTheme(Brightness.light, const Color(0xffff5858)),
            home: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox()),
                  MiniPlayerHost(
                    controller: controller,
                    section: 0,
                    rail: false,
                    placement: MiniPlayerPlacement.body,
                    onOpenPlayer: () {},
                    onTogglePlay: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      controller.queue = [];
      controller.queueIndex = -1;
      await host();
      expect(find.byType(ModernMiniPlayer), findsNothing);
      controller.queue = [_track];
      controller.queueIndex = 0;
      await host();
      expect(find.byType(ModernMiniPlayer), findsOneWidget);
      expect(find.text('Aurora Boreal'), findsOneWidget);
    });
  });

  group('anuncio y Jam en el subtítulo', () {
    for (final scale in const [1.0, 2.0]) {
      final tag = '360 · ×${scale.toInt()}';
      Future<void> pump(WidgetTester tester, MiniPlayerState state) =>
          mount(tester, width: 360, scale: scale, state: state);

      testWidgets('anuncio · $tag', (tester) async {
        await pump(tester, _state(ad: true, playing: true));
        expect(tester.takeException(), isNull);
        expect(find.text('Anuncio · tu canción sigue después'), findsOneWidget);
        expect(find.text('Aurora Boreal'), findsNothing);
      });

      testWidgets('Jam · $tag', (tester) async {
        await pump(tester, _state(jam: true, playing: true));
        expect(tester.takeException(), isNull);
        expect(find.text('Aurora Boreal · Jam'), findsOneWidget);
      });
    }
  });
}
