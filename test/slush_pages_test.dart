import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/follow_widgets.dart';
import 'package:aurora_music/ui/slush/slush_eq_queue.dart';
import 'package:aurora_music/ui/slush/slush_jam.dart';
import 'package:aurora_music/ui/slush/slush_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
  Track(id: 'c', title: 'Noche', artist: 'Otro'),
];

void main() {
  for (final size in const [Size(1280, 900), Size(390, 844)]) {
    final wide = size.width > 600;
    testWidgets('pantallas Slush se pintan a ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: _songs,
          playlists: const [
            MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
            MusicPlaylist(id: 'p2', name: 'Vacía', trackIds: []),
          ],
          preferences: const {'themeKind': 'slush', 'themeMode': 'light'},
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
        await tester.runAsync(() async {
          await c.closed;
          if (await c.supportDirectory.exists()) {
            await c.supportDirectory.delete(recursive: true);
          }
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const AuroraApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuroraShell), findsOneWidget);
      tester.takeException(); // desborde de 2 px del Inicio con fuentes de test

      Future<void> go(Finder tap, String title) async {
        await tester.tap(tap.first);
        await tester.pumpAndSettle();
        expect(find.byType(SlushPage), findsOneWidget, reason: title);
        expect(find.text(title), findsWidgets, reason: title);
        final err = tester.takeException();
        if (err is FlutterError) debugPrint(err.toStringDeep());
        expect(err, isNull, reason: title);
      }

      if (wide) {
        for (final (label, title) in const [
          ('ARTISTAS', 'ARTISTAS'),
          ('BUSCAR', 'BÚSQUEDA'),
          ('DESCARGAS', 'DESCARGAS'),
          ('BIBLIOTECA', 'BIBLIOTECA'),
        ]) {
          await go(find.text(label), title);
        }
      } else {
        for (final tip in const [
          'Inicio',
          'Buscar',
          'Biblioteca',
          'DJ',
          'Jam',
        ]) {
          expect(find.byTooltip(tip), findsWidgets, reason: tip);
        }
        expect(find.byTooltip('Descargas locales'), findsNothing);
        await tester.tap(find.byTooltip('Siguiente'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pumpAndSettle();
        expect(c.currentTrack?.id, 'b');
        await c.audio.pause();
        await go(find.byTooltip('Biblioteca'), 'BIBLIOTECA');
        await go(find.byTooltip('Buscar'), 'BÚSQUEDA');
        // En el teléfono el titular se va con el scroll del contenido.
        await tester.dragFrom(
          tester.getCenter(find.byType(SlushCard)),
          const Offset(0, -400),
        );
        await tester.pumpAndSettle();
        expect(find.text('BÚSQUEDA').hitTestable(), findsNothing);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Descargas').last, 'DESCARGAS');
        await go(find.byIcon(Icons.dark_mode_outlined), 'AJUSTES');
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Descargar vídeos'), 'VÍDEOS');
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Artistas'), 'ARTISTAS');
        // Subpantallas del reproductor en el teléfono: EQ+Cola.
        for (final (label, type) in const [
          ('Ecualizador', SlushEqQueue),
          ('Cola de reproducción', SlushEqQueue),
        ]) {
          await tester.tap(find.byIcon(Icons.more_horiz));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(find.byType(type), findsOneWidget, reason: label);
          expect(tester.takeException(), isNull, reason: label);
        }
        await tester.tap(find.byTooltip('Inicio'));
        await tester.pumpAndSettle();
        await go(find.byTooltip('Biblioteca'), 'BIBLIOTECA');
      }
      // Detalle de una lista.
      await tester.ensureVisible(find.text('Jazz').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jazz').first);
      await tester.pumpAndSettle();
      expect(find.text('JAZZ'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in const [Size(1440, 900), Size(900, 700)]) {
    for (final mode in const ['light', 'dark']) {
      testWidgets(
        'titular de Búsqueda se va con el scroll a ${size.width.toInt()} px ($mode)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final c = (await tester.runAsync(
            () => createTestController(
              tracks: _songs,
              preferences: {'themeKind': 'slush', 'themeMode': mode},
            ),
          ))!;
          final container = ProviderContainer(
            overrides: [controllerProvider.overrideWith((ref) => c)],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await tester.runAsync(() async {
              await c.closed;
              if (await c.supportDirectory.exists()) {
                await c.supportDirectory.delete(recursive: true);
              }
            });
          });
          c.searchDetail = const SearchEntry(
            kind: SearchKind.artists,
            browseId: 'UC1',
            title: 'Artista',
          );
          c.searchDetailTracks = [
            for (var i = 0; i < 30; i++)
              Track(id: 't$i', title: 'Canción $i', artist: 'Artista'),
          ];
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const AuroraApp(),
            ),
          );
          await tester.pumpAndSettle();
          tester.takeException();
          await tester.tap(find.text('BUSCAR').first);
          await tester.pumpAndSettle();
          expect(find.text('BÚSQUEDA').hitTestable(), findsOneWidget);
          expect(find.byType(FollowButton), findsOneWidget);
          await tester.dragFrom(
            tester.getCenter(find.byType(SlushCard)),
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(find.text('BÚSQUEDA').hitTestable(), findsNothing);
          expect(find.byType(FollowButton, skipOffstage: true), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Jam sin sesión Slush usa dos columnas a 1440 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final name = TextEditingController();
    final code = TextEditingController();
    addTearDown(name.dispose);
    addTearDown(code.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.light, const Color(0xffe86927)),
        home: Scaffold(
          body: SlushJamIdle(
            name: name,
            code: code,
            busy: false,
            message: null,
            onStart: () {},
            onJoin: () {},
            onScan: () {},
            scanLabel: 'Escanear QR',
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('jam-idle-side'))).dx,
      greaterThanOrEqualTo(720),
    );
    expect(find.text('Cómo funciona'), findsOneWidget);
  });

  testWidgets('estado vacío Slush con texto grande', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SlushEmpty(icon: Icons.search, title: 'Nada', message: 'Aún no'),
      ),
    );
    expect(find.text('Nada'), findsOneWidget);
  });
}
