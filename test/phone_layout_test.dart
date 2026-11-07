import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/friends/friends_providers.dart';
import 'package:aurora_music/friends/friends_service.dart';
import 'package:aurora_music/theme/modern_widgets.dart';
import 'package:aurora_music/ui/cassette_player.dart';
import 'package:aurora_music/ui/friends_page.dart';
import 'package:aurora_music/ui/mini_player/mini_player_host.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/queue_panel.dart';
import 'package:aurora_music/ui/mini_player/atelier_mini_player.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/ui/follow_widgets.dart';
import 'package:aurora_music/ui/home_music_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/friends_fakes.dart';

const _long =
    'Un título extremadamente largo para comprobar que se recorta con puntos suspensivos en móvil';
const _tracks = [
  Track(
    id: 'a',
    title: _long,
    artist: 'Artista con un nombre también bastante largo para el móvil',
    pageUrl: 'https://www.youtube.com/watch?v=a',
    artworkUrl: 'https://i.ytimg.com/vi/a/hq720.jpg',
    duration: Duration(minutes: 3),
  ),
  Track(
    id: 'b',
    title: 'Segunda pista',
    artist: 'Aurora',
    pageUrl: 'https://www.youtube.com/watch?v=b',
    artworkUrl: 'https://i.ytimg.com/vi/b/hq720.jpg',
    duration: Duration(minutes: 3),
  ),
];

