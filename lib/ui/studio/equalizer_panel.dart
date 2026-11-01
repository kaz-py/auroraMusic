import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_controller.dart';
import '../../audio/eq_model.dart';
import '../../audio/equalizer_controller.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../slush/slush_eq_queue.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

/// Hoja compacta con el ecualizador: se abre sobre la pantalla actual (Jam,
/// cola, letras…) sin salir de ella. Reutiliza [EqualizerPanel].
Future<void> showEqualizerSheet(BuildContext context, AppController c) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: EqualizerPanel(
          controller: c,
          onClose: () => Navigator.pop(context),
        ),
      ),
    );

String eqFrequencyLabel(double f, {bool short = false}) {
  if (f >= 1000) {
    final k = (f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1);
    return short ? '${k}k' : '$k kHz';
  }
  return short ? '${f.round()}' : '${f.round()} Hz';
}

String eqGainLabel(double db) => '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)}';

/// Panel del ecualizador paramétrico: curva sobre el espectro, presets,
/// ocho bandas y ajuste fino de la banda elegida. Es el único panel de EQ de
/// la aplicación (lateral, hoja de la barra y Ajustes).
class EqualizerPanel extends StatefulWidget {
  const EqualizerPanel({
    super.key,
    required this.controller,
    this.onClose,
    this.slushBoard = false,
  });

  /// Layout Slush completo (pantalla EQ + Cola); false = versión compacta.
  final bool slushBoard;
  final AppController controller;
  final VoidCallback? onClose;
  @override
  State<EqualizerPanel> createState() => _EqualizerPanelState();
}

class _EqualizerPanelState extends State<EqualizerPanel> {
  int _selected = 0;
  String? _message;

  EqualizerController get _eq => widget.controller.eq;

  /// Tocar un control equivale a querer oír el resultado.
  void _engage() {
    if (!_eq.enabled) {
      _eq.setEnabled(true);
    } else if (_eq.bypass) {
      _eq.setBypass(false);
    }
  }

