import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_eq_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track _t(int i) => Track(
  id: 't$i',
  title: 'Tema $i',
  artist: 'Artista $i',
  duration: const Duration(minutes: 3),
);

Future<AppController> _boot(
  WidgetTester tester, {
  required Size size,
  Brightness brightness = Brightness.light,
  int count = 40,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final tracks = [for (var i = 0; i < count; i++) _t(i)];
  final app = (await tester.runAsync(
    () => createTestController(tracks: tracks, audio: FakeAudio()),
  ))!;
  addTearDown(() => tester.runAsync(() => closeTestController(app)));
  app.queue = [...tracks];
  await tester.runAsync(() => app.playQueueAt(0));
  await tester.pumpWidget(
    MaterialApp(
      theme: slushTheme(brightness, Colors.blue),
      home: Scaffold(
        body: SlushEqQueue(
          controller: app,
          onNavigate: (_) {},
          showQueueTab: true,
        ),
      ),
    ),
  );
  await tester.pump();
  return app;
}

Future<void> _next(WidgetTester tester, AppController app, [int n = 1]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(() => app.next());
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// La fila de [title] está construida y dentro del área visible de la lista.
bool _inView(WidgetTester tester, String title) {
  final row = find.text(title);
  if (row.evaluate().isEmpty) return false;
  final list = tester.getRect(find.byType(ReorderableListView));
  final r = tester.getRect(row.first);
  return r.top >= list.top && r.bottom <= list.bottom;
}

void main() {
  for (final (name, size) in const [
    ('escritorio', Size(1400, 1000)),
    ('móvil', Size(400, 800)),
  ]) {
    group('cola Slush en vivo ($name)', () {
      testWidgets('la fila activa, SONANDO y el scroll siguen a la canción', (
        tester,
      ) async {
        final app = await _boot(tester, size: size);
        expect(find.text('SONANDO'), findsOneWidget);
        await _next(tester, app, 25);
        expect(app.queueIndex, 25);
        // Lo escuchado queda plegado: la actual arranca arriba.
        expect(find.text('Tema 24'), findsNothing);
        expect(find.text('ESCUCHADAS · 25'), findsOneWidget);
        expect(find.text('A CONTINUACIÓN'), findsOneWidget);
        expect(find.text('SONANDO'), findsOneWidget);
        expect(_inView(tester, 'Tema 25'), isTrue);
        final dy = tester.getCenter(find.text('SONANDO')).dy;
        expect(
          (dy - tester.getCenter(find.text('Tema 25')).dy).abs(),
          lessThan(40),
        );
        // Desplegadas, la lista sigue mostrando la actual.
        await tester.tap(find.text('ESCUCHADAS · 25'));
        await tester.pumpAndSettle();
        expect(_inView(tester, 'Tema 25'), isTrue);
        await _next(tester, app, 10);
        expect(app.queueIndex, 35);
        expect(_inView(tester, 'Tema 35'), isTrue);
        expect(find.text('SONANDO'), findsOneWidget);
        // También hacia atrás.
        await tester.runAsync(() => app.previous());
        await tester.pumpAndSettle();
        expect(_inView(tester, 'Tema 34'), isTrue);
        expect(find.text('IR A LA ACTUAL'), findsNothing);
      });

      testWidgets('si el usuario se aleja no se pelea con su scroll', (
        tester,
      ) async {
        final app = await _boot(tester, size: size);
        await _next(tester, app, 3);
        await tester.tap(find.text('ESCUCHADAS · 3'));
        await tester.pumpAndSettle();
        ScrollPosition position() => tester
            .state<ScrollableState>(
              find.descendant(
                of: find.byType(ReorderableListView),
                matching: find.byType(Scrollable),
              ),
            )
            .position;
        await tester.drag(
          find.byType(ReorderableListView),
          const Offset(0, -900),
        );
        await tester.pumpAndSettle();
        expect(_inView(tester, 'Tema 3'), isFalse);
        expect(find.text('IR A LA ACTUAL'), findsOneWidget);
        final before = position().pixels;
        await _next(tester, app);
        expect(position().pixels, before);
        expect(find.text('IR A LA ACTUAL'), findsOneWidget);
        await tester.tap(find.text('IR A LA ACTUAL'));
        await tester.pumpAndSettle();
        expect(_inView(tester, 'Tema 4'), isTrue);
        expect(find.text('IR A LA ACTUAL'), findsNothing);
        // Tras volver, la lista vuelve a seguir la canción.
        await _next(tester, app, 20);
        expect(_inView(tester, 'Tema 24'), isTrue);
      });

      testWidgets('cabecera con conteo y tiempo restante se actualiza', (
        tester,
      ) async {
        final app = await _boot(tester, size: size, count: 10);
        // 9 por delante, 3 min cada una + lo que queda de la actual.
        expect(find.textContaining('9 A CONTINUACIÓN'), findsOneWidget);
        await _next(tester, app, 2);
        expect(find.textContaining('7 A CONTINUACIÓN'), findsOneWidget);
        await tester.runAsync(
          () => app.addToQueue(
            const Track(id: 'x', title: 'Añadida', artist: 'Z'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('8 A CONTINUACIÓN'), findsOneWidget);
        await tester.runAsync(() => app.removeFromQueue(app.queue.length - 1));
        await tester.pumpAndSettle();
        expect(find.textContaining('7 A CONTINUACIÓN'), findsOneWidget);
      });
    });
  }

  testWidgets('con lo escuchado plegado, reordenar usa el índice real', (
    tester,
  ) async {
    final app = await _boot(tester, size: const Size(1400, 1000));
    await _next(tester, app, 5);
    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // Fila 0 de la lista = pista 5 de la cola (0..4 están plegadas).
    list.onReorder(0, 2);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(app.queue[6].id, 't5');
    expect(app.queue[5].id, 't6');
    expect(app.queueIndex, 6);
    expect(find.text('SONANDO'), findsOneWidget);
  });

  testWidgets('en móvil la pestaña COLA va antes que el ecualizador', (
    tester,
  ) async {
    await _boot(tester, size: const Size(400, 800));
    expect(
      tester.getTopLeft(find.text('Tema 0')).dy,
      lessThan(tester.getTopLeft(find.text('EQ')).dy),
    );
  });

  testWidgets('modo oscuro: SONANDO y pastilla se pintan', (tester) async {
    final app = await _boot(
      tester,
      size: const Size(1400, 1000),
      brightness: Brightness.dark,
    );
    await _next(tester, app, 25);
    expect(find.text('SONANDO'), findsOneWidget);
    expect(_inView(tester, 'Tema 25'), isTrue);
  });
}
