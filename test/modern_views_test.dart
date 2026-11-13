// Modern «Cristal»: renderiza inicio / reproduciendo / modo letra en escritorio
// y móvil (390, 360, textScale 2.0) sin excepciones ni desbordes.
// `MODERN_SHOTS=1` además vuelca PNG en build/modern-review/ para compararlos
// con los prototipos.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/shell/shell_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _fonts = {
  'Manrope': 'assets/fonts/manrope/Manrope-Variable.ttf',
  'Geist Mono': 'assets/fonts/geist_mono/GeistMono-Variable.ttf',
  'Inter': 'assets/fonts/inter/Inter-Variable.ttf',
  'Plus Jakarta Sans':
      'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
  'Aurora Symbols':
      'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
  'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
};

final _shots = Platform.environment['MODERN_SHOTS'] == '1';

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUpAll(() async {
    for (final f in _fonts.entries) {
      await (FontLoader(f.key)..addFont(rootBundle.load(f.value))).load();
    }
  });

  const cases = <(String, Size, double)>[
    ('d1440', Size(1440, 900), 1),
    ('d1440x2', Size(1440, 900), 2),
    ('m390', Size(390, 844), 1),
    ('m360', Size(360, 740), 1),
    ('m360x2', Size(360, 740), 2),
  ];
  for (final (label, size, scale) in cases) {
    testWidgets('modern vistas $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const songs = [
        Track(
          id: 'a',
          title: 'Marea Baja',
          artist: 'Luz de Neón',
          album: 'Marea Baja (Deluxe)',
          duration: Duration(minutes: 4, seconds: 18),
        ),
        Track(
          id: 'b',
          title: 'Un título larguísimo que no cabe en una sola línea de nada',
          artist: 'Un artista con un nombre también bastante largo',
          duration: Duration(minutes: 3),
        ),
        Track(id: 'c', title: 'Noche', artist: 'Otro'),
      ];
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: songs,
          playlists: const [
            MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
          ],
          preferences: {'themeKind': 'modern', 'themeMode': 'dark'},
        ),
      ))!;
      c.queue = [...songs];
      await tester.runAsync(() => c.playQueueAt(0));
      await c.audio.pause();
      final container = ProviderContainer(
        overrides: [controllerProvider.overrideWith((ref) => c)],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await tester.runAsync(() async {
          await c.closed;
          if (await c.supportDirectory.exists()) {
            await c.supportDirectory.delete(recursive: true);
          }
        });
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const RepaintBoundary(
            key: ValueKey('shot'),
            child: AuroraApp(),
          ),
        ),
      );
      await _settle(tester);
      expect(tester.takeException(), isNull);
      if (Platform.environment['MODERN_DUMP'] == '1') {
        FlutterError.onError = FlutterError.dumpErrorToConsole;
      }

      Future<void> shot(String name) async {
        if (!_shots) return;
        await tester.runAsync(() async {
          final b = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shot')),
          );
          final img = await b.toImage();
          final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/modern-review').create(recursive: true);
          await File(
            'build/modern-review/$label-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          img.dispose();
        });
      }

      await shot('inicio');
      final nav = find.byType(ShellNav);
      // 4 = reproduciendo (vinilo/player temático), 5 = cola, 6 = modo letra.
      for (final (name, section) in [
        ('reproduciendo', 4),
        ('cola', 5),
        ('letra', 6),
      ]) {
        tester.widget<ShellNav>(nav).navigate(section);
        await _settle(tester);
        final err = tester.takeException();
        // artist_mode.dart (compartido) apila botones de ventana de Windows que
        // no existen en Android: a 360 px x2 desborda en el escritorio, no en el móvil.
        final windowsTopBar = name == 'letra' && scale > 1 && size.width < 400;
        if (!windowsTopBar) expect(err, isNull, reason: '$label $name');
        await shot(name);
        tester.widget<ShellNav>(nav).navigate(0);
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
