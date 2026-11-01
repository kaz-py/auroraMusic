import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

class _WebUiSource extends FakeSource {
  @override
  bool get usesYouTubeWebAudio => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const track = Track(
    id: 'yt:6geljA2OZSY',
    title: 'Que Se Mueran',
    artist: 'Romeo Santos',
    pageUrl: 'https://music.youtube.com/watch?v=6geljA2OZSY',
  );
  late AppController controller;
  late ProviderContainer container;
  setUp(() async {
    final audio = FakeAudio();
    controller = await createTestController(
      tracks: [track],
      audio: audio,
      source: _WebUiSource(),
    );
    await controller.playTrack(track);
    await audio.pause();
    container = ProviderContainer(
      overrides: [controllerProvider.overrideWith((ref) => controller)],
    );
  });
  tearDown(() async {
    container.dispose();
    await controller.closed;
    await controller.supportDirectory.delete(recursive: true);
  });

  testWidgets('web songs retain Aurora player and its queue controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const AuroraApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(StudioTransport),
            matching: find.text(track.title),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('AHORA SUENA'), findsOneWidget);
    expect(find.text(track.title).hitTestable(), findsOneWidget);
    expect(find.byTooltip('Anterior'), findsWidgets);
    expect(find.byTooltip('Siguiente'), findsWidgets);
    expect(find.byTooltip('Añadir a favoritos'), findsOneWidget);
    expect(find.byTooltip('Descargar audio'), findsNothing);
    expect(find.text('music.youtube.com'), findsNothing);
    await tester.tap(find.byTooltip('Cola de reproducción').last);
    await tester.pumpAndSettle();
    expect(find.text('Cola'), findsOneWidget);
    expect(controller.queue.single.id, track.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
