import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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

BoxDecoration _card(BuildContext context, [Color? color, double r = 28]) =>
    BoxDecoration(
      color: color ?? context.slush.paper,
      borderRadius: BorderRadius.circular(r),
      border: Border.fromBorderSide(context.slush.border),
    );

String _gain(double db) {
  final a = db.abs();
  final s = a % 1 < .05 ? a.round().toString() : a.toStringAsFixed(1);
  final sign = db > .04 ? '+' : (db < -.04 ? '−' : '');
  return '$sign$s dB';
}

/// Pantallas Slush de Cola y Ecualizador. Con [queueFirst] la cola es el
/// contenido principal (lista a alto completo, único scroll vertical) y el EQ
/// queda a un lado en ancho; sin él, el EQ lidera. En estrecho cada vista
/// ocupa su propia pestaña: Cola o Ecualizador.
class SlushEqQueue extends StatefulWidget {
  const SlushEqQueue({
    super.key,
    required this.controller,
    required this.onNavigate,
    this.queueFirst = false,
  });
  final AppController controller;
  final ValueChanged<int> onNavigate;
  final bool queueFirst;
  @override
  State<SlushEqQueue> createState() => _SlushEqQueueState();
}

class _SlushEqQueueState extends State<SlushEqQueue> {
  int? _sleepChoice; // minutos; -1 = fin de canción

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ColoredBox(
      color: context.slush.screen,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 900;
          final eq = EqualizerPanel(controller: c, slushBoard: true);
          final queue = _QueueCard(
            controller: c,
            onSearch: () => widget.onNavigate(1),
            fill: wide || widget.queueFirst,
          );
          if (widget.queueFirst && !wide) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _top(c),
                  const SizedBox(height: 20),
                  Expanded(child: queue),
                ],
              ),
            );
          }
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) ...[Expanded(child: queue), const SizedBox(height: 16)],
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
                        if (widget.queueFirst) ...[
                          Expanded(flex: 11, child: side),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 9,
                            child: SingleChildScrollView(child: eq),
                          ),
                        ] else ...[
                          Expanded(
                            flex: 11,
                            child: SingleChildScrollView(child: eq),
                          ),
                          const SizedBox(width: 24),
                          Expanded(flex: 8, child: side),
                        ],
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
    color: context.slush.paper,
    shape: StadiumBorder(side: context.slush.border),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: f,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: context.slush.ink),
              const SizedBox(width: 6),
            ],
            Text(
              t,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.slush.ink,
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
      final current = widget.queueFirst ? 5 : 13;
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 10,
        spacing: 12,
        children: [
          _pill('VOLVER', () => widget.onNavigate(0), icon: Icons.arrow_back),
          DecoratedBox(
            decoration: _card(context, null, 40),
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
        color: on ? context.slush.ink : Colors.transparent,
        shape: const StadiumBorder(),
      ),
      child: Text(
        t,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: on ? context.slush.paper : context.slush.ink,
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
              color: on ? context.slush.ink : context.slush.paper,
              shape: StadiumBorder(side: context.slush.border),
            ),
            child: Text(
              t,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: on ? context.slush.paper : context.slush.ink,
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
              decoration: _card(context, Slush.mint),
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

class _QueueCard extends StatefulWidget {
  const _QueueCard({
    required this.controller,
    required this.onSearch,
    this.fill = false,
  });
  final AppController controller;
  final VoidCallback onSearch;

  /// Ocupa toda la altura disponible (escritorio) en vez de encogerse.
  final bool fill;

  @override
  State<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<_QueueCard> {
  /// Alto medio de una fila: solo estima dónde está una fila aún sin construir.
  static const _rowExtent = 60.0;

  final _scroll = ScrollController();
  final _currentKey = GlobalKey();
  String? _sig;

  /// La lista sigue a la canción mientras el usuario no se aleje a mano.
  bool _follow = true;
  bool _endPending = false;
  bool _syncQueued = false;

  /// Dónde queda la fila actual respecto a la ventana: -1 arriba, 1 abajo.
  int _away = 0;
  bool _showPlayed = false;

  /// Filas escuchadas ocultas arriba (desplazan los índices de la lista).
  int _hidden = 0;

  AppController get _c => widget.controller;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  static String _kind(Track t) =>
      t.isLocal ? (t.pageUrl != null ? 'DESCARGADA' : 'LOCAL') : 'YOUTUBE';
  static String _time(Duration v) =>
      '${v.inMinutes}:${(v.inSeconds % 60).toString().padLeft(2, '0')}';
  static String _left(Duration v) {
    final m = (v.inSeconds / 60).ceil();
    return m >= 60
        ? '${m ~/ 60} H ${(m % 60).toString().padLeft(2, '0')} MIN'
        : '$m MIN';
  }

  /// Resumen vivo: cuántas faltan y cuánto queda (lo que resta de la actual
  /// más lo que viene). En aleatorio el orden lo decide el azar.
  String _summary(bool ordered) {
    final c = _c;
    final q = c.queue;
    if (q.isEmpty) return '';
    if (c.shuffle) return 'ALEATORIO · ${q.length} EN COLA';
    if (!ordered) return '${q.length} EN COLA';
    final rest = q.skip(c.queueIndex + 1).toList();
    var left = c.queue[c.queueIndex].duration - c.audio.position;
    if (left.isNegative) left = Duration.zero;
    var unknown = false;
    for (final t in rest) {
      left += t.duration;
      unknown |= t.duration == Duration.zero;
    }
    return '${rest.length} A CONTINUACIÓN · ${_left(left)}${unknown ? '+' : ''} RESTANTES';
  }

  // --- scroll -------------------------------------------------------------

  RenderAbstractViewport? _viewportOf(RenderObject? ro) =>
      ro == null ? null : RenderAbstractViewport.maybeOf(ro);

  /// 0 = la fila actual se ve entera; -1 = queda arriba; 1 = queda abajo.
  int _awayDirection() {
    if (!_scroll.hasClients || _c.currentTrack == null) return 0;
    final p = _scroll.position;
    final ro = _currentKey.currentContext?.findRenderObject();
    final vp = _viewportOf(ro);
    if (ro == null || vp == null) {
      return (_c.queueIndex - _hidden) * _rowExtent < p.pixels ? -1 : 1;
    }
    double at(double a) => vp
        .getOffsetToReveal(ro, a)
        .offset
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    if (p.pixels > at(0) + 1) return -1;
    if (p.pixels < at(1) - 1) return 1;
    return 0;
  }

  void _setAway(int d) {
    if (d != _away && mounted) setState(() => _away = d);
  }

  /// Lleva la fila actual a la vista (sin mover nada si ya se ve).
  void _reveal({bool animate = true, int retry = 1}) {
    if (!mounted || !_scroll.hasClients) return;
    if (_awayDirection() == 0) return _setAway(0);
    final p = _scroll.position;
    final ro = _currentKey.currentContext?.findRenderObject();
    final vp = _viewportOf(ro);
    final built = ro != null && vp != null;
    final target =
        (built
                ? vp.getOffsetToReveal(ro, .3).offset
                : (_c.queueIndex - _hidden) * _rowExtent -
                      p.viewportDimension * .3)
            .clamp(p.minScrollExtent, p.maxScrollExtent);
    _setAway(0);
    if (animate && built && !_c.reducedMotion) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scroll.jumpTo(target);
    }
    // Sin construir solo se estimó: se afina cuando la fila ya existe.
    if (!built && retry > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(animate: animate, retry: retry - 1),
      );
    }
  }

  void _onChange(String sig) {
    if (sig == _sig) return;
    final first = _sig == null;
    _sig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_follow) {
        _reveal(animate: !first);
      } else {
        _setAway(_awayDirection());
      }
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    // Solo el gesto o la rueda del usuario son «UserScroll»: animateTo no.
    if (n is UserScrollNotification && n.direction != ScrollDirection.idle) {
      _follow = false;
    }
    if (n is ScrollEndNotification) _endPending = true;
    if ((n is ScrollUpdateNotification || n is ScrollEndNotification) &&
        !_syncQueued) {
      _syncQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncQueued = false;
        if (!mounted) return;
        final d = _awayDirection();
        // Al soltar con la actual a la vista, la lista vuelve a seguirla.
        if (_endPending && d == 0) _follow = true;
        _endPending = false;
        _setAway(d);
      });
    }
    return false;
  }

  void _goCurrent() {
    _follow = true;
    _reveal();
  }

  // --- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = _c;
      final q = c.queue;
      final cur = c.queueIndex;
      // Con orden real (sin aleatorio) lo ya escuchado va aparte y atenuado.
      final ordered = !c.shuffle && cur >= 0 && cur < q.length;
      final played = ordered ? cur : 0;
      _hidden = ordered && !_showPlayed ? played : 0;
      _onChange('$cur:${c.currentTrack?.id}:${q.length}:$_hidden');
      final count = q.length - _hidden;
      final platform = Theme.of(context).platform;
      // En el móvil arrastrar una fila es desplazar: reordenar pide mantener.
      final desktop = const {
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.macOS,
      }.contains(platform);
      Widget itemBuilder(BuildContext context, int i) => _row(
        context,
        q[i + _hidden],
        i + _hidden,
        played: played,
        ordered: ordered,
        desktop: desktop,
      );
      Future<void> reorder(int o, int n) =>
          c.reorderQueue(o + _hidden, n + _hidden);
      final list = NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ReorderableListView.builder(
          scrollController: _scroll,
          shrinkWrap: !widget.fill,
          buildDefaultDragHandles: false,
          itemCount: count,
          onReorder: reorder,
          itemBuilder: itemBuilder,
        ),
      );
      final stack = Stack(
        children: [
          list,
          if (_away != 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 6,
              child: Center(child: _goPill(context)),
            ),
        ],
      );
      final summary = _summary(ordered);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: _card(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'COLA',
                      style: TextStyle(
                        fontFamily: 'Bagel Fat One',
                        fontSize: 52,
                        height: 1,
                        color: context.slush.ink,
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
                      color: c.shuffle ? Slush.mint : context.slush.paper,
                    ),
                  ),
                ),
              ],
            ),
            if (summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  summary,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: context.slush.ink,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            if (q.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No hay canciones en la cola')),
              )
            else if (widget.fill)
              Expanded(child: stack)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: stack,
              ),
            if (widget.fill && q.isEmpty) const Spacer(),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.onSearch,
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

  Widget _goPill(BuildContext context) => Material(
    color: Slush.yellow,
    elevation: 2,
    shape: StadiumBorder(side: context.slush.border),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: _goCurrent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _away < 0 ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: Slush.ink,
            ),
            const SizedBox(width: 6),
            const Text(
              'IR A LA ACTUAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Slush.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _caption(BuildContext context, String text, {VoidCallback? onTap}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
          child: Row(
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: context.slush.ink,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  _showPlayed ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: context.slush.ink,
                ),
              ],
            ],
          ),
        ),
      );

  Widget _row(
    BuildContext context,
    Track t,
    int i, {
    required int played,
    required bool ordered,
    required bool desktop,
  }) {
    final c = _c;
    final active = i == c.queueIndex;
    final dim = ordered && i < c.queueIndex;
    // Sobre lila el contenido va en tinta fija (también en oscuro), con tema
    // claro para iconos y menús.
    final Widget Function(BuildContext, Widget) wrap = active
        ? slushOnVivid
        : (_, w) => w;
    final extras = [
      (label: 'Quitar de la cola', run: () => c.removeFromQueue(i)),
    ];
    final String? caption = !ordered
        ? null
        : i == c.queueIndex + 1
        ? 'A CONTINUACIÓN'
        : null;
    final togglePlayed = ordered && played > 0 && i == _hidden;
    final body = TrackActionsRegion(
      controller: c,
      track: t,
      extras: extras,
      builder: (context, _) => Padding(
        key: active ? _currentKey : null,
        padding: const EdgeInsets.only(bottom: 8),
        child: Opacity(
          opacity: dim ? .5 : 1,
          child: Material(
            color: active ? Slush.lilac : context.slush.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: context.slush.border,
            ),
            child: InkWell(
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              onTap: () {
                _follow = true;
                c.playQueueAt(i);
              },
              child: wrap(
                context,
                Builder(
                  builder: (context) => Padding(
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
                        // Con texto grande la fila no cabe en el teléfono: la
                        // activa se distingue por el color.
                        if (MediaQuery.textScalerOf(context).scale(1) <= 1.3) ...[
                          if (active)
                            const SlushPill('Sonando', color: Slush.yellow)
                          else
                            SlushPill(_kind(t), color: context.slush.paper),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _time(t.duration),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TrackMenuButton(
                          controller: c,
                          track: t,
                          extras: extras,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final child = caption == null && !togglePlayed
        ? body
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (togglePlayed)
                _caption(
                  context,
                  'ESCUCHADAS · $played',
                  onTap: () => setState(() => _showPlayed = !_showPlayed),
                ),
              ?(caption == null ? null : _caption(context, caption)),
              body,
            ],
          );
    final key = ValueKey('$i:${t.id}');
    return desktop
        ? ReorderableDragStartListener(
            key: key,
            index: i - _hidden,
            child: child,
          )
        : ReorderableDelayedDragStartListener(
            key: key,
            index: i - _hidden,
            child: child,
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
          (s) => s.contains(WidgetState.selected) ? Slush.yellow : Slush.lilac,
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
            Text(
              'EQ',
              style: TextStyle(
                fontFamily: 'Bagel Fat One',
                fontSize: 130,
                height: .95,
                color: context.slush.ink,
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
                    decoration: _card(context, null, 20),
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
              // 36 arriba: el disco flotante (bajo 32 px) no tapa el dB de la 8ª banda.
              padding: const EdgeInsets.fromLTRB(12, 36, 12, 10),
              decoration: _card(context),
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
                backgroundColor: context.slush.ink,
                foregroundColor: context.slush.paper,
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
    color: on ? context.slush.ink : context.slush.paper,
    shape: StadiumBorder(side: context.slush.border),
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
            color: on ? context.slush.paper : context.slush.ink,
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
          BorderSide(color: Colors.white, width: 3), // sobre color vivo
        ),
        boxShadow: [BoxShadow(color: Slush.ink, spreadRadius: 2)],
      ),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Slush.mint,
            border: Border.fromBorderSide(context.slush.border),
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
                          color: Color.lerp(
                            context.slush.paper,
                            context.slush.ink,
                            .08,
                          ),
                          borderRadius: BorderRadius.circular(_w / 2),
                          border: Border.all(
                            color: context.slush.line,
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
                            border: Border.symmetric(
                              horizontal: BorderSide(
                                color: context.slush.line,
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
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: context.slush.paper,
                            border: Border.fromBorderSide(context.slush.border),
                          ),
                          child: Center(
                            child: SizedBox(
                              width: 9,
                              height: 2,
                              child: ColoredBox(color: context.slush.ink),
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
