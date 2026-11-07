import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/mini_player/blurred_cover_backdrop.dart';
import 'package:aurora_music/ui/mini_player/cover_backdrop_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

Track _track(String id, {String? art = 'https://covers.test/x.jpg'}) =>
    Track(id: id, title: 'Título $id', artist: 'Artista $id', artworkUrl: art);

List<Color> _flat(Color c) => List.filled(64, c);

/// Portadas sintéticas: extremos, saturados, medios y mezclas duras.
Map<String, List<Color>> _covers() {
  final random = math.Random(7);
  return {
    'blanca': _flat(const Color(0xffffffff)),
    'negra': _flat(const Color(0xff000000)),
    'gris medio': _flat(const Color(0xff808080)),
    'gris claro': _flat(const Color(0xffc8c8c8)),
    'rojo': _flat(const Color(0xffff0000)),
    'verde': _flat(const Color(0xff00ff00)),
    'azul': _flat(const Color(0xff0000ff)),
    'amarillo': _flat(const Color(0xffffff00)),
    'cian': _flat(const Color(0xff00ffff)),
    'magenta': _flat(const Color(0xffff00ff)),
    'ajedrez': [
      for (var i = 0; i < 64; i++)
        i.isEven ? const Color(0xffffffff) : const Color(0xff000000),
    ],
    'aleatoria': [
      for (var i = 0; i < 64; i++)
        Color.fromARGB(
          255,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        ),
    ],
  };
}

class _FakeCovers implements CoverBackdropSource {
  _FakeCovers(this.image);
  final ui.Image image;
  final warm = <String>{};
  final pending = <String, Completer<CoverBackdropData?>>{};
  final failing = <String>{};
  final loads = <String>[];

  CoverBackdropData get _data =>
      CoverBackdropData(image: image, samples: _flat(const Color(0xff202020)));

  @override
  String? keyOf(Track track) => track.artworkUrl == null ? null : track.id;

  @override
  CoverBackdropData? peek(Track track) =>
      warm.contains(track.id) ? _data : null;

  @override
  Future<CoverBackdropData?> load(Track track) {
    loads.add(track.id);
    if (failing.contains(track.id)) return Future.value();
    return pending[track.id]?.future ?? Future.value(_data);
  }
}

