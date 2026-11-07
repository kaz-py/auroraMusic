import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(
    id: 'a',
    title: 'Ok Alright',
    artist: 'Travis Scott',
    duration: Duration(minutes: 3),
  ),
  Track(id: 'b', title: 'Segunda', artist: 'Aurora'),
];

class _FakeLyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.synced,
    lines: [
      LyricLine(Duration.zero, 'Primera línea'),
      LyricLine(Duration(seconds: 30), 'Segunda línea'),
    ],
  );
}

/// LRCLIB solo tiene texto plano para la pista; con [withSynced] además hay un
/// candidato sincronizado con título, artista y duración que casan.
class _PlainLyrics extends LyricsService {
  _PlainLyrics({this.withSynced = false});
  final bool withSynced;

  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(
    LyricsKind.plain,
    text: 'Línea uno\nLínea dos\nLínea tres',
  );

  @override
  Future<List<LyricsCandidate>> candidates(Track track) async => [
    if (withSynced)
      const LyricsCandidate(
        title: 'Ok Alright',
        artist: 'Travis Scott',
        album: '',
        seconds: 180,
        content: '[00:00.00] Línea sincronizada',
        synced: true,
        score: .9,
      ),
  ];

  @override
  Future<LyricsResult> choose(
    Track track,
    Directory root,
    LyricsCandidate c,
  ) async => const LyricsResult(
    LyricsKind.synced,
    lines: [LyricLine(Duration.zero, 'Línea sincronizada')],
  );
}

/// LRCLIB no tiene nada para la pista.
class _NoLyrics extends LyricsService {
  @override
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async => const LyricsResult(LyricsKind.notFound);
}

