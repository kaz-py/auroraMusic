import '../friends_page.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../lyrics/lyrics_service.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';

/// Reproductor Vinilo + Letras del tema Slush (escritorio y móvil).
/// Secciones del shell: 4 vinilo, 6 letras, 13 ecualizador, 5 cola.

/// Naranja/color de pantalla móvil: tono de la portada, saturado y lo bastante
/// claro para que el texto negro llegue a contraste AA (4,5). En oscuro se
/// hunde hacia negro para que el texto crema siga legible.
Color slushScreenColor(Color accent, {bool dark = false}) {
  final h = HSLColor.fromColor(accent);
  var l = .56;
  var c = h.withSaturation(h.saturation.clamp(.8, 1.0)).withLightness(l);
  while (c.toColor().computeLuminance() < .175 && l < .9) {
    l += .02;
    c = c.withLightness(l);
  }
  return dark ? Color.lerp(c.toColor(), Colors.black, .70)! : c.toColor();
}

String _clock(Duration d) =>
    '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

const _label = TextStyle(
  fontFamily: 'Inter',
  fontSize: 11,
  fontWeight: FontWeight.w800,
  letterSpacing: .3,
  color: Slush.ink,
);

/// [_label] en tinta del tema, para papel y fondo de pantalla.
TextStyle _inkLabel(BuildContext context) =>
    _label.copyWith(color: context.slush.ink);

/// Píldora de pestañas VINILO / LETRAS / ECUALIZADOR / COLA.
class SlushPlayerTabs extends StatelessWidget {
  const SlushPlayerTabs({
    super.key,
    required this.current,
    required this.onSection,
    this.short = false,
  });
  final int current;
  final ValueChanged<int> onSection;

  /// Móvil: «EQ» en vez de «ECUALIZADOR».
  final bool short;

  static const _items = [
    (4, 'Vinilo', 'Vinilo'),
    (6, 'Letras', 'Letras'),
    (13, 'Ecualizador', 'EQ'),
    (5, 'Cola', 'Cola'),
  ];

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: context.slush.paper,
      shape: StadiumBorder(side: context.slush.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (section, long, shortName) in _items)
            Semantics(
              button: true,
              selected: current == section,
              label: long,
              child: Material(
                color: current == section
                    ? context.slush.ink
                    : Colors.transparent,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSection(section),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: short ? 11 : 16,
                      vertical: 8,
                    ),
                    child: Text(
                      (short ? shortName : long).toUpperCase(),
                      style: _label.copyWith(
                        color: current == section
                            ? context.slush.paper
                            : context.slush.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Cabecera de las pantallas del reproductor que no son Vinilo (Letras, EQ,
/// Cola): VOLVER, pestañas y chip de sueño.
class SlushPlayerHeader extends StatelessWidget {
  const SlushPlayerHeader({
    super.key,
    required this.controller,
    required this.current,
    required this.onSection,
  });
  final AppController controller;
  final int current;
  final ValueChanged<int> onSection;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    final tabs = SlushPlayerTabs(
      current: current,
      onSection: onSection,
      short: compact,
    );
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Center(child: tabs),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(
        children: [
          _BackPill(onTap: () => onSection(0)),
          Expanded(child: Center(child: tabs)),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _SleepChip(controller: controller),
          ),
        ],
      ),
    );
  }
}

class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: context.slush.paper,
    shape: StadiumBorder(side: context.slush.border),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 16, color: context.slush.ink),
            const SizedBox(width: 6),
            Text('VOLVER', style: _inkLabel(context)),
          ],
        ),
      ),
    ),
  );
}

/// Menú de temporizador de sueño; [builder] recibe «ZZ · 28 MIN» o «ZZ».
class _SleepMenu extends StatelessWidget {
  const _SleepMenu({required this.controller, required this.builder});
  final AppController controller;
  final Widget Function(String label) builder;

  @override
  Widget build(BuildContext context) {
    final left = controller.sleepRemaining;
    final label = left == null
        ? 'ZZ'
        : 'ZZ · ${(left.inSeconds / 60).ceil()} MIN';
    return PopupMenuButton<int>(
      tooltip: 'Temporizador de sueño',
      onSelected: (m) =>
          controller.setSleepTimer(m == 0 ? null : Duration(minutes: m)),
      itemBuilder: (_) => [
        for (final m in const [15, 30, 45, 60])
          PopupMenuItem(value: m, child: Text('$m minutos')),
        if (left != null)
          const PopupMenuItem(value: 0, child: Text('Desactivar')),
      ],
      child: builder(label),
    );
  }
}