void main() {
  setUpAll(() async {
    for (final font in {
      'Newsreader': 'assets/fonts/newsreader/Newsreader-Variable.ttf',
      'Plus Jakarta Sans':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'monospace':
          'assets/fonts/plus_jakarta_sans/PlusJakartaSans-Variable.ttf',
      'Aurora Symbols':
          'assets/fonts/material_symbols_outlined/MaterialSymbolsOutlined.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
  });

  for (final size in const [Size(360, 640), Size(412, 915)]) {
    for (final scale in const [1.0, 2.0]) {
      for (final mode in const ['dark', 'light']) {
        final label =
            '${size.width.toInt()}x${size.height.toInt()} x$scale $mode';
        testWidgets('phone layout $label', (tester) async {
          final controller = (await tester.runAsync(
            () => createTestController(
              tracks: _tracks,
              audio: FakeAudio(),
              preferences: {'themeMode': mode},
            ),
          ))!;
          final container = ProviderContainer(
            overrides: [controllerProvider.overrideWith((ref) => controller)],
          );
          addTearDown(() async {
            container.dispose();
            await tester.runAsync(() async {
              await controller.closed;
              if (await controller.supportDirectory.exists()) {
                await controller.supportDirectory.delete(recursive: true);
              }
            });
          });
          controller.queue = [..._tracks];
          await tester.runAsync(() => controller.playQueueAt(0));
          await controller.audio.pause();

          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const AuroraApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'home');

          // Mini transport: ellipsized title, tappable controls with labels.
          final transport = find.byType(AtelierMiniPlayer);
          expect(transport, findsOneWidget);
          final mini = find.descendant(
            of: transport,
            matching: find.text(_long),
          );
          expect(mini, findsOneWidget);
          expect(tester.widget<Text>(mini).overflow, TextOverflow.ellipsis);
          _expectTargets(
            tester,
            find.descendant(of: transport, matching: find.byType(IconButton)),
          );
          expect(find.byTooltip('Reproducir'), findsWidgets);

          // Tapping the mini opens the full player (vinyl page, section 4)
          // and the mini steps aside.
          await tester.tap(mini);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'player');
          expect(find.byType(AtelierMiniPlayer), findsNothing);
          expect(find.text(_long), findsWidgets);
          for (final tip in const ['Anterior', 'Siguiente']) {
            expect(find.byTooltip(tip), findsWidgets, reason: tip);
          }
          expect(tester.takeException(), isNull, reason: 'player controls');
        });
      }
    }
  }

  testWidgets('queue panel fits narrow phones with large text', (tester) async {
    final controller = (await tester.runAsync(
      () => createTestController(tracks: _tracks, audio: FakeAudio()),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(controller)));
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    controller.queue = [..._tracks];
    await tester.runAsync(() => controller.playQueueAt(0));
    for (final size in const [Size(360, 640), Size(412, 915)]) {
      for (final scale in const [1.0, 2.0]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MaterialApp(
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(body: QueuePanel(controller: controller)),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: '$size $scale');
        expect(find.text('Segunda pista'), findsWidgets);
      }
    }
  });

  Future<AppController> pumpPhone(
    WidgetTester tester, {
    FriendsService? friends,
    String? theme,
    bool play = false,
  }) async {
    final controller = (await tester.runAsync(
      () => createTestController(
        tracks: _tracks,
        audio: FakeAudio(),
        preferences: {'themeKind': ?theme},
      ),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(controller)));
    if (play) {
      controller.queue = [..._tracks];
      await tester.runAsync(() => controller.playQueueAt(0));
      await controller.audio.pause();
    }
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          controllerProvider.overrideWith((ref) => controller),
          if (friends != null)
            friendsServiceProvider.overrideWith((ref) => friends),
        ],
        child: const AuroraApp(),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('artist detail header scrolls away on phones', (tester) async {
    final controller = await pumpPhone(tester);
    controller.searchDetail = const SearchEntry(
      kind: SearchKind.artists,
      browseId: 'UC1',
      title: 'Artista',
    );
    controller.searchDetailTracks = [
      for (var i = 0; i < 30; i++)
        Track(id: 't$i', title: 'Canción $i', artist: 'Artista'),
    ];
    await tester.tap(find.byTooltip('Buscar música'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowButton), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byType(FollowButton, skipOffstage: true), findsNothing);
  });

  testWidgets('system back from Buscar returns to Inicio', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.byTooltip('Buscar música'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Buscar música'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(HomeMusicPage), findsOneWidget);
  });

  testWidgets('back from another section ignores a hidden search detail', (
    tester,
  ) async {
    final controller = await pumpPhone(tester);
    controller.searchDetail = const SearchEntry(
      kind: SearchKind.artists,
      browseId: 'UC1',
      title: 'Artista',
    );
    await tester.tap(find.byTooltip('Buscar música'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Biblioteca').last);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(controller.searchDetail, isNotNull);
    expect(find.byTooltip('Volver a los resultados'), findsOneWidget);
  });

  testWidgets('atrás cierra el chat de Amigos sin salir de la sección', (
    tester,
  ) async {
    await pumpPhone(tester, friends: seededFriendsService());
    await _openFriends(tester);
    await tester.tap(find.byKey(const ValueKey('friends-tab-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('friends-chat-u1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-back')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-back')), findsNothing);
    expect(find.byKey(const ValueKey('friends-tab-2')), findsOneWidget);
  });

  for (final theme in const ['atelier', 'modern', 'brasa', 'slush']) {
    testWidgets('$theme: «Más vistas» → Amigos abre FriendsPage', (
      tester,
    ) async {
      await pumpPhone(tester, theme: theme, friends: seededFriendsService());
      await _openFriends(tester);
      expect(find.byType(FriendsPage), findsOneWidget);
    });

    testWidgets('$theme: «Más vistas» muestra la insignia de Amigos', (
      tester,
    ) async {
      await pumpPhone(tester, theme: theme, friends: seededFriendsService());
      final badge = find.descendant(
        of: find.byTooltip('Más vistas'),
        matching: find.byType(Badge),
      );
      expect(badge, findsOneWidget);
      expect(tester.widget<Badge>(badge).isLabelVisible, isTrue);
    });

    testWidgets('$theme: ⋯ del reproductor abre la tarjeta de acciones', (
      tester,
    ) async {
      await pumpPhone(
        tester,
        theme: theme,
        friends: seededFriendsService(),
        play: true,
      );
      await tester.tap(
        find
            .descendant(
              of: find.byType(MiniPlayerHost),
              matching: find.text(_long),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Más acciones'));
      await tester.pumpAndSettle();
      expect(find.text('Reproducir a continuación'), findsNothing);
      if (theme != 'slush') {
        expect(find.text('Cola de reproducción'), findsOneWidget);
      }
      for (final label in const ['Añadir a la cola', 'Enviar a un amigo']) {
        final tile = find.text(label);
        expect(tile, findsOneWidget, reason: label);
        expect(tester.getRect(tile).bottom, lessThanOrEqualTo(640));
      }
    });
  }

  testWidgets('Modern: el reproductor abre con la portada sola y más botones', (
    tester,
  ) async {
    await pumpPhone(tester, theme: 'modern', play: true);
    await tester.tap(
      find
          .descendant(
            of: find.byType(MiniPlayerHost),
            matching: find.text(_long),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('vinyl-disc')), findsNothing);
    for (final tip in const ['Aleatorio', 'Repetir', 'Anterior', 'Siguiente']) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    // Se puede cambiar a vinilo o casete y volver a la portada.
    Finder inPicker(String tip) => find.descendant(
      of: find.byKey(const ValueKey('modern-view-picker')),
      matching: find.byTooltip(tip),
    );
    await tester.tap(inPicker('Ver vinilo'));
    await tester.pump();
    expect(find.byKey(const ValueKey('vinyl-disc')), findsOneWidget);
    await tester.tap(inPicker('Ver casete'));
    await tester.pump();
    expect(find.byType(CassettePlayer), findsOneWidget);
    expect(find.byKey(const ValueKey('vinyl-disc')), findsNothing);
    await tester.tap(inPicker('Ver portada'));
    await tester.pump();
    expect(find.byType(CassettePlayer), findsNothing);
    expect(find.byKey(const ValueKey('vinyl-disc')), findsNothing);
  });

  testWidgets('Modern en móvil no muestra titular ni saludo en Inicio', (
    tester,
  ) async {
    await pumpPhone(tester, theme: 'modern');
    expect(find.byType(ModernHeadline), findsNothing);
    expect(find.textContaining('siempre'), findsNothing);
    expect(find.text('Encontrar música'), findsOneWidget);
  });
}

Future<void> _openFriends(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Más vistas'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Amigos'));
  await tester.pumpAndSettle();
}

void _expectTargets(WidgetTester tester, Finder buttons) {
  for (var i = 0; i < buttons.evaluate().length; i++) {
    final size = tester.getSize(buttons.at(i));
    expect(
      size.shortestSide,
      greaterThanOrEqualTo(44),
      reason: 'tap target #$i $size',
    );
    final w = tester.widget<IconButton>(buttons.at(i));
    expect(w.tooltip, isNotEmpty, reason: 'tooltip #$i');
  }
}
