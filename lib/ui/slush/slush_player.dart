import '../friends_page.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../lyrics/lyrics_service.dart';
import '../../theme/slush_theme.dart';
import '../../theme/accent_transition.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../mini_player/mini_player_model.dart';
import '../studio/studio_transport.dart' show transportJamAudio;

/// Reproductor Vinilo + Letras del tema Slush (escritorio y móvil).
/// Secciones del shell: 4 vinilo, 6 letras, 13 ecualizador, 5 cola.

/// Color de pantalla móvil: en claro, tono de la portada saturado y lo bastante
/// claro para que el texto negro llegue a contraste AA (4,5); en oscuro, la
/// capa `screen` con un tinte leve de la portada (el crema sigue legible).
Color slushScreenColor(Color accent, {bool dark = false}) {
  final h = HSLColor.fromColor(accent);
  if (dark) {
    final tint = HSLColor.fromAHSL(1, h.hue, .45, .30).toColor();
    return Color.lerp(SlushPalette.dark.screen, tint, .10)!;
  }
  var l = .56;
  var c = h.withSaturation(h.saturation.clamp(.8, 1.0)).withLightness(l);
  while (c.toColor().computeLuminance() < .175 && l < .9) {
    l += .02;
    c = c.withLightness(l);
  }
  return c.toColor();
}

String _clock(Duration d) =>
    '${d.inSeconds ~/ 60}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

const _label = TextStyle(
  fontFamily: 'Inter',
  fontSize: 12,
  fontWeight: FontWeight.w800,
  letterSpacing: .3,
  color: Slush.ink,
);

