import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';

/// Tinta de las filas sobre relleno vivo (lima, rosa): fija en ambos modos.
const _inkOnVivid = Slush.ink;
const _ink2OnVivid = Color(0xff3b3844);

String _two(int v) => v.toString().padLeft(2, '0');

/// `m:ss` o `h:mm:ss` a partir de [d].
String _clock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s % 60)}' : '${s ~/ 60}:${_two(s % 60)}';
}

/// Panel derecho de escritorio de Slush (secciones 4 y 5): pestañas
/// «Ahora suena · Cola · Letras», lista «Siguiente» con la pista actual en lima
/// y el temporizador de sueño integrado. «Letras» abre el modo letra (6).
class SlushAside extends StatefulWidget {
  const SlushAside({
    super.key,
    required this.controller,
    required this.onNavigate,
  });
  final AppController controller;
  final ValueChanged<int> onNavigate;

  @override
  State<SlushAside> createState() => _SlushAsideState();
}

class _SlushAsideState extends State<SlushAside> {
  /// 0 ahora suena, 1 cola.
  int _tab = 1;

  AppController get _c => widget.controller;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return SizedBox(
      width: 340,
      child: Padding(
        // Derecha y abajo: sitio para la sombra dura de la tarjeta.
        padding: const EdgeInsets.only(right: 4, bottom: 5),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(SlushRadius.r32),
            border: Border.fromBorderSide(p.borderSoft),
            boxShadow: p.shadowsFor(SlushElevation.card),
          ),
          child: Padding(
            padding: const EdgeInsets.all(SlushSpacing.s16),
            child: ListenableBuilder(
              listenable: _c,
              builder: (context, _) => LayoutBuilder(
                builder: (context, box) {
                  final bounded = box.hasBoundedHeight;
                  final body = _tab == 0
                      ? _now(context, bounded)
                      : _queue(context, bounded);
                  return Column(
                    mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tabs(context),
                      const SizedBox(height: 14),
                      if (bounded) Expanded(child: body) else body,
                      const SizedBox(height: 12),
                      _SleepCard(controller: _c),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- pestañas -----------------------------------------------------------

  Widget _tabs(BuildContext context) {
    final p = context.slush;
    Widget seg(String label, bool on, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        selected: on,
        label: label,
        child: Material(
          color: on ? p.ink : Colors.transparent,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: on ? p.paper : p.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.paper,
          shape: StadiumBorder(side: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            children: [
              seg('Ahora suena', _tab == 0, () => setState(() => _tab = 0)),
              seg(
                'Cola · ${_c.queue.length}',
                _tab == 1,
                () => setState(() => _tab = 1),
              ),
              seg('Letras', false, () => widget.onNavigate(6)),
            ],
          ),
        ),
      ),
    );
  }

  // --- cola ---------------------------------------------------------------

  /// Lo que queda por sonar: resto de la actual más las que vienen.
  Duration _remaining() {
    final c = _c;
    final q = c.queue;
    final cur = c.queueIndex;
    if (cur < 0 || cur >= q.length) return Duration.zero;
    final total = c.audio.duration > Duration.zero
        ? c.audio.duration
        : q[cur].duration;
    var left = total - c.audio.position;
    if (left.isNegative) left = Duration.zero;
    for (final t in q.skip(cur + 1)) {
      left += t.duration;
    }
    return left;
  }

  Widget _queue(BuildContext context, bool bounded) {
    final p = context.slush;
    final c = _c;
    final q = c.queue;
    final cur = c.queueIndex;
    final start = cur >= 0 && cur < q.length ? cur : 0;
    final label = slushMono(11, color: p.ink2, letterSpacing: 1.4);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          Text('SIGUIENTE', style: label),
          ListenableBuilder(
            listenable: c.audio,
            builder: (context, _) => Text(
              'Quedan ${_clock(_remaining())}',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: p.ink2,
              ),
            ),
          ),
        ],
      ),
    );
    final Widget list = q.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay canciones en la cola',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.ink2),
              ),
            ),
          )
        : ListView.builder(
            shrinkWrap: !bounded,
            padding: EdgeInsets.zero,
            itemCount: q.length - start,
            itemBuilder: (context, i) {
              final index = start + i;
              return _QueueRow(
                key: ValueKey('aside-row-$index:${q[index].id}'),
                track: q[index],
                current: index == cur,
                onTap: () => c.playQueueAt(index),
              );
            },
          );
    return Column(
      mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (bounded) Expanded(child: list) else list,
      ],
    );
  }

  // --- ahora suena --------------------------------------------------------

  Widget _now(BuildContext context, bool bounded) {
    final p = context.slush;
    final c = _c;
    final t = c.currentTrack;
    if (t == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Nada sonando',
            textAlign: TextAlign.center,
            style: TextStyle(color: p.ink2),
          ),
        ),
      );
    }
    final album = (t.album ?? '').trim();
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 220,
            height: 220,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Slush.violet,
              borderRadius: BorderRadius.circular(SlushRadius.r24),
              border: Border.fromBorderSide(p.border),
              boxShadow: p.shadowsFor(SlushElevation.card),
            ),
            child: Artwork(track: t, size: 216, radius: 22),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t.title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: slushHeadline(26, height: 1.05, color: p.ink),
        ),
        const SizedBox(height: 4),
        Text(
          album.isEmpty ? t.artist : '${t.artist} · $album',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: p.ink2,
          ),
        ),
        const SizedBox(height: 14),
        _NowProgress(controller: c),
      ],
    );
    return bounded ? SingleChildScrollView(child: card) : card;
  }
}