void main() {
  Future<AppController> mountPage(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    double scale = 1,
    VoidCallback? onClose,
    LyricsService? service,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(
      () => createTestController(tracks: _songs),
    ))!;
    c.queue = [..._songs];
    await tester.runAsync(() => c.playQueueAt(0));
    await c.audio.pause();
    addTearDown(() => tester.runAsync(() => closeTestController(c)));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ArtistModePage(
            controller: c,
            service: service ?? _FakeLyrics(),
            onClose: onClose ?? () {},
            onTogglePlay: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  testWidgets('muestra título, artista, letra sincronizada y controles', (
    tester,
  ) async {
    await mountPage(tester);
    expect(find.text('Ok Alright'), findsOneWidget);
    expect(find.text('Travis Scott'), findsOneWidget);
    expect(find.text('Primera línea'), findsOneWidget);
    for (final tip in [
      'Aleatorio',
      'Anterior',
      'Reproducir',
      'Siguiente',
      'Repetir',
      'Salir del modo artista',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('la línea activa se resalta y sigue a la reproducción', (
    tester,
  ) async {
    final c = await mountPage(tester);
    // El estilo animado más cercano al texto de la línea.
    AnimatedDefaultTextStyle lineStyle(String text) =>
        tester.widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text(text),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        );
    double sizeOf(String text) => lineStyle(text).style.fontSize!;
    Color colorOf(String text) => lineStyle(text).style.color!;

    // Al principio manda la primera línea: más grande y más opaca.
    expect(sizeOf('Primera línea'), greaterThan(sizeOf('Segunda línea')));
    expect(colorOf('Primera línea').a, greaterThan(colorOf('Segunda línea').a));

    // A los 31 s manda la segunda.
    (c.audio as FakeAudio).advanceTo(const Duration(seconds: 31));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(sizeOf('Segunda línea'), greaterThan(sizeOf('Primera línea')));
    expect(colorOf('Segunda línea').a, greaterThan(colorOf('Primera línea').a));
  });

  testWidgets('letra sin sincronizar: se reparte por la pista y se avisa', (
    tester,
  ) async {
    await mountPage(tester, service: _PlainLyrics());
    expect(find.text('Sincronización aproximada'), findsOneWidget);
    expect(find.text('Línea uno'), findsOneWidget);
    expect(find.text('Línea dos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'letra sin sincronizar: si hay una sincronizada que casa, la usa',
    (tester) async {
      await mountPage(tester, service: _PlainLyrics(withSynced: true));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sincronización aproximada'), findsNothing);
      expect(find.text('Línea sincronizada'), findsOneWidget);
    },
  );

  testWidgets('el botón de salir llama a onClose', (tester) async {
    var closed = 0;
    await mountPage(tester, onClose: () => closed++);
    await tester.tap(find.byTooltip('Salir del modo artista'));
    expect(closed, 1);
  });

  group('pantalla completa', () {
    List<MethodCall> mockWindow(WidgetTester tester) {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('aurora/window'),
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('aurora/window'),
          null,
        ),
      );
      return calls;
    }

    testWidgets('botón, Esc sale primero de pantalla completa y luego cierra', (
      tester,
    ) async {
      final calls = mockWindow(tester);
      var closed = 0;
      await mountPage(tester, onClose: () => closed++);
      await tester.tap(find.byTooltip('Pantalla completa'));
      await tester.pump();
      expect(calls.last.method, 'setFullscreen');
      expect((calls.last.arguments as Map)['enabled'], isTrue);
      expect(find.byTooltip('Salir de pantalla completa'), findsOneWidget);
      expect(find.byTooltip('Maximizar o restaurar'), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(calls.last.method, 'setFullscreen');
      expect((calls.last.arguments as Map)['enabled'], isFalse);
      expect(closed, 0);
      expect(find.byTooltip('Pantalla completa'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, 1);
    });

    testWidgets('F11 alterna la pantalla completa', (tester) async {
      final calls = mockWindow(tester);
      await mountPage(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect((calls.last.arguments as Map)['enabled'], isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f11);
      await tester.pump();
      expect((calls.last.arguments as Map)['enabled'], isFalse);
    });

    testWidgets('al desmontar en pantalla completa se restaura la ventana', (
      tester,
    ) async {
      final calls = mockWindow(tester);
      await mountPage(tester);
      await tester.tap(find.byTooltip('Pantalla completa'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(calls.last.method, 'setFullscreen');
      expect((calls.last.arguments as Map)['enabled'], isFalse);
    });
  });

  group('sin letra', () {
    Finder cover() => find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.label?.startsWith('Portada de ') ?? false),
    );
    Finder labelFade() => find.ancestor(
      of: find.text('Sin letra para esta pista'),
      matching: find.byType(AnimatedOpacity),
    );

    testWidgets('con letra la portada va a la izquierda', (tester) async {
      await mountPage(tester);
      expect(cover(), findsOneWidget);
      expect(tester.getCenter(cover()).dx, lessThan(400));
    });

    testWidgets('sin letra hay una sola portada, en el centro', (tester) async {
      await mountPage(tester, service: _NoLyrics());
      await tester.pump(const Duration(milliseconds: 100));
      expect(cover(), findsOneWidget);
      expect(tester.getCenter(cover()).dx, closeTo(720, 40));
      expect(tester.widget<AnimatedOpacity>(labelFade()).opacity, 1);
    });

    testWidgets('el aviso se oculta solo a los pocos segundos', (tester) async {
      await mountPage(tester, service: _NoLyrics());
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(cover(), findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(labelFade()).opacity, 0);
    });
  });

  testWidgets('Copiar letra deja las líneas en el portapapeles', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await mountPage(tester);
    await tester.tap(find.byTooltip('Copiar letra'));
    await tester.pump();
    expect(copied, 'Primera línea\nSegunda línea');
    expect(find.text('Letra copiada'), findsOneWidget);
  });

  for (final (size, scale) in const [
    (Size(1440, 900), 1.0),
    (Size(900, 700), 2.0),
    (Size(412, 915), 1.0),
    (Size(360, 640), 2.0),
  ]) {
    testWidgets(
      'sin desbordes a ${size.width.toInt()}x${size.height.toInt()} ×$scale',
      (tester) async {
        await mountPage(tester, size: size, scale: scale);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<void> pumpShell(WidgetTester tester, String theme, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = (await tester.runAsync(
      () => createTestController(
        tracks: _songs,
        preferences: {'themeKind': theme, 'themeMode': 'dark'},
      ),
    ))!;
    c.queue = [..._songs];
    await tester.runAsync(() => c.playQueueAt(0));
    await c.audio.pause();
    final container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => c)],
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      await tester.runAsync(() => closeTestController(c));
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuroraApp()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  for (final theme in const ['atelier', 'modern', 'brasa', 'slush']) {
    testWidgets('$theme: «Letras» del mini abre el modo artista y oculta '
        'la barra', (tester) async {
      await pumpShell(tester, theme, const Size(1440, 900));
      expect(find.byType(ArtistModePage), findsNothing);
      expect(find.byType(MiniPlayerHost), findsWidgets);

      await tester.tap(
        find
            .descendant(
              of: find.byType(MiniPlayerHost),
              matching: find.byTooltip('Letras'),
            )
            .first,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsOneWidget);
      // Se oculta toda la UI (menús, barra de abajo): solo queda esta página.
      expect(find.byType(MiniPlayerHost), findsNothing);
      expect(find.byTooltip('Minimizar'), findsOneWidget);
      expect(find.byTooltip('Salir del modo artista'), findsOneWidget);

      await tester.tap(find.byTooltip('Salir del modo artista'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsNothing);
      expect(find.byType(MiniPlayerHost), findsWidgets);
    });

    testWidgets('$theme: Ctrl+L abre el modo artista', (tester) async {
      await pumpShell(tester, theme, const Size(1440, 900));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ArtistModePage), findsOneWidget);
    });
  }

  testWidgets('Android (360×640): «Más vistas» → «Letras» abre el modo '
      'artista y «Salir» vuelve', (tester) async {
    await pumpShell(tester, 'atelier', const Size(360, 640));
    await tester.tap(find.byTooltip('Más vistas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Letras'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ArtistModePage), findsOneWidget);
    expect(find.byType(MiniPlayerHost), findsNothing);

    await tester.tap(find.text('Salir'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ArtistModePage), findsNothing);
    expect(find.byType(MiniPlayerHost), findsWidgets);
  });
}
