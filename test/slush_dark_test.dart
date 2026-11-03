import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/slush/slush_dj.dart';
import 'package:aurora_music/ui/slush/slush_eq_queue.dart';
import 'package:aurora_music/ui/slush/slush_jam.dart';
import 'package:aurora_music/ui/mini_player/slush_mini_player_v2.dart';
import 'package:aurora_music/ui/slush/slush_pages.dart';
import 'package:aurora_music/ui/slush/slush_player.dart';
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
    testWidgets('Slush oscuro pinta las pantallas a ${size.width.toInt()} px', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: _songs,
          preferences: const {'themeKind': 'slush', 'themeMode': 'dark'},
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

      void dark(String screen) {
        final err = tester.takeException();
        if (err is FlutterError) debugPrint(err.toStringDeep());
        expect(err, isNull, reason: screen);
        final scaffold = find.byType(Scaffold).first;
        final bg =
            tester.widget<Scaffold>(scaffold).backgroundColor ??
            Theme.of(tester.element(scaffold)).scaffoldBackgroundColor;
        expect(Theme.of(tester.element(scaffold)).brightness, Brightness.dark);
        expect(bg.computeLuminance(), lessThan(.2), reason: screen);
      }

      Future<void> go(Finder tap, Type screen) async {
        await tester.tap(tap.first);
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsWidgets, reason: '$screen');
        dark('$screen');
      }

      // Solo el Inicio tolera un desborde de 2 px (fuentes de test); cualquier otro error falla.
      final inicio = tester.takeException();
      expect(
        inicio == null || inicio.toString().contains('overflowed'),
        isTrue,
        reason: 'Inicio: $inicio',
      );
      dark('Inicio');
      if (wide) {
        await go(find.text('BUSCAR'), SlushPage);
        await go(find.text('DJ'), SlushDj);
        await go(find.text('JAM'), SlushJamIdle);
        // Sin barra de transporte: el mini abre Vinilo y de ahí se llega al EQ.
        await go(
          find.descendant(
            of: find.byType(SlushMiniPlayer),
            matching: find.text('Luz de luna'),
          ),
          SlushPlayerScreen,
        );
        await go(find.text('ECUALIZADOR'), SlushEqQueue);
        double lum(Color a, Color b) {
          final l1 = a.computeLuminance(), l2 = b.computeLuminance();
          return (l1 > l2 ? l1 + .05 : l2 + .05) /
              (l1 > l2 ? l2 + .05 : l1 + .05);
        }

        final ctx = tester.element(find.byType(SlushEqQueue));
        final cola = tester.widget<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && w.data == 'COLA' && w.style?.fontSize == 52,
          ),
        );
        expect(
          lum(cola.style!.color!, ctx.slush.paper),
          greaterThanOrEqualTo(4.5),
        );
        final sw = tester.widgetList<Switch>(find.byType(Switch));
        for (final s in sw.where((s) => !s.value)) {
          final st = <WidgetState>{};
          final thumb =
              s.thumbColor?.resolve(st) ??
              Theme.of(ctx).switchTheme.thumbColor?.resolve(st);
          final track = s.trackColor?.resolve(st);
          if (thumb != null && track != null) {
            expect(lum(thumb, track), greaterThanOrEqualTo(3));
          }
        }
        await go(find.text('VINILO'), SlushPlayerScreen);
      } else {
        await go(find.byTooltip('Buscar'), SlushPage);
        await go(find.byTooltip('DJ'), SlushDj);
        await go(find.byTooltip('Jam'), SlushJamIdle);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await go(find.text('Ecualizador').last, SlushEqQueue);
        await go(find.byTooltip('Inicio'), AuroraShell);
        await go(
          find.descendant(
            of: find.byType(SlushMiniPlayer),
            matching: find.text('Luz de luna'),
          ),
          SlushPlayerScreen,
        );
      }
    });
  }
}
