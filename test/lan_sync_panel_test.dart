import 'package:aurora_music/account/lan_sync.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/ui/jam/jam_qr_code.dart';
import 'package:aurora_music/ui/lan_sync_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('Enviar muestra un QR con un código válido de red local', (
    tester,
  ) async {
    final origin = (await tester.runAsync(createTestController))!;
    final target = (await tester.runAsync(createTestController))!;
    addTearDown(() => closeTestController(origin));
    addTearDown(() => closeTestController(target));
    await tester.runAsync(() async {
      await origin.database.saveTrack(
        const Track(id: 'a', title: 'A', artist: 'X'),
      );
      await origin.database.setFavorite('a', true);
    });

    Future<void> mount(WidgetTester t, panelOf) => t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: panelOf)),
      ),
    );

    // Origen: pulsa Enviar → aparece el QR.
    await mount(
      tester,
      LanSyncPanel(
        controller: origin,
        addresses: () async => ['127.0.0.1'],
        allowLoopback: true,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('lan-send')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    expect(find.byType(JamQrCode), findsOneWidget);
    final code = tester.widget<JamQrCode>(find.byType(JamQrCode)).data;
    expect(code, startsWith(lanSyncPrefix));

    // El QR lleva un código válido hacia una dirección de red local.
    final invite = LanSyncInvite.decode(code, allowLoopback: true);
    expect(invite.address, '127.0.0.1');
    expect(invite.expiresAt.isAfter(DateTime.now()), isTrue);
    // La transferencia en sí (servidor ↔ cliente) la prueba lan_sync_test.dart.
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
  });

  testWidgets('un código mal pegado explica el problema', (tester) async {
    final c = (await tester.runAsync(createTestController))!;
    addTearDown(() => closeTestController(c));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: LanSyncPanel(controller: c)),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('lan-receive-open')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lan-code-field')),
      'hola',
    );
    await tester.tap(find.byKey(const ValueKey('lan-receive')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lan-message')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('lan-message'))).data,
      contains('no es de una transferencia'),
    );
  });
}
