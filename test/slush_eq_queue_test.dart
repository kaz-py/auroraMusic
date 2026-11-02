import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_eq_queue.dart';
import 'package:aurora_music/ui/slush/slush_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(id: 's', title: 'Luz de luna', artist: 'Mare Sol');
final _many = [
  for (var i = 0; i < 30; i++)
    Track(id: 't$i', title: 'Tema $i', artist: 'Artista $i'),
];

Future<AppController> _app(WidgetTester tester, List<Track> queue) async {
  final app = (await tester.runAsync(
    () => createTestController(tracks: queue, audio: FakeAudio()),
  ))!;
  addTearDown(() => tester.runAsync(() => closeTestController(app)));
  app.queue = queue;
  return app;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required Size size,
  double scale = 1,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: slushTheme(brightness, Colors.blue),
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pump();
}

int _verticalScrollables(WidgetTester tester) => tester
    .widgetList<Scrollable>(find.byType(Scrollable))
    .where((s) => s.axis == Axis.vertical)
    .length;

void main() {
  testWidgets('pantalla Slush EQ + Cola se construye y el temporizador actúa', (
    tester,
  ) async {
    final app = await _app(tester, [_song]);
    await _pump(
      tester,
      SlushEqQueue(controller: app, onNavigate: (_) {}),
      size: const Size(1400, 1000),
    );
    expect(find.text('EQ'), findsOneWidget);
    expect(find.text('COLA'), findsWidgets);
    await tester.ensureVisible(find.text('30'));
    await tester.tap(find.text('30'));
    await tester.pump();
    expect(app.sleepRemaining, isNotNull);
    app.setSleepTimer(null);
  });

  for (final dark in [false, true]) {
    testWidgets('cola primero en ancho: lista a alto completo (dark=$dark)', (
      tester,
    ) async {
      final app = await _app(tester, _many);
      await _pump(
        tester,
        SlushEqQueue(controller: app, onNavigate: (_) {}, queueFirst: true),
        size: const Size(1400, 1000),
        brightness: dark ? Brightness.dark : Brightness.light,
      );
      expect(tester.takeException(), isNull);
      final list = tester.getSize(find.byType(ReorderableListView));
      expect(list.height, greaterThan(400));
      expect(find.text('Tema 0'), findsOneWidget);
    });
  }

  for (final w in [360.0, 390.0, 412.0]) {
    testWidgets('cola primero en estrecho $w: un solo scroll, sin overflow', (
      tester,
    ) async {
      final app = await _app(tester, _many);
      await _pump(
        tester,
        SlushEqQueue(controller: app, onNavigate: (_) {}, queueFirst: true),
        size: Size(w, 780),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      // Con texto 2x el panel entero se desplaza (1) y la lista conserva su
      // propio scroll (2): nunca más de dos y sin overflow.
      expect(_verticalScrollables(tester), lessThanOrEqualTo(2));
      expect(find.text('No hay canciones en la cola'), findsNothing);
    });

    testWidgets('EQ en estrecho $w: sin overflow con texto grande', (
      tester,
    ) async {
      final app = await _app(tester, [_song]);
      await _pump(
        tester,
        SlushEqQueue(controller: app, onNavigate: (_) {}),
        size: Size(w, 780),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(ReorderableListView), findsNothing);
    });
  }

  testWidgets('chip «A continuación» abre la cola y muestra cuántas faltan', (
    tester,
  ) async {
    final app = await _app(tester, [_song, ..._many.take(13)]);
    app.queueIndex = 0;
    final opened = <int>[];
    await _pump(
      tester,
      SlushPlayerScreen(
        controller: app,
        track: _song,
        compact: false,
        recordBuilder: (_) => const SizedBox.shrink(),
        onToggleCassette: () {},
        cassette: false,
        onSection: opened.add,
      ),
      size: const Size(1400, 1000),
    );
    expect(find.text('A CONTINUACIÓN'), findsOneWidget);
    expect(find.byKey(const ValueKey('next-up-remaining')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('next-up-remaining'))).data,
      '+13',
    );
    await tester.tap(find.text('A CONTINUACIÓN'));
    expect(opened, [5]);
    expect(app.queueIndex, 0);
  });
}
