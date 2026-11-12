// El modo letra (sección 6) hereda textTheme, fontFamily y los temas de
// IconButton/Slider/Tooltip del tema activo. El shell lo envuelve con el tema
// congelado de `lib/theme/legacy`: estos valores no deben moverse al
// rediseñar los temas vivos.
import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/theme/aurora_tokens.dart';
import 'package:aurora_music/theme/legacy/legacy_themes.dart';
import 'package:aurora_music/ui/artist_mode.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/shell/shell_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
];

Set<WidgetState> _s([Iterable<WidgetState> v = const []]) => v.toSet();

/// Foto de lo que el modo letra lee del tema.
Map<String, Object?> _lyricsView(ThemeData t) {
  final icon = t.iconButtonTheme.style;
  return {
    'fontFamily': t.textTheme.bodyMedium?.fontFamily,
    'themeFontFamily': t.textTheme.titleMedium?.fontFamily,
    'titleMedium': t.textTheme.titleMedium,
    'bodyMedium': t.textTheme.bodyMedium,
    'labelSmall': t.textTheme.labelSmall,
    'slider': t.sliderTheme,
    'tooltip': t.tooltipTheme,
    'colorScheme': t.colorScheme,
    'scaffold': t.scaffoldBackgroundColor,
    'iconFg': [
      for (final st in [
        _s(),
        _s([WidgetState.hovered]),
        _s([WidgetState.focused]),
        _s([WidgetState.disabled]),
      ])
        icon?.foregroundColor?.resolve(st),
    ],
    'iconOverlay': [
      for (final st in [
        _s([WidgetState.pressed]),
        _s([WidgetState.hovered]),
        _s([WidgetState.focused]),
      ])
        icon?.overlayColor?.resolve(st),
    ],
  };
}

void main() {
  for (final (kind, mode) in const [
    (AuroraThemeKind.atelier, 'light'),
    (AuroraThemeKind.atelier, 'dark'),
    (AuroraThemeKind.modern, 'light'),
    (AuroraThemeKind.modern, 'dark'),
    (AuroraThemeKind.brasa, 'dark'),
    (AuroraThemeKind.slush, 'light'),
    (AuroraThemeKind.slush, 'dark'),
  ]) {
    testWidgets('modo letra congelado: ${kind.name}/$mode', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = (await tester.runAsync(
        () => createTestController(
          tracks: _songs,
          preferences: {'themeKind': kind.name, 'themeMode': mode},
        ),
      ))!;
      c.queue = [..._songs];
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
          child: const AuroraApp(),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AuroraShell), findsOneWidget);

      // Tema vivo (fuera del modo letra) y tema dentro de ArtistModePage.
      final live = Theme.of(tester.element(find.byType(AuroraShell)));
      tester.widget<ShellNav>(find.byType(ShellNav)).navigate(6);
      await tester.pump(const Duration(seconds: 1));
      final inside = Theme.of(tester.element(find.byType(ArtistModePage)));
      final frozen = legacyThemeFor(kind, live.brightness, c.accentColor);

      expect(inside.brightness, frozen.brightness);
      expect(_lyricsView(inside), _lyricsView(frozen));
    });
  }
}
