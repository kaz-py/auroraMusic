import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Ajustes de memoria que solo hacen falta en Linux; en otras plataformas no
/// hace nada.
///
/// En Linux el proceso retiene RAM que en Windows no aparece:
/// - glibc no devuelve al sistema lo que malloc ya liberó (el motor de Flutter,
///   Skia y Rust reservan con malloc). `malloc_trim` lo devuelve.
/// - Skia guarda su caché de texturas en la GPU, que con Mesa (WSLg, gráficas
///   integradas o llvmpipe) es RAM del propio proceso. El motor la dimensiona
///   por tamaño de ventana (ancho × alto × 4 × 12 bytes: unos 100 MB a 1080p y
///   400 MB a 4K); aquí se le pone techo.
///
/// El límite de arenas de malloc va aparte, en `linux/runner/main.cc`.
class LinuxMemoryTuning {
  LinuxMemoryTuning({
    bool? enabled,
    int Function()? trim,
    Future<void> Function(int bytes)? setSkiaCacheBytes,
    void Function(VoidCallback task)? runWhenIdle,
    DateTime Function()? now,
    this.skiaCacheBytes = defaultSkiaCacheBytes,
    this.idleInterval = const Duration(minutes: 2),
    this.settleDelay = const Duration(seconds: 2),
    this.minGap = const Duration(seconds: 20),
  }) : enabled = enabled ?? Platform.isLinux,
       _trim = trim,
       _setSkiaCacheBytes = setSkiaCacheBytes ?? _setSkiaCacheBytesOnEngine,
       _runWhenIdle = runWhenIdle ?? _runWhenSchedulerIdle,
       _now = now ?? DateTime.now;

  /// Igual que la caché por defecto del motor con una ventana de 1280 × 720.
  static const defaultSkiaCacheBytes = 48 << 20;

  final bool enabled;
  final int skiaCacheBytes;

  /// Cada cuánto se devuelve memoria mientras la app sigue abierta.
  final Duration idleInterval;

  /// Espera tras ocultar la ventana, para que termine lo que se estaba liberando.
  final Duration settleDelay;

  /// Distancia mínima entre dos recortes.
  final Duration minGap;

  int Function()? _trim;
  final Future<void> Function(int bytes) _setSkiaCacheBytes;
  final void Function(VoidCallback task) _runWhenIdle;
  final DateTime Function() _now;

  Timer? _periodic;
  Timer? _settle;
  bool _idlePending = false;
  bool _started = false;
  DateTime? _lastTrim;

  /// Recortes hechos (diagnóstico y pruebas).
  int get trims => _trims;
  int _trims = 0;

  void start() {
    if (!enabled || _started) return;
    _started = true;
    _trim ??= lookupMallocTrim();
    unawaited(_applySkiaCache());
    _periodic = Timer.periodic(idleInterval, (_) => _trimWhenIdle());
  }

  void dispose() {
    _periodic?.cancel();
    _settle?.cancel();
    _periodic = _settle = null;
    _started = false;
  }

  /// Al ocultar o minimizar la ventana se devuelve la memoria liberada.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        trimSoon();
      case AppLifecycleState.resumed:
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Recorta tras [settleDelay]; varias llamadas seguidas cuentan como una.
  void trimSoon() {
    if (!_started) return;
    _settle?.cancel();
    _settle = Timer(settleDelay, () {
      _settle = null;
      trimNow();
    });
  }

  /// Devuelve al sistema la memoria libre de malloc. Falso si no hizo nada.
  bool trimNow() {
    final trim = _trim;
    if (!_started || trim == null) return false;
    final now = _now();
    final last = _lastTrim;
    if (last != null && now.difference(last) < minGap) return false;
    _lastTrim = now;
    _trims++;
    trim();
    return true;
  }

  // El recorte periódico espera a que no haya animaciones en marcha.
  void _trimWhenIdle() {
    if (_idlePending) return;
    _idlePending = true;
    _runWhenIdle(() {
      _idlePending = false;
      trimNow();
    });
  }

  Future<void> _applySkiaCache() async {
    try {
      await _setSkiaCacheBytes(skiaCacheBytes);
    } catch (_) {
      // Con Impeller o sin canal Skia no hay nada que limitar.
    }
  }

  static Future<void> _setSkiaCacheBytesOnEngine(int bytes) => SystemChannels
      .skia
      .invokeMethod<void>('Skia.setResourceCacheMaxBytes', bytes);

  static void _runWhenSchedulerIdle(VoidCallback task) =>
      runWhenSchedulerIdle(SchedulerBinding.instance, task);

  /// Ejecuta [task] cuando no hay animaciones en marcha, o ya mismo si no se
  /// dibujan fotogramas (ventana oculta o en la bandeja).
  ///
  /// No usa `scheduleTask(Priority.idle)`: con la ventana oculta el motor deja
  /// de pedir fotogramas, una animación a medias no termina nunca y el
  /// planificador reintenta la tarea en bucle con `Timer.run`, con un núcleo al
  /// 100 % mientras la app está en la bandeja.
  @visibleForTesting
  static void runWhenSchedulerIdle(
    SchedulerBinding scheduler,
    VoidCallback task,
  ) {
    if (!scheduler.framesEnabled || scheduler.transientCallbackCount == 0) {
      task();
      return;
    }
    // Hay animaciones y se dibujan fotogramas: se mira de nuevo tras el
    // siguiente, sin sondear entre medias.
    scheduler.addPostFrameCallback(
      (_) => runWhenSchedulerIdle(scheduler, task),
    );
  }

  /// `malloc_trim(0)` de glibc, o null si la libc no lo tiene (p. ej. musl).
  static int Function()? lookupMallocTrim() {
    try {
      final trim = DynamicLibrary.process()
          .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
            'malloc_trim',
          );
      return () => trim(0);
    } catch (_) {
      return null;
    }
  }
}
