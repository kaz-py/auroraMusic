import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'theme/atelier_theme.dart';
import 'theme/brasa_theme.dart';
import 'theme/accent_transition.dart';
import 'theme/slush_theme.dart';
import 'theme/modern_theme.dart';
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
  // Por defecto Flutter retiene hasta 100 MB de imágenes decodificadas; las
  // portadas se vuelven a decodificar rápido, así que 32 MB bastan.
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = 32 << 20
    ..maximumSize = 300;
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
      audio: Platform.isAndroid ? AndroidMusicAudio() : RustMusicAudio.create(),
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
