import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../audio/eq_model.dart';
import '../../audio/equalizer_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../studio/equalizer_panel.dart';
import '../track_actions.dart';

const _bandColors = [Slush.blue, Slush.mint, Slush.yellow, Color(0xffc9a8f5)];

BoxDecoration _card([Color color = Colors.white, double r = 28]) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(r),
      border: const Border.fromBorderSide(Slush.border),
    );

String _gain(double db) {
  final a = db.abs();
  final s = a % 1 < .05 ? a.round().toString() : a.toStringAsFixed(1);
  final sign = db > .04 ? '+' : (db < -.04 ? '−' : '');
  return '$sign$s dB';
}

/// Pantalla Slush «Ecualizador + Cola»: pestañas, EQ gigante, cola y
/// temporizador de apagado.
class SlushEqQueue extends StatefulWidget {
  const SlushEqQueue({
    super.key,
    required this.controller,
    required this.onNavigate,
    this.showQueueTab = false,
  });
  final AppController controller;
  final ValueChanged<int> onNavigate;
  final bool showQueueTab;
  @override
  State<SlushEqQueue> createState() => _SlushEqQueueState();
}

class _SlushEqQueueState extends State<SlushEqQueue> {
  int? _sleepChoice; // minutos; -1 = fin de canción

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ColoredBox(
      color: const Color(0xffd9dbe0),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final eq = EqualizerPanel(controller: c, slushBoard: true);
          final queue = _QueueCard(
            controller: c,
            onSearch: () => widget.onNavigate(1),
            fill: wide,
          );
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) Expanded(child: queue) else queue,
              const SizedBox(height: 16),
              _timer(c),
            ],
          );
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _top(c),
                const SizedBox(height: 20),
                if (wide)
                  SizedBox(
                    height: math.max(560.0, box.maxHeight - 140),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 11,
                          child: SingleChildScrollView(child: eq),
                        ),
                        const SizedBox(width: 24),
                        Expanded(flex: 8, child: side),
                      ],
                    ),
                  )
                else ...[
                  eq,
                  const SizedBox(height: 20),
                  side,
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _pill(String t, VoidCallback f, {IconData? icon}) => Material(
    color: Colors.white,
    shape: const StadiumBorder(side: Slush.border),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: f,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: Slush.ink),
              const SizedBox(width: 6),
            ],
            Text(
              t,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Slush.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _top(AppController c) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final left = c.sleepRemaining;
      final current = widget.showQueueTab ? 5 : 13;
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          _pill('VOLVER', () => widget.onNavigate(0), icon: Icons.arrow_back),
          DecoratedBox(
            decoration: _card(Colors.white, 40),
            child: Padding(
              padding: const EdgeInsets.all(4),
              // En el teléfono las cuatro pestañas no caben: se desplazan.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (label, idx) in [
                      ('VINILO', 4),
                      ('LETRAS', 6),
                      ('ECUALIZADOR', 13),
                      ('COLA', 5),
                    ])
                      _tab(label, idx == current, () => widget.onNavigate(idx)),
                  ],
                ),
              ),
            ),
          ),
          _pill(
            left == null ? 'ZZ · OFF' : 'ZZ · ${left.inMinutes + 1} MIN',
            () => setState(() {
              c.setSleepTimer(null);
              _sleepChoice = null;
            }),
            icon: Icons.bedtime_outlined,
          ),
        ],
      );
    },
  );

  Widget _tab(String t, bool on, VoidCallback f) => InkWell(
    customBorder: const StadiumBorder(),
    onTap: f,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: ShapeDecoration(
        color: on ? Slush.ink : Colors.transparent,
        shape: const StadiumBorder(),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: on ? Colors.white : Slush.ink,
        ),
      ),
    ),
  );

  Widget _timer(AppController c) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final active = c.sleepRemaining != null ? _sleepChoice : null;
      Widget chip(String t, int v) {
        final on = active == v;
        return InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            if (on) {
              c.setSleepTimer(null);
              setState(() => _sleepChoice = null);
              return;
            }
            Duration d;
            if (v < 0) {
              final left = c.audio.duration - c.audio.position;
              d = left > Duration.zero ? left : const Duration(minutes: 1);
            } else {
              d = Duration(minutes: v);
            }
            c.setSleepTimer(d);
            setState(() => _sleepChoice = v);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: ShapeDecoration(
              color: on ? Slush.ink : Colors.white,
              shape: const StadiumBorder(side: Slush.border),
            ),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : Slush.ink,
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 44, right: 20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: _card(Slush.mint),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Text(
                        'ZZ',
                        style: TextStyle(
                          fontFamily: 'Bagel Fat One',
                          fontSize: 40,
                          color: Slush.ink,
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Temporizador de apagado',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Slush.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      chip('15', 15),
                      chip('30', 30),
                      chip('45', 45),
                      chip('60', 60),
                      chip('FIN DE CANCIÓN', -1),
                    ],
                  ),
                ],
              ),
            ),
            const Positioned(
              right: -14,
              bottom: -44,
              child: SlushSticker('BOOM', size: 84),
            ),
          ],
        ),
      );
    },
  );
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.controller,
    required this.onSearch,
    this.fill = false,
  });
  final AppController controller;
  final VoidCallback onSearch;

  /// Ocupa toda la altura disponible (escritorio) en vez de encogerse.
  final bool fill;

  static String _kind(Track t) =>
      t.isLocal ? (t.pageUrl != null ? 'DESCARGADA' : 'LOCAL') : 'YOUTUBE';
  static String _time(Duration v) =>
      '${v.inMinutes}:${(v.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final q = c.queue;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'COLA',
                      style: TextStyle(
                        fontFamily: 'Bagel Fat One',
                        fontSize: 52,
                        height: 1,
                        color: Slush.ink,
                      ),
                    ),
                  ),
                ),
                Tooltip(
                  message: c.shuffle
                      ? 'Desactivar aleatorio'
                      : 'Activar aleatorio',
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => c.setShuffle(!c.shuffle),
                    child: SlushPill(
                      c.shuffle ? 'Aleatorio activo' : 'Aleatorio',
                      color: c.shuffle ? Slush.mint : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (q.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No hay canciones en la cola')),
              )
            else if (fill)
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: q.length,
                  onReorder: c.reorderQueue,
                  itemBuilder: (context, i) => _row(context, q[i], i),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: q.length,
                  onReorder: c.reorderQueue,
                  itemBuilder: (context, i) => _row(context, q[i], i),
                ),
              ),
            if (fill && q.isEmpty) const Spacer(),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onSearch,
              icon: const Icon(Icons.add, size: 16),
              label: const Text(
                'REPRODUCIR A CONTINUACIÓN…',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _row(BuildContext context, Track t, int i) {
    final c = controller;
    final active = i == c.queueIndex;
    final extras = [
      (label: 'Quitar de la cola', run: () => c.removeFromQueue(i)),
    ];
    return ReorderableDragStartListener(
      key: ValueKey('$i:${t.id}'),
      index: i,
      child: TrackActionsRegion(
        controller: c,
        track: t,
        extras: extras,
        builder: (context, _) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: active ? Slush.lilac : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: Slush.border,
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onTap: () => c.playQueueAt(i),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Artwork(track: t, size: 36, radius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            t.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    SlushPill(_kind(t), color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _time(t.duration),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TrackMenuButton(controller: c, track: t, extras: extras),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tablero del ecualizador Slush: «EQ» gigante, presets y ocho sliders píldora.
class SlushEqBoard extends StatefulWidget {
  const SlushEqBoard({
    super.key,
    required this.eq,
    required this.webPlayback,
    required this.selected,
    required this.onSelect,
    required this.onEngage,
    required this.onSave,
    required this.onImport,
    required this.onExport,
    this.message,
  });
  final EqualizerController eq;
  final bool webPlayback;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onEngage, onSave, onImport, onExport;
  final String? message;
  @override
  State<SlushEqBoard> createState() => _SlushEqBoardState();
}

class _SlushEqBoardState extends State<SlushEqBoard> {
  bool _fine = false;

  Widget _toggle(String t, bool v, ValueChanged<bool>? f) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Switch(
        value: v,
        onChanged: f,
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Slush.yellow : Colors.white,
        ),
      ),
      Text(
        t,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final eq = widget.eq;
    final ok = eq.supported;
    final sel = widget.selected.clamp(0, eq.bands.length - 1);
    final note = widget.webPlayback
        ? 'En canciones de YouTube el EQ se desactiva'
        : !ok
        ? 'Este dispositivo no ofrece EQ'
        : null;
    final band = eq.bands[sel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 16,
          children: [
            const Text(
              'EQ',
              style: TextStyle(
                fontFamily: 'Bagel Fat One',
                fontSize: 130,
                height: .95,
                color: Slush.ink,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '8 bandas DSP · preamp automático',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (note != null) ...[
                  const SizedBox(height: 6),
                  DecoratedBox(
                    decoration: _card(Colors.white, 20),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(
                            radius: 4,
                            backgroundColor: Slush.orange,
                          ),
                          const SizedBox(width: 6),
                          Text(note, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in eq.presets)
              GestureDetector(
                onLongPress: p.builtIn ? null : () => eq.deletePreset(p.name),
                child: _chip(
                  p.name.toUpperCase(),
                  eq.presetName == p.name,
                  ok
                      ? () {
                          eq.applyPreset(p);
                          widget.onEngage();
                        }
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              decoration: _card(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < eq.bands.length; i++)
                    Expanded(
                      child: _Band(
                        band: eq.bands[i],
                        color: _bandColors[i % _bandColors.length],
                        selected: i == sel,
                        enabled: ok,
                        onSelect: () => widget.onSelect(i),
                        onChanged: (db) {
                          widget.onEngage();
                          eq.setGain(i, db);
                        },
                        onReset: () => eq.resetBand(i),
                      ),
                    ),
                ],
              ),
            ),
            const Positioned(right: -10, top: -52, child: _Disc()),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            _toggle(
              'A/B sin EQ',
              eq.bypass,
              ok && eq.enabled ? eq.setBypass : null,
            ),
            _toggle(
              'Preamp automático',
              eq.autoPreamp,
              ok ? eq.setAutoPreamp : null,
            ),
            _toggle('EQ activo', eq.enabled, ok ? eq.setEnabled : null),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Slush.ink,
                foregroundColor: Colors.white,
              ),
              onPressed: ok ? widget.onSave : null,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('GUARDAR'),
            ),
            OutlinedButton(
              onPressed: widget.onImport,
              child: const Text('IMPORTAR'),
            ),
            OutlinedButton(
              onPressed: widget.onExport,
              child: const Text('EXPORTAR'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _fine = !_fine),
              child: Text(_fine ? 'OCULTAR AJUSTE' : 'AJUSTE FINO'),
            ),
          ],
        ),
        if (widget.message != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.message!,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        if (_fine) ...[
          const SizedBox(height: 8),
          Text(
            'Banda ${sel + 1} · ${eqFrequencyLabel(band.frequency)} · '
            '${_gain(band.gainDb)} · Q ${band.q.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          _fineSlider(
            'Frecuencia',
            math.log(band.frequency / eqMinHz) / math.log(eqMaxHz / eqMinHz),
            ok
                ? (t) {
                    widget.onEngage();
                    eq.setBand(
                      sel,
                      band.copyWith(
                        frequency: eqMinHz * math.pow(eqMaxHz / eqMinHz, t),
                      ),
                    );
                  }
                : null,
          ),
          _fineSlider(
            'Q (ancho)',
            math.log(band.q / eqMinQ) / math.log(eqMaxQ / eqMinQ),
            ok
                ? (t) {
                    widget.onEngage();
                    eq.setBand(
                      sel,
                      band.copyWith(q: eqMinQ * math.pow(eqMaxQ / eqMinQ, t)),
                    );
                  }
                : null,
          ),
          TextButton(
            onPressed: ok ? () => eq.resetBand(sel) : null,
            child: const Text('REINICIAR BANDA'),
          ),
        ],
      ],
    );
  }

  Widget _fineSlider(String l, double v, ValueChanged<double>? f) => Row(
    children: [
      SizedBox(width: 92, child: Text(l, style: const TextStyle(fontSize: 11))),
      Expanded(
        child: Slider(
          value: v.clamp(0.0, 1.0),
          onChanged: f,
          semanticFormatterCallback: (_) => l,
        ),
      ),
    ],
  );

  Widget _chip(String t, bool on, VoidCallback? f) => Material(
    color: on ? Slush.ink : Colors.white,
    shape: const StadiumBorder(side: Slush.border),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: f,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: on ? Colors.white : Slush.ink,
          ),
        ),
      ),
    ),
  );
}

class _Disc extends StatelessWidget {
  const _Disc();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 84,
      height: 84,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Slush.ink,
        border: Border.fromBorderSide(
          BorderSide(color: Colors.white, width: 3),
        ),
        boxShadow: [BoxShadow(color: Slush.ink, spreadRadius: 2)],
      ),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Slush.mint,
            border: Border.fromBorderSide(Slush.border),
          ),
          child: const Center(
            child: CircleAvatar(radius: 3, backgroundColor: Slush.ink),
          ),
        ),
      ),
    ),
  );
}

