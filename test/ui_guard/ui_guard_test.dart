// Guarda de interfaz: todo visible en todos los temas y siempre responsive.
//
// Bombea `AuroraApp` en una matriz tema × modo × anchura × escala de texto ×
// pantalla y exige, en cada caso:
//  * ninguna excepción ni desborde (`RenderFlex overflowed`, etc.);
//  * contraste texto/icono >= 3 contra su fondo resuelto;
//  * objetivos táctiles >= 40x40 px lógicos en móvil (< 600 px);
//  * nada importante cortado por el borde horizontal de la pantalla.
//
// Dos niveles:
//  * quick (por defecto, también con `flutter test`): matriz reducida.
//  * full: matriz completa. `flutter test test/ui_guard --dart-define=UI_GUARD=full`
//    (o la variable de entorno `UI_GUARD=full`).
//
// Los fallos conocidos viven en `known_issues.dart`; ver docs/ui_guard.md.
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/friends/friends_providers.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:aurora_music/ui/slush/slush_bars.dart';
import 'package:aurora_music/ui/studio/studio_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/friends_fakes.dart';
import 'guard_checks.dart';
import 'known_issues.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
  Track(id: 'c', title: 'Noche', artist: 'Otro'),
];

final bool _full =
    const String.fromEnvironment('UI_GUARD') == 'full' ||
    Platform.environment['UI_GUARD'] == 'full';

/// Tema + modo. Brasa es siempre oscuro.
typedef _Variant = (String theme, String mode);

const _allVariants = <_Variant>[
  ('atelier', 'light'),
  ('atelier', 'dark'),
  ('modern', 'light'),
  ('modern', 'dark'),
  ('brasa', 'dark'),
  ('slush', 'light'),
  ('slush', 'dark'),
];
const _quickVariants = <_Variant>[
  ('slush', 'light'),
  ('slush', 'dark'),
  ('atelier', 'light'),
];

/// Anchura × altura realistas (móvil, móvil grande, tablet, portátil, escritorio).
const _allSizes = <Size>[
  Size(360, 740),
  Size(412, 915),
  Size(600, 960),
  Size(900, 700),
  Size(1440, 900),
  Size(1920, 1080),
];
const _quickSizes = <Size>[Size(360, 740), Size(900, 700), Size(1440, 900)];

/// Pantallas -> sección del shell (`_section` en aurora_shell.dart).
const _allScreens = <String, int>{
  'Inicio': 0,
  'Búsqueda': 1,
  'Biblioteca': 2,
  'DJ': 8,
  'Jam': 9,
  'Cola/EQ': 5,
  'Vinilo': 4,
  'Ajustes': 7,
  'Descargas': 3,
  'Artistas': 12,
  'Amigos': 14,
  'Chat': 14,
  'Ecualizador': 13,
  // Última: el modo artista cubre todo el shell, así que no se puede navegar
  // desde ella.
  'Letras': 6,
};
const _quickScreens = <String>[
  'Inicio',
  'Búsqueda',
  'DJ',
  'Jam',
  'Cola/EQ',
  'Vinilo',
  'Amigos',
  'Chat',
  'Letras',
];

/// Tras navegar, pantallas que piden abrir algo más (pestaña, hilo) antes de
/// medir. Cada clave se pulsa por orden.
const _openAfterNavigate = <String, List<String>>{
  'Chat': ['friends-tab-2', 'friends-chat-u1'],
};

const _navSize = Size(1440, 900);

final _exercised = <String>{};
final _reproduced = <String>{};

/// Deja que las animaciones terminen. Una pantalla con animación infinita
/// (spinner, vinilo girando) no se estabiliza nunca: tras 3 s se mide igual.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
  } on FlutterError catch (e) {
    if (!e.message.contains('pumpAndSettle timed out')) rethrow;
  }
}

Future<void> _resize(WidgetTester tester, Size s) async {
  tester.view.physicalSize = s;
  await _settle(tester);
}

/// El shell solo expone la navegación completa con barra/rail (>= 600 px):
/// se navega con el callback de la barra y luego se restaura el tamaño.
Future<void> _navigate(
  WidgetTester tester,
  int section,
  Size target,
  ErrorCollector errors,
) async {
  final detour = target.width < phoneMaxWidth;
  if (detour) await _resize(tester, _navSize);
  final slush = find.byType(SlushTopBar);
  if (slush.evaluate().isNotEmpty) {
    tester.widget<SlushTopBar>(slush).onNavigate(section);
  } else {
    tester
        .widget<StudioTitleBar>(find.byType(StudioTitleBar))
        .onNavigate(section);
  }
  await _settle(tester);
  if (slush.evaluate().isNotEmpty) {
    if (tester.widget<SlushTopBar>(slush).selected != section) {
      errors.restore();
      fail('la navegación a la sección $section no llegó a la barra superior');
    }
  }
  if (detour) {
    errors.drain(); // fallos del tamaño de paso no son de este caso
    await _resize(tester, target);
  }
}

