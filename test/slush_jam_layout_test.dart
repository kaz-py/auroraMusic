import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/jam/jam_flows.dart';
import 'package:aurora_music/ui/jam/jam_qr_code.dart';
import 'package:aurora_music/ui/jam/jam_session_panel.dart';
import 'package:aurora_music/ui/slush/slush_jam.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

JamTrack _jt(String id, String title) =>
    JamTrack.fromTrack(Track(id: id, title: title, artist: 'Artista $id'));

JamController _jam(AppController app, {required bool host}) {
  final jam = JamController(app: app);
  final s = jam.service;
  s.connection = host ? JamConnection.hosting : JamConnection.connected;
  s.participantId = host ? 'host' : 'guest';
  s.invite = JamInvite.remote(
    code: 'K7M2QX9A',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );
  s.participants = [
    const JamParticipant(
      id: 'host',
      name: 'Lucía con un nombre larguísimo que no cabe en una línea',
      role: JamRole.host,
      permissions: JamPermissions.all,
    ),
    const JamParticipant(id: 'guest', name: 'Beto', muted: true),
    const JamParticipant(id: 'g2', name: 'Ana', role: JamRole.coHost),
  ];
  s.mode = JamMode.synchronized;
  s.queue = [
    JamQueueEntry(
      id: 'q1',
      track: _jt('a', 'Un tema con un título larguísimo que no cabe'),
      addedBy: 'host',
    ),
    JamQueueEntry(
      id: 'q2',
      track: _jt('b', 'Tema dos'),
      addedBy: 'guest',
      suggestedFor: 'guest',
    ),
  ];
  s.playback = const JamPlayback(
    sequence: 1,
    serverTimeMs: 0,
    entryId: 'q1',
    isPlaying: true,
  );
  return jam;
}

Widget _app(Widget body, Brightness b, double scale) => MaterialApp(
  theme: slushTheme(b, Slush.yellow),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

void main() {
  panelTests();
  const widths = [360.0, 412.0, 600.0, 900.0, 1440.0, 1920.0];
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final w in widths) {
        final tag =
            'Jam Slush ${dark ? 'oscuro' : 'claro'} w=${w.toInt()} x$scale';
        testWidgets('$tag activa: sin desbordes y con código tabular', (
          tester,
        ) async {
          tester.view.physicalSize = Size(w, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final app = (await tester.runAsync(() => createTestController()))!;
          addTearDown(() => closeTestController(app));
          final jam = _jam(app, host: true);
          await tester.pumpWidget(
            _app(
              SlushJamActive(controller: jam),
              dark ? Brightness.dark : Brightness.light,
              scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('ESCANEA PARA UNIRTE'), findsOneWidget);
          final code = tester.widget<SelectableText>(
            find.byWidgetPredicate(
              (w) => w is SelectableText && w.data == 'K7M2QX9A',
            ),
          );
          expect(
            code.style?.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
          expect(find.byType(JamQrCode), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets('$tag sin sesión: sin desbordes', (tester) async {
          tester.view.physicalSize = Size(w, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final name = TextEditingController();
          final code = TextEditingController();
          addTearDown(name.dispose);
          addTearDown(code.dispose);
          await tester.pumpWidget(
            _app(
              SlushJamIdle(
                name: name,
                code: code,
                busy: false,
                message: 'Algo salió mal con la Jam',
                onStart: () {},
                onJoin: () {},
                onScan: () {},
                scanLabel: 'Importar imagen QR',
              ),
              dark ? Brightness.dark : Brightness.light,
              scale,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('EMPIEZA UNA JAM'), findsOneWidget);
        });
      }
    }
  }

  testWidgets('Jam activa en Slush: dos columnas desde 900 px', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = (await tester.runAsync(() => createTestController()))!;
    addTearDown(() => closeTestController(app));
    final jam = _jam(app, host: true);
    await tester.pumpWidget(
      _app(SlushJamActive(controller: jam), Brightness.light, 1),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Cola compartida')).dx,
      greaterThan(400),
    );
    tester.view.physicalSize = const Size(899, 900);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Cola compartida')).dx, lessThan(100));
    await tester.pumpWidget(const SizedBox());
  });
}

void panelTests() {
  for (final dark in [false, true]) {
    for (final w in [360.0, 900.0]) {
      testWidgets(
        'Panel e invitación de la Jam en Slush ${dark ? 'oscuro' : 'claro'} '
        'w=${w.toInt()} x2: sin desbordes',
        (tester) async {
          tester.view.physicalSize = Size(w, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final app = (await tester.runAsync(() => createTestController()))!;
          addTearDown(() => closeTestController(app));
          final jam = _jam(app, host: true);
          await tester.pumpWidget(
            _app(
              JamSessionPanel(controller: jam),
              dark ? Brightness.dark : Brightness.light,
              2,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final list = find.byType(Scrollable).first;
          await tester.scrollUntilVisible(
            find.textContaining('Participantes'),
            300,
            scrollable: list,
          );
          await tester.scrollUntilVisible(
            find.text('Beto'),
            300,
            scrollable: list,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            _app(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => showJamInviteSheet(context, jam),
                  child: const Text('abrir'),
                ),
              ),
              dark ? Brightness.dark : Brightness.light,
              2,
            ),
          );
          await tester.tap(find.text('abrir'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Invitar a la Jam'), findsOneWidget);
          expect(find.byType(JamQrCode), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