/// Slider vertical píldora: relleno desde 0 dB y perilla con «−».
class _Band extends StatelessWidget {
  const _Band({
    required this.band,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onSelect,
    required this.onChanged,
    required this.onReset,
  });
  final EqBand band;
  final Color color;
  final bool selected, enabled;
  final VoidCallback onSelect, onReset;
  final ValueChanged<double> onChanged;

  static const _h = 170.0, _w = 34.0, _k = 28.0;

  double _dbAt(double dy) {
    final t = ((dy - _k / 2) / (_h - _k)).clamp(0.0, 1.0);
    return ((eqMaxDb - t * (eqMaxDb - eqMinDb)) * 10).round() / 10;
  }

  @override
  Widget build(BuildContext context) {
    final t = (eqMaxDb - band.gainDb) / (eqMaxDb - eqMinDb);
    final knobY = _k / 2 + t * (_h - _k);
    final zeroY = _k / 2 + (eqMaxDb / (eqMaxDb - eqMinDb)) * (_h - _k);
    final top = math.min(knobY, zeroY), bottom = math.max(knobY, zeroY);
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _gain(band.gainDb),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 6),
        Semantics(
          label:
              '${eqFrequencyLabel(band.frequency)} ${band.gainDb.toStringAsFixed(1)} decibelios',
          slider: true,
          onIncrease: enabled
              ? () => onChanged((band.gainDb + .5).clamp(eqMinDb, eqMaxDb))
              : null,
          onDecrease: enabled
              ? () => onChanged((band.gainDb - .5).clamp(eqMinDb, eqMaxDb))
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: enabled ? onReset : null,
            onTapDown: enabled
                ? (d) {
                    onSelect();
                    onChanged(_dbAt(d.localPosition.dy));
                  }
                : null,
            onVerticalDragStart: enabled ? (_) => onSelect() : null,
            onVerticalDragUpdate: enabled
                ? (d) => onChanged(_dbAt(d.localPosition.dy))
                : null,
            child: SizedBox(
              width: _w + 8,
              height: _h,
              child: Center(
                child: SizedBox(
                  width: _w,
                  height: _h,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xffeaeaea),
                          borderRadius: BorderRadius.circular(_w / 2),
                          border: Border.all(
                            color: Slush.ink,
                            width: selected ? 3 : 2,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 2,
                        right: 2,
                        top: top,
                        height: bottom - top,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: color,
                            border: const Border.symmetric(
                              horizontal: BorderSide(
                                color: Slush.ink,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (_w - _k) / 2,
                        top: knobY - _k / 2,
                        child: Container(
                          width: _k,
                          height: _k,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            border: Border.fromBorderSide(Slush.border),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 9,
                              height: 2,
                              child: ColoredBox(color: Slush.ink),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: onSelect,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  eqFrequencyLabel(band.frequency, short: true).toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
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
