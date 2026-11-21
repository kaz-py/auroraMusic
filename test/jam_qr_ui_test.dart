import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zxing2/qrcode.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/jam/jam_qr.dart';
import 'package:aurora_music/ui/jam/jam_page.dart';
import 'package:aurora_music/ui/jam/jam_qr_code.dart';
import 'support/fakes.dart';

void main() {
  test(
    'Dart QR encoder and decoder roundtrip invitation without another image package',
    () {
      // Many random invites: zxing2's detector used to miss ~2% of them.
      for (var n = 0; n < 400; n++) {
        final invite = JamInvite(
          address: '192.168.1.2',
          port: 12345,
          sessionId: jamRandomSecret(16),
          accessToken: jamRandomSecret(),
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
        final encoded = invite.encode();
        final matrix = Encoder.encode(encoded, ErrorCorrectionLevel.m).matrix!;
        const scale = 4;
        final side = (matrix.width + 8) * scale;
        final pixels = Uint8List(side * side * 4)
          ..fillRange(0, side * side * 4, 255);
        for (var y = 0; y < matrix.height; y++) {
          for (var x = 0; x < matrix.width; x++) {
            if (matrix.get(x, y) == 1) {
              for (var dy = 0; dy < scale; dy++) {
                for (var dx = 0; dx < scale; dx++) {
                  final i =
                      (((y + 4) * scale + dy) * side + (x + 4) * scale + dx) *
                      4;
                  pixels[i] = 0;
                  pixels[i + 1] = 0;
                  pixels[i + 2] = 0;
                }
              }
            }
          }
        }
        // Compare as a boolean so a failing assertion cannot print invitation credentials.
        expect(decodeJamQrPixels(pixels, side, side) == encoded, isTrue);
      }
    },
  );
  test('QR decoder validates allocation and malformed image bytes', () async {
    expect(
      () => decodeJamQrPixels(Uint8List(4), 0, 1),
      throwsA(isA<JamException>()),
    );
    expect(
      () => decodeJamQrPixels(Uint8List(4), 5000, 5000),
      throwsA(isA<JamException>()),
    );
    await expectLater(
      decodeJamQrImage(Uint8List(jamMaxImageBytes + 1)),
      throwsA(isA<JamException>()),
    );
    await expectLater(
      decodeJamQrImage(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<JamException>()),
    );
  });
  testWidgets('painted QR decodes from its actual Flutter image', (
    tester,
  ) async {
    final invite = JamInvite(
      address: '192.168.1.2',
      port: 12345,
      sessionId: jamRandomSecret(16),
      accessToken: jamRandomSecret(),
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: JamQrCode(data: invite.encode()),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final decoded = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return decodeJamQrImage(bytes!.buffer.asUint8List());
    });
    expect(decoded == invite.encode(), isTrue);
  });
  testWidgets(
    'Jam view creates no controller networking or camera until user activation',
    (tester) async {
      final app = (await tester.runAsync(createTestController))!;
      addTearDown(() => closeTestController(app));
      var created = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: JamPage(controller: app, onControllerReady: (_) => created++),
          ),
        ),
      );
      expect(created, 0);
      expect(find.text('Iniciar una Jam'), findsOneWidget);
      expect(app.jamPlaybackActive, isFalse);
      await tester.tap(find.text('Unirme'));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(
        find.text('El QR no contiene una Jam local válida o ya venció.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'narrow layout and enlarged text keep real shared queue actions accessible',
    (tester) async {
      final app = (await tester.runAsync(
        () => createTestController(
          tracks: [
            const Track(id: 'song', title: 'Library song', artist: 'Artist'),
          ],
        ),
      ))!;
      addTearDown(() => closeTestController(app));
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      JamController? jam;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: JamPage(
              controller: app,
              onControllerReady: (created) {
                jam = created;
                created.service.connection = JamConnection.hosting;
                created.service.participants = [
                  const JamParticipant(
                    id: 'host',
                    name: 'Anfitrión',
                    permissions: JamPermissions(
                      skip: true,
                      reorder: true,
                      remove: true,
                    ),
                  ),
                ];
                created.service.invite = JamInvite(
                  address: '192.168.1.2',
                  port: 12345,
                  sessionId: jamRandomSecret(16),
                  accessToken: jamRandomSecret(),
                  expiresAt: DateTime.now().add(const Duration(hours: 1)),
                );
                created.service.queue = [
                  JamQueueEntry(
                    id: 'entry',
                    track: JamTrack.fromTrack(
                      const Track(
                        id: 'fixture',
                        title: 'Una canción de la biblioteca compartida',
                        artist: 'Artista de la sesión',
                      ),
                    ),
                    addedBy: 'host',
                  ),
                ];
              },
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Unirme'));
      await tester.tap(find.text('Unirme'));
      await tester.pump();
      expect(jam, isNotNull);
      await tester.scrollUntilVisible(find.text('Cola · 1'), 200);
      expect(find.text('Cola · 1'), findsOneWidget);
      // La cola es perezosa: la fila se construye al acercarse.
      await tester.scrollUntilVisible(
        find.textContaining('Añadida por Anfitrión'),
        200,
      );
      expect(find.textContaining('Añadida por Anfitrión'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
