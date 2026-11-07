import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:aurora_music/jam/jam_models.dart';
import 'package:aurora_music/shortcuts/shortcut_service.dart';
import 'package:aurora_music/ui/studio/equalizer_panel.dart';
import 'package:aurora_music/ui/studio/studio_transport.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _song = Track(
  id: 'song',
  title: 'Canción base',
  artist: 'Artista',
  duration: Duration(minutes: 3),
);

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

  late FakeAudio audio;
  late AppController app;

  setUp(() async {
    audio = FakeAudio();
    app = await createTestController(tracks: [_song], audio: audio);
    await app.playTrack(_song);
    await app.pausePlayback();
  });

  tearDown(() => closeTestController(app));

  void size(WidgetTester tester, Size value, [double scale = 1]) {
    tester.view.physicalSize = value;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Widget bar({JamController? jam, ShortcutService? shortcuts}) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.bottomCenter,
        child: StudioTransport(
          controller: app,
          jam: jam,
          shortcuts: shortcuts,
          onLyrics: () {},
          onVinyl: () {},
          onQueue: () {},
          onOpenPlayer: () {},
          onJam: () {},
          onStartJam: () {},
        ),
      ),
    ),
  );

  Finder eqIconButton() => find.descendant(
    of: find.byType(TransportEqualizerButton),
    matching: find.byType(IconButton),
  );

  testWidgets('the bar shows the EQ button with the current shortcut', (
    tester,
  ) async {
    for (final width in [1400.0, 500.0]) {
      size(tester, Size(width, 700));
      final shortcuts = ShortcutService(app.preferences);
      await tester.pumpWidget(bar(shortcuts: shortcuts));
      expect(find.byType(TransportEqualizerButton), findsOneWidget);
      expect(
        tester.widget<IconButton>(eqIconButton()).tooltip,
        'Ecualizador (Ctrl+E)',
      );
      expect(tester.takeException(), isNull, reason: 'width $width');
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without EQ support the button is disabled and says why', (
    tester,
  ) async {
    audio.eqSupported = false;
    for (final width in [1400.0, 500.0]) {
      size(tester, Size(width, 700));
      await tester.pumpWidget(bar());
      final button = tester.widget<IconButton>(eqIconButton());
      expect(button.onPressed, isNull);
      expect(button.tooltip, contains('no disponible'));
      await tester.tap(eqIconButton(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(EqualizerPanel), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('narrow bar (320 px, 200 % text) moves EQ to the overflow menu', (
    tester,
  ) async {
    size(tester, const Size(320, 700), 2);
    await tester.pumpWidget(bar());
    expect(tester.takeException(), isNull);
    expect(find.byType(TransportEqualizerButton), findsNothing);
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ecualizador'), findsOneWidget);
    await tester.tap(find.textContaining('Ecualizador'));
    await tester.pumpAndSettle();
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('overflow entry explains an unsupported engine', (tester) async {
    audio.eqSupported = false;
    size(tester, const Size(320, 700), 2);
    await tester.pumpWidget(bar());
    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no disponible'), findsOneWidget);
    await tester.tap(find.textContaining('no disponible'));
    await tester.pumpAndSettle();
    expect(find.byType(EqualizerPanel), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the panel fits 320, 500 and 1400 px at 200 % text', (
    tester,
  ) async {
    for (final width in [320.0, 500.0, 1400.0]) {
      size(tester, Size(width, 800), 2);
      await tester.pumpWidget(bar());
      // At 200 % text the bar is "large": EQ lives in the overflow menu.
      await tester.tap(find.byTooltip('Más acciones'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Ecualizador'));
      await tester.pumpAndSettle();
      expect(find.byType(EqualizerPanel), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'panel at $width');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the sheet edits bands, A/B and presets without leaving', (
    tester,
  ) async {
    size(tester, const Size(1400, 900));
    await tester.pumpWidget(bar());
    await tester.tap(eqIconButton());
    await tester.pumpAndSettle();
    expect(app.eq.enabled, isFalse);
    // Moving a slider turns the EQ on.
    final slider = find
        .descendant(
          of: find.byType(EqualizerPanel),
          matching: find.byType(Slider),
        )
        .first;
    await tester.drag(slider, const Offset(0, -30));
    await tester.pumpAndSettle();
    expect(app.eq.enabled, isTrue);
    expect(app.eq.bands.first.gainDb, isNot(0));
    expect(audio.eqCalls.last.$1, isTrue);
    expect(
      app.eq.bands.first.gainDb * 10,
      closeTo((app.eq.bands.first.gainDb * 10).round(), 1e-9),
    );
    // Double tap resets the band (away from the centre, so a plain tap that
    // jumps the slider could not be mistaken for the reset).
    app.eq.setGain(0, 6);
    await tester.pump();
    final spot = tester.getCenter(slider) + const Offset(0, -25);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(spot);
    await tester.pumpAndSettle();
    expect(app.eq.bands.first.gainDb, 0);
    // Preset chip and A/B.
    await tester.tap(find.text('Rock'));
    await tester.pumpAndSettle();
    expect(app.eq.presetName, 'Rock');
    await tester.tap(find.text('A/B sin EQ'));
    await tester.pumpAndSettle();
    expect(app.eq.bypass, isTrue);
    expect(audio.eqCalls.last.$1, isFalse);
    // The bar behind is still there: nothing navigated away.
    expect(find.byType(StudioTransport), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Jam listener: the button works and EQ is not a Jam action', (
    tester,
  ) async {
    size(tester, const Size(1400, 700));
    final jam = JamController(app: app);
    jam.service
      ..connection = JamConnection.connected
      ..participantId = 'guest'
      ..participants = const [
        JamParticipant(
          id: 'host',
          name: 'Lucía',
          role: JamRole.host,
          permissions: JamPermissions.all,
        ),
        JamParticipant(id: 'guest', name: 'Beto'),
      ];
    await tester.pumpWidget(bar(jam: jam));
    expect(find.byType(TransportEqualizerButton), findsOneWidget);
    expect(tester.widget<IconButton>(eqIconButton()).onPressed, isNotNull);
    await tester.tap(eqIconButton());
    await tester.pumpAndSettle();
    expect(find.byType(EqualizerPanel), findsOneWidget);
    expect(find.textContaining('no se comparte en una Jam'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
