import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'theme/brasa_theme.dart';
import 'theme/accent_transition.dart';
import 'theme/slush_theme.dart';
import 'theme/modern_theme.dart';
import 'ui/aurora_states.dart';
import 'core/window_controls.dart';
import 'jam/jam_protocol.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'bridge/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'account/account_service.dart';
import 'account/account_wiring.dart';
import 'audio/rust_music_audio.dart';
import 'audio/android_music_audio.dart';
import 'audio/routed_music_audio.dart';
import 'audio_web/web_music_audio.dart';
import 'library/library_database.dart';
import 'lastfm/lastfm_service.dart';
import 'lastfm/lastfm_storage.dart';
import 'sources/yt_dlp_source.dart';
import 'sources/innertube_source.dart';
import 'terms/terms_acceptance.dart';
import 'terms/terms_screen.dart';
import 'ui/aurora_shell.dart';

Future<void> main(List<String> args) async {
  // Errores async sin capturar (unawaited) no deben dejar la app inconsistente.
  await runZonedGuarded(
    () => _main(args),
    (e, s) => debugPrint('Error no capturado: $e\n$s'),
  );
}

Future<void> _main(List<String> args) async {
  WindowControls.launchArguments = args;
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  FlutterError.onError = (d) =>
      debugPrint('FlutterError: ${d.exceptionAsString()}');
  PlatformDispatcher.instance.onError = (e, s) {
    debugPrint('Error de plataforma: $e\n$s');
    return true;
  };
  // Puerta de términos: sin aceptar no arranca protocolo, audio, proxy ni red.
  final terms = TermsAcceptance(await SharedPreferences.getInstance());
  if (terms.isAccepted) {
    _start();
    return;
  }
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: auroraTheme(Brightness.dark, const Color(0xffe86927)),
      home: TermsScreen(
        onAccept: () async {
          await terms.accept();
          _start();
        },
      ),
    ),
  );
}

void _start() {
  unawaited(registerAuroraProtocol()); // aurora://jam/CODIGO (HKCU)
  runApp(const AuroraBootstrap());
}

class AuroraBootstrap extends StatefulWidget {
  const AuroraBootstrap({super.key});
  @override
  State<AuroraBootstrap> createState() => _AuroraBootstrapState();
}

class _AuroraBootstrapState extends State<AuroraBootstrap> {
  late Future<AppController> _startup = _createController();
  AppController? _controller;
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onInactive: () {
      if (_controller != null) unawaited(_controller!.persistSession());
    },
  );

  Future<AppController> _createController() async {
    final preferences = await SharedPreferences.getInstance();
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final database = await LibraryDatabase.open();
    // Restos de la integración anterior (token, cola, ajustes).
    await removeLegacyScrobbleData(
      directory,
      preferences.getKeys(),
      preferences.remove,
    );
    // Opcional y apagado por defecto: sin interruptor ni sesión no hace nada.
    final lastfm = LastfmService(
      preferences: preferences,
      tokenStore: SecureTokenStore(),
      queueStore: FileListenQueueStore(directory),
    );
    await lastfm.init();
    final controller = AppController(
      lastfm: lastfm,
      // YouTube plays in the official site (hidden WebView); local files natively.
      audio: RoutedMusicAudio(
        native: Platform.isAndroid
            ? AndroidMusicAudio()
            : RustMusicAudio.create(),
        web: WebMusicAudio(),
      ),
      source: InnerTubeSource(YtDlpSource(preferences)),
      database: database,
      preferences: preferences,
      supportDirectory: directory,
    );
    await controller.initialize();
    if (!controller.ready) {
      final message = controller.error ?? 'No se pudo iniciar el reproductor.';
      controller.dispose();
      throw StateError(message);
    }
    try {
      await connectAccount(controller);
    } catch (_) {} // la cuenta es opcional: nunca bloquea el arranque
    _controller = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    // Keep the listener alive without stopping background playback on Android.
    _lifecycle;
    return FutureBuilder<AppController>(
      future: _startup,
      builder: (context, snapshot) {
        final controller = snapshot.data;
        if (controller != null) {
          return ProviderScope(
            overrides: [
              controllerProvider.overrideWith((ref) => controller),
              accountServiceProvider.overrideWith(
                (ref) => controller.accounts ?? AccountService(config: null),
              ),
            ],
            child: const AuroraApp(),
          );
        }
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: auroraTheme(Brightness.dark, const Color(0xffe86927)),
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.graphic_eq_rounded, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      snapshot.hasError
                          ? 'No se pudo iniciar Aurora'
                          : 'Preparando tu música',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 16),
                    if (snapshot.hasError) ...[
                      Text('${snapshot.error}', textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () => setState(() {
                          _startup = _createController();
                        }),
                        child: const Text('Reintentar'),
                      ),
                    ] else
                      const CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }
}