/// Fila de la cola: portada 42, título, artista y duración tabular. La actual
/// va en lima con borde y sombra dura.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    required this.current,
    required this.onTap,
  });
  final Track track;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final title = current ? _inkOnVivid : p.ink;
    final sub = current ? _ink2OnVivid : p.ink2;
    final d = track.duration;
    return Padding(
      // Derecha y abajo: sitio para la sombra dura de la fila actual.
      padding: const EdgeInsets.only(right: 4, bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: current ? Slush.lime : Colors.transparent,
          borderRadius: BorderRadius.circular(SlushRadius.r16),
          border: current ? Border.fromBorderSide(p.border) : null,
          boxShadow: current ? p.shadowsFor(SlushElevation.card) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(SlushRadius.r16),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Artwork(track: track, size: 42, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: title,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12,
                              color: sub,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      d > Duration.zero ? _clock(d) : '–:––',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: sub,
                      ),
                    ),
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

/// Barra fina de progreso con tiempos, para la pestaña «Ahora suena».
class _NowProgress extends StatelessWidget {
  const _NowProgress({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final c = controller;
    final style = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: p.ink2,
    );
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final total = c.audio.duration > Duration.zero
            ? c.audio.duration
            : c.currentTrack?.duration ?? Duration.zero;
        final value = total.inMilliseconds <= 0
            ? 0.0
            : (c.audio.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: ShapeDecoration(
                color: p.inset,
                shape: StadiumBorder(side: p.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(SlushRadius.pill),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 8,
                    color: Slush.violet,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(c.audio.position), style: style),
                Text(_clock(total), style: style),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Tarjeta rosa del temporizador de sueño (API de sueño del controlador).
class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final c = controller;
    final left = c.sleepRemaining;
    final big = MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
    Widget pill(String label, VoidCallback onTap, {String? tooltip}) => Tooltip(
      message: tooltip ?? label,
      child: SlushPressable(
        elevation: SlushElevation.none,
        onTap: onTap,
        child: Material(
          color: p.paper,
          shape: StadiumBorder(side: p.border),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: left == null
          ? [
              pill(
                '30 min',
                () => c.setSleepTimer(const Duration(minutes: 30)),
                tooltip: 'Dormir en 30 minutos',
              ),
            ]
          : [
              pill(
                '+15',
                () => c.setSleepTimer(left + const Duration(minutes: 15)),
                tooltip: 'Añadir 15 minutos',
              ),
              pill(
                'Quitar',
                () => c.setSleepTimer(null),
                tooltip: 'Quitar el temporizador',
              ),
            ],
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Temporizador',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _inkOnVivid,
          ),
        ),
        Text(
          left == null ? 'Apagado' : 'Se detiene en ${_clock(left)}',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _ink2OnVivid,
          ),
        ),
      ],
    );
    final head = Row(
      children: [
        const Icon(Icons.bedtime_outlined, size: 22, color: _inkOnVivid),
        const SizedBox(width: 10),
        Expanded(child: texts),
      ],
    );
    return Padding(
      // Derecha y abajo: sitio para la sombra dura (2,3).
      padding: const EdgeInsets.only(right: 3, bottom: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Slush.pink,
          borderRadius: BorderRadius.circular(SlushRadius.r24),
          border: Border.fromBorderSide(p.border),
          boxShadow: p.shadowsFor(SlushElevation.control),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: big
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [head, const SizedBox(height: 10), actions],
                )
              : Row(
                  children: [
                    Expanded(child: head),
                    const SizedBox(width: 8),
                    actions,
                  ],
                ),
        ),
      ),
    );
  }
}
