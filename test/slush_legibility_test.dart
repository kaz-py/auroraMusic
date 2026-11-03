import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/mini_player/slush_mini_player_v2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'ui_guard/legibility_scan.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
  Track(id: 'c', title: 'Noche', artist: 'Otro'),
];


void main() {
  for (final mode in const ['light', 'dark']) {
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      final wide = size.width > 600;
      testWidgets(
        'Slush $mode legible a ${size.width.toInt()} px',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final c = (await tester.runAsync(
            () => createTestController(
              tracks: _songs,
              playlists: const [
                MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
              ],
              preferences: {'themeKind': 'slush', 'themeMode': mode},
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

          final rows = <String>[];
          void audit(String screen) {
            // Desbordes de fuentes de test no son asunto de esta prueba.
            tester.takeException();
            final scaffold = find.byType(Scaffold).first;
            final bg =
                tester.widget<Scaffold>(scaffold).backgroundColor ??
                Theme.of(tester.element(scaffold)).scaffoldBackgroundColor;
            final hits = scanLegibility(tester.binding.renderViews.first, bg, size);
            final seen = <String>{};
            for (final h in hits) {
              final row =
                  '$screen | $mode | ${size.width.toInt()} | "${h.text}" | '
                  'fg ${hexColor(h.fg)} | bg ${hexColor(h.bg)} | ${h.ratio.toStringAsFixed(2)}';
              if (seen.add(row)) rows.add(row);
            }
          }

          Future<void> go(Finder tap, String screen) async {
            expect(tap, findsWidgets, reason: screen);
            await tester.tap(tap.first);
            await tester.pumpAndSettle();
            audit(screen);
          }

          Future<void> more(String label, String screen) async {
            await tester.tap(find.byIcon(Icons.more_horiz).first);
            await tester.pumpAndSettle();
            await go(find.text(label).last, screen);
          }

          audit('Inicio');
          if (wide) {
            await go(find.text('BUSCAR'), 'Busqueda');
            await go(find.text('BIBLIOTECA'), 'Biblioteca');
            await go(find.text('DJ'), 'DJ');
            await go(find.text('JAM'), 'Jam');
            // Sin barra de transporte: el mini abre Vinilo y de ahí se llega al EQ.
            await go(
              find.descendant(
                of: find.byType(SlushMiniPlayer),
                matching: find.text('Luz de luna'),
              ),
              'Vinilo',
            );
            await go(find.text('ECUALIZADOR'), 'EQ+Cola');
            await go(find.byTooltip('Ajustes'), 'Ajustes');
            await go(find.text('DESCARGAS'), 'Descargas');
            await go(find.text('ARTISTAS'), 'Artistas');
            await go(find.text('AMIGOS'), 'Amigos');
          } else {
            await go(find.byTooltip('Buscar'), 'Busqueda');
            await go(find.byTooltip('Biblioteca'), 'Biblioteca');
            await go(find.byTooltip('DJ'), 'DJ');
            await go(find.byTooltip('Jam'), 'Jam');
            await more('Ecualizador', 'EQ+Cola');
            await more('Modo Vinilo', 'Vinilo');
            await go(find.byTooltip('Inicio'), 'Inicio2');
            await go(find.byIcon(Icons.dark_mode_outlined), 'Ajustes');
            await more('Descargas', 'Descargas');
            await more('Artistas', 'Artistas');
            await more('Amigos', 'Amigos');
          }

          debugPrint(
            '--- LEGIBILIDAD ${mode.toUpperCase()} ${size.width.toInt()} ---\n'
            '${rows.isEmpty ? '(sin ofensores)' : rows.join('\n')}',
          );
          expect(rows, isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }
}
