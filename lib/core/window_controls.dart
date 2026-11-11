import 'dart:io';
import 'package:flutter/services.dart';

/// Desktop title-bar operations stay outside widgets.
abstract final class WindowControls {
  static bool get supported => Platform.isWindows;
  static const _channel = MethodChannel('aurora/window');

  /// Se ejecuta tras confirmar un cierre real (Alt+F4 / Salir): detener audio.
  static Future<void> Function()? onRealExit;

  /// Acciones de la bandeja: playPause, next, previous.
  static void Function(String action)? onTrayAction;

  /// Argumentos de una segunda instancia (p. ej. aurora://jam/CODIGO).
  static void Function(String arguments)? onArguments;

  /// Argumentos con los que arrancó el proceso (p. ej. aurora://jam/CODIGO).
  static List<String> launchArguments = const [];

  static bool _installed = false;

  /// Instala el canal nativo (cierre real, bandeja y segunda instancia).
  static void install() {
    if (_installed || !Platform.isWindows) return;
    _installed = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'confirmClose':
          if (call.arguments == true) await onRealExit?.call();
          return true;
        case 'trayAction':
          onTrayAction?.call(call.arguments as String);
          return null;
        case 'arguments':
          onArguments?.call(call.arguments as String);
          return null;
      }
      throw MissingPluginException();
    });
  }

  /// Tamaño lógico de la ventana del modo mini.
  static const miniWindowSize = Size(380, 150);

  /// Modo mini: ventana compacta y siempre visible abajo a la derecha; al
  /// desactivarlo la ventana vuelve a su sitio y tamaño. `false` si no hay
  /// ventana nativa que cambiar (fuera de Windows).
  static Future<bool> setMiniWindow(bool enabled) => invoke('setMini', {
    'enabled': enabled,
    'width': miniWindowSize.width.round(),
    'height': miniWindowSize.height.round(),
  });

  /// Pantalla completa: ventana nativa en Windows, modo inmersivo en Android.
  static bool get fullscreenSupported =>
      Platform.isWindows || Platform.isAndroid;

  /// `false` si no hay nada que cambiar (otras plataformas o fallo nativo).
  static Future<bool> setFullscreen(bool enabled) async {
    if (Platform.isAndroid) {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
        overlays: enabled ? null : SystemUiOverlay.values,
      );
      return true;
    }
    return invoke('setFullscreen', {'enabled': enabled});
  }

  static Future<bool> invoke(String operation, [Object? arguments]) async {
    if (!Platform.isWindows) return false;
    install();
    try {
      await _channel.invokeMethod<void>(operation, arguments);
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Cierre real de la app (ignora «minimizar a la bandeja»): detiene el audio,
  /// cierra la bandeja y termina el proceso. Es la única vía que debe usar el
  /// actualizador antes de lanzar el instalador. No hace nada fuera de Windows.
  static Future<bool> requestHardExit() => invoke('hardExit');

  static int? _background;

  /// Fondo nativo de la ventana (sin franjas blancas al redimensionar/mover).
  static void setBackground(Color color) {
    final rgb = color.toARGB32() & 0xFFFFFF;
    if (_background == rgb) return;
    _background = rgb;
    invoke('setBackground', rgb);
  }

  static Future<bool> query(String operation) async {
    if (!Platform.isWindows) return false;
    try {
      return await _channel.invokeMethod<bool>(operation) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
