import 'package:aurora_music/ui/mini_player/mini_player_gestures.dart';
import 'package:aurora_music/ui/mini_player/mini_player_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

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

const _bar = ValueKey('bar');
const _body = ValueKey('body');

Widget _app(
  _Calls calls, {
  bool reduced = false,
  bool hasNext = true,
  bool hasPrevious = true,
  bool list = false,
  ScrollController? scroll,
}) {
  final bar = MiniPlayerGestures(
    key: _bar,
    actions: calls.actions,
    hasNext: hasNext,
    hasPrevious: hasPrevious,
    child: SizedBox(
      key: _body,
      height: 64,
      child: Row(
        children: [
          const Expanded(child: Text('Artista · Título')),
          IconButton(
            tooltip: 'Reproducir',
            onPressed: calls.actions.togglePlay,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    ),
  );
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
      child: child!,
    ),
    home: Scaffold(
      body: Column(
        children: [
          if (list)
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  for (var i = 0; i < 40; i++)
                    SizedBox(height: 56, child: Text('fila $i')),
                ],
              ),
            )
          else
            const Spacer(),
          SizedBox(width: 360, child: bar),
        ],
      ),
    ),
  );
}

// Zona de la barra sin botón.
Offset _spot(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(_body)) + const Offset(40, 32);

void main() {
  testWidgets('toque abre el reproductor; el botón no lo abre', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.tapAt(_spot(tester));
    expect(calls.open, 1);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    expect(calls.play, 1);
    expect(calls.open, 1);
  });

  testWidgets('arrastre vertical: rápido o largo abre, corto no', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.dragFrom(_spot(tester), const Offset(0, -24));
    await tester.pumpAndSettle();
    expect(calls.open, 0, reason: 'bajo el umbral');
    await tester.dragFrom(_spot(tester), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(calls.open, 1);
    await tester.timedDragFrom(
      _spot(tester),
      const Offset(0, -50),
      const Duration(milliseconds: 40),
    );
    await tester.pumpAndSettle();
    expect(calls.open, 2, reason: 'un gesto rápido basta');
    await tester.dragFrom(_spot(tester), const Offset(0, 90));
    await tester.pumpAndSettle();
    expect(calls.open, 2, reason: 'hacia abajo no abre');
  });

  testWidgets('deslizar a los lados salta de pista según umbral y velocidad', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    await tester.dragFrom(_spot(tester), const Offset(-30, 0));
    await tester.pumpAndSettle();
    expect((calls.next, calls.previous), (0, 0));
    await tester.dragFrom(_spot(tester), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect((calls.next, calls.previous), (1, 0));
    await tester.dragFrom(_spot(tester), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect((calls.next, calls.previous), (1, 1));
    await tester.timedDragFrom(
      _spot(tester),
      const Offset(-50, 0),
      const Duration(milliseconds: 40),
    );
    await tester.pumpAndSettle();
    expect((calls.next, calls.previous), (2, 1));
    expect(calls.open, 0);
  });

  testWidgets('sin siguiente/anterior el gesto rebota sin confirmar', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls, hasNext: false, hasPrevious: false));
    await tester.dragFrom(_spot(tester), const Offset(-120, 0));
    await tester.dragFrom(_spot(tester), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect((calls.next, calls.previous), (0, 0));
    expect(
      tester.getTopLeft(find.byKey(_body)).dx,
      closeTo(tester.getTopLeft(find.byKey(_bar)).dx, .01),
    );
  });

  testWidgets('la barra sigue al dedo y vuelve al soltar', (tester) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    final rest = tester.getTopLeft(find.byKey(_body));
    final gesture = await tester.startGesture(_spot(tester));
    await gesture.moveBy(const Offset(-20, 0)); // cruza el umbral de arrastre
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    final dx = tester.getTopLeft(find.byKey(_body)).dx - rest.dx;
    expect(dx, lessThan(-20), reason: 'sigue al dedo');
    expect(dx, greaterThan(-70), reason: 'con resistencia: menos que el dedo');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      (tester.getTopLeft(find.byKey(_body)) - rest).distance,
      lessThan(.01),
    );
  });

  testWidgets('movimiento reducido: mismos umbrales, sin seguimiento', (
    tester,
  ) async {
    final calls = _Calls();
    await tester.pumpWidget(_app(calls, reduced: true));
    final rest = tester.getTopLeft(find.byKey(_body));
    final gesture = await tester.startGesture(_spot(tester));
    await gesture.moveBy(const Offset(-20, 0));
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_body)), rest);
    await gesture.up();
    await tester.pump();
    expect(calls.next, 1);
    await tester.dragFrom(_spot(tester), const Offset(0, -80));
    await tester.pump();
    expect(calls.open, 1);
    expect(tester.getTopLeft(find.byKey(_body)), rest);
  });

  testWidgets('no roba el scroll vertical de la página', (tester) async {
    final calls = _Calls();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_app(calls, list: true, scroll: scroll));
    await tester.drag(find.text('fila 1'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect((calls.open, calls.next, calls.previous), (0, 0, 0));
  });

  testWidgets('semántica: un nodo con acciones y botones propios', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final calls = _Calls();
    await tester.pumpWidget(_app(calls));
    final node = tester.getSemantics(
      find.bySemanticsLabel(RegExp('Mini reproductor')),
    );
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.customSemanticsActionIds, hasLength(3));
    var buttons = 0;
    node.visitChildren((child) {
      if (child.getSemanticsData().flagsCollection.isButton) buttons++;
      return true;
    });
    expect(buttons, 1, reason: 'el botón conserva su propio nodo');
    tester.semantics.tap(find.semantics.byLabel('Mini reproductor'));
    expect(calls.open, 1);
    handle.dispose();
  });
}
