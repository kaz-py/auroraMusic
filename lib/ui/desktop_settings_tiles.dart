import 'dart:io';

import 'package:flutter/material.dart';

import '../core/desktop_shell.dart';
import '../core/duvet_presence.dart';
import '../core/window_controls.dart';
import '../theme/brasa_theme.dart';

/// Ajustes de escritorio: comportamiento de la X (Windows y Linux), inicio con
/// Windows (solo Windows) y lo que escuchas en Duvet (Windows y Linux).
class DesktopSettingsTiles extends StatefulWidget {
  const DesktopSettingsTiles({
    super.key,
    required this.shell,
    required this.duvet,
  });
  final DesktopShell shell;
  final DuvetPresence duvet;

  @override
  State<DesktopSettingsTiles> createState() => _DesktopSettingsTilesState();
}

class _DesktopSettingsTilesState extends State<DesktopSettingsTiles> {
  late bool _tray = widget.shell.closeToTray;
  late bool _duvet = widget.duvet.enabled;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    if (WindowControls.supported) {
      WindowControls.query('getAutostart').then((v) {
        if (mounted) setState(() => _autostart = v);
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      // Bandeja: Windows y Linux; inicio con el sistema: solo Windows.
      if (WindowControls.traySupported)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: isBrasa(context) ? Brasa.cream : null,
          activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
          title: const Text('Al cerrar con X: minimizar a la bandeja'),
          subtitle: Text(switch ((_tray, Platform.isLinux)) {
            (true, false) =>
              'La X siempre oculta Aurora en la bandeja (suene o no la música). Alt+F4 y «Salir» de la bandeja siempre cierran.',
            (false, false) => 'La X cierra Aurora. Alt+F4 siempre cierra.',
            (true, true) =>
              'La X oculta Aurora en la bandeja y la música sigue. «Salir» en el menú del icono la cierra. Sin bandeja en el escritorio, la X cierra.',
            (false, true) => 'La X cierra Aurora.',
          }),
          value: _tray,
          onChanged: (v) {
            setState(() => _tray = v);
            widget.shell.setCloseToTray(v);
          },
        ),
      if (WindowControls.supported)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeTrackColor: isBrasa(context) ? Brasa.cream : null,
          activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
          title: const Text('Iniciar con Windows'),
          value: _autostart,
          onChanged: (v) async {
            final ok = await WindowControls.invoke('setAutostart', v);
            if (ok && mounted) setState(() => _autostart = v);
          },
        ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeTrackColor: isBrasa(context) ? Brasa.cream : null,
        activeThumbColor: isBrasa(context) ? Brasa.void_ : null,
        title: const Text('Mostrar en Duvet lo que escuchas'),
        subtitle: const Text(
          'Con la app de escritorio de Duvet abierta, tu perfil dice qué suena en Aurora mientras suena.',
        ),
        value: _duvet,
        onChanged: (v) {
          setState(() => _duvet = v);
          widget.duvet.setEnabled(v);
        },
      ),
    ],
  );
}
