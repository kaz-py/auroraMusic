import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../app_controller.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../jam/jam_qr.dart';
import 'jam_flows.dart';
import 'jam_scanner_dialog.dart';
import 'jam_session_panel.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../slush/slush_jam.dart';

class JamPage extends StatefulWidget {
  const JamPage({
    super.key,
    required this.controller,
    this.jam,
    this.onControllerReady,
  });
  final AppController controller;

  /// Controlador compartido con el resto de la app (barra, chip, panel).
  final JamController? jam;
  final ValueChanged<JamController>? onControllerReady;
  @override
  State<JamPage> createState() => _JamPageState();
}

class _JamPageState extends State<JamPage> {
  JamController? _jam;
  final _name = TextEditingController();
  final _code = TextEditingController();
  String? _inputError;
  bool _readingImage = false;
  JamController get jam {
    if (_jam != null) return _jam!;
    final created = widget.jam ?? JamController(app: widget.controller);
    created.addListener(_changed);
    _jam = created;
    widget.onControllerReady?.call(created);
    return created;
  }

  @override
  void initState() {
    super.initState();
    _name.text = widget.controller.profileName.trim();
    if (widget.jam != null) {
      jam; // registra el oyente del controlador compartido
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _jam?.removeListener(_changed);
    if (widget.jam == null) _jam?.dispose();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  String _participantName({bool host = false}) {
    final typed = _name.text.trim();
    if (typed.isNotEmpty) return typed;
    final profile = widget.controller.profileName.trim();
    return profile.isNotEmpty ? profile : (host ? 'Anfitrión' : 'Invitado');
  }

  Future<void> _join(String value) async {
    _inputError = null;
    await jam.join(value, _participantName());
    if (mounted && jam.service.connected) _code.clear();
  }

  Future<void> _scan() async {
    jam;
    if (!Platform.isAndroid) {
      await _readImage();
      return;
    }
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const JamScannerDialog(),
    );
    if (code != null && mounted) await _join(code);
  }

  Future<void> _readImage() async {
    jam;
    setState(() {
      _readingImage = true;
      _inputError = null;
    });
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (result.isEmpty || !mounted) return;
      final selected = result.single;
      if (selected.path == null) {
        throw const JamException('La imagen QR debe pesar menos de ocho MiB.');
      }
      final file = File(selected.path!);
      if (await file.length() > jamMaxImageBytes) {
        throw const JamException('La imagen QR es demasiado grande.');
      }
      final value = await decodeJamQrImage(await file.readAsBytes());
      if (mounted) await _join(value);
    } catch (failure) {
      if (mounted) {
        _inputError = failure is JamException
            ? failure.message
            : 'No se pudo abrir la imagen QR.';
      }
    } finally {
      if (mounted) setState(() => _readingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _jam;
    final session = c?.service;
    final active =
        session?.connected == true ||
        session?.connection == JamConnection.disconnected &&
            session?.invite != null;
    final busy = c?.busy == true || _readingImage;
    final colors = Theme.of(context).colorScheme;
    final message = _inputError ?? c?.error ?? session?.error;
    if (isSlush(context)) {
      return ColoredBox(
        color: context.slush.paper,
        child: active
            ? SlushJamActive(controller: c!)
            : SlushJamIdle(
                name: _name,
                code: _code,
                busy: busy,
                message: message,
                onStart: () => startJamFlow(
                  context,
                  jam,
                  name: _participantName(host: true),
                ),
                onJoin: () => _join(_code.text),
                onScan: _scan,
                scanLabel: Platform.isAndroid
                    ? 'Escanear QR'
                    : 'Importar imagen QR',
              ),
      );
    }
    final header = <Widget>[
      if (isSlush(context))
        Text(
          'JAM',
          style: Theme.of(
            context,
          ).textTheme.displayLarge?.copyWith(fontSize: 96, height: .9),
        )
      else if (isModern(context)) ...[
        const Align(alignment: Alignment.centerLeft, child: ModernBadge('Jam')),
        const SizedBox(height: 12),
        ModernHeadline(
          before: active ? 'Una cola ' : 'Escuchen ',
          emphasis: active ? 'compartida' : 'juntos',
          size: 40,
        ),
      ] else
        Text('Jam', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 8),
      Text(
        active
            ? 'Una cola para quienes están contigo.'
            : 'Escuchen juntos: todos añaden canciones y Aurora mezcla lo que le gusta a cada quien.',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
      ),
      const SizedBox(height: 16),
      if (busy) const LinearProgressIndicator(),
      if (message != null && !active) ...[
        _notice(message, Icons.info_outline),
        const SizedBox(height: 16),
      ],
    ];
    final page = Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: active
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...header,
                    Expanded(child: JamSessionPanel(controller: c!)),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [...header, ..._idle(c, busy)],
                  ),
                ),
        ),
      ),
    );
    // Slush: Jam sobre fondo blanco.
    return isSlush(context)
        ? ColoredBox(color: context.slush.paper, child: page)
        : page;
  }

  List<Widget> _idle(JamController? c, bool busy) => [
    FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(220, 52)),
      onPressed: busy
          ? null
          : () =>
                startJamFlow(context, jam, name: _participantName(host: true)),
      icon: const Icon(Icons.group_add_outlined),
      label: const Text('Iniciar una Jam'),
    ),
    const SizedBox(height: 4),
    const Text(
      'Se crea al instante y te mostramos el QR y el código para invitar.',
      style: TextStyle(fontSize: 12),
    ),
    const SizedBox(height: 32),
    Text('Unirme a una Jam', style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    TextField(
      controller: _name,
      maxLength: 32,
      decoration: const InputDecoration(
        labelText: 'Tu nombre (opcional)',
        hintText: 'Se verá junto a las canciones que añadas',
      ),
    ),
    TextField(
      controller: _code,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.go,
      onSubmitted: busy ? null : _join,
      decoration: const InputDecoration(
        labelText: 'Código o enlace de la Jam',
        hintText: 'Por ejemplo K7M2QX',
      ),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: busy ? null : () => _join(_code.text),
          child: const Text('Unirme'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(
            Platform.isAndroid ? 'Escanear QR' : 'Importar imagen QR',
          ),
        ),
      ],
    ),
    const SizedBox(height: 24),
    _notice(
      'Cada dispositivo usa sus propias fuentes de audio; los archivos locales no se envían.',
      Icons.info_outline,
    ),
  ];

  Widget _notice(String message, IconData icon, {Widget? action}) =>
      jamNotice(context, message, icon, action: action);
}