class _SleepChip extends StatelessWidget {
  const _SleepChip({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) => _SleepMenu(
    controller: controller,
    builder: (label) => DecoratedBox(
      decoration: ShapeDecoration(
        color: Slush.lilac,
        shape: StadiumBorder(side: context.slush.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.nightlight_round, size: 14, color: Slush.ink),
            const SizedBox(width: 6),
            Text(label, style: _label),
          ],
        ),
      ),
    ),
  );
}

/// Etiqueta del disco: fondo de acento, círculo lila y semicírculos blanco y
/// amarillo recortados por el borde.
class SlushLabelArt extends StatelessWidget {
  const SlushLabelArt({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _LabelPainter(color), size: Size.infinite);
}

class _LabelPainter extends CustomPainter {
  const _LabelPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, r * .035)
      ..color = Slush.ink;
    Paint fill(Color f) => Paint()..color = f;
    final lilac = c + Offset(r * .38, -r * .42);
    canvas.drawCircle(lilac, r * .27, fill(Slush.lilac));
    canvas.drawCircle(lilac, r * .27, stroke);
    final base = c + Offset(0, r * .2);
    final white = Rect.fromCircle(center: base, radius: r * .62);
    final yellow = Rect.fromCircle(center: base, radius: r * .38);
    canvas.drawArc(
      white,
      math.pi,
      math.pi,
      true,
      fill(Colors.white),
    ); // sobre color vivo
    canvas.drawArc(white, math.pi, math.pi, true, stroke);
    canvas.drawArc(yellow, math.pi, math.pi, true, fill(Slush.yellow));
    canvas.drawArc(yellow, math.pi, math.pi, true, stroke);
    canvas.drawCircle(c, r * .07, fill(Colors.white)); // sobre color vivo
    canvas.drawCircle(c, r * .07, stroke);
  }

  @override
  bool shouldRepaint(_LabelPainter old) => old.color != color;
}

/// Tarjeta «LETRAS» (escritorio): líneas alrededor de la activa con marcador
/// lila, fuente, importar LRC y volumen.
class SlushLyricsCard extends StatefulWidget {
  const SlushLyricsCard({super.key, required this.controller, this.service});
  final AppController controller;
  final LyricsService? service;
  @override
  State<SlushLyricsCard> createState() => _SlushLyricsCardState();
}

class _SlushLyricsCardState extends State<SlushLyricsCard> {
  late final LyricsService _service = widget.service ?? LyricsService();
  LyricsResult? _result;
  String? _id;
  int _request = 0;
  bool _loading = false;
  double _lastVolume = .75;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  void _sync() {
    final track = widget.controller.nowTrack;
    if (track?.id == _id) return;
    _id = track?.id;
    _result = null;
    final request = ++_request;
    if (track == null) return;
    _loading = true;
    unawaited(
      _service
          .load(track, widget.controller.supportDirectory)
          .then((r) {
            if (mounted && request == _request) setState(() => _result = r);
          })
          .catchError((Object _) {})
          .whenComplete(() {
            if (mounted && request == _request) {
              setState(() => _loading = false);
            }
          }),
    );
  }

  Future<void> _import() async {
    final track = widget.controller.nowTrack;
    if (track == null) return;
    final request = ++_request;
    try {
      final r = await _service.importFile(
        track,
        widget.controller.supportDirectory,
      );
      if (mounted && request == _request && r != null) {
        setState(() => _result = r);
      }
    } catch (_) {}
  }

