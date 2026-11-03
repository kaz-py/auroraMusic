import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/modern_theme.dart';
import 'package:aurora_music/ui/mini_player/blurred_cover_backdrop.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/mini_player/modern_mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

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
  int open = 0, play = 0, next = 0, previous = 0, like = 0;
  final seeks = <double>[];
  late final actions = MiniPlayerActions(
    openPlayer: () => open++,
    togglePlay: () => play++,
    next: () => next++,
    previous: () => previous++,
    toggleLike: () => like++,
    seek: seeks.add,
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
);

class _Covers implements CoverBackdropSource {
  _Covers(this.image, this.color);
  final ui.Image image;
  final Color color;

  CoverBackdropData get data =>
      CoverBackdropData(image: image, samples: List.filled(64, color));

  @override
  String? keyOf(Track track) => track.id;

  @override
  CoverBackdropData? peek(Track track) => data;

  @override
  Future<CoverBackdropData?> load(Track track) => Future.value(data);
}

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
    bool blurred = false,
    bool? wide,
    bool dark = false,
    bool reduced = false,
    Color accent = const Color(0xffff5858),
    CoverBackdropSource? source,
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
                        blurred: blurred,
                        wide: isWide,
                        source: source,
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

    testWidgets('móvil: tarjeta de 60 px con título, artista, corazón y play', (
      tester,
    ) async {
      await mount(tester);
      expect(find.text('Noches de neón'), findsOneWidget);
      expect(find.text('Aurora Boreal'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
      final card = tester.getSize(find.byType(ModernMiniPlayer));
      // 60 px de tarjeta + 4 y 8 de margen.
      expect(card.height, closeTo(72, .01));
      expect(card.width, 390);
      // Título arriba, artista debajo.
      expect(
        tester.getTopLeft(find.text('Noches de neón')).dy,
        lessThan(tester.getTopLeft(find.text('Aurora Boreal')).dy),
      );
    });

    testWidgets('ancho: tarjeta centrada de 760 con anterior/siguiente', (
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
      expect(scrub.width, closeTo(760 - 28, 1));
      expect(scrub.center.dx, closeTo(720, 1));
      expect(play.dx, greaterThan(720));
    });

    for (final width in [360.0, 412.0, 600.0, 900.0, 1440.0]) {
      for (final scale in [1.0, 2.0]) {
        for (final dark in [false, true]) {
          for (final blurred in [false, true]) {
            testWidgets(
              'sin desbordes ni toques < 44: ${width.toInt()} px x$scale '
              '${dark ? 'oscuro' : 'claro'}${blurred ? ' difuminado' : ''}',
              (tester) async {
                final image = (await tester.runAsync(
                  () => decodeImageFromList(base64Decode(_png)),
                ))!;
                await mount(
                  tester,
                  state: _state(track: _long, error: scale == 2, liked: dark),
                  width: width,
                  scale: scale,
                  dark: dark,
                  blurred: blurred,
                  source: _Covers(image, dark ? Colors.black : Colors.white),
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

    for (final (name, cover) in [
      ('blanca', Colors.white),
      ('negra', Colors.black),
    ]) {
      testWidgets('difuminado sobre portada $name: artista grande y legible', (
        tester,
      ) async {
        final image = (await tester.runAsync(
          () => decodeImageFromList(base64Decode(_png)),
        ))!;
        final covers = _Covers(image, cover);
        await mount(tester, blurred: true, source: covers);
        expect(find.byType(RawImage), findsWidgets);
        final tone = covers.data.adaptiveTone;
        final bg = Color.alphaBlend(tone.scrim, cover);
        final artist = tester.widget<Text>(find.text('Aurora Boreal'));
        final title = tester.widget<Text>(find.text('Noches de neón'));
        expect(artist.style!.color, tone.foreground);
        expect(title.style!.color, tone.secondary);
        expect(ratio(artist.style!.color!, bg), greaterThanOrEqualTo(4.5));
        expect(ratio(title.style!.color!, bg), greaterThanOrEqualTo(4.5));
        // El artista manda: más grande, semi-negrita y arriba.
        expect(artist.style!.fontSize, greaterThan(title.style!.fontSize!));
        expect(artist.style!.fontWeight, FontWeight.w600);
        expect(artist.style!.letterSpacing, lessThan(0));
        expect(
          tester.getTopLeft(find.text('Aurora Boreal')).dy,
          lessThan(tester.getTopLeft(find.text('Noches de neón')).dy),
        );
      });
    }

    testWidgets('difuminado activo pero portada sin cargar: aspecto normal', (
      tester,
    ) async {
      await mount(tester, blurred: true, source: _Never());
      expect(find.byType(RawImage), findsNothing);
      expect(tester.takeException(), isNull);
      final artist = tester.widget<Text>(find.text('Aurora Boreal'));
      final scheme = Theme.of(
        tester.element(find.byType(ModernMiniPlayer)),
      ).colorScheme;
      expect(artist.style!.color, scheme.onSurface);
    });
  });

  group('Registro en el host', () {
    test('Modern ya no es legacy', () {
      expect(miniPlayerThemes['modern']!.legacy, isFalse);
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
}

class _Never implements CoverBackdropSource {
  final _c = Completer<CoverBackdropData?>();
  @override
  String? keyOf(Track track) => track.id;
  @override
  CoverBackdropData? peek(Track track) => null;
  @override
  Future<CoverBackdropData?> load(Track track) => _c.future;
}
