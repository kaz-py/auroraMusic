import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../account/lan_sync.dart';
import '../account/sync_store.dart';
import '../app_controller.dart';
import '../jam/jam_service.dart';
import 'jam/jam_qr_code.dart';
import 'jam/jam_scanner_dialog.dart';

/// Ajustes → Transferir por QR: pasa favoritos, listas, historial y gusto del
/// DJ a otro dispositivo **de la misma red**, sin servidor y sin cuenta. El
/// destino solo recibe lo que cambió desde la última vez.
class LanSyncPanel extends StatefulWidget {
  const LanSyncPanel({
    super.key,
    required this.controller,
    this.addresses,
    this.allowLoopback = false,
  });

  final AppController controller;

  /// Direcciones locales (por defecto, las de la red); inyectable en pruebas.
  final Future<List<String>> Function()? addresses;
  final bool allowLoopback;

  @override
  State<LanSyncPanel> createState() => _LanSyncPanelState();
}

class _LanSyncPanelState extends State<LanSyncPanel> {
  LanSyncServer? _server;
  String? _message;
  bool _busy = false;

  @override
  void dispose() {
    unawaited(_server?.stop());
    super.dispose();
  }

  void _say(String text) {
    if (mounted) setState(() => _message = text);
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final found = await (widget.addresses ?? JamService.localAddresses)();
      if (found.isEmpty) {
        _say(
          'No encontré una red local. Conéctate a una red Wi-Fi o Ethernet.',
        );
        return;
      }
      final c = widget.controller;
      await _server?.stop();
      final server = _server = LanSyncServer(
        c.database,
        deviceId: lanDeviceId(c.preferences),
        allowLoopback: widget.allowLoopback,
      );
      await c.database.seedSyncMeta();
      final invite = await server.start(found.first);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Escanéalo en el otro dispositivo'),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                JamQrCode(data: invite.encode()),
                const SizedBox(height: 12),
                Text(
                  'En Aurora del otro dispositivo: Ajustes → Cuenta y '
                  'servicios → Transferir por QR → Recibir. Ambos deben estar '
                  'en la misma red (${invite.address}). El código caduca en 5 minutos.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
      await server.stop();
    } catch (error) {
      _say('$error'.replaceFirst(RegExp(r'^[A-Za-z]*Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => const _CodeDialog(),
    );
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final c = widget.controller;
      final invite = LanSyncInvite.decode(
        text,
        allowLoopback: widget.allowLoopback,
      );
      final result = await LanSyncClient(
        c.database,
        c.preferences,
      ).receive(invite);
      if (result.total > 0) await c.reloadLibrary();
      final a = result.applied;
      _say(
        result.total == 0
            ? 'Ya estaba todo al día: no había nada nuevo que recibir.'
            : 'Recibido: ${a['favorites'] ?? 0} favoritos, '
                  '${a['playlists'] ?? 0} listas y ${a['history'] ?? 0} del historial.',
      );
    } on FormatException catch (error) {
      _say(error.message);
    } on LanSyncException catch (error) {
      _say(error.message);
    } catch (_) {
      _say('No se pudo completar la transferencia.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Pasa tus favoritos, listas e historial a otro dispositivo de la misma '
        'red con un código QR. No usa internet ni tu cuenta, y la segunda vez '
        'solo viaja lo que cambió.',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            key: const ValueKey('lan-send'),
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Enviar'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('lan-receive-open'),
            onPressed: _busy ? null : _receive,
            icon: const Icon(Icons.download),
            label: const Text('Recibir'),
          ),
        ],
      ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_message!, key: const ValueKey('lan-message')),
        ),
    ],
  );
}

/// Diálogo de «Recibir»: el controlador del campo vive con el diálogo (no se
/// libera mientras se anima el cierre).
class _CodeDialog extends StatefulWidget {
  const _CodeDialog();

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Recibir de otro dispositivo'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'En el otro dispositivo: Ajustes → Cuenta y servicios → '
          'Transferir por QR → Enviar. Escanea su código o pégalo aquí.',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('lan-code-field'),
          controller: _field,
          decoration: const InputDecoration(
            labelText: 'Código',
            hintText: 'aurora-sync:…',
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      if (Platform.isAndroid || Platform.isIOS)
        TextButton(
          key: const ValueKey('lan-scan'),
          onPressed: () async {
            final scanned = await showDialog<String>(
              context: context,
              builder: (_) => const JamScannerDialog(),
            );
            if (scanned != null && context.mounted) {
              Navigator.pop(context, scanned);
            }
          },
          child: const Text('Escanear'),
        ),
      FilledButton(
        key: const ValueKey('lan-receive'),
        onPressed: () => Navigator.pop(context, _field.text),
        child: const Text('Recibir'),
      ),
    ],
  );
}
