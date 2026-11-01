import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(id: 'song', title: 'Canción base', artist: 'Artista');

JamController _jam(AppController app) {
  final jam = JamController(app: app);
  final s = jam.service;
  s.connection = JamConnection.hosting;
  s.participantId = 'host';
  s.participants = [
    const JamParticipant(
      id: 'host',
      name: 'Lucía',
      role: JamRole.host,
      permissions: JamPermissions.all,
    ),
    const JamParticipant(id: 'guest', name: 'Beto'),
  ];
  s.mode = JamMode.synchronized;
  return jam;
}

void main() {
  // Regresión: con una Jam activa la barra de Slush (píldora) recortaba el
  // tiempo por la izquierda y desbordaba la fila de acciones.
  for (final dark in [false, true]) {
    for (final (width, scale) in [
      (900.0, 1.0),
      (1152.0, 1.0),
      (1440.0, 1.0),
      (1700.0, 1.0),
      (900.0, 2.0),
      (1440.0, 2.0),
      (390.0, 1.0),
    ]) {
      testWidgets(
        'transporte con Jam en Slush ${dark ? 'oscuro' : 'claro'} '
        '${width.round()} px x$scale: sin desbordes y dentro de la barra',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final app = (await tester.runAsync(
            () => createTestController(tracks: [_song]),
          ))!;
          addTearDown(() => closeTestController(app));
          await tester.runAsync(() => app.playTrack(_song));
          final jam = _jam(app);
          await tester.pumpWidget(
            MaterialApp(
              theme: slushTheme(
                dark ? Brightness.dark : Brightness.light,
                Slush.yellow,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: StudioTransport(
                    controller: app,
                    jam: jam,
                    onLyrics: () {},
                    onVinyl: () {},
                    onQueue: () {},
                    onOpenPlayer: () {},
                    onJam: () {},
                    onStartJam: () {},
                  ),
                ),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          // La píldora redondeada recorta lo que quede en sus esquinas: tiempos
          // y botones deben caber DENTRO de la forma, no solo del rectángulo.
          final container = find
              .descendant(
                of: find.byType(StudioTransport),
                matching: find.byType(Container),
              )
              .first;
          final box = tester.getRect(container);
          final deco =
              tester.widget<Container>(container).decoration! as BoxDecoration;
          final radius = deco.borderRadius!.resolve(TextDirection.ltr).topLeft;
          final shape = RRect.fromRectAndRadius(
            box,
            Radius.circular(radius.x.clamp(0, box.shortestSide / 2)),
          );
          final inside = [
            ...find.textContaining(RegExp(r'^\d+:\d\d$')).evaluate(),
            ...find.byType(IconButton).evaluate(),
          ];
          expect(inside, isNotEmpty);
          for (final e in inside) {
            final r = tester.getRect(find.byWidget(e.widget));
            for (final p in [
              r.topLeft,
              r.topRight,
              r.bottomLeft,
              r.bottomRight,
            ]) {
              expect(
                shape.contains(p),
                isTrue,
                reason: '${e.widget.runtimeType} $r fuera de la píldora $box',
              );
            }
          }
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
