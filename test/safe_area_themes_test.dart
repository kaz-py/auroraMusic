import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/friends/friends_providers.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/friends_fakes.dart';

/// Invariante de zona segura en móvil (390x844, notch 47 arriba, barra de
/// gestos 34 abajo): nada interactivo ni legible queda bajo los insets del
/// sistema, y el teclado (`viewInsets.bottom`) no tapa el campo enfocado.
const _w = 390.0, _h = 844.0, _top = 47.0, _bottom = 34.0, _keyboard = 300.0;
const _safeBottom = _h - _bottom;

const _tracks = [
  Track(
    id: 'a',
    title: 'Primera pista',
    artist: 'Aurora',
    pageUrl: 'https://www.youtube.com/watch?v=a',
    duration: Duration(minutes: 3),
  ),
  Track(
    id: 'b',
    title: 'Segunda pista',
    artist: 'Aurora',
    pageUrl: 'https://www.youtube.com/watch?v=b',
    duration: Duration(minutes: 3),
  ),
];

/// Play/pausa: tooltip (Atelier/Modern/Slush) o etiqueta semántica (Brasa).
Finder _playButton() => find.byWidgetPredicate(
  (w) =>
      (w is Tooltip && (w.message == 'Reproducir' || w.message == 'Pausar')) ||
      (w is Semantics &&
          (w.properties.label == 'Reproducir' ||
              w.properties.label == 'Pausar')),
);

Finder _searchEntry() => find
    .byWidgetPredicate(
      (w) =>
          w is Tooltip &&
          (w.message == 'Buscar música' || w.message == 'Buscar'),
    )
    .first;

void main() {
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  Future<void> pump(
    WidgetTester tester,
    String theme, {
    bool play = true,
    bool friends = false,
  }) async {
    final controller = (await tester.runAsync(
      () => createTestController(
        tracks: _tracks,
        audio: FakeAudio(),
        preferences: {'themeKind': theme},
      ),
    ))!;
    addTearDown(
      () => tester.runAsync(() async {
        await controller.closed;
        if (await controller.supportDirectory.exists()) {
          await controller.supportDirectory.delete(recursive: true);
        }
      }),
    );
    // Desmontar (el proveedor libera el controlador) aunque la prueba falle.
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    if (play) {
      controller.queue = [..._tracks];
      await tester.runAsync(() => controller.playQueueAt(0));
      await controller.audio.pause();
    }
    tester.view
      ..physicalSize = const Size(_w, _h)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: _top, bottom: _bottom)
      ..viewPadding = const FakeViewPadding(top: _top, bottom: _bottom);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          controllerProvider.overrideWith((ref) => controller),
          if (friends)
            friendsServiceProvider.overrideWith(
              (ref) => seededFriendsService(),
            ),
        ],
        child: const AuroraApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Todo lo que casa debe acabar por encima de la barra de gestos.
  void above(WidgetTester tester, Finder f, String what) {
    expect(f, findsWidgets, reason: what);
    for (final e in f.evaluate()) {
      final r = tester.getRect(find.byElementPredicate((x) => x == e));
      expect(r.bottom, lessThanOrEqualTo(_safeBottom), reason: '$what $r');
    }
  }

  /// Ningún texto ni botón en reposo asoma bajo la barra de estado.
  void nothingUnderStatusBar(WidgetTester tester, String where) {
    for (final f in [find.byType(Text), find.byType(IconButton)]) {
      for (final e in f.evaluate()) {
        final r = tester.getRect(find.byElementPredicate((x) => x == e));
        if (r.isEmpty || r.bottom <= 0) continue;
        expect(r.top, greaterThanOrEqualTo(_top), reason: '$where ${e.widget}');
      }
    }
  }

  Future<void> openPlayer(WidgetTester tester) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(MiniPlayerHost),
            matching: find.text('Primera pista'),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Más vistas'));
    await tester.pumpAndSettle();
  }

  for (final theme in const ['atelier', 'modern', 'brasa', 'slush']) {
    group(theme, () {
      testWidgets('Inicio: barra inferior y mini player sobre los gestos', (
        tester,
      ) async {
        await pump(tester, theme);
        above(tester, find.byTooltip('Más vistas'), 'nav');
        above(tester, find.byType(MiniPlayerHost), 'mini player');

        nothingUnderStatusBar(tester, 'inicio');
      });

      testWidgets('reproductor móvil: controles dentro de la zona segura', (
        tester,
      ) async {
        await pump(tester, theme);
        await openPlayer(tester);
        for (final tip in const ['Anterior', 'Siguiente', 'Aleatorio']) {
          above(tester, find.byTooltip(tip), tip);
        }
        above(tester, _playButton(), 'play/pausa');
        nothingUnderStatusBar(tester, 'reproductor');
      });

      testWidgets('tarjeta ⋯ del reproductor dentro de la zona segura', (
        tester,
      ) async {
        await pump(tester, theme, friends: true);
        await openPlayer(tester);
        await tester.tap(find.byTooltip('Más acciones'));
        await tester.pumpAndSettle();
        above(tester, find.text('Añadir a la cola'), 'Añadir a la cola');
        above(tester, find.text('Enviar a un amigo'), 'Enviar a un amigo');
      });

      testWidgets('hoja «Más»: última fila alcanzable sobre los gestos', (
        tester,
      ) async {
        await pump(tester, theme);
        await openMore(tester);
        expect(find.text('Ajustes'), findsWidgets);
        await tester.fling(
          find.text('Ajustes').last,
          const Offset(0, -600),
          2000,
        );
        await tester.pumpAndSettle();
        above(tester, find.text('Ajustes').last, 'Ajustes');
        final first = tester.getRect(find.text('Más').last);
        expect(first.top, greaterThanOrEqualTo(_top), reason: 'título Más');
      });

      testWidgets('modo letra: Salir bajo el notch, transporte sobre gestos', (
        tester,
      ) async {
        await pump(tester, theme);
        await openMore(tester);
        await tester.tap(find.text('Letras').last);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 600));
        final salir = find.textContaining('Salir').first;
        expect(
          tester.getTopLeft(salir).dy,
          greaterThanOrEqualTo(_top),
          reason: 'Salir',
        );
        above(tester, _playButton(), 'play/pausa');
        nothingUnderStatusBar(tester, 'modo letra');
      });

      testWidgets('teclado no tapa el campo de búsqueda', (tester) async {
        await pump(tester, theme, play: false);
        await tester.tap(_searchEntry());
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
        await tester.pumpAndSettle();
        final field = find.byType(TextField).first;
        await tester.showKeyboard(field);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(field).bottom,
          lessThanOrEqualTo(_h - _keyboard),
          reason: 'campo de búsqueda',
        );
      });

      testWidgets('teclado no tapa el campo del chat de amigos', (
        tester,
      ) async {
        await pump(tester, theme, play: false, friends: true);
        await openMore(tester);
        await tester.tap(find.textContaining('Amigos').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('friends-chat-u1')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
        await tester.pumpAndSettle();
        final field = find.byType(TextField).last;
        await tester.showKeyboard(field);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(field).bottom,
          lessThanOrEqualTo(_h - _keyboard),
          reason: 'campo del chat',
        );
      });
    });
  }
}
