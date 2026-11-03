import 'package:aurora_music/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

void main() {
  test('blurredCoverMode: apagado por defecto, persiste y avisa', () async {
    final controller = await createTestController();
    addTearDown(() => closeTestController(controller));
    expect(controller.blurredCoverMode, isFalse);

    var notified = 0;
    controller.addListener(() => notified++);
    controller.setBlurredCoverMode(true);
    expect(controller.blurredCoverMode, isTrue);
    expect(notified, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('blurredCoverMode'), isTrue);

    controller.setBlurredCoverMode(true);
    expect(notified, 1, reason: 'mismo valor: sin aviso');
  });

  test('blurredCoverMode se carga desde las preferencias', () async {
    final AppController controller = await createTestController(
      preferences: const {'blurredCoverMode': true},
    );
    addTearDown(() => closeTestController(controller));
    expect(controller.blurredCoverMode, isTrue);
  });
}