class AuroraApp extends ConsumerWidget {
  const AuroraApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      controllerProvider.select(
        (controller) => (
          controller.themeMode,
          controller.accentColor,
          controller.reducedMotion,
          controller.themeKind,
        ),
      ),
    );
    final build = switch (settings.$4) {
      'modern' => modernTheme,
      'brasa' => brasaTheme,
      'slush' => slushTheme,
      _ => auroraTheme,
    };
    return AccentTransition(
      accent: settings.$2,
      instant: settings.$3,
      builder: (context, accent, moving) => MaterialApp(
        title: 'Aurora',
        debugShowCheckedModeBanner: false,
        themeMode: settings.$4 == 'brasa' ? ThemeMode.dark : settings.$1,
        theme: build(
          settings.$4 == 'brasa' ? Brightness.dark : Brightness.light,
          accent,
        ),
        darkTheme: build(Brightness.dark, accent),
        // El acento ya llega interpolado fotograma a fotograma: animarlo otra
        // vez en AnimatedTheme sería una segunda animación encima. Cambiar de
        // tema o de modo sí conserva su fundido.
        themeAnimationDuration: settings.$3 || moving
            ? Duration.zero
            : const Duration(milliseconds: 300),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          WindowControls.setBackground(Theme.of(context).colorScheme.surface);
          return AccentScope(
            accent: accent,
            child: MediaQuery(
              data: media.copyWith(
                disableAnimations: media.disableAnimations || settings.$3,
              ),
              child: child!,
            ),
          );
        },
        home: const AuroraShell(),
      ),
    );
  }
}