  Future<void> _save() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _PromptDialog(
        title: 'Guardar preset',
        hint: 'Nombre del preset',
        action: 'Guardar',
      ),
    );
    if (name == null || !mounted) return;
    setState(
      () => _message = _eq.savePreset(name)
          ? 'Preset «${name.trim()}» guardado.'
          : 'Nombre no válido o reservado.',
    );
  }

  Future<void> _import() async {
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _PromptDialog(
        title: 'Importar presets',
        hint: 'Pega aquí el JSON exportado',
        action: 'Importar',
        initial: clip.trimLeft().startsWith('{') ? clip : '',
        multiline: true,
      ),
    );
    if (text == null || !mounted) return;
    try {
      final added = _eq.importPresets(text);
      setState(() => _message = '$added preset(s) importado(s).');
    } on FormatException catch (error) {
      setState(() => _message = error.message);
    }
  }

  Future<void> _export() async {
    await Clipboard.setData(ClipboardData(text: _eq.exportPresets()));
    if (mounted) {
      setState(() => _message = 'JSON de tus presets copiado al portapapeles.');
    }
  }

  @override
  Widget build(BuildContext context) => widget.slushBoard && isSlush(context)
      ? ListenableBuilder(
          listenable: _eq,
          builder: (context, _) => SlushEqBoard(
            eq: _eq,
            webPlayback: widget.controller.webPlayback,
            selected: _selected,
            onSelect: (i) => setState(() => _selected = i),
            onEngage: _engage,
            onSave: _save,
            onImport: _import,
            onExport: _export,
            message: _message,
          ),
        )
      : isBrasa(context)
      ? DecoratedBox(
          decoration: BoxDecoration(
            color: Brasa.obsidian,
            borderRadius: BorderRadius.circular(6),
            boxShadow: Brasa.cardShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _panel(context),
          ),
        )
      : _panel(context);

  Widget _panel(BuildContext context) => ListenableBuilder(
    listenable: _eq,
    builder: (context, _) {
      final eq = _eq;
      final c = widget.controller;
      final colors = Theme.of(context).colorScheme;
      final supported = eq.supported;
      final selected = _selected.clamp(0, eq.bands.length - 1);
      final band = eq.bands[selected];
      final status = eq.active
          ? 'EQ ACTIVO'
          : eq.enabled && eq.bypass
          ? 'EQ EN A/B'
          : 'EQ INACTIVO';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(StudioSymbols.tune, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Ecualizador',
                      style: isBrasa(context)
                          ? const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Brasa.cream,
                            )
                          : isModern(context)
                          ? const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              letterSpacing: -.16,
                              fontWeight: FontWeight.w600,
                            )
                          : const TextStyle(
                              fontFamily: 'Newsreader',
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                    ),
                    StudioStamp(status, filled: true),
                  ],
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Cerrar ecualizador',
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            supported
                ? 'Ajuste local de este dispositivo; no se comparte en una Jam.'
                : c.webPlayback
                ? 'El ecualizador no se aplica al reproductor oficial de YouTube Music.'
                : 'Este dispositivo no ofrece un ecualizador compatible.',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 12),
          _EqChart(
            bands: eq.bands,
            spectrum: c.audio.spectrum,
            active: eq.active,
            selected: selected,
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StudioStamp('20 Hz'),
              StudioStamp('1 kHz'),
              StudioStamp('20 kHz'),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Ecualizador', style: TextStyle(fontSize: 13)),
            value: eq.enabled,
            onChanged: supported ? eq.setEnabled : null,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilterChip(
                tooltip: 'Compara con y sin ecualizador sin perder el ajuste',
                avatar: const Icon(Icons.compare_arrows, size: 16),
                label: const Text('A/B sin EQ'),
                selected: eq.bypass,
                onSelected: supported && eq.enabled ? eq.setBypass : null,
              ),
              FilterChip(
                tooltip:
                    'Baja el nivel general para que las subidas no recorten',
                label: const Text('Preamp automático'),
                selected: eq.autoPreamp,
                onSelected: supported ? eq.setAutoPreamp : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const StudioStamp('PRESETS'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              for (final preset in eq.presets)
                preset.builtIn
                    ? ChoiceChip(
                        label: Text(preset.name),
                        selected: eq.presetName == preset.name,
                        onSelected: supported
                            ? (_) {
                                eq.applyPreset(preset);
                                _engage();
                              }
                            : null,
                      )
                    : InputChip(
                        label: Text(preset.name),
                        selected: eq.presetName == preset.name,
                        onPressed: supported
                            ? () {
                                eq.applyPreset(preset);
                                _engage();
                              }
                            : null,
                        onDeleted: () => eq.deletePreset(preset.name),
                        deleteButtonTooltipMessage:
                            'Eliminar preset ${preset.name}',
                      ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: supported ? _save : null,
                icon: const Icon(StudioSymbols.bookmarkAdd, size: 16),
                label: const Text('Guardar'),
              ),
              TextButton.icon(
                onPressed: _import,
                icon: const Icon(StudioSymbols.uploadFile, size: 16),
                label: const Text('Importar'),
              ),
              TextButton.icon(
                onPressed: _export,
                icon: const Icon(StudioSymbols.share, size: 16),
                label: const Text('Exportar'),
              ),
            ],
          ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: Text(_message!, style: const TextStyle(fontSize: 11)),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < eq.bands.length; i++)
                Expanded(
                  child: _BandColumn(
                    band: eq.bands[i],
                    selected: i == selected,
                    enabled: supported,
                    onSelect: () => setState(() => _selected = i),
                    onChanged: (db) {
                      _engage();
                      eq.setGain(i, db);
                    },
                    onReset: () => eq.resetBand(i),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Banda ${selected + 1} · ${eqFrequencyLabel(band.frequency)} · '
            '${eqGainLabel(band.gainDb)} dB · Q ${band.q.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          _LabeledSlider(
            label: 'Frecuencia',
            value:
                math.log(band.frequency / eqMinHz) /
                math.log(eqMaxHz / eqMinHz),
            display: eqFrequencyLabel(band.frequency),
            onChanged: supported
                ? (t) {
                    _engage();
                    eq.setBand(
                      selected,
                      band.copyWith(
                        frequency: eqMinHz * math.pow(eqMaxHz / eqMinHz, t),
                      ),
                    );
                  }
                : null,
          ),
          _LabeledSlider(
            label: 'Q (ancho)',
            value: math.log(band.q / eqMinQ) / math.log(eqMaxQ / eqMinQ),
            display: band.q.toStringAsFixed(2),
            onChanged: supported
                ? (t) {
                    _engage();
                    eq.setBand(
                      selected,
                      band.copyWith(q: eqMinQ * math.pow(eqMaxQ / eqMinQ, t)),
                    );
                  }
                : null,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: supported ? () => eq.resetBand(selected) : null,
              icon: const Icon(StudioSymbols.restartAlt, size: 16),
              label: const Text('Reiniciar banda'),
            ),
          ),
          const Text(
            'Doble clic en una banda la reinicia. Pasos de 0,1 dB, ±12 dB.',
            style: TextStyle(fontSize: 10),
          ),
        ],
      );
    },
  );
}

