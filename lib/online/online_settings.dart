import 'package:flutter/material.dart';

import '../core/online_status.dart';

/// Ajustes → servicios en línea: usar el servidor (cuenta, amigos, Jam en línea)
/// o quedarse en modo local. Muestra si el servidor responde ahora.
class OnlineSettings extends StatefulWidget {
  const OnlineSettings({super.key, required this.status});

  final OnlineStatus status;

  @override
  State<OnlineSettings> createState() => _OnlineSettingsState();
}

class _OnlineSettingsState extends State<OnlineSettings> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await widget.status.available(force: true);
    if (mounted) setState(() => _checking = false);
  }

  String _text(OnlineStatus s) {
    if (!s.enabled) {
      return 'Los servicios en línea (cuenta, amigos y Jam por internet) '
          'están desactivados temporalmente. Todo lo demás sigue igual, '
          'incluida la Jam por red local (código QR) y la transferencia de '
          'biblioteca por QR.';
    }
    if (s.mode == OnlineMode.off) {
      return 'Modo local: Aurora no contacta con el servidor. La Jam por red '
          'local (código QR) sigue funcionando.';
    }
    return switch (s.lastKnown) {
      true =>
        'El servidor responde. Cuenta, amigos y Jam en línea disponibles.',
      false =>
        'El servidor no responde (pausado o sin conexión). Aurora usa el '
            'modo local y lo vuelve a probar sola cada pocos minutos.',
      null => 'Sin comprobar todavía.',
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.status,
    builder: (context, _) {
      final status = widget.status;
      if (!status.enabled) {
        return Text(_text(status), key: const ValueKey('online-status'));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('online-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Usar servicios en línea'),
            subtitle: const Text(
              'Cuenta, amigos y Jam por internet (Supabase). Si está '
              'apagado, o el servidor no responde, Aurora funciona igual en '
              'modo local.',
            ),
            value: status.mode == OnlineMode.auto,
            onChanged: (on) =>
                status.setMode(on ? OnlineMode.auto : OnlineMode.off),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _text(status),
              key: const ValueKey('online-status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (status.mode == OnlineMode.auto)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('online-check'),
                onPressed: _checking ? null : _check,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_checking ? 'Comprobando…' : 'Comprobar ahora'),
              ),
            ),
        ],
      );
    },
  );
}