  String get _chip {
    final r = _result;
    if (_loading) return 'Buscando…';
    if (r == null || r.kind == LyricsKind.notFound) return 'Sin letra';
    if (r.kind == LyricsKind.instrumental) return 'Instrumental';
    final kind = r.kind == LyricsKind.synced ? 'Sincronizada' : 'Texto plano';
    return r.source.isEmpty ? kind : '$kind · ${r.source}';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final r = _result;
    final synced = r != null && r.kind == LyricsKind.synced;
    final plain = r == null || synced
        ? const <String>[]
        : r.text
              .split(RegExp(r'\r?\n'))
              .where((l) => l.trim().isNotEmpty)
              .toList();
    final muted = c.audio.volume <= 0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.slush.paper,
        borderRadius: BorderRadius.circular(24),
        border: Border.fromBorderSide(context.slush.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'LETRAS',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 24),
                ),
                const Spacer(),
                Flexible(child: SlushPill(_chip)),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: synced
                  ? ListenableBuilder(
                      listenable: c.audio,
                      builder: (context, _) =>
                          _syncedLines(r.lines, c.audio.position),
                    )
                  : plain.isNotEmpty
                  ? ListView(
                      children: [
                        for (final l in plain)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Text(l, style: _lineStyle(1)),
                          ),
                      ],
                    )
                  : Center(
                      child: Text(
                        _loading
                            ? 'Buscando letras…'
                            : 'Esta pista no tiene letra.',
                        style: _lineStyle(2),
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Material(
                  color: context.slush.paper,
                  shape: StadiumBorder(side: context.slush.border),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: c.nowTrack == null ? null : _import,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_download_outlined,
                            size: 15,
                            color: context.slush.ink,
                          ),
                          const SizedBox(width: 6),
                          Text('IMPORTAR LRC', style: _inkLabel(context)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: context.slush.paper,
                  shape: CircleBorder(side: context.slush.border),
                  child: IconButton(
                    tooltip: muted ? 'Activar sonido' : 'Silenciar',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: () {
                      if (muted) {
                        c.setVolume(_lastVolume);
                      } else {
                        _lastVolume = c.audio.volume;
                        c.setVolume(0);
                      }
                      setState(() {});
                    },
                    icon: Icon(
                      muted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 0 atenuada, 1 normal, 2 mensaje.
  TextStyle _lineStyle(int kind) => TextStyle(
    fontFamily: 'Inter',
    fontSize: kind == 2 ? 14 : 15,
    height: 1.3,
    fontWeight: kind == 0 ? FontWeight.w700 : FontWeight.w600,
    color: kind == 0
        ? context.slush.ink.withValues(alpha: .5)
        : context.slush.ink,
  );

  Widget _syncedLines(List<LyricLine> lines, Duration position) {
    final active = lines.lastIndexWhere((l) => l.at <= position);
    final from = (math.max(active, 0) - 3)
        .clamp(0, math.max(0, lines.length - 8))
        .toInt();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = from; i < math.min(lines.length, from + 8); i++)
          Flexible(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: i == active
                  ? DecoratedBox(
                      decoration: BoxDecoration(
                        color: Slush.lilac,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        child: Text(
                          lines[i].text,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 19,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: Slush.ink,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      lines[i].text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _lineStyle(i == active + 1 ? 1 : 0),
                    ),
            ),
          ),
      ],
    );
  }
}

class _SlushThumb extends SliderComponentShape {
  const _SlushThumb(this.line);
  final Color line;
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(11);
  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 9, Paint()..color = Slush.yellow);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = line,
    );
  }
}

