import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/accent_transition.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/ui/mini_player/slush_mini_player_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _track = Track(
  id: 'a',
  title: 'Una canción con un título larguísimo para comprobar el recorte',
  artist: 'Un artista con un nombre igual de largo que el título anterior',
  duration: Duration(minutes: 3),
);

const _short = Track(id: 'b', title: 'Luz de luna', artist: 'Mare Sol');

MiniPlayerState _state({
  Track? track = _short,
  bool isPlaying = false,
  double progress = .4,
  bool buffering = false,
  bool hasError = false,
  bool liked = false,
  bool hasNext = true,
  bool hasPrevious = true,
  bool canTogglePlay = true,
  String? jamHostName,
  bool ad = false,
  bool jam = false,
  bool canSeek = false,
  double volume = .75,
  int queueLength = 3,
  bool equalizerAvailable = true,
  bool equalizerActive = false,
  bool lyricsAvailable = true,
}) => MiniPlayerState(
  track: track,
  isPlaying: isPlaying,
  progress: progress,
  buffering: buffering,
  hasError: hasError,
  liked: liked,
  hasNext: hasNext,
  hasPrevious: hasPrevious,
  jamActive: false,
  canTogglePlay: canTogglePlay,
  jamHostName: jamHostName,
  adPlaying: ad,
  jamAudio: jam,
  canSeek: canSeek,
  volume: volume,
  queueLength: queueLength,
  equalizerAvailable: equalizerAvailable,
  equalizerActive: equalizerActive,
  lyricsAvailable: lyricsAvailable,
);

class _Calls {
  final log = <String>[];
  int count(String name) => log.where((e) => e == name).length;
  MiniPlayerActions get actions => MiniPlayerActions(
    openPlayer: () => log.add('open'),
    togglePlay: () => log.add('toggle'),
    next: () => log.add('next'),
    previous: () => log.add('previous'),
    toggleLike: () => log.add('like'),
    seek: (v) => log.add('seek:${v.toStringAsFixed(2)}'),
    setVolume: (v) => log.add('volume:${v.toStringAsFixed(2)}'),
    toggleMute: () => log.add('mute'),
    openQueue: () => log.add('queue'),
    openEqualizer: () => log.add('eq'),
    openLyrics: () => log.add('lyrics'),
  );
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

Color fillBehind(WidgetTester tester, Finder child) => tester
    .widgetList<DecoratedBox>(
      find.ancestor(of: child, matching: find.byType(DecoratedBox)),
    )
    .map((d) => d.decoration)
    .whereType<ShapeDecoration>()
    .map((d) => d.color)
    .whereType<Color>()
    .first;

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

  late _Calls calls;
  setUp(() => calls = _Calls());