/// [_label] en tinta del tema, para papel y fondo de pantalla.
TextStyle _inkLabel(BuildContext context) =>
    _label.copyWith(color: context.slush.ink);

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Objetivo táctil: 44 por debajo de 900 px; 36 en escritorio (puntero fino).
double _touch(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Breakpoints.medium
    ? SlushControl.touch
    : 36;

/// Crema de la tinta oscura y papel claro: brillos y figuras decorativas del
/// disco (no son texto ni fondo de texto).
final _cream = SlushPalette.dark.ink;
final _paperLight = SlushPalette.light.paper;

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
  Widget build(BuildContext context) {
    final p = context.slush;
    final reduce = SlushMotion.reduce(context);
    final minHeight = _touch(context);
    // Etiquetas: no escalan más de 1,3; si aún no caben, la píldora encoge.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: p.paper,
            shape: StadiumBorder(side: p.border),
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
                    child: AnimatedContainer(
                      duration: reduce ? Duration.zero : SlushMotion.select,
                      curve: SlushMotion.easeOut,
                      decoration: ShapeDecoration(
                        color: current == section
                            ? Slush.mint
                            : Colors.transparent,
                        shape: const StadiumBorder(),
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: InkWell(
                          customBorder: const StadiumBorder(),
                          onTap: () => onSection(section),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: minHeight - 6,
                              minWidth: minHeight,
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: short ? 10 : 16,
                                vertical: 8,
                              ),
                              child: Center(
                                widthFactor: 1,
                                child: Text(
                                  (short ? shortName : long).toUpperCase(),
                                  style: _label.copyWith(
                                    color: current == section
                                        ? Slush.ink
                                        : p.ink,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
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
  Widget build(BuildContext context) => SlushPressable(
    onTap: onTap,
    minSize: _touch(context),
    child: Material(
      color: context.slush.paper,
      shape: StadiumBorder(side: context.slush.border),
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
    builder: (label) => ConstrainedBox(
      constraints: BoxConstraints(minHeight: _touch(context)),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: Slush.lilac,
          shape: StadiumBorder(side: context.slush.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.nightlight_round, size: 16, color: Slush.ink),
              const SizedBox(width: 6),
              Text(label, style: _label),
            ],
          ),
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
    canvas.drawArc(white, math.pi, math.pi, true, fill(_paperLight));
    canvas.drawArc(white, math.pi, math.pi, true, stroke);
    canvas.drawArc(yellow, math.pi, math.pi, true, fill(Slush.yellow));
    canvas.drawArc(yellow, math.pi, math.pi, true, stroke);
    canvas.drawCircle(c, r * .07, fill(_paperLight));
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
    final p = context.slush;
    final r = _result;
    final synced = r != null && r.kind == LyricsKind.synced;
    final plain = r == null || synced
        ? const <String>[]
        : r.text
              .split(RegExp(r'\r?\n'))
              .where((l) => l.trim().isNotEmpty)
              .toList();
    final muted = c.audio.volume <= 0;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(SlushRadius.r24),
          border: Border.fromBorderSide(p.borderSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: SlushSpacing.s8,
                runSpacing: SlushSpacing.s4,
                children: [
                  Text(
                    'LETRAS',
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(fontSize: 24),
                  ),
                  SlushPill(_chip),
                ],
              ),
              const SizedBox(height: SlushSpacing.s12),
              Expanded(
                child: synced
                    ? ListenableBuilder(
                        listenable: c.audio,
                        builder: (context, _) => _SyncedScroll(
                          lines: r.lines,
                          active: r.lines.lastIndexWhere(
                            (l) => l.at <= c.audio.position,
                          ),
                        ),
                      )
                    : plain.isNotEmpty
                    ? ListView(
                        children: [
                          for (final l in plain)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Text(l, style: _lineStyle(false)),
                            ),
                        ],
                      )
                    : Center(
                        child: Text(
                          _loading
                              ? 'Buscando letras…'
                              : 'Esta pista no tiene letra.',
                          textAlign: TextAlign.center,
                          style: _lineStyle(true),
                        ),
                      ),
              ),
              const SizedBox(height: SlushSpacing.s12),
              Wrap(
                spacing: SlushSpacing.s8,
                runSpacing: SlushSpacing.s8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SlushPressable(
                    elevation: SlushElevation.none,
                    onTap: c.nowTrack == null ? null : _import,
                    child: Material(
                      color: p.paper,
                      shape: StadiumBorder(side: p.border),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download_outlined,
                              size: 18,
                              color: p.ink,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'IMPORTAR LRC',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _inkLabel(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Tooltip(
                    message: muted ? 'Activar sonido' : 'Silenciar',
                    child: SlushPressable(
                      elevation: SlushElevation.none,
                      onTap: () {
                        if (muted) {
                          c.setVolume(_lastVolume);
                        } else {
                          _lastVolume = c.audio.volume;
                          c.setVolume(0);
                        }
                        setState(() {});
                      },
                      child: Material(
                        color: p.paper,
                        shape: CircleBorder(side: p.border),
                        child: SizedBox.square(
                          dimension: SlushControl.touch,
                          child: Center(
                            child: Icon(
                              muted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              size: 20,
                              color: p.ink,
                            ),
                          ),
                        ),
                      ),
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

  TextStyle _lineStyle(bool message) => TextStyle(
    fontFamily: 'Inter',
    fontSize: message ? 14 : 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: message ? context.slush.ink2 : context.slush.ink,
  );
}

/// Letras sincronizadas: lista con la línea activa centrada (24, tinta sobre
/// lila); el resto en `ink3` w600. El desplazamiento es suave (280 ms,
/// curva drawer) y instantáneo con movimiento reducido o la primera vez;
/// 40 % de relleno arriba y abajo para que cualquier línea pueda centrarse.
class _SyncedScroll extends StatefulWidget {
  const _SyncedScroll({required this.lines, required this.active});
  final List<LyricLine> lines;
  final int active;
  @override
  State<_SyncedScroll> createState() => _SyncedScrollState();
}

class _SyncedScrollState extends State<_SyncedScroll> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  bool _first = true;

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_SyncedScroll old) {
    super.didUpdateWidget(old);
    if (!identical(old.lines, widget.lines)) {
      _keys.clear();
      _first = true;
    }
    if (old.active != widget.active || !identical(old.lines, widget.lines)) {
      _reveal();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reveal({int tries = 4}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.active < 0) return;
      final target = _keys[widget.active]?.currentContext;
      if (target != null) {
        final instant = _first || SlushMotion.reduce(context);
        _first = false;
        Scrollable.ensureVisible(
          target,
          alignment: .5,
          duration: instant ? Duration.zero : SlushMotion.sheetIn,
          curve: SlushMotion.drawer,
        );
      } else if (tries > 0 && _scroll.hasClients) {
        // Lista perezosa: la línea aún no existe; salta a su zona (proporcional
        // a la extensión medida, las alturas varían) y reintenta.
        final max = _scroll.position.maxScrollExtent;
        final n = widget.lines.length;
        _scroll.jumpTo(
          (max * widget.active / (n > 1 ? n - 1 : 1)).clamp(0.0, max),
        );
        _reveal(tries: tries - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return LayoutBuilder(
      builder: (context, box) => ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.symmetric(vertical: box.maxHeight * .4),
        itemCount: widget.lines.length,
        itemBuilder: (context, i) {
          final on = i == widget.active;
          final text = widget.lines[i].text;
          return Padding(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: on
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: Slush.lilac,
                      borderRadius: BorderRadius.circular(SlushRadius.r8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 24,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Slush.ink,
                        ),
                      ),
                    ),
                  )
                : Text(
                    text,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: p.ink3,
                    ),
                  ),
          );
        },
      ),
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
        ..strokeWidth = SlushStroke.base
        ..color = line,
    );
  }
}

/// Barra de progreso gruesa con punto amarillo y tiempos.
class _Progress extends StatelessWidget {
  const _Progress({required this.controller});
  final AppController controller;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = context.slush;
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
            SizedBox(
              height: SlushControl.touch,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 10,
                  activeTrackColor: p.ink,
                  // Oscuro: pista `lineSoft` (3,8:1); el papel se perdería.
                  inactiveTrackColor: _isDark(context) ? p.lineSoft : p.paper,
                  thumbShape: _SlushThumb(p.line),
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
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SlushPill(_clock(c.audio.position), color: p.paper),
                  SlushPill('-${_clock(left)}', color: p.paper),
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
    this.size = SlushControl.bar,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool big, on;
  final Color? fill;
  final double size;
  @override
  Widget build(BuildContext context) {
    final dim = big ? size * 1.3 : size;
    final vivid = big || fill != null || on;
    return Tooltip(
      message: tooltip ?? '',
      child: SlushPressable(
        onTap: onTap,
        child: Material(
          color: big
              ? Slush.mint
              : fill ?? (on ? Slush.mint : context.slush.paper),
          shape: CircleBorder(side: context.slush.border),
          child: SizedBox.square(
            dimension: dim,
            child: Center(
              child: Icon(
                icon,
                size: dim * .5,
                color: vivid ? Slush.ink : context.slush.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Línea del artista de los reproductores completos: misma prioridad que
/// `miniSubtitle` (anuncio, Jam, artista) pero con la pista que pinta la
/// pantalla. Con audio de Jam manda la Jam, no el anuncio del sitio.
String playerArtistLine(AppController c, JamController? jam, Track track) {
  if (transportJamAudio(c, jam)) return '${track.artist} \u00b7 Jam';
  return c.adPlaying ? miniAdNotice : track.artist;
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.controller,
    this.jam,
    this.size = SlushControl.bar,
    this.gap = 10,
    this.wrap = false,
  });
  final AppController controller;
  final JamController? jam;
  final double size, gap;

  /// Móvil: salta de línea en vez de encoger (objetivos >= 44 siempre).
  final bool wrap;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final track = c.currentTrack;
    final liked = track != null && c.favoriteIds.contains(track.id);
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.audio, ?jam]),
      builder: (context, _) {
        // Con audio de Jam mandan los permisos de la sesión (como el mini).
        final s = MiniPlayerState.fromController(c, jam: jam);
        final a = MiniPlayerActions.forController(
          c,
          jam: jam,
          openPlayer: () {},
        );
        final j = jam;
        final handsOff = s.jamAudio && !j!.canSkip;
        final votes = handsOff && j.service.rules.votes;
        final items = <Widget>[
          _Round(
            icon: Icons.shuffle_rounded,
            tooltip: 'Aleatorio',
            on: c.shuffle,
            size: size,
            onTap: () => c.setShuffle(!c.shuffle),
          ),
          _Round(
            icon: Icons.skip_previous_rounded,
            tooltip: s.jamAudio ? 'No disponible en una Jam' : 'Anterior',
            size: size,
            onTap: track == null || s.jamActive ? null : a.previous,
          ),
          _Round(
            icon: c.audio.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            tooltip: s.jamHostName != null
                ? 'Lo controla ${s.jamHostName}'
                : c.audio.isPlaying
                ? 'Pausar'
                : 'Reproducir',
            big: true,
            size: size,
            onTap: s.canTogglePlay ? a.togglePlay : null,
          ),
          _Round(
            icon: votes ? Icons.how_to_vote_outlined : Icons.skip_next_rounded,
            tooltip: !handsOff
                ? 'Siguiente'
                : votes
                ? 'Votar para saltar'
                : 'Lo controla ${j.hostName}',
            size: size,
            onTap: !s.hasTrack || (s.jamAudio ? !s.hasNext : track == null)
                ? null
                : a.next,
          ),
          _Round(
            icon: c.repeat == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            tooltip: 'Repetir',
            on: c.repeat != RepeatMode.off,
            size: size,
            onTap: c.cycleRepeat,
          ),
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
              builder: (context, f) => _Round(
                icon: Icons.send_rounded,
                tooltip: 'Enviar a un amigo',
                size: size,
                onTap: () => showSendToFriendSheet(context, f, track),
              ),
            ),
        ];
        if (wrap) {
          return Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: items,
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              items[i],
            ],
          ],
        );
      },
    );
  }
}

/// Onda azul gruesa con borde negro y brillo, detrás del contenido.
class _BigWave extends StatelessWidget {
  const _BigWave();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    // Contorno de contenedor: en oscuro `lineSoft` (el crema haría halo).
    child: CustomPaint(painter: _BigWavePainter(context.slush.lineSoft)),
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
        ..color = _cream.withValues(alpha: .45), // brillo sobre el disco negro
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
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: 'Me gusta',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: SlushControl.touch,
          minHeight: SlushControl.touch,
        ),
        child: Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.favorite_rounded,
                  size: size,
                  color: context.slush.line,
                ),
                Icon(
                  Icons.favorite_rounded,
                  size: size * .84,
                  color: Slush.orange,
                ),
                Positioned(
                  left: size * .26,
                  top: size * .25,
                  child: Transform.rotate(
                    angle: -.7,
                    child: Container(
                      width: size * .22,
                      height: size * .08,
                      decoration: BoxDecoration(
                        color: Slush.yellow, // brillo decorativo sobre naranja
                        borderRadius: BorderRadius.circular(SlushRadius.r8),
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
    this.jam,
    this.onBack,
  });
  final AppController controller;
  final Track? track;
  final bool compact;
  final Widget Function(double size) recordBuilder;
  final VoidCallback onToggleCassette;
  final bool cassette;
  final ValueChanged<int>? onSection;

  /// Con una Jam activa: permisos y etiqueta «· Jam» (ver `playerArtistLine`).
  final JamController? jam;

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
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Slush.orange,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          'AHORA SUENA · ${_source.toUpperCase()}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _inkLabel(context),
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
      // El display ya es enorme: no escala más de 1,3.
      textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      style: Theme.of(
        context,
      ).textTheme.displayLarge?.copyWith(fontSize: size, height: .95),
    );
  }

  Widget _artist(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.audio, ?jam]),
    builder: (context, _) => Text(
      track == null
          ? 'Elige una canción de tu biblioteca'
          : playerArtistLine(controller, jam, track!),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 16,
        fontWeight: FontWeight.w700,
        // Sobre el color vivo de la portada (claro) solo la tinta plena llega a 4,5.
        color: _isDark(context) ? context.slush.ink2 : context.slush.ink,
      ),
    ),
  );

  Widget _noteDisc(BuildContext context) => Tooltip(
    message: cassette ? 'Ver vinilo' : 'Ver casete',
    child: SlushPressable(
      onTap: onToggleCassette,
      child: Material(
        key: const ValueKey('cassette-toggle'),
        color: Slush.yellow,
        shape: CircleBorder(side: context.slush.border),
        child: const SizedBox.square(
          dimension: 46,
          child: Center(
            child: Icon(Icons.music_note_rounded, size: 26, color: Slush.ink),
          ),
        ),
      ),
    ),
  );

  Widget _nextUp(BuildContext context) {
    final c = controller;
    final i = c.queueIndex + 1;
    if (i <= 0 || i >= c.queue.length) return const SizedBox.shrink();
    final t = c.queue[i];
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SlushPressable(
        onTap: onSection == null ? null : () => onSection!(5),
        child: Material(
          color: context.slush.paper,
          shape: StadiumBorder(side: context.slush.border),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(SlushRadius.r8),
                    border: Border.fromBorderSide(context.slush.border),
                    color: Slush.mint,
                  ),
                  child: Artwork(
                    track: t,
                    artworkContext: ArtworkContext.thumbnailCompact,
                    radius: 6,
                  ),
                ),
                const SizedBox(width: SlushSpacing.s8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A CONTINUACIÓN',
                      style: _inkLabel(context).copyWith(fontSize: 11),
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
                const SizedBox(width: SlushSpacing.s8),
                Text(
                  '+${c.queue.length - i}',
                  key: const ValueKey('next-up-remaining'),
                  style: _inkLabel(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
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
            if (c.audio.isPlaying &&
                !c.reducedMotion &&
                !SlushMotion.reduce(context))
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
              width: infoW,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _Controls(controller: c, jam: jam),
              ),
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
      final body = box.maxHeight >= 600
          ? stack
          : SingleChildScrollView(child: stack);
      return Theme.of(context).brightness == Brightness.dark
          ? ColoredBox(
              color: slushScreenColor(
                AccentScope.of(context, c.accentColor),
                dark: true,
              ),
              child: body,
            )
          : body;
    },
  );

  Widget _mobile(BuildContext context) {
    final c = controller;
    final bg = slushScreenColor(
      AccentScope.of(context, c.accentColor),
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    Widget circle(IconData icon, VoidCallback? onTap, String tip) => _Round(
      icon: icon,
      tooltip: tip,
      size: SlushControl.touch,
      onTap: onTap,
    );
    return ColoredBox(
      color: bg,
      child: LayoutBuilder(
        builder: (context, box) {
          final margin = SlushSpacing.margin(box.maxWidth);
          final inner = math.min(box.maxWidth - margin * 2, 460.0);
          final side = math.min(inner, 420.0);
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  margin,
                  SlushSpacing.s12,
                  margin,
                  SlushSpacing.s16,
                ),
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
                                size: SlushControl.touch,
                                onTap: null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: SlushSpacing.s12),
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
                                    size: SlushControl.touch,
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
                        const SizedBox(height: SlushSpacing.s12),
                        _title(context, inner, max: 54),
                        const SizedBox(height: SlushSpacing.s8),
                        _artist(context),
                        const SizedBox(height: SlushSpacing.s8),
                        Wrap(
                          spacing: SlushSpacing.s8,
                          runSpacing: SlushSpacing.s8,
                          children: _pills(),
                        ),
                        const SizedBox(height: SlushSpacing.s12),
                        _Progress(controller: c),
                        const SizedBox(height: SlushSpacing.s8),
                        Center(
                          child: _Controls(
                            controller: c,
                            jam: jam,
                            size: SlushControl.touch,
                            gap: SlushSpacing.s8,
                            wrap: true,
                          ),
                        ),
                        const SizedBox(height: SlushSpacing.s16),
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
