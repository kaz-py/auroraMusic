import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../app_controller.dart';
import '../updater/hard_exit.dart';
import 'window_controls.dart';

/// Preferencia «Al cerrar con X»: true = minimizar a la bandeja, false = salir.
abstract final class CloseBehavior {
  static const key = 'closeToTray';
  static bool read(SharedPreferences p) => p.getBool(key) ?? true;
}

/// Une la ventana nativa de Windows y Linux (bandeja, cierre) con el reproductor.
/// No toca el motor de audio: solo llama a los métodos públicos existentes.
class DesktopShell {
  DesktopShell(this.controller);
  final AppController controller;
  String? _lastState;

  static bool get supported => WindowControls.traySupported;

  void start() {
    if (!supported) return;
    WindowControls.onTrayAction = _tray;
    WindowControls.onRealExit = () => controller.pausePlayback();
    // El actualizador cierra la app de verdad antes de lanzar el instalador.
    hardExitHandler = () async {
      if (!await WindowControls.requestHardExit()) exit(0);
    };
    controller.addListener(_push);
    pushCloseBehavior();
    _push();
  }

  void dispose() {
    if (!supported) return;
    controller.removeListener(_push);
    WindowControls.onTrayAction = null;
    WindowControls.onRealExit = null;
  }

  bool get closeToTray => CloseBehavior.read(controller.preferences);

  Future<void> setCloseToTray(bool value) async {
    await controller.preferences.setBool(CloseBehavior.key, value);
    pushCloseBehavior();
  }

  void pushCloseBehavior() =>
      WindowControls.invoke('setCloseToTray', closeToTray);

  void _tray(String action) {
    switch (action) {
      case 'playPause':
        controller.audio.isPlaying
            ? controller.pausePlayback()
            : controller.resumePlayback();
      case 'next':
        controller.next();
      case 'previous':
        controller.previous();
    }
  }

  // Envía a la bandeja solo cuando cambia título/artista/estado.
  void _push() {
    final t = controller.currentTrack;
    final playing = controller.audio.isPlaying;
    final state = '${t?.title}|${t?.artist}|$playing';
    if (state == _lastState) return;
    _lastState = state;
    WindowControls.invoke('setPlayback', {
      'playing': playing,
      'title': t?.title ?? '',
      'artist': t?.artist ?? '',
    });
  }
}
