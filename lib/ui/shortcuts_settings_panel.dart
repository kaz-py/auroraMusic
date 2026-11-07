import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shortcuts/shortcut_service.dart';
import '../theme/slush_theme.dart';

class ShortcutsSettingsPanel extends StatefulWidget {
  const ShortcutsSettingsPanel({super.key, required this.service});
  final ShortcutService service;

  @override
  State<ShortcutsSettingsPanel> createState() => _ShortcutsSettingsPanelState();
}

class _ShortcutsSettingsPanelState extends State<ShortcutsSettingsPanel> {
  String? _message;

  void _say(String? error, String ok) => setState(() => _message = error ?? ok);

  Future<void> _capture(ShortcutId id) async {
    final captured = await showDialog<SingleActivator>(
      context: context,
      builder: (_) => _CaptureDialog(id: id),
    );
    if (captured == null) return;
    _say(widget.service.assign(id, captured), '${id.label}: asignado.');
  }

  Future<void> _import() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar atajos'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(hintText: 'Pega aquí el JSON'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (text != null) {
      _say(widget.service.importJson(text), 'Atajos importados.');
    }
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: widget.service.exportJson()));
    _say(null, 'JSON copiado al portapapeles.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.service,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                widget.service.resetAll();
                _say(null, 'Atajos restablecidos.');
              },
              icon: const Icon(Icons.restore),
              label: const Text('Restablecer todo'),
            ),
            OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_outlined),
              label: const Text('Exportar'),
            ),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download_outlined),
              label: const Text('Importar'),
            ),
          ],
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _message!,
              style: isSlush(context)
                  ? TextStyle(color: context.slush.ink2)
                  : null,
            ),
          ),
        for (final id in ShortcutId.values)
          isSlush(context)
              ? ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.service.isCustom(id)
                              ? '${id.label} *'
                              : id.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: OutlinedButton(
                          onPressed: () => _capture(id),
                          child: Text(
                            widget.service.labelOf(id),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Restablecer',
                        constraints: const BoxConstraints(
                          minWidth: 44,
                          minHeight: 44,
                        ),
                        onPressed: widget.service.isCustom(id)
                            ? () => widget.service.reset(id)
                            : null,
                        icon: const Icon(Icons.restore, size: 18),
                      ),
                    ],
                  ),
                )
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        widget.service.isCustom(id)
                            ? '${id.label} *'
                            : id.label,
                      ),
                    ),
                    OutlinedButton(
                      onPressed: () => _capture(id),
                      child: Text(widget.service.labelOf(id)),
                    ),
                    IconButton(
                      tooltip: 'Restablecer',
                      onPressed: widget.service.isCustom(id)
                          ? () => widget.service.reset(id)
                          : null,
                      icon: const Icon(Icons.restore, size: 18),
                    ),
                  ],
                ),
      ],
    ),
  );
}

class _CaptureDialog extends StatelessWidget {
  const _CaptureDialog({required this.id});
  final ShortcutId id;

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.handled;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        Navigator.pop(context);
        return KeyEventResult.handled;
      }
      if (HardwareKeyboard.instance.logicalKeysPressed.length == 1 &&
          _isModifier(key)) {
        return KeyEventResult.handled;
      }
      if (_isModifier(key)) return KeyEventResult.handled;
      final k = HardwareKeyboard.instance;
      Navigator.pop(
        context,
        SingleActivator(
          key,
          control: k.isControlPressed,
          shift: k.isShiftPressed,
          alt: k.isAltPressed,
          meta: k.isMetaPressed,
        ),
      );
      return KeyEventResult.handled;
    },
    child: AlertDialog(
      title: Text(id.label),
      content: const Text('Pulsa la nueva combinación (Esc cancela).'),
    ),
  );

  static bool _isModifier(LogicalKeyboardKey k) => {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  }.contains(k);
}