class _BandColumn extends StatelessWidget {
  const _BandColumn({
    required this.band,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
    required this.onReset,
  });
  final EqBand band;
  final bool selected, enabled;
  final VoidCallback onSelect, onReset;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brasa = isBrasa(context);
    final slush = isSlush(context);
    final modern = isModern(context) || brasa;
    final style = TextStyle(
      fontFamily: modern ? 'Inter' : 'monospace',
      fontSize: modern ? 10 : 9,
      color: brasa
          ? (selected ? Brasa.cream : Brasa.steel)
          : slush
          // Seleccionada: sobre menta plana, tinta fija; si no, sobre papel.
          ? (selected ? Slush.ink : colors.onSurfaceVariant)
          : modern
          ? (selected ? Tracky.navy : Tracky.slate)
          : selected
          ? colors.primary
          : colors.onSurfaceVariant,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
    );
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          // La ganancia va sobre papel (no sobre la banda menta): tinta del tema.
          child: Text(
            eqGainLabel(band.gainDb),
            style: slush ? style.copyWith(color: colors.onSurface) : style,
          ),
        ),
        GestureDetector(
          onDoubleTap: enabled ? onReset : null,
          child: SizedBox(
            height: 112,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: band.gainDb,
                  min: eqMinDb,
                  max: eqMaxDb,
                  divisions: ((eqMaxDb - eqMinDb) * 10).round(),
                  onChangeStart: (_) => onSelect(),
                  onChanged: enabled ? onChanged : null,
                  semanticFormatterCallback: (v) =>
                      '${eqFrequencyLabel(band.frequency)} ${v.toStringAsFixed(1)} decibelios',
                ),
              ),
            ),
          ),
        ),
        InkWell(
          onTap: onSelect,
          borderRadius: modern ? BorderRadius.circular(8) : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: brasa && selected
                    ? Brasa.graphite
                    : modern && !brasa && selected
                    ? (slush
                          ? Slush.mint
                          : Tracky.mint.withValues(alpha: .5))
                    : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    eqFrequencyLabel(band.frequency, short: true),
                    style: style,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.display,
    required this.onChanged,
  });
  final String label, display;
  final double value;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 92,
        child: Text(
          label,
          style: const TextStyle(fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      Expanded(
        child: Slider(
          value: value.clamp(0.0, 1.0),
          onChanged: onChanged,
          semanticFormatterCallback: (_) => '$label $display',
        ),
      ),
    ],
  );
}

