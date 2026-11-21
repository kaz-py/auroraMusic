import 'package:flutter/material.dart';

import '../bridge/api/voice.dart' as rust;
import 'voice_command_service.dart';

/// Sección de Ajustes «Comandos de voz»: interruptor, estado y frases.
class VoiceSettings extends StatelessWidget {
  const VoiceSettings({super.key, required this.service});

  final VoiceCommandService service;

  static const _names = {
    rust.VoiceIntent.pause: 'Pausar',
    rust.VoiceIntent.resume: 'Continuar',
    rust.VoiceIntent.play: 'Reproducir música',
    rust.VoiceIntent.next: 'Siguiente canción',
    rust.VoiceIntent.previous: 'Canción anterior',
  };

  String _status() => switch (service.state) {
    VoiceState.off => '',
    VoiceState.downloading =>
      'Descargando el modelo de voz (180 MB)… ${(service.progress * 100).round()} %',
    VoiceState.starting => 'Iniciando el micrófono…',
    VoiceState.listening =>
      service.awaitingCommand
          ? 'Te escucho… di la orden.'
          : 'Escuchando. Di «Aurora» y la orden.',
    VoiceState.error => service.error ?? 'No se pudo activar.',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final theme = Theme.of(context);
      final busy =
          service.state == VoiceState.downloading ||
          service.state == VoiceState.starting;
      final phrases = rust.voicePhrases();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('voice-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar comandos de voz'),
            subtitle: const Text(
              'Aurora escucha el micrófono y solo obedece lo que empieza por '
              '«Aurora». El audio se reconoce en este equipo con Whisper: no '
              'se guarda ni se envía. Se descarga un modelo de ≈ 180 MB.',
            ),
            value: service.enabled,
            onChanged: busy ? null : service.setEnabled,
          ),
          if (service.state == VoiceState.downloading || service.modelBusy)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(value: service.progress),
            ),
          if (service.enabled && _status().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _status(),
                key: const ValueKey('voice-status'),
                style: service.state == VoiceState.error
                    ? TextStyle(color: theme.colorScheme.error)
                    : null,
              ),
            ),
          if (service.state == VoiceState.listening &&
              service.lastHeard != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Escuché: “${service.lastHeard}”',
                key: const ValueKey('voice-heard'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (service.state == VoiceState.listening && service.microphoneSilent)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'El micrófono no entrega sonido. Comprueba que no esté '
                'silenciado y que Windows permita a las apps de escritorio '
                'usarlo (Configuración → Privacidad → Micrófono).',
                key: const ValueKey('voice-silent'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (service.state == VoiceState.listening)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(
                // Nivel del micrófono: si no se mueve al hablar, no llega audio.
                value: (service.level * 4).clamp(0.02, 1.0),
                minHeight: 4,
              ),
            ),
          const SizedBox(height: 4),
          SwitchListTile(
            key: const ValueKey('lyrics-sync-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Sincronizar las letras con el audio'),
            subtitle: const Text(
              'Mide cuánto se desvía la letra respecto a la canción (por '
              'ejemplo, por una introducción larga) y la corrige sola. Analiza '
              'el audio una vez por canción, en segundo plano, con el mismo '
              'modelo de voz (≈ 180 MB).',
            ),
            value: service.lyricsSyncEnabled,
            onChanged: busy || service.modelBusy ? null : service.setLyricsSync,
          ),
          SwitchListTile(
            key: const ValueKey('voice-diagnostics-switch'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Guardar diagnóstico de voz'),
            subtitle: Text(
              'Para saber por qué una orden no se reconoce: guarda en este '
              'equipo las últimas 40 frases (audio y lo que se entendió) en '
              '${service.diagnosticsDirectory.path}. No se envía a ningún sitio.',
            ),
            value: service.diagnosticsEnabled,
            onChanged: busy ? null : service.setDiagnostics,
          ),
          if (service.modelError != null)
            Text(
              service.modelError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (service.lastCommand != null)
            Text('Última orden: ${service.lastCommand}'),
          if (service.state == VoiceState.listening || !service.enabled) ...[
            const SizedBox(height: 8),
            Text('Ejemplos', style: theme.textTheme.labelLarge),
            for (final group in phrases)
              Text(
                '${_names[group.intent]}: '
                '${group.phrases.take(3).map((t) => '«Aurora, $t»').join(', ')}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      );
    },
  );
}
