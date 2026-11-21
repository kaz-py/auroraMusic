import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'remote_control_service.dart';

/// Sección de Ajustes «Control remoto (Stream Deck)»: interruptor de la API,
/// URL y token. El plugin de Stream Deck (carpeta `streamdeck/`) los lee solo
/// del archivo de descubrimiento; copiarlos sirve para otros clientes.
class RemoteControlSettings extends StatelessWidget {
  const RemoteControlSettings({super.key, required this.service});

  final RemoteControlService service;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      void copy(String text, String what) {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text('$what copiado.')));
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar la API local'),
            subtitle: const Text(
              'Solo escucha en este equipo (127.0.0.1) y exige un token.',
            ),
            value: service.enabled,
            onChanged: service.setEnabled,
          ),
          if (service.problem != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                service.problem!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (service.enabled && service.running) ...[
            const Text(
              'El plugin de Stream Deck se conecta solo. Su URL y token '
              'aparecen aquí por si usas otro cliente.',
            ),
            const SizedBox(height: 4),
            SelectableText(service.baseUrl),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: () => copy(service.baseUrl, 'URL'),
                  icon: const Icon(Icons.link_rounded),
                  label: const Text('Copiar URL'),
                ),
                TextButton.icon(
                  onPressed: () => copy(service.token, 'Token'),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Copiar token'),
                ),
                TextButton.icon(
                  onPressed: service.regenerateToken,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Regenerar token'),
                ),
              ],
            ),
          ],
        ],
      );
    },
  );
}