/// Curva de respuesta (20 Hz a 20 kHz, ±12 dB) dibujada sobre el espectro.
class _EqChart extends StatelessWidget {
  const _EqChart({
    required this.bands,
    required this.spectrum,
    required this.active,
    required this.selected,
  });
  final List<EqBand> bands;
  final ValueListenable<List<double>> spectrum;
  final bool active;
  final int selected;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final curve = eqResponseCurve(bands);
    return Semantics(
      label: 'Curva de respuesta del ecualizador',
      child: SizedBox(
        height: 120,
        width: double.infinity,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _EqChartPainter(
              curve: curve,
              bands: bands,
              spectrum: spectrum,
              active: active,
              selected: selected,
              line: active ? colors.primary : colors.outline,
              bars: colors.primary.withValues(alpha: .22),
              grid: colors.outlineVariant,
              ground: colors.surfaceContainerLowest,
            ),
          ),
        ),
      ),
    );
  }
}

class _EqChartPainter extends CustomPainter {
  _EqChartPainter({
    required this.curve,
    required this.bands,
    required this.spectrum,
    required this.active,
    required this.selected,
    required this.line,
    required this.bars,
    required this.grid,
    required this.ground,
  }) : super(repaint: spectrum);
  final List<double> curve;
  final List<EqBand> bands;
  final ValueListenable<List<double>> spectrum;
  final bool active;
  final int selected;
  final Color line, bars, grid, ground;

  static double _x(double hz, double w) =>
      (math.log(hz / eqMinHz) / math.log(eqMaxHz / eqMinHz)).clamp(0, 1) * w;
  static double _y(double db, double h) =>
      h / 2 - db.clamp(eqMinDb, eqMaxDb) / eqMaxDb * (h / 2 - 2);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final db in [-12.0, -6.0, 0.0, 6.0, 12.0]) {
      canvas.drawLine(
        Offset(0, _y(db, h)),
        Offset(w, _y(db, h)),
        gridPaint..color = grid.withValues(alpha: db == 0 ? .9 : .4),
      );
    }
    for (final hz in [100.0, 1000.0, 10000.0]) {
      canvas.drawLine(
        Offset(_x(hz, w), 0),
        Offset(_x(hz, w), h),
        gridPaint..color = grid.withValues(alpha: .4),
      );
    }
    // Barras del mixer: la barra i está en 93,75 Hz · 256^((i + .5) / n).
    final values = spectrum.value;
    final n = values.length;
    final barPaint = Paint()..color = bars;
    for (var i = 0; i < n; i++) {
      final v = values[i].isFinite ? values[i].clamp(0.0, 1.0) : 0.0;
      if (v <= 0) continue;
      final hz = 93.75 * math.pow(256, (i + .5) / n);
      final bw = math.max(2.0, w / n * .7);
      canvas.drawRect(
        Rect.fromLTWH(_x(hz, w) - bw / 2, h - v * (h - 4), bw, v * (h - 4)),
        barPaint,
      );
    }
    final path = Path();
    for (var i = 0; i < curve.length; i++) {
      final x = i / (curve.length - 1) * w;
      final y = _y(curve[i].isFinite ? curve[i] : 0, h);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var i = 0; i < bands.length; i++) {
      canvas.drawCircle(
        Offset(_x(bands[i].frequency, w), _y(bands[i].gainDb, h)),
        i == selected ? 5 : 3,
        Paint()..color = i == selected ? line : line.withValues(alpha: .7),
      );
    }
  }

  @override
  bool shouldRepaint(_EqChartPainter old) =>
      old.curve != curve ||
      old.active != active ||
      old.selected != selected ||
      old.line != line ||
      old.spectrum != spectrum;
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.hint,
    required this.action,
    this.initial = '',
    this.multiline = false,
  });
  final String title, hint, action, initial;
  final bool multiline;
  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _text = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _text,
      autofocus: true,
      maxLines: widget.multiline ? 6 : 1,
      maxLength: widget.multiline ? null : 40,
      decoration: InputDecoration(labelText: widget.hint),
      onSubmitted: widget.multiline ? null : (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _text.text),
        child: Text(widget.action),
      ),
    ],
  );
}
