import 'dart:convert';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/brasa_theme.dart';
import 'package:aurora_music/ui/artwork.dart';
import 'package:aurora_music/ui/mini_player/blurred_cover_backdrop.dart';
import 'package:aurora_music/ui/mini_player/brasa_mini_player.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

const _plain = Track(
  id: 'a',
  title: 'Cenizas',
  artist: 'Los Rescoldos',
  duration: Duration(minutes: 3),
);

// Portada «con imagen» que no sale a la red: el asset no existe y Artwork
// cae al marcador.
const _withCover = Track(
  id: 'c',
  title: 'Cenizas',
  artist: 'Los Rescoldos',
  artworkUrl: 'asset:none.png',
  duration: Duration(minutes: 3),
);

class _Calls {
  int open = 0, play = 0, next = 0, previous = 0, like = 0;
  late final actions = MiniPlayerActions(
    openPlayer: () => open++,
    togglePlay: () => play++,
    next: () => next++,
    previous: () => previous++,
    toggleLike: () => like++,
  );
}

MiniPlayerState _state({
  Track? track = _plain,
  bool isPlaying = false,
  double progress = .5,
  bool buffering = false,
  bool hasError = false,
  bool liked = false,
  bool hasNext = true,
  bool hasPrevious = true,
  bool canTogglePlay = true,
  String? jamHostName,
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
);

List<Color> _flat(Color c) => List.filled(64, c);

class _Covers implements CoverBackdropSource {
  _Covers(this.image, this.color);
  final ui.Image image;
  final Color color;

  CoverBackdropData get _data =>
      CoverBackdropData(image: image, samples: _flat(color));

  @override
  String? keyOf(Track track) => track.artworkUrl == null ? null : track.id;

  @override
  CoverBackdropData? peek(Track track) => _data;

  @override
  Future<CoverBackdropData?> load(Track track) async => _data;
}

Future<void> _mount(
  WidgetTester tester,
  _Calls calls, {
  MiniPlayerState? state,
  double width = 412,
  double scale = 1,
  bool blurred = false,
  bool? wide,
  bool reduced = false,
  CoverBackdropSource? covers,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final s = state ?? _state();
  await tester.pumpWidget(
    MaterialApp(
      theme: brasaTheme(Brightness.dark, const Color(0xffe86927)),
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
            MiniPlayerGestures(
              actions: calls.actions,
              hasNext: s.hasNext,
              hasPrevious: s.hasPrevious,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      ((wide ?? width >= 600) ? 64.0 : 56.0) *
                      scale.clamp(1.0, 1.5),
                ),
                child: BrasaMiniPlayer(
                  state: s,
                  actions: calls.actions,
                  blurred: blurred,
                  wide: wide ?? width >= 600,
                  covers: covers,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get _bar => find.byType(BrasaMiniPlayer);

void main() {
  test('el tema ya no es legacy', () {
    expect(brasaMiniPlayer.legacy, isFalse);
  });

  test('reloj m:ss y h:mm:ss', () {
    expect(brasaClock(Duration.zero), '0:00');
    expect(brasaClock(const Duration(seconds: 65)), '1:05');
    expect(
      brasaClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(brasaClock(const Duration(seconds: -4)), '0:00');
  });

  group('tamaños', () {
    for (final width in <double>[360, 412, 600, 900, 1440]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('sin desbordes a $width px, texto ×$scale', (tester) async {
          final calls = _Calls();
          await _mount(
            tester,
            calls,
            width: width,
            scale: scale,
            state: _state(
              track: const Track(
                id: 'l',
                title:
                    'Un título larguísimo con emoji 🔥🔥🔥 para comprobar el recorte sin romper la fila',
                artist:
                    'Un artista con un nombre igual de largo que el título anterior ✨',
                duration: Duration(hours: 1, minutes: 20),
              ),
              isPlaying: true,
              liked: true,
            ),
          );
          expect(tester.takeException(), isNull);
          final box = tester.getSize(_bar);
          expect(box.width, width);
          expect(
            box.height,
            greaterThanOrEqualTo(
              (width >= 600 ? 64 : 60) * (scale > 1.5 ? 1.5 : scale) - .01,
            ),
          );
        });
      }
    }

    testWidgets('la hora cabe desde 412 y se oculta a 360', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 360);
      expect(find.text('1:30 / 3:00'), findsNothing);
      await _mount(tester, calls, width: 412);
      expect(find.textContaining('1:30'), findsOneWidget);
      expect(find.textContaining('3:00'), findsOneWidget);
    });

    testWidgets('con texto ×2 se oculta la hora y el texto se recorta', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 412, scale: 2);
      expect(find.textContaining('1:30'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ancho: anterior/siguiente y división en columnas', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 900);
      expect(find.byTooltip('Pista anterior'), findsOneWidget);
      expect(find.byTooltip('Pista siguiente'), findsOneWidget);
      expect(find.textContaining('1:30'), findsOneWidget);
      await _mount(tester, calls, width: 360);
      expect(find.byTooltip('Pista anterior'), findsNothing);
    });

    testWidgets('todos los botones miden ≥ 44 px', (tester) async {
      final calls = _Calls();
      for (final (width, scale) in [(360.0, 1.0), (900.0, 1.0), (412.0, 2.0)]) {
        await _mount(tester, calls, width: width, scale: scale);
        for (final label in [
          'Añadir a favoritos',
          'Reproducir',
          if (width >= 600) ...['Pista anterior', 'Pista siguiente'],
        ]) {
          final size = tester.getSize(find.byTooltip(label));
          expect(
            size.width,
            greaterThanOrEqualTo(44),
            reason: '$label @$width',
          );
          expect(
            size.height,
            greaterThanOrEqualTo(44),
            reason: '$label @$width',
          );
        }
      }
    });
  });

  group('estados', () {
    testWidgets('sin pista no pinta nada', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls, state: _state(track: null));
      expect(find.byType(Artwork), findsNothing);
    });

    testWidgets('reproduciendo: pausar con icono de pausa', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls, state: _state(isPlaying: true));
      expect(find.byTooltip('Pausar'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Pausar'));
      expect((calls.play, calls.open), (1, 0));
    });

    testWidgets('en pausa: reproducir con icono de play', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls);
      expect(find.byTooltip('Reproducir'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Reproducir'));
      expect(calls.play, 1);
    });

    testWidgets('búfer: anillo en lugar del icono', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls, state: _state(buffering: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('fallo: reintento en rojo y ERR en la hora', (tester) async {
      final calls = _Calls();
      await _mount(
        tester,
        calls,
        width: 900,
        state: _state(hasError: true, isPlaying: true),
      );
      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.text('ERR'), findsOneWidget);
      await tester.tap(find.byTooltip('Error de reproducción, reintentar'));
      expect(calls.play, 1);
    });

    testWidgets('sin permiso de Jam: play desactivado y nombra al anfitrión', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(
        tester,
        calls,
        state: _state(canTogglePlay: false, jamHostName: 'Ana'),
      );
      expect(find.byTooltip('Lo controla Ana'), findsOneWidget);
      await tester.tap(find.byTooltip('Lo controla Ana'));
      expect(calls.play, 0);
    });

    testWidgets('favorito alterna icono y llama a la acción', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls, state: _state(liked: true));
      expect(find.byTooltip('Quitar de favoritos'), findsOneWidget);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar de favoritos'));
      expect((calls.like, calls.open), (1, 0));
      await _mount(tester, calls);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    });

    testWidgets('anterior y siguiente (ancho) llaman a sus acciones', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 900);
      await tester.tap(find.byTooltip('Pista siguiente'));
      await tester.tap(find.byTooltip('Pista anterior'));
      expect((calls.next, calls.previous, calls.open), (1, 1, 0));
    });

    testWidgets('sin siguiente ni anterior: botones desactivados', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(
        tester,
        calls,
        width: 900,
        state: _state(hasNext: false, hasPrevious: false),
      );
      await tester.tap(find.byTooltip('Pista siguiente'));
      await tester.tap(find.byTooltip('Pista anterior'));
      expect((calls.next, calls.previous), (0, 0));
    });
  });

  group('gestos del host', () {
    testWidgets('tocar la barra abre el reproductor', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls);
      await tester.tapAt(
        tester.getTopLeft(find.byType(Artwork)) + const Offset(8, 8),
      );
      expect(calls.open, 1);
    });

    testWidgets('deslizar a los lados salta de pista', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls);
      final from = tester.getCenter(find.byType(Artwork));
      await tester.dragFrom(from, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect((calls.next, calls.previous), (1, 0));
      await tester.dragFrom(from, const Offset(120, 0));
      await tester.pumpAndSettle();
      expect((calls.next, calls.previous), (1, 1));
    });

    testWidgets('arrastrar hacia arriba abre', (tester) async {
      final calls = _Calls();
      await _mount(tester, calls);
      await tester.dragFrom(
        tester.getCenter(find.byType(Artwork)),
        const Offset(0, -90),
      );
      await tester.pumpAndSettle();
      expect(calls.open, 1);
    });
  });

  group('movimiento', () {
    testWidgets('al pulsar encoge; con movimiento reducido no', (tester) async {
      final calls = _Calls();
      double smallest() => tester
          .widgetList<AnimatedScale>(
            find.descendant(of: _bar, matching: find.byType(AnimatedScale)),
          )
          .map((w) => w.scale)
          .reduce((a, b) => a < b ? a : b);

      await _mount(tester, calls);
      var press = await tester.startGesture(
        tester.getCenter(find.byTooltip('Reproducir')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(smallest(), .92);
      await press.up();
      await tester.pumpAndSettle();

      await _mount(tester, calls, reduced: true);
      press = await tester.startGesture(
        tester.getCenter(find.byTooltip('Reproducir')),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(smallest(), 1);
      final opacity = tester
          .widgetList<AnimatedOpacity>(
            find.descendant(of: _bar, matching: find.byType(AnimatedOpacity)),
          )
          .map((w) => w.opacity)
          .reduce((a, b) => a < b ? a : b);
      expect(opacity, .7);
      await press.up();
      await tester.pumpAndSettle();
    });

    testWidgets('el cursor encima enciende la marca de la línea sin errores', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 900);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_bar));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_bar) + const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
    });
  });

  group('contraste', () {
    testWidgets('normal: artista ámbar, pista y hora sobre la brasa ≥ 4,5', (
      tester,
    ) async {
      final calls = _Calls();
      await _mount(tester, calls, width: 900);
      const bg = Brasa.obsidian;
      Color colorOf(String text) {
        final t = tester.widget<Text>(find.text(text));
        return t.style!.color!;
      }

      expect(
        coverContrast(colorOf('LOS RESCOLDOS'), bg),
        greaterThanOrEqualTo(4.5),
      );
      expect(coverContrast(colorOf('Cenizas'), bg), greaterThanOrEqualTo(4.5));
      expect(coverContrast(Brasa.cloud, bg), greaterThanOrEqualTo(4.5));
      expect(coverContrast(Brasa.accent, bg), greaterThanOrEqualTo(3));
      // Texto sobre el relleno ámbar del botón al sonar.
      expect(
        coverContrast(Brasa.void_, Brasa.accent),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('error: rojo sobre la barra ≥ 4,5', (tester) async {
      expect(
        coverContrast(const Color(0xffff8a7a), Brasa.obsidian),
        greaterThanOrEqualTo(4.5),
      );
    });

    group('difuminado', () {
      late ui.Image image;

      for (final (name, cover) in [
        ('blanca', Colors.white),
        ('negra', Colors.black),
        ('gris medio', const Color(0xff808080)),
        ('ámbar', const Color(0xffffb04a)),
      ]) {
        testWidgets('portada $name: texto ≥ 4,5 y ámbar ≥ 3 sobre su fondo', (
          tester,
        ) async {
          image = (await tester.runAsync(
            () => decodeImageFromList(base64Decode(_png)),
          ))!;
          final calls = _Calls();
          await _mount(
            tester,
            calls,
            width: 900,
            blurred: true,
            state: _state(track: _withCover, isPlaying: true),
            covers: _Covers(image, cover),
          );
          expect(find.byType(RawImage), findsWidgets);
          final context = tester.element(find.text('LOS RESCOLDOS'));
          final tone = BlurredCoverTheme.of(context);
          expect(BlurredCoverTheme.isActive(context), isTrue);
          final bg = Color.alphaBlend(tone.scrim, cover);
          final artist = tester.widget<Text>(find.text('LOS RESCOLDOS'));
          final title = tester.widget<Text>(find.text('Cenizas'));
          expect(artist.style!.color, tone.foreground);
          expect(title.style!.color, tone.secondary);
          expect(
            coverContrast(artist.style!.color!, bg),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            coverContrast(title.style!.color!, bg),
            greaterThanOrEqualTo(4.5),
          );
          // Tiempo: ambas partes.
          expect(coverContrast(tone.secondary, bg), greaterThanOrEqualTo(4.5));
          // Teclas y línea de brasa llevan un fondo negro al 55-60 %.
          final backed = Color.alphaBlend(
            Colors.black.withValues(alpha: .55),
            bg,
          );
          expect(coverContrast(Brasa.accent, backed), greaterThanOrEqualTo(3));
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('el artista crece y se pone en mayúsculas condensadas', (
        tester,
      ) async {
        image = (await tester.runAsync(
          () => decodeImageFromList(base64Decode(_png)),
        ))!;
        final calls = _Calls();
        await _mount(tester, calls, state: _state(track: _withCover));
        final normal = tester.widget<Text>(find.text('LOS RESCOLDOS')).style!;
        expect(find.byType(RawImage), findsNothing);
        await _mount(
          tester,
          calls,
          blurred: true,
          state: _state(track: _withCover),
          covers: _Covers(image, Colors.black),
        );
        final big = tester.widget<Text>(find.text('LOS RESCOLDOS')).style!;
        expect(big.fontSize! / normal.fontSize!, greaterThan(1.5));
        expect(big.letterSpacing!, lessThan(0));
        expect(big.fontWeight, FontWeight.w800);
        expect(find.byType(RawImage), findsWidgets);
      });

      testWidgets('difuminado sin desbordes a 360 y texto ×2', (tester) async {
        image = (await tester.runAsync(
          () => decodeImageFromList(base64Decode(_png)),
        ))!;
        final calls = _Calls();
        for (final scale in [1.0, 2.0]) {
          await _mount(
            tester,
            calls,
            width: 360,
            scale: scale,
            blurred: true,
            state: _state(track: _withCover, isPlaying: true),
            covers: _Covers(image, Colors.white),
          );
          expect(tester.takeException(), isNull);
        }
      });
    });
  });

  group('con el host', () {
    late AppController controller;
    final themes = {'brasa': brasaMiniPlayer, 'atelier': brasaMiniPlayer};

    Future<void> mountHost(WidgetTester tester, {int section = 0}) async {
      tester.view.physicalSize = const Size(412, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: brasaTheme(Brightness.dark, const Color(0xffe86927)),
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                MiniPlayerHost(
                  controller: controller,
                  section: section,
                  rail: false,
                  placement: MiniPlayerPlacement.body,
                  themes: themes,
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

    testWidgets('sin pista oculto; con pista visible; en la sección 4 oculto', (
      tester,
    ) async {
      controller = (await tester.runAsync(
        () => createTestController(tracks: [_plain]),
      ))!;
      addTearDown(() => closeTestController(controller));
      await mountHost(tester);
      expect(_bar, findsNothing);
      controller.queue = [_plain];
      controller.queueIndex = 0;
      await mountHost(tester);
      expect(_bar, findsOneWidget);
      expect(tester.takeException(), isNull);
      await mountHost(tester, section: 4);
      expect(_bar, findsNothing);
    });
  });
}