void main() {
  group('CoverTone garantiza contraste', () {
    for (final entry in _covers().entries) {
      test('adaptativo sobre portada ${entry.key}', () {
        final tone = CoverTone.adaptive(entry.value);
        expect(tone.worstContrast(entry.value), greaterThanOrEqualTo(4.5));
        expect(
          tone.worstContrast(entry.value),
          greaterThanOrEqualTo(kCoverContrastTarget),
        );
        // El velo no tapa la portada del todo.
        expect(tone.scrim.a, lessThan(.95));
      });
    }

    test('elige velo claro con texto oscuro sobre portada blanca', () {
      final tone = CoverTone.adaptive(_flat(Colors.white));
      expect(tone.darkScrim, isFalse);
      expect(tone.foreground.computeLuminance(), lessThan(.1));
    });

    test('elige velo oscuro con texto claro sobre portada negra', () {
      final tone = CoverTone.adaptive(_flat(Colors.black));
      expect(tone.darkScrim, isTrue);
      expect(tone.foreground.computeLuminance(), greaterThan(.9));
    });

    test('el texto secundario también llega a 4,5', () {
      for (final samples in _covers().values) {
        final tone = CoverTone.adaptive(samples);
        for (final pixel in samples) {
          final bg = Color.alphaBlend(tone.scrim, pixel);
          expect(coverContrast(tone.secondary, bg), greaterThanOrEqualTo(4.5));
        }
      }
    });

    test(
      'temático conserva el texto del tema y supera 4,5 sobre cualquier portada',
      () {
        for (final (surface, fg, sub) in [
          (
            const Color(0xff121212),
            const Color(0xffffffff),
            const Color(0xffc8c8c8),
          ),
          (
            const Color(0xfffafafa),
            const Color(0xff111111),
            const Color(0xff4a4a4a),
          ),
        ]) {
          for (final samples in _covers().values) {
            final tone = CoverTone.themed(
              samples,
              surface: surface,
              onSurface: fg,
              onSurfaceVariant: sub,
            );
            expect(tone.foreground, fg);
            expect(tone.worstContrast(samples), greaterThanOrEqualTo(4.5));
          }
        }
      },
    );

    test(
      'temático cae a la superficie opaca si el tema no llega al objetivo',
      () {
        final tone = CoverTone.themed(
          _flat(Colors.white),
          surface: const Color(0xff808080),
          onSurface: const Color(0xff909090),
          onSurfaceVariant: const Color(0xff909090),
        );
        expect(tone.scrim.a, 1);
      },
    );
  });

  _pipelineTests();

  test('gridSamples promedia por celda', () {
    // 16×16: mitad izquierda blanca, mitad derecha negra.
    final rgba = Uint8List(16 * 16 * 4);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final i = (y * 16 + x) * 4;
        final v = x < 8 ? 255 : 0;
        rgba.setRange(i, i + 4, [v, v, v, 255]);
      }
    }
    final cells = gridSamples(rgba, 16, 16);
    expect(cells, hasLength(64));
    expect(cells[0], const Color(0xffffffff));
    expect(cells[7], const Color(0xff000000));
  });

  group('CoverBackdropCache', () {
    late ui.Image image;
    setUpAll(() async {
      image = await decodeImageFromList(base64Decode(_png));
    });
    CoverBackdropData data() =>
        CoverBackdropData(image: image, samples: _flat(Colors.black));

    test(
      'una sola carga para peticiones simultáneas y peek tras cargar',
      () async {
        var calls = 0;
        final gate = Completer<CoverBackdropData?>();
        final cache = CoverBackdropCache(
          loader: (_) {
            calls++;
            return gate.future;
          },
        );
        final t = _track('a');
        final first = cache.load(t), second = cache.load(t);
        expect(cache.peek(t), isNull);
        gate.complete(data());
        expect(identical(await first, await second), isTrue);
        expect(calls, 1);
        expect(cache.peek(t), isNotNull);
      },
    );

    test('sin portada no carga; los fallos no se guardan', () async {
      var calls = 0;
      final cache = CoverBackdropCache(
        loader: (_) async {
          calls++;
          throw StateError('sin red');
        },
      );
      expect(await cache.load(_track('x', art: null)), isNull);
      expect(calls, 0);
      expect(await cache.load(_track('b')), isNull);
      expect(await cache.load(_track('b')), isNull);
      expect(calls, 2, reason: 'el fallo se reintenta');
    });

    test('expulsa la menos usada al superar la capacidad', () async {
      final cache = CoverBackdropCache(
        capacity: 2,
        loader: (_) async => data(),
      );
      final a = _track('a'), b = _track('b'), c = _track('c');
      await cache.load(a);
      await cache.load(b);
      cache.peek(a); // a pasa a ser la más reciente
      await cache.load(c);
      expect(cache.peek(b), isNull);
      expect(cache.peek(a), isNotNull);
      expect(cache.peek(c), isNotNull);
    });
  });

  group('BlurredCoverBackdrop', () {
    late ui.Image image;
    late _FakeCovers covers;

    Future<void> mount(
      WidgetTester tester,
      Track? track, {
      bool reduced = false,
      Key? key,
    }) => tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: child!,
        ),
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 80,
            child: BlurredCoverBackdrop(
              key: key,
              track: track,
              source: covers,
              child: Builder(
                builder: (context) => Text(
                  'artista',
                  key: const ValueKey('probe'),
                  style: TextStyle(
                    color: BlurredCoverTheme.of(context).foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    setUp(() {});

    Future<void> prepare(WidgetTester tester) async {
      image = (await tester.runAsync(
        () => decodeImageFromList(base64Decode(_png)),
      ))!;
      covers = _FakeCovers(image);
    }

    testWidgets('sin pista o sin portada deja solo el hijo, aspecto del tema', (
      tester,
    ) async {
      await prepare(tester);
      await mount(tester, null);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byKey(const ValueKey('probe')), findsOneWidget);
      expect(
        BlurredCoverTheme.isActive(
          tester.element(find.byKey(const ValueKey('probe'))),
        ),
        isFalse,
      );
      await mount(tester, _track('s', art: null));
      expect(find.byType(RawImage), findsNothing);
    });

    testWidgets('fallo de carga: hijo sobre el tema, sin imagen', (
      tester,
    ) async {
      await prepare(tester);
      covers.failing.add('f');
      await mount(tester, _track('f'));
      await tester.pump(kCoverCrossfade * 2);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byKey(const ValueKey('probe')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'portada en caché se pinta al instante, con colores garantizados',
      (tester) async {
        await prepare(tester);
        covers.warm.add('w');
        await mount(tester, _track('w'));
        expect(find.byType(RawImage), findsOneWidget);
        final context = tester.element(find.byKey(const ValueKey('probe')));
        expect(BlurredCoverTheme.isActive(context), isTrue);
        final tone = BlurredCoverTheme.of(context);
        expect(
          tone.worstContrast(_flat(const Color(0xff202020))),
          greaterThan(4.5),
        );
        expect(
          tester.widget<Text>(find.byKey(const ValueKey('probe'))).style!.color,
          tone.foreground,
        );
      },
    );

    testWidgets('cruza en 350 ms al cambiar de pista y deja una sola capa', (
      tester,
    ) async {
      await prepare(tester);
      covers.warm.add('a');
      await mount(tester, _track('a'));
      final gate = Completer<CoverBackdropData?>();
      covers.pending['b'] = gate;
      await mount(tester, _track('b'));
      // Mientras carga la nueva, la antigua sigue (sin parpadeo).
      expect(find.byType(RawImage), findsOneWidget);
      gate.complete(covers._data);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(RawImage), findsNWidgets(2), reason: 'cruzando');
      await tester.pump(kCoverCrossfade + const Duration(milliseconds: 20));
      await tester.pump();
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('movimiento reducido: cambio instantáneo', (tester) async {
      await prepare(tester);
      covers.warm.add('a');
      await mount(tester, _track('a'), reduced: true);
      covers.warm.add('b');
      await mount(tester, _track('b'), reduced: true);
      expect(find.byType(RawImage), findsOneWidget);
    });

    testWidgets('el estado del hijo sobrevive a la carga de la portada', (
      tester,
    ) async {
      await prepare(tester);
      final gate = Completer<CoverBackdropData?>();
      covers.pending['k'] = gate;
      await mount(tester, _track('k'));
      final before = tester.element(find.byKey(const ValueKey('probe')));
      gate.complete(covers._data);
      await tester.pump();
      await tester.pump(kCoverCrossfade * 2);
      expect(tester.element(find.byKey(const ValueKey('probe'))), same(before));
    });

    testWidgets('con texto al doble no desborda', (tester) async {
      await prepare(tester);
      covers.warm.add('t');
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 200,
                child: BlurredCoverBackdrop(
                  track: _track('t'),
                  source: covers,
                  radius: BorderRadius.circular(16),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Un artista con un nombre largo largo largo',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

void _pipelineTests() {
  testWidgets(
    'loadBlurredCover decodifica, difumina y muestrea una portada real',
    (tester) async {
      final data = await tester.runAsync(
        () => loadBlurredCover(
          _track(
            'real',
            art: 'asset:assets/design_idea/descargas_locales_aurora_00.png',
          ),
        ),
      );
      expect(data, isNotNull);
      expect(data!.samples, hasLength(64));
      expect(data.image.width, lessThanOrEqualTo(kCoverDecodeWidth));
      expect(
        data.adaptiveTone.worstContrast(data.samples),
        greaterThanOrEqualTo(4.5),
      );
    },
  );

  testWidgets('loadBlurredCover devuelve null si la imagen no existe', (
    tester,
  ) async {
    final data = await tester.runAsync(
      () => loadBlurredCover(_track('nada', art: 'asset:assets/no_existe.png')),
    );
    expect(data, isNull);
  });
}