  /// Monta el mini como lo hace el host: con los gestos compartidos y la
  /// altura mínima, en una columna con la barra inferior de Slush a los
  /// márgenes de 12 px.
  Future<void> mount(
    WidgetTester tester, {
    MiniPlayerState? state,
    bool wide = false,
    Size size = const Size(390, 800),
    double scale = 1,
    Brightness brightness = Brightness.light,
    Color accent = const Color(0xff00aa55),
    bool reduce = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = state ?? _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: slushTheme(brightness, accent),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
            disableAnimations: reduce,
          ),
          child: AccentScope(
            accent: accent,
            child: Scaffold(
              body: Column(
                children: [
                  const Expanded(child: SizedBox(width: double.infinity)),
                  Padding(
                    padding: wide
                        ? EdgeInsets.zero
                        : const EdgeInsets.symmetric(horizontal: 12),
                    child: MiniPlayerGestures(
                      actions: calls.actions,
                      hasNext: s.hasNext,
                      hasPrevious: s.hasPrevious,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: (wide ? 64.0 : 56.0) * scale.clamp(1, 1.5),
                        ),
                        child: SlushMiniPlayer(
                          state: s,
                          actions: calls.actions,
                          wide: wide,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder pill() => find.byType(SlushMiniPlayer);

  group('registro', () {
    test('Slush está registrado', () {
      expect(miniPlayerThemes['slush'], same(slushMiniPlayerV2));
    });

    test('el color vivo sale del tono del acento', () {
      expect(slushVividFor(const Color(0xff00aa55)), Slush.mint);
      expect(slushVividFor(const Color(0xffddbb00)), Slush.yellow);
      expect(slushVividFor(const Color(0xff7755dd)), Slush.lilac);
      expect(slushVividFor(const Color(0xffee3300)), Slush.orange);
      expect(slushVividFor(const Color(0xffff0033)), Slush.orange);
      expect(slushVividFor(const Color(0xff808080)), Slush.lilac);
    });
  });

  group('host con el registro real', () {
    late AppController controller;

    Future<void> mountHost(
      WidgetTester tester, {
      required int section,
      required bool rail,
      required MiniPlayerPlacement placement,
      bool track = true,
    }) async {
      tester.view.physicalSize = rail
          ? const Size(1300, 800)
          : const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      controller.queue = track ? [_short] : [];
      controller.queueIndex = track ? 0 : -1;
      await tester.pumpWidget(
        MaterialApp(
          theme: slushTheme(Brightness.light, Colors.teal),
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox(width: double.infinity)),
                MiniPlayerHost(
                  controller: controller,
                  section: section,
                  rail: rail,
                  placement: placement,
                  onOpenPlayer: () => calls.log.add('open'),
                  onTogglePlay: () => calls.log.add('toggle'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> setup(WidgetTester tester) async {
      controller = (await tester.runAsync(
        () => createTestController(tracks: [_short]),
      ))!;
      addTearDown(() => closeTestController(controller));
    }

    testWidgets('móvil: solo en la barra inferior; oculto sin pista y en 4', (
      tester,
    ) async {
      await setup(tester);
      await mountHost(
        tester,
        section: 0,
        rail: false,
        placement: MiniPlayerPlacement.bottomBar,
      );
      expect(pill(), findsOneWidget);
      await mountHost(
        tester,
        section: 0,
        rail: false,
        placement: MiniPlayerPlacement.body,
      );
      expect(pill(), findsNothing);
      await mountHost(
        tester,
        section: 4,
        rail: false,
        placement: MiniPlayerPlacement.bottomBar,
      );
      expect(pill(), findsNothing);
      await mountHost(
        tester,
        section: 0,
        rail: false,
        placement: MiniPlayerPlacement.bottomBar,
        track: false,
      );
      expect(pill(), findsNothing);
    });

    testWidgets(
      'con carril: dock en el cuerpo, centrado y de 920 como máximo (1300 px)',
      (tester) async {
        await setup(tester);
        await mountHost(
          tester,
          section: 0,
          rail: true,
          placement: MiniPlayerPlacement.body,
        );
        final rect = tester.getRect(pill());
        expect(rect.width, lessThanOrEqualTo(kSlushMiniMaxWidthLarge + 64));
        expect(rect.center.dx, closeTo(650, 1));
        // Todo el dock es la zona de gestos: no hay franjas muertas que abran.
        await tester.tapAt(const Offset(20, 790));
        expect(calls.count('open'), 0);
        // Con carril el clic abre el menú de la canción; el Vinilo es una
        // entrada del menú.
        await tester.tap(find.text('Luz de luna'));
        await tester.pumpAndSettle();
        expect(calls.count('open'), 0);
        expect(find.text('Compartir'), findsOneWidget);
        await tester.tap(find.text('Abrir Modo Vinilo'));
        await tester.pumpAndSettle();
        expect(calls.count('open'), 1);
      },
    );
  });

  group('maquetación', () {
    final sizes = <(Size, double, bool)>[
      (const Size(360, 640), 1, false),
      (const Size(412, 800), 1, false),
      (const Size(600, 800), 1, true),
      (const Size(900, 800), 1, true),
      (const Size(1440, 900), 1, true),
      (const Size(360, 640), 2, false),
      (const Size(412, 800), 2, false),
      (const Size(900, 800), 2, true),
      (const Size(600, 800), 2, true),
      (const Size(1920, 1080), 1, true),
      (const Size(1920, 1080), 2, true),
    ];
    for (final (size, scale, wide) in sizes) {
      for (final dark in [false, true]) {
        testWidgets('${size.width.toInt()} px, texto ×$scale, '
            '${dark ? 'oscuro' : 'claro'}: sin desborde y táctil ≥ 44', (
          tester,
        ) async {
          await mount(
            tester,
            state: _state(track: _track, isPlaying: true, liked: true),
            size: size,
            scale: scale,
            wide: wide,
            brightness: dark ? Brightness.dark : Brightness.light,
          );
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(pill());
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(rect.height, greaterThanOrEqualTo(56 * scale.clamp(1, 1.5)));
          if (wide) {
            expect(
              rect.width,
              lessThanOrEqualTo(slushMiniMaxWidthFor(size.width) + 64),
            );
          }
          for (final tip in [
            'Pausar',
            'Quitar de favoritos',
            if (wide) 'Anterior',
            if (wide || size.width >= 412) 'Siguiente',
          ]) {
            final box = tester.getSize(find.byTooltip(tip));
            expect(box.shortestSide, greaterThanOrEqualTo(44), reason: tip);
          }
          if (!wide && size.width < 412) {
            expect(find.byTooltip('Siguiente'), findsNothing);
          }
        });
      }
    }

    testWidgets('el dock ancho no pasa de 920 px de pastilla (720 bajo 1100)', (
      tester,
    ) async {
      await mount(
        tester,
        size: const Size(1440, 900),
        wide: true,
        state: _state(track: _track),
      );
      final rect = tester.getRect(pill());
      expect(rect.center.dx, closeTo(720, 1));
      expect(rect.width, lessThanOrEqualTo(kSlushMiniMaxWidthLarge + 2 * 32));
      // Los gestos cubren el dock y nada más.
      final gestures = tester.getRect(find.byType(MiniPlayerGestures));
      expect(
        gestures.width,
        lessThanOrEqualTo(kSlushMiniMaxWidthLarge + 2 * 32),
      );
    });
  });

  group('estados', () {
    testWidgets('reproduciendo / en pausa cambian icono y tooltip', (
      tester,
    ) async {
      await mount(tester, state: _state(isPlaying: true));
      expect(find.byTooltip('Pausar'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await mount(tester, state: _state());
      expect(find.byTooltip('Reproducir'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('buffering: spinner en el play (y estático con movimiento '
        'reducido)', (tester) async {
      await mount(tester, state: _state(buffering: true), settle: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(
        tester,
        state: _state(buffering: true),
        reduce: true,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.more_horiz_rounded), findsOneWidget);
    });

    testWidgets('error: avisa en lugar del artista y el play sigue activo', (
      tester,
    ) async {
      await mount(tester, state: _state(hasError: true));
      expect(find.text('No se pudo reproducir'), findsOneWidget);
      expect(find.text('Mare Sol'), findsNothing);
      await tester.tap(find.byTooltip('Reproducir'));
      expect(calls.count('toggle'), 1);
    });

    testWidgets('favorito: icono lleno y rosa cuando es favorito', (
      tester,
    ) async {
      await mount(tester, state: _state());
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await mount(tester, state: _state(liked: true));
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      final fill = tester
          .widgetList<DecoratedBox>(
            find.ancestor(
              of: find.byIcon(Icons.favorite_rounded),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<ShapeDecoration>()
          .map((d) => d.color)
          .whereType<Color>()
          .first;
      expect(fill, Slush.pink);
    });

    testWidgets('Jam sin permiso: play desactivado y avisa quién controla', (
      tester,
    ) async {
      await mount(
        tester,
        state: _state(canTogglePlay: false, jamHostName: 'Marta'),
      );
      await tester.tap(find.byTooltip('Lo controla Marta'));
      expect(calls.count('toggle'), 0);
    });

    testWidgets('sin siguiente / anterior sus botones no actúan', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        size: const Size(900, 800),
        state: _state(hasNext: false, hasPrevious: false),
      );
      await tester.tap(find.byTooltip('Siguiente'));
      await tester.tap(find.byTooltip('Anterior'));
      expect(calls.count('next') + calls.count('previous'), 0);
    });

    testWidgets(
      'la barra de progreso se anuncia y no desborda al 0 ni al 100',
      (tester) async {
        for (final p in [0.0, 1.0]) {
          await mount(tester, state: _state(progress: p));
          expect(tester.takeException(), isNull);
          expect(
            find.bySemanticsLabel('Progreso'),
            findsOneWidget,
            reason: 'progreso $p',
          );
        }
      },
    );
  });

  group('acciones y gestos', () {
    testWidgets('botones: play, favorito, siguiente y anterior', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        size: const Size(900, 800),
        state: _state(),
      );
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.tap(find.byTooltip('Guardar en favoritos'));
      await tester.tap(find.byTooltip('Siguiente'));
      await tester.tap(find.byTooltip('Anterior'));
      expect(calls.log, ['toggle', 'like', 'next', 'previous']);
    });

    testWidgets('tocar la barra abre; los botones no abren', (tester) async {
      await mount(tester);
      await tester.tap(find.text('Luz de luna'));
      expect(calls.log, ['open']);
      await tester.tap(find.byTooltip('Reproducir'));
      expect(calls.log, ['open', 'toggle']);
    });

    testWidgets('deslizar a los lados salta de pista y arriba abre', (
      tester,
    ) async {
      await mount(tester);
      await tester.fling(pill(), const Offset(-200, 0), 1200);
      await tester.pumpAndSettle();
      await tester.fling(pill(), const Offset(200, 0), 1200);
      await tester.pumpAndSettle();
      await tester.fling(pill(), const Offset(0, -120), 1200);
      await tester.pumpAndSettle();
      expect(calls.log, ['next', 'previous', 'open']);
    });

    testWidgets('con movimiento reducido los umbrales son los mismos', (
      tester,
    ) async {
      await mount(tester, reduce: true);
      await tester.fling(pill(), const Offset(-200, 0), 1200);
      await tester.pumpAndSettle();
      expect(calls.log, ['next']);
    });
  });

  group('escritorio', () {
    testWidgets('móvil: sin controles de escritorio', (tester) async {
      await mount(tester, state: _state());
      expect(find.byType(MiniPlayerDesktopControls), findsNothing);
      expect(find.byTooltip('Abrir cola (3)'), findsNothing);
    });

    testWidgets('ancho 1440: volumen, cola, EQ y letras actúan', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        size: const Size(1440, 900),
        state: _state(equalizerActive: true),
      );
      expect(find.byType(MiniPlayerDesktopControls), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      await tester.tap(find.byTooltip('Silenciar'));
      await tester.tap(find.byTooltip('Abrir cola (3)'));
      await tester.tap(find.byTooltip('Ecualizador (activo)'));
      await tester.tap(find.byTooltip('Letras'));
      await tester.tap(find.byType(Slider));
      expect(calls.count('mute'), 1);
      expect(calls.count('queue'), 1);
      expect(calls.count('eq'), 1);
      expect(calls.count('lyrics'), 1);
      expect(calls.log.where((e) => e.startsWith('volume:')), hasLength(1));
      // Ningún botón de escritorio abre el reproductor.
      expect(calls.count('open'), 0);
    });

    testWidgets('600 px: los controles se pliegan en el menú «⋯»', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        size: const Size(600, 800),
        state: _state(),
      );
      expect(find.byType(Slider), findsNothing);
      await tester.tap(find.byTooltip('Más acciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abrir cola (3)'));
      await tester.pumpAndSettle();
      expect(calls.count('queue'), 1);
    });

    for (final (size, scale) in [
      (const Size(600, 800), 2.0),
      (const Size(900, 800), 2.0),
      (const Size(1440, 900), 2.0),
      (const Size(1920, 1080), 2.0),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('${size.width.toInt()} px ×$scale '
            '${dark ? 'oscuro' : 'claro'}: sin desborde, controles ≥ 44 y '
            'contraste ≥ 3', (tester) async {
          await mount(
            tester,
            wide: true,
            size: size,
            scale: scale,
            brightness: dark ? Brightness.dark : Brightness.light,
            state: _state(track: _track, canSeek: true, equalizerActive: true),
          );
          expect(tester.takeException(), isNull);
          final rect = tester.getRect(pill());
          expect(rect.right, lessThanOrEqualTo(size.width));
          final controls = tester.getRect(
            find.byType(MiniPlayerDesktopControls),
          );
          expect(controls.right, lessThanOrEqualTo(rect.right));
          final play = tester.getRect(find.byTooltip('Reproducir'));
          expect(controls.right, lessThanOrEqualTo(play.left + 1));
          final glyph = find.descendant(
            of: find.byType(MiniPlayerDesktopControls),
            matching: find.byType(Icon),
          );
          final color = tester.widget<Icon>(glyph.first).color!;
          expect(
            _contrast(color, fillBehind(tester, glyph.first)),
            greaterThanOrEqualTo(3),
            reason: 'iconos',
          );
        });
      }
    }
  });

  group('progreso arrastrable', () {
    Finder bar() => find.bySemanticsLabel('Progreso');

    testWidgets('con canSeek: tocar y arrastrar llaman a seek al soltar', (
      tester,
    ) async {
      await mount(
        tester,
        wide: true,
        size: const Size(1440, 900),
        state: _state(canSeek: true),
      );
      final strip = find.descendant(
        of: pill(),
        matching: find.byType(CustomPaint),
      );
      final rect = tester.getRect(strip.last);
      await tester.tapAt(Offset(rect.left + rect.width * .25, rect.center.dy));
      expect(calls.log.where((e) => e.startsWith('seek:0.2')), hasLength(1));
      expect(calls.count('open'), 0);
      final g = await tester.startGesture(rect.center);
      await g.moveTo(Offset(rect.left + rect.width * .9, rect.center.dy));
      expect(calls.log.where((e) => e.startsWith('seek:')), hasLength(1));
      await g.up();
      await tester.pump();
      expect(calls.log.last, 'seek:0.90');
      // Arrastrar la franja no salta de pista.
      expect(calls.count('next'), 0);
      expect(calls.count('previous'), 0);
    });

    testWidgets('sin canSeek: solo se ve y no llama a seek', (tester) async {
      await mount(
        tester,
        wide: true,
        size: const Size(1440, 900),
        state: _state(),
      );
      final strip = find.descendant(
        of: pill(),
        matching: find.byType(CustomPaint),
      );
      final rect = tester.getRect(strip.last);
      await tester.dragFrom(
        Offset(rect.left + 20, rect.center.dy),
        const Offset(200, 0),
      );
      expect(calls.log.where((e) => e.startsWith('seek:')), isEmpty);
      expect(bar(), findsOneWidget);
    });
  });

  group('movimiento', () {
    testWidgets('entra con 8 px de recorrido y sin él con movimiento '
        'reducido', (tester) async {
      await mount(tester, settle: false);
      Finder face() =>
          find.descendant(of: pill(), matching: find.byType(Stack)).first;
      final start = tester.getTopLeft(face());
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(face()).dy, lessThan(start.dy));
      await tester.pumpWidget(const SizedBox.shrink());

      await mount(tester, reduce: true, settle: false);
      final still = tester.getTopLeft(face());
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(face()), still);
    });
  });

  group('contraste', () {
    Color textColor(WidgetTester tester, Finder f) =>
        tester.widget<Text>(f).style!.color!;

    for (final (name, accent) in [
      ('menta', const Color(0xff00aa55)),
      ('amarillo', const Color(0xffddbb00)),
      ('lila', const Color(0xff7755dd)),
      ('naranja', const Color(0xffee4400)),
    ]) {
      for (final dark in [false, true]) {
        testWidgets('acento $name ${dark ? 'oscuro' : 'claro'}', (
          tester,
        ) async {
          await mount(
            tester,
            accent: accent,
            brightness: dark ? Brightness.dark : Brightness.light,
            state: _state(liked: true),
          );
          final title = find.text('Luz de luna'),
              artist = find.text('Mare Sol');
          final pillFill = fillBehind(tester, title);
          expect(
            _contrast(textColor(tester, title), pillFill),
            greaterThanOrEqualTo(4.5),
            reason: 'título',
          );
          expect(
            _contrast(textColor(tester, artist), pillFill),
            greaterThanOrEqualTo(4.5),
            reason: 'artista',
          );
          // Iconos de los botones (UI ≥ 3) sobre su propio relleno.
          final play = find.byIcon(Icons.play_arrow_rounded);
          final icon = tester.widget<Icon>(play).color!;
          expect(
            _contrast(icon, fillBehind(tester, play)),
            greaterThanOrEqualTo(3),
            reason: 'play',
          );
          final heart = find.byIcon(Icons.favorite_rounded);
          expect(
            _contrast(
              tester.widget<Icon>(heart).color!,
              fillBehind(tester, heart),
            ),
            greaterThanOrEqualTo(3),
            reason: 'corazón',
          );
        });
      }
    }
  });

  group('anuncio y Jam en el subtítulo', () {
    for (final scale in const [1.0, 2.0]) {
      final tag = '360 · ×${scale.toInt()}';
      Future<void> pump(WidgetTester tester, MiniPlayerState state) =>
          mount(tester, size: const Size(360, 640), scale: scale, state: state);

      testWidgets('anuncio · $tag', (tester) async {
        await pump(tester, _state(ad: true, isPlaying: true));
        expect(tester.takeException(), isNull);
        expect(find.text('Anuncio · tu canción sigue después'), findsOneWidget);
        expect(find.text('Mare Sol'), findsNothing);
      });

      testWidgets('Jam · $tag', (tester) async {
        await pump(tester, _state(jam: true, isPlaying: true));
        expect(tester.takeException(), isNull);
        expect(find.text('Mare Sol · Jam'), findsOneWidget);
      });
    }
  });
}