ThemeData auroraTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  const ink = Color(0xff110f0e);
  const paper = Color(0xfff7f3ee);
  const ivory = Color(0xfff4eee7);
  const mutedIvory = Color(0xffd9cec1);
  const brown = Color(0xff38312c);
  Color tinted(Color base, double amount) => Color.lerp(base, accent, amount)!;
  final surface = tinted(dark ? ink : paper, dark ? .08 : .04);
  final surfaceLow = tinted(
    dark ? const Color(0xff191512) : const Color(0xfffffaf5),
    dark ? .11 : .055,
  );
  final surfaceMid = tinted(
    dark ? const Color(0xff211b17) : const Color(0xffeee6dd),
    dark ? .15 : .07,
  );
  final surfaceHigh = tinted(
    dark ? const Color(0xff2b231e) : const Color(0xffe7ddd2),
    dark ? .19 : .085,
  );
  final onPrimary = dark ? const Color(0xff151514) : Colors.white;
  var primary = dark
      ? accent
      : HSLColor.fromColor(accent).withLightness(0.32).toColor();
  double contrast(Color a, Color b) {
    final first = a.computeLuminance(), second = b.computeLuminance();
    return (math.max(first, second) + .05) / (math.min(first, second) + .05);
  }

  // Artwork can be any hue: preserve action labels and accent text contrast.
  for (
    var step = 0;
    step < 100 &&
        (contrast(primary, surface) < 4.7 ||
            contrast(primary, onPrimary) < 4.7);
    step++
  ) {
    final hsl = HSLColor.fromColor(primary);
    primary = hsl
        .withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0.0, 1.0))
        .toColor();
  }
  var scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: onPrimary,
        secondary: dark ? const Color(0xffd9cec1) : brown,
        onSecondary: dark ? ink : paper,
        tertiary: dark ? const Color(0xffb9a99a) : const Color(0xff55483e),
        surface: surface,
        surfaceDim: tinted(
          dark ? const Color(0xff0c0a09) : const Color(0xffded5cc),
          dark ? .06 : .04,
        ),
        surfaceBright: tinted(
          dark ? const Color(0xff39302a) : const Color(0xfffffcf8),
          dark ? .09 : .05,
        ),
        onSurface: dark ? ivory : const Color(0xff201a16),
        onSurfaceVariant: dark ? mutedIvory : const Color(0xff44392f),
        outline: dark ? const Color(0xff827468) : const Color(0xff76675b),
        outlineVariant: dark
            ? const Color(0xff51463d)
            : const Color(0xffc4b6a8),
        surfaceContainerLowest: tinted(
          dark ? const Color(0xff100d0b) : const Color(0xfffbf8f4),
          .02,
        ),
        surfaceContainerLow: surfaceLow,
        surfaceContainer: surfaceMid,
        surfaceContainerHigh: surfaceHigh,
        surfaceContainerHighest: tinted(
          dark ? const Color(0xff352b24) : const Color(0xffddd1c5),
          dark ? .085 : .065,
        ),
        primaryContainer: tinted(
          dark ? const Color(0xff33251c) : const Color(0xfff0dfd1),
          .12,
        ),
        onPrimaryContainer: dark ? ivory : const Color(0xff352218),
        secondaryContainer: tinted(
          dark ? const Color(0xff29231e) : const Color(0xffe8dfd6),
          .12,
        ),
        onSecondaryContainer: dark ? ivory : const Color(0xff302820),
      );
  if (dark) {
    // Values from the supplied Atelier Sonoro HTML, with artwork accent retained.
    scheme = scheme.copyWith(
      primary: accent.toARGB32() == 0xffe86927
          ? const Color(0xffffb596)
          : primary,
      onPrimary: accent.toARGB32() == 0xffe86927
          ? const Color(0xff581e00)
          : onPrimary,
      primaryContainer: accent.toARGB32() == 0xffe86927
          ? const Color(0xffea6b29)
          : primary,
      onPrimaryContainer: accent.toARGB32() == 0xffe86927
          ? const Color(0xff4d1900)
          : onPrimary,
      surface: const Color(0xff151312),
      surfaceDim: const Color(0xff151312),
      surfaceBright: const Color(0xff3c3937),
      surfaceContainerLowest: const Color(0xff100e0d),
      surfaceContainerLow: const Color(0xff1d1b1a),
      surfaceContainer: const Color(0xff211f1e),
      surfaceContainerHigh: const Color(0xff2c2928),
      surfaceContainerHighest: const Color(0xff373433),
      onSurface: const Color(0xffe8e1df),
      onSurfaceVariant: const Color(0xffdfc0b3),
      outline: const Color(0xffa78b7f),
      outlineVariant: const Color(0xff584239),
      secondary: const Color(0xffd0c5b8),
      tertiary: const Color(0xffd0c4bd),
    );
  }
  const bodyFont = 'Plus Jakarta Sans';
  const headlineFont = 'Newsreader';
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(
        fontFamily: bodyFont,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: TextStyle(
          fontFamily: headlineFont,
          fontSize: 56,
          height: 64 / 56,
          letterSpacing: -1.12,
          color: scheme.onSurface,
        ),
        headlineLarge: TextStyle(
          fontFamily: headlineFont,
          fontSize: 36,
          height: 44 / 36,
          color: scheme.onSurface,
        ),
        headlineMedium: TextStyle(
          fontFamily: headlineFont,
          fontSize: 28,
          height: 1.18,
          color: scheme.onSurface,
        ),
        headlineSmall: TextStyle(
          fontFamily: headlineFont,
          fontSize: 24,
          height: 1.2,
          color: scheme.onSurface,
        ),
        titleLarge: TextStyle(
          fontFamily: headlineFont,
          fontSize: 22,
          height: 1.2,
          color: scheme.onSurface,
        ),
      );
  final states = AuroraStates.from(scheme);
  return ThemeData(
    useMaterial3: true,
    extensions: [states],
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    visualDensity: VisualDensity.standard,
    chipTheme: const ChipThemeData(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ).copyWith(overlayColor: _overlay(states)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ).copyWith(
            overlayColor: _overlay(states),
            side: WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? states.disabledText
                    : s.contains(WidgetState.focused)
                    ? states.focusRing
                    : scheme.outline,
                width: s.contains(WidgetState.focused) ? 2 : 1,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ).copyWith(overlayColor: _overlay(states)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainer,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: states.onSelected,
      selectedTileColor: states.selected,
      iconColor: scheme.onSurfaceVariant,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: scheme.onSurface),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? states.disabledText
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
        overlayColor: _overlay(states),
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      thumbColor: scheme.primary,
      inactiveTrackColor: scheme.outlineVariant,
      overlayColor: scheme.primary.withValues(alpha: .14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? scheme.surfaceContainerHighest : ink,
      contentTextStyle: TextStyle(
        color: dark ? scheme.onSurface : paper,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: dark ? scheme.primary : scheme.inversePrimary,
      closeIconColor: dark ? scheme.onSurface : paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

WidgetStateProperty<Color?> _overlay(AuroraStates st) =>
    WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed)
          ? st.pressed
          : s.contains(WidgetState.focused)
          ? st.focusRing.withValues(alpha: .28)
          : s.contains(WidgetState.hovered)
          ? st.hover
          : null,
    );