void main() {
  final variants = _full ? _allVariants : _quickVariants;
  final sizes = _full ? _allSizes : _quickSizes;
  final scales = const [1.0, 2.0];
  final screens = _full ? _allScreens.keys.toList() : _quickScreens;

  for (final (theme, mode) in variants) {
    for (final size in sizes) {
      for (final scale in scales) {
        testWidgets('guarda ${_full ? 'full' : 'quick'}: $theme/$mode '
            '${size.width.toInt()}x${size.height.toInt()} x$scale', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final errors = ErrorCollector.install(tester);
          // Cualquier excepción del cuerpo (también las no-Flutter) debe ver el
          // manejador original: el binding lo exige para registrarla.
          try {
            final c = (await tester.runAsync(
              () => createTestController(
                tracks: _songs,
                playlists: const [
                  MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
                ],
                preferences: {'themeKind': theme, 'themeMode': mode},
              ),
            ))!;
            c.queue = [..._songs];
            await tester.runAsync(() => c.playQueueAt(0));
            await c.audio.pause();
            final container = ProviderContainer(
              overrides: [
                controllerProvider.overrideWith((ref) => c),
                friendsServiceProvider.overrideWith(
                  (ref) => seededFriendsService(),
                ),
              ],
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
            await _settle(tester);
            expect(find.byType(AuroraShell), findsOneWidget);
            errors.drain();

            final offenders = <String>[];
            for (final name in screens) {
              final where = GuardCase(
                theme,
                mode,
                size.width.toInt(),
                scale,
                name,
              );
              if (name != 'Inicio') {
                await _navigate(tester, _allScreens[name]!, size, errors);
                for (final key
                    in _openAfterNavigate[name] ?? const <String>[]) {
                  final target = find.byKey(ValueKey(key));
                  // Al cuarto superior: `ensureVisible` a secas lo deja en el
                  // borde, bajo la barra inferior/mini que se superpone.
                  await Scrollable.ensureVisible(
                    tester.element(target),
                    alignment: .25,
                  );
                  await tester.pump();
                  await tester.tap(target);
                  await _settle(tester);
                }
              }
              final scaffold = find.byType(Scaffold).first;
              final bg =
                  tester.widget<Scaffold>(scaffold).backgroundColor ??
                  Theme.of(tester.element(scaffold)).scaffoldBackgroundColor;
              final found = <GuardViolation>[
                ...errors.drain(),
                ...checkContrast(tester, bg, size),
                if (size.width < phoneMaxWidth) ...checkHitTargets(tester),
                ...checkClipping(tester, size),
              ];
              for (final issue in knownIssues) {
                if (issue.covers(where)) _exercised.add(issue.id);
              }
              for (final v in found) {
                final known = knownIssues
                    .where((i) => i.matches(where, v))
                    .toList();
                if (known.isEmpty) {
                  offenders.add('$where  $v');
                } else {
                  for (final k in known) {
                    _reproduced.add(k.id);
                  }
                }
              }
            }
            if (offenders.isNotEmpty) {
              final text = offenders.map((o) => 'UI-GUARD ✗ $o').join('\n');
              debugPrint(text);
              errors.restore();
              fail(
                '${offenders.length} fallo(s) de interfaz, detalle en las '
                'líneas impresas arriba (arréglalos o anótalos en known_issues.dart)',
              );
            }
          } finally {
            errors.restore();
          }
        }, timeout: const Timeout(Duration(minutes: 5)));
      }
    }
  }

  // Las entradas de known_issues.dart son TODOs: si una se ejercitó y ya no se
  // reproduce hay que borrarla.
  test('known_issues.dart solo contiene fallos que aún se reproducen', () {
    final stale = [
      for (final i in knownIssues)
        if (_exercised.contains(i.id) && !_reproduced.contains(i.id)) i,
    ];
    if (stale.isNotEmpty) {
      final text = stale
          .map((i) => 'UI-GUARD ✓ ya arreglado, borra "${i.id}" (${i.file})')
          .join('\n');
      debugPrint(text);
      fail(text);
    }
  });
}