/// Barra de progreso gruesa con punto amarillo y tiempos.
class _Progress extends StatelessWidget {
  const _Progress({required this.controller, this.trackColor});
  final AppController controller;
  final Color? trackColor;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final duration = c.audio.duration > Duration.zero
            ? c.audio.duration
            : c.currentTrack?.duration ?? Duration.zero;
        final max = math.max(1, duration.inMilliseconds).toDouble();
        final pos = c.audio.position.inMilliseconds.toDouble().clamp(0.0, max);
        final left = Duration(milliseconds: (max - pos).round());
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                activeTrackColor: context.slush.ink,
                inactiveTrackColor: trackColor ?? context.slush.paper,
                thumbShape: _SlushThumb(context.slush.line),
                overlayShape: SliderComponentShape.noOverlay,
                trackShape: const RoundedRectSliderTrackShape(),
              ),
              child: Slider(
                semanticFormatterCallback: (v) =>
                    'Ir a ${Duration(milliseconds: v.round()).inSeconds} segundos',
                min: 0,
                max: max,
                value: pos,
                onChanged: duration > Duration.zero
                    ? (v) => c.seek(Duration(milliseconds: v.round()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_clock(c.audio.position), style: _inkLabel(context)),
                  Text('-${_clock(left)}', style: _inkLabel(context)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.big = false,
    this.on = false,
    this.fill,
    this.size = 36,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool big, on;
  final Color? fill;
  final double size;
  @override
  Widget build(BuildContext context) {
    final dim = big ? size * 1.6 : size;
    final vivid = !big && (fill != null || on);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: big
            ? context.slush.ink
            : fill ?? (on ? Slush.mint : context.slush.paper),
        shape: CircleBorder(side: context.slush.border),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(
            dimension: dim,
            child: Icon(
              icon,
              size: big ? dim * .55 : dim * .5,
              color: big
                  ? context.slush.paper
                  : vivid
                  ? Slush.ink
                  : context.slush.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, this.size = 36, this.gap = 10});
  final AppController controller;
  final double size, gap;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final track = c.currentTrack;
    final liked = track != null && c.favoriteIds.contains(track.id);
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.audio]),
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Round(
            icon: Icons.shuffle_rounded,
            tooltip: 'Aleatorio',
            on: c.shuffle,
            size: size,
            onTap: () => c.setShuffle(!c.shuffle),
          ),
          SizedBox(width: gap),
          _Round(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Anterior',
            size: size,
            onTap: track == null ? null : c.previous,
          ),
          SizedBox(width: gap),
          _Round(
            icon: c.audio.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            tooltip: c.audio.isPlaying ? 'Pausar' : 'Reproducir',
            big: true,
            size: size,
            onTap: track == null ? null : c.togglePlayback,
          ),
          SizedBox(width: gap),
          _Round(
            icon: Icons.skip_next_rounded,
            tooltip: 'Siguiente',
            size: size,
            onTap: track == null ? null : c.next,
          ),
          SizedBox(width: gap),
          _Round(
            icon: c.repeat == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            tooltip: 'Repetir',
            on: c.repeat != RepeatMode.off,
            size: size,
            onTap: c.cycleRepeat,
          ),
          SizedBox(width: gap),
          _Round(
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            tooltip: 'Me gusta',
            fill: liked ? Slush.orange : null,
            size: size,
            onTap: track == null ? null : () => c.toggleFavorite(track),
          ),
          if (track != null && !track.isLocal)
            FriendsGate(
              builder: (context, f) => Padding(
                padding: EdgeInsets.only(left: gap),
                child: _Round(
                  icon: Icons.send_rounded,
                  tooltip: 'Enviar a un amigo',
                  size: size,
                  onTap: () => showSendToFriendSheet(context, f, track),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Onda azul gruesa con borde negro y brillo, detrás del contenido.
class _BigWave extends StatelessWidget {
  const _BigWave();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: CustomPaint(painter: _BigWavePainter(context.slush.line)),
  );
}

class _BigWavePainter extends CustomPainter {
  const _BigWavePainter(this.line);
  final Color line;
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(0, h * .12)
      ..cubicTo(w * .22, h * .2, w * .3, h * .62, w * .55, h * .72)
      ..cubicTo(w * .78, h * .82, w * .88, h * .45, w * 1.06, h * .1);
    final thick = math.min(h * .3, 90.0);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick + 7
        ..strokeCap = StrokeCap.round
        ..color = line,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick
        ..strokeCap = StrokeCap.round
        ..color = Slush.blue,
    );
    canvas.drawPath(
      path.shift(Offset(0, -thick * .18)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thick * .1
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xffbfdcff),
    );
  }

  @override
  bool shouldRepaint(_BigWavePainter old) => old.line != line;
}

class _ShinePainter extends CustomPainter {
  const _ShinePainter();
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawArc(
      Rect.fromCircle(center: s.center(Offset.zero), radius: s.width * .43),
      math.pi * 1.08,
      math.pi * .3,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .45), // sobre color vivo
    );
  }

  @override
  bool shouldRepaint(_ShinePainter old) => false;
}

