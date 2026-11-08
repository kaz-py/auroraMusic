import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/profile/avatar_image.dart';
import 'package:aurora_music/profile/profile_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const Color(0xFFCC3355),
  );
  final image = await recorder.endRecording().toImage(w, h);
  return (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
}

void main() {
  test('makeAvatarThumbnail yields a small 128px square', () async {
    final out = await runIt(() async {
      final bytes = await makeAvatarThumbnail(await _png(400, 200));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = (await codec.getNextFrame()).image;
      return (bytes.length, frame.width, frame.height);
    });
    expect(out.$1, lessThanOrEqualTo(24 * 1024));
    expect((out.$2, out.$3), (128, 128));
  });

  test('makeAvatarThumbnail rejects garbage and huge input', () async {
    await expectLater(
      makeAvatarThumbnail(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(isA<AvatarException>()),
    );
    await expectLater(
      makeAvatarThumbnail(Uint8List(9 * 1024 * 1024)),
      throwsA(isA<AvatarException>()),
    );
  });

  test('AppController persists and reloads the profile', () async {
    final c = await createTestController();
    await c.setProfileName('  Ana\u202e María  ${'x' * 40}');
    expect(c.profileName.length, lessThanOrEqualTo(24));
    expect(c.profileName, startsWith('Ana'));
    await c.setProfileAvatar(Uint8List.fromList([1, 2, 3]));
    final c2 = AppController(
      audio: FakeAudio(),
      source: FakeSource(),
      database: LibraryDatabase.memory(),
      preferences: c.preferences,
      supportDirectory: c.supportDirectory,
    );
    await c2.initialize(mediaControls: false);
    expect(c2.profileName, c.profileName);
    expect(c2.profileAvatar, [1, 2, 3]);
    await c.setProfileAvatar(null);
    expect(
      File('${c.supportDirectory.path}/profile_avatar.bin').existsSync(),
      isFalse,
    );
    c2.dispose();
    await closeTestController(c);
  });

  testWidgets('settings field saves the name', (tester) async {
    final c = await tester.runAsync(createTestController) as AppController;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfileSettings(controller: c)),
      ),
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-name-field')),
      'Luna',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(c.profileName, 'Luna');
    expect(find.byKey(const ValueKey('profile-choose-photo')), findsOneWidget);
  });
}

Future<T> runIt<T>(Future<T> Function() f) => f();