class _Heart extends StatelessWidget {
  const _Heart({required this.size, required this.onTap});
  final double size;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.favorite_rounded, size: size, color: context.slush.line),
          Icon(Icons.favorite_rounded, size: size * .84, color: Slush.orange),
          Positioned(
            left: size * .26,
            top: size * .25,
            child: Transform.rotate(
              angle: -.7,
              child: Container(
                width: size * .22,
                height: size * .08,
                decoration: BoxDecoration(
                  color: Colors.white, // sobre color vivo
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Pantalla completa del reproductor Vinilo. [recordBuilder] pinta el disco
/// (giro, seek y casete los gestiona el reproductor).
class SlushPlayerScreen extends StatelessWidget {
  const SlushPlayerScreen({
    super.key,
    required this.controller,
    required this.track,
    required this.compact,
    required this.recordBuilder,
    required this.onToggleCassette,
    required this.cassette,
    this.onSection,
    this.onBack,
  });
  final AppController controller;
  final Track? track;
  final bool compact;
  final Widget Function(double size) recordBuilder;
  final VoidCallback onToggleCassette;
  final bool cassette;
  final ValueChanged<int>? onSection;

  /// Flecha atrás del móvil; por defecto vuelve a Inicio.
  final VoidCallback? onBack;

  String get _source => track == null
      ? 'Nada sonando'
      : track!.isLocal
      ? 'Biblioteca local'
      : 'YouTube Music';

  List<Widget> _pills() {
    final t = track;
    if (t == null) return const [];
    return [
      if (t.genres.isNotEmpty) SlushPill(t.genres.first, color: Slush.mint),
      if ((t.album ?? '').isNotEmpty) SlushPill(t.album!, color: Slush.yellow),
      if (t.duration > Duration.zero)
        SlushPill(_clock(t.duration), color: Slush.lilac),
    ];
  }

  Widget _nowPlaying(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xffe5252a),
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          'AHORA SUENA · ${_source.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _inkLabel(context).copyWith(fontSize: 10),
        ),
      ),
    ],
  );

  Widget _title(BuildContext context, double width, {double max = 92}) {
    final text = (track?.title ?? 'Nada sonando').toUpperCase();
    final longest = text
        .split(RegExp(r'\s+'))
        .fold<int>(5, (m, w) => math.max(m, w.length));
    final size = (width / (longest * .66)).clamp(34.0, max);
    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.displayLarge?.copyWith(fontSize: size, height: .95),
    );
  }

  Widget _artist(BuildContext context) => Text(
    track == null ? 'Elige una canción de tu biblioteca' : track!.artist,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: 'Inter',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: context.slush.ink,
    ),
  );

  Widget _noteDisc(BuildContext context) => Tooltip(
    message: cassette ? 'Ver vinilo' : 'Ver casete',
    child: Material(
      key: const ValueKey('cassette-toggle'),
      color: Slush.yellow,
      shape: CircleBorder(side: context.slush.border),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onToggleCassette,
        child: const SizedBox.square(
          dimension: 46,
          child: Icon(Icons.music_note_rounded, size: 26, color: Slush.ink),
        ),
      ),
    ),
  );

  Widget _nextUp(BuildContext context) {
    final c = controller;
    final i = c.queueIndex + 1;
    if (i <= 0 || i >= c.queue.length) return const SizedBox.shrink();
    final t = c.queue[i];
    return Material(
      color: context.slush.paper,
      shape: StadiumBorder(side: context.slush.border),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => c.playQueueAt(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.fromBorderSide(context.slush.border),
                  color: Slush.mint,
                ),
                child: Artwork(
                  track: t,
                  artworkContext: ArtworkContext.thumbnailCompact,
                  radius: 6,
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A CONTINUACIÓN',
                    style: _inkLabel(context).copyWith(fontSize: 8),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      '${t.artist} — ${t.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inkLabel(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.audio]),
    builder: (context, _) => compact ? _mobile(context) : _desktop(context),
  );

  Widget _desktop(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      final h = math.max(box.maxHeight, 600.0);
      const pad = 24.0;
      final cardW = (w * .3).clamp(300.0, 420.0);
      var side = math.min(w * .5, h * .66).clamp(260.0, 640.0);
      side = math.min(side, (w - pad - cardW - 340) / .745).clamp(240.0, 640.0);
      final discLeft = -side * .255;
      final discTop = math.max(76.0, h * .53 - side / 2);
      final infoLeft = side * .745 + 16;
      final cardLeft = w - pad - cardW;
      final infoW = math.max(240.0, cardLeft - infoLeft - 24);
      final cardH = ((h - 84) * .6).clamp(330.0, 500.0);
      final bar = h * .6;
      final c = controller;
      final stack = SizedBox(
        width: w,
        height: h,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: infoLeft * .8,
              right: 0,
              top: h * .5,
              height: h * .45,
              child: const _BigWave(),
            ),
            Positioned(
              left: discLeft,
              top: discTop,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  recordBuilder(side),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: cassette
                          ? const SizedBox.shrink()
                          : const CustomPaint(painter: _ShinePainter()),
                    ),
                  ),
                ],
              ),
            ),
            if (c.audio.isPlaying)
              Positioned(
                left: discLeft + side * .5 + side * .3 - side * .15,
                top: discTop + side * .5 - side * .43 - side * .15,
                child: SlushSticker('GIRANDO', size: side * .3),
              ),
            Positioned(
              top: 16,
              left: pad,
              right: pad,
              child: Row(
                children: [
                  _BackPill(onTap: () => onSection?.call(0)),
                  Expanded(
                    child: Center(
                      child: onSection == null
                          ? const SizedBox.shrink()
                          : SlushPlayerTabs(current: 4, onSection: onSection!),
                    ),
                  ),
                  _SleepChip(controller: c),
                ],
              ),
            ),
            Positioned(
              left: infoLeft,
              top: 92,
              width: infoW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _nowPlaying(context),
                  const SizedBox(height: 8),
                  _title(context, infoW),
                  const SizedBox(height: 10),
                  _artist(context),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: _pills()),
                ],
              ),
            ),
            Positioned(
              left: cardLeft,
              top: 84,
              width: cardW,
              height: cardH,
              child: SlushLyricsCard(controller: c),
            ),
            Positioned(
              left: infoLeft,
              top: bar,
              width: infoW,
              child: _Progress(controller: c),
            ),
            Positioned(
              left: infoLeft - 56,
              top: bar + 52,
              child: _noteDisc(context),
            ),
            Positioned(
              left: infoLeft,
              top: bar + 52,
              child: _Controls(controller: c),
            ),
            Positioned(left: 14, top: h * .78, child: _nextUp(context)),
            Positioned(
              right: 22,
              top: 84 + cardH + 14,
              child: _Heart(
                size: 64,
                onTap: track == null ? null : () => c.toggleFavorite(track!),
              ),
            ),
          ],
        ),
      );
      return box.maxHeight >= 600 ? stack : SingleChildScrollView(child: stack);
    },
  );

  Widget _mobile(BuildContext context) {
    final c = controller;
    final bg = slushScreenColor(
      c.accentColor,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    Widget circle(IconData icon, VoidCallback? onTap, String tip) =>
        _Round(icon: icon, tooltip: tip, size: 40, onTap: onTap);
    return ColoredBox(
      color: bg,
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(box.maxWidth - 24, 420.0);
          final inner = math.min(box.maxWidth - 40, 460.0);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                child: Center(
                  child: SizedBox(
                    width: inner,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            circle(
                              Icons.arrow_back_rounded,
                              onBack ?? () => onSection?.call(0),
                              'Volver',
                            ),
                            Expanded(
                              child: Center(child: _nowPlaying(context)),
                            ),
                            _SleepMenu(
                              controller: c,
                              builder: (_) => const _Round(
                                icon: Icons.nightlight_round,
                                size: 40,
                                onTap: null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: SizedBox.square(
                            dimension: side,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                recordBuilder(side),
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: cassette
                                        ? const SizedBox.shrink()
                                        : const CustomPaint(
                                            painter: _ShinePainter(),
                                          ),
                                  ),
                                ),
                                Positioned(
                                  right: -4,
                                  bottom: side * .05,
                                  child: _Heart(
                                    size: 44,
                                    onTap: track == null
                                        ? null
                                        : () => c.toggleFavorite(track!),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  bottom: 0,
                                  child: _noteDisc(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _title(context, inner, max: 54),
                        const SizedBox(height: 6),
                        _artist(context),
                        const SizedBox(height: 6),
                        Wrap(spacing: 6, runSpacing: 6, children: _pills()),
                        const SizedBox(height: 12),
                        _Progress(
                          controller: c,
                          trackColor: context.slush.paper.withValues(
                            alpha: .85,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Center(
                          child: FittedBox(
                            child: _Controls(controller: c, size: 38, gap: 8),
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (onSection != null)
                          Center(
                            child: SlushPlayerTabs(
                              current: 4,
                              onSection: onSection!,
                              short: true,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
