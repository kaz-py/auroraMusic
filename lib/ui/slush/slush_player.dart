import '../friends_page.dart';
import '../jam/jam_widgets.dart';
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
import '../mini_player/mini_player_model.dart';
import 'slush_bars.dart' show SlushDotBackdrop;
import 'slush_home.dart' show SlushCover;
import '../mini_player/song_card.dart';
import '../studio/studio_transport.dart' show transportJamAudio;

/// Reproductor Vinilo + Letras del tema Slush (escritorio y móvil).
/// Secciones del shell: 4 vinilo, 6 letras, 13 ecualizador, 5 cola.

/// Color de pantalla del reproductor: en claro, el lila del hero (tinta 9,8:1);
/// en oscuro, la capa `screen` con un tinte leve de la portada (el crema sigue
/// legible).
Color slushScreenColor(Color accent, {bool dark = false}) {
  if (!dark) return Slush.lilacHero;
  final h = HSLColor.fromColor(accent);
  final tint = HSLColor.fromAHSL(1, h.hue, .45, .30).toColor();
  return Color.lerp(SlushPalette.dark.screen, tint, .10)!;
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

TextStyle _time(BuildContext context) => TextStyle(
  fontFamily: 'Inter',
  fontSize: 13,
  fontWeight: FontWeight.w800,
  fontFeatures: const [FontFeature.tabularFigures()],
  color: context.slush.ink,
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

/// Papel claro: figuras decorativas de la etiqueta del disco (no son texto ni
/// fondo de texto).
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
                              // Móvil: la zona pulsable mide el mínimo táctil
                              // entero (la píldora crece los 6 px del margen).
                              minHeight: short ? minHeight : minHeight - 6,
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

/// Tarjeta de letras (escritorio): líneas alrededor de la activa con
/// subrayado lima, fuente, importar LRC y volumen. [snippet] (móvil) pinta solo
/// la línea anterior, la activa y la siguiente, sin tarjeta; [onTap] la abre.
class SlushLyricsCard extends StatefulWidget {
  const SlushLyricsCard({
    super.key,
    required this.controller,
    this.service,
    this.snippet = false,
    this.onTap,
  });
  final AppController controller;
  final LyricsService? service;
  final bool snippet;
  final VoidCallback? onTap;
  @override
  State<SlushLyricsCard> createState() => _SlushLyricsCardState();
}

class _SlushLyricsCardState extends State<SlushLyricsCard> {
  late final LyricsService _service = widget.service ?? LyricsService();
  // La letra tal como llegó (`_raw`) y la mostrada con su ajuste aplicado.
  LyricsResult? _raw;
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
    _raw = null;
    _result = null;
    final request = ++_request;
    if (track == null) return;
    _loading = true;
    unawaited(_load(track, request));
  }

  Future<void> _load(Track track, int request) async {
    final root = widget.controller.supportDirectory;
    try {
      final raw = await _service.load(track, root);
      if (!mounted || request != _request) return;
      _raw = raw;
      final shown = await _service.adjusted(track, root, raw);
      if (!mounted || request != _request) return;
      setState(() => _result = shown);
      if (raw.kind == LyricsKind.plain) {
        unawaited(_upgrade(track, request));
      } else if (raw.kind == LyricsKind.synced) {
        unawaited(_autoSync(track, raw, request));
      }
    } catch (_) {
      // Sin letra: se muestra el aviso de siempre.
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  /// Mide cuándo suena cada línea en el audio real (una vez por pista, en
  /// segundo plano) y, si saca una corrección, la aplica.
  Future<void> _autoSync(Track track, LyricsResult raw, int request) async {
    final root = widget.controller.supportDirectory;
    final changed = await widget.controller.lyricsAutoSync?.run(
      track,
      raw,
      widget.controller.audio.currentSource,
      root,
    );
    if (changed != true || !mounted || request != _request) return;
    final shown = await _service.adjusted(track, root, raw);
    if (mounted && request == _request) setState(() => _result = shown);
  }

  /// Letra sin tiempos: se busca una versión sincronizada que case; si no la
  /// hay, se le pone hora con el audio.
  Future<void> _upgrade(Track track, int request) async {
    final root = widget.controller.supportDirectory;
    final plain = _raw;
    try {
      final up = await _service.upgradeToSynced(track, root);
      if (!mounted || request != _request) return;
      if (up == null) {
        if (plain != null) unawaited(_autoSync(track, plain, request));
        return;
      }
      _raw = up;
      final shown = await _service.adjusted(track, root, up);
      if (!mounted || request != _request) return;
      setState(() => _result = shown);
      unawaited(_autoSync(track, up, request));
    } catch (_) {
      // Se queda la letra aproximada.
    }
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
        _raw = r;
        setState(() => _result = r);
      }
    } catch (_) {}
  }

  String get _chip {
    final r = _result;
    if (_loading) return 'Buscando…';
    if (r == null || r.kind == LyricsKind.notFound) return 'Sin letra';
    if (r.kind == LyricsKind.instrumental) return 'Instrumental';
    return r.source.isEmpty ? 'Letra' : r.source;
  }

  /// Etiqueta de la tarjeta: estado de la letra y su fuente.
  String _header(bool synced) {
    final r = _result;
    if (_loading || r == null || r.kind != LyricsKind.synced) {
      final tail = _chip;
      return 'LETRAS DINÁMICAS · ${tail.toUpperCase()}';
    }
    return 'LETRAS DINÁMICAS · SINCRONIZADAS';
  }

  /// Móvil: tres líneas (anterior, activa, siguiente) sobre el fondo lila.
  Widget _snippet(BuildContext context) {
    final c = widget.controller;
    final p = context.slush;
    final r = _result;
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final lines = r == null
            ? const <LyricLine>[]
            : r.kind == LyricsKind.synced
            ? r.lines
            : r.kind == LyricsKind.plain
            ? LyricsService.spreadLines(r.text, c.audio.duration)
            : const <LyricLine>[];
        String at(int k) => k >= 0 && k < lines.length ? lines[k].text : '';
        final i = lines.lastIndexWhere((l) => l.at <= c.audio.position);
        final dim = TextStyle(
          fontFamily: 'Inter',
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: p.ink2,
        );
        final body = lines.isEmpty
            ? Text(
                _loading ? 'Buscando letra…' : 'Esta pista no tiene letra.',
                textAlign: TextAlign.center,
                style: dim,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (k, style) in [
                    (i - 1, dim),
                    (i, slushHeadline(24, height: 1.15, color: p.ink)),
                    (i + 1, dim),
                  ])
                    if (at(k).isNotEmpty || k == i)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          at(k),
                          textAlign: TextAlign.center,
                          maxLines: k == i ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: style,
                        ),
                      ),
                ],
              );
        return Semantics(
          button: widget.onTap != null,
          label: 'Letra de la canción',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 88),
              child: Center(child: body),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.snippet) return _snippet(context);
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
          child: LayoutBuilder(
            builder: (context, box) {
              // shortcut: umbral según la escala de texto, no medido.
              final scale = MediaQuery.textScalerOf(context).scale(1);
              final scroll = box.maxHeight < 120 + 160 * scale;
              final body = synced
                  ? ListenableBuilder(
                      listenable: c.audio,
                      builder: (context, _) => _SyncedScroll(
                        lines: r.lines,
                        active: r.lines.lastIndexWhere(
                          (l) =>
                              l.at.inMilliseconds <=
                              c.audio.position.inMilliseconds,
                        ),
                      ),
                    )
                  : plain.isNotEmpty
                  // Sin tiempos: se reparten por la pista (como el modo artista)
                  // y, sin duración aún, se ve el texto plano.
                  ? ListenableBuilder(
                      listenable: c.audio,
                      builder: (context, _) {
                        final lines = LyricsService.spreadLines(
                          r!.text,
                          c.audio.duration,
                        );
                        if (lines.isNotEmpty) {
                          return _SyncedScroll(
                            lines: lines,
                            active: lines.lastIndexWhere(
                              (l) => l.at <= c.audio.position,
                            ),
                          );
                        }
                        return ListView(
                          children: [
                            for (final l in plain)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 5,
                                ),
                                child: Text(l, style: _lineStyle(false)),
                              ),
                          ],
                        );
                      },
                    )
                  : Center(
                      child: Text(
                        _loading
                            ? 'Buscando letras…'
                            : 'Esta pista no tiene letra.',
                        textAlign: TextAlign.center,
                        style: _lineStyle(true),
                      ),
                    );
              final column = Column(
                mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _header(synced),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: slushMono(11, color: p.ink2, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: SlushSpacing.s12),
                  scroll
                      ? SizedBox(height: 120, child: body)
                      : Expanded(child: body),
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
              );
              // Sin altura para cabecera + letra + controles (móvil con texto
              // grande): la tarjeta se desplaza en vez de desbordar.
              return scroll ? SingleChildScrollView(child: column) : column;
            },
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
                    // Subrayado lima (firma de Slush): franja en el tercio
                    // inferior de la línea activa; en oscuro, filete bajo
                    // texto crema (el crema sobre lima no se lee).
                    decoration: _isDark(context)
                        ? const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Slush.lime, width: 4),
                            ),
                          )
                        : BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Slush.lime.withValues(alpha: 0),
                                Slush.lime.withValues(alpha: 0),
                                Slush.lime,
                                Slush.lime,
                              ],
                              stops: const [0, .62, .62, 1],
                            ),
                          ),
                    child: Text(
                      text,
                      style: slushHeadline(26, height: 1.2, color: p.ink),
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
    canvas.drawCircle(center, 10, Paint()..color = Slush.lime);
    canvas.drawCircle(
      center,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SlushStroke.base
        ..color = line,
    );
  }
}

/// Barra de progreso: relleno violeta, pista de papel, thumb lima y tiempos.
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
                  trackHeight: 12,
                  activeTrackColor: p.violetAccent,
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
                  Text(_clock(c.audio.position), style: _time(context)),
                  Text('-${_clock(left)}', style: _time(context)),
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
    this.bare = false,
    this.squircle = false,
    this.size = SlushControl.bar,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Play: lima con sombra dura (círculo; [squircle] en móvil, 76 radio 30).
  final bool big, on;
  final Color? fill;

  /// Solo el glifo (controles móviles); activo, recupera el círculo de papel.
  final bool bare, squircle;
  final double size;
  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final dim = squircle ? 76.0 : (big ? size * 1.3 : size);
    final vivid = big || fill != null || on;
    final glyph = Icon(
      icon,
      size: dim * (squircle ? .46 : .5),
      color: vivid ? Slush.ink : p.ink,
    );
    final plain = bare && !vivid;
    return Tooltip(
      message: tooltip ?? '',
      child: SlushPressable(
        onTap: onTap,
        elevation: plain ? SlushElevation.none : SlushElevation.control,
        radius: squircle ? 30 : SlushRadius.pill,
        minSize: math.max(dim, SlushControl.touch),
        child: plain
            ? SizedBox.square(
                dimension: dim,
                child: Center(child: glyph),
              )
            : Material(
                color: big ? Slush.lime : fill ?? (on ? Slush.mint : p.paper),
                shape: squircle
                    ? RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                        side: p.border,
                      )
                    : CircleBorder(side: p.border),
                child: SizedBox.square(
                  dimension: dim,
                  child: Center(child: glyph),
                ),
              ),
      ),
    );
  }
}

/// Línea del artista de los reproductores completos: misma prioridad que
/// `miniSubtitle` (Jam, artista) pero con la pista que pinta la pantalla.
String playerArtistLine(AppController c, JamController? jam, Track track) {
  if (transportJamAudio(c, jam)) return '${track.artist} \u00b7 Jam';
  return track.artist;
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller, this.jam, this.mobile = false});
  final AppController controller;
  final JamController? jam;

  /// Móvil: cinco controles (aleatorio, anterior, Play squircle, siguiente,
  /// repetir) solo con glifo y repartidos a todo el ancho; el corazón vive en
  /// el titular.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    const size = SlushControl.bar, gap = 10.0;
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
            bare: mobile,
            onTap: () => c.setShuffle(!c.shuffle),
          ),
          _Round(
            icon: Icons.skip_previous_rounded,
            tooltip: s.jamAudio ? 'No disponible en una Jam' : 'Anterior',
            size: size,
            bare: mobile,
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
            squircle: mobile,
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
            bare: mobile,
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
            bare: mobile,
            onTap: c.cycleRepeat,
          ),
          if (!mobile)
            _Round(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              tooltip: 'Me gusta',
              fill: liked ? Slush.orange : null,
              size: size,
              bare: mobile,
              onTap: track == null ? null : () => c.toggleFavorite(track),
            ),
          if (!mobile && track != null && !track.isLocal)
            FriendsGate(
              builder: (context, f) => _Round(
                icon: Icons.send_rounded,
                tooltip: 'Enviar a un amigo',
                size: size,
                bare: mobile,
                onTap: () => showSendToFriendSheet(context, f, track),
              ),
            ),
        ];
        if (mobile) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  bool get _flac => track?.localPath?.toLowerCase().endsWith('.flac') ?? false;

  /// «FLAC» si el archivo lo es; si no, el origen real (no se inventa un
  /// formato o una DAC que la app no mide).
  String get _formatTag => _flac
      ? 'FLAC'
      : track == null
      ? 'SIN PISTA'
      : track!.isLocal
      ? 'LOCAL'
      : 'YOUTUBE';

  Widget _title(BuildContext context, double size) => Text(
    track?.title ?? 'Nada sonando',
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    // El titular ya es grande: no escala más de 1,3.
    textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
    style: slushHeadline(size, height: 1.02, color: context.slush.ink),
  );

  Widget _artist(BuildContext context, {bool album = false}) =>
      ListenableBuilder(
        listenable: Listenable.merge([controller, controller.audio, ?jam]),
        builder: (context, _) {
          final t = track;
          final extra = album && t != null && (t.album ?? '').isNotEmpty
              ? ' · ${t.album}'
              : '';
          return Text(
            t == null
                ? 'Elige una canción de tu biblioteca'
                : '${playerArtistLine(controller, jam, t)}$extra',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.slush.ink,
            ),
          );
        },
      );

  /// Etiqueta pequeña (Ahora suena, FLAC…): [fill] con texto [fg].
  Widget _tag(String label, Color fill, Color fg, {bool mono = false}) =>
      DecoratedBox(
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: mono
                ? slushMono(12, color: fg, letterSpacing: .4)
                : TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
          ),
        ),
      );

  Widget _chipFace(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
  ) {
    final p = context.slush;
    final fg = color == p.paper ? p.ink : Slush.ink;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _touch(context)),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: color,
          shape: StadiumBorder(side: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: fg),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _label.copyWith(color: fg),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    String? tooltip,
    Key? key,
  }) => Tooltip(
    key: key,
    message: tooltip ?? label,
    child: SlushPressable(
      onTap: onTap,
      minSize: _touch(context),
      child: _chipFace(context, label, icon, color),
    ),
  );

  /// Me gusta, EQ, Dormir, Jam (y el selector vinilo/casete): chips de color.
  List<Widget> _actions(BuildContext context, {bool labels = true}) {
    final c = controller;
    final p = context.slush;
    final t = track;
    final liked = t != null && c.favoriteIds.contains(t.id);
    final left = c.sleepRemaining;
    final j = jam;
    final inJam = j != null && j.service.connected;
    return [
      if (labels)
        _chip(
          context,
          liked ? 'En favoritos' : 'Me gusta',
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          Slush.pink,
          t == null ? null : () => c.toggleFavorite(t),
          tooltip: liked ? 'Quitar de favoritos' : 'Me gusta',
        ),
      _chip(
        context,
        'EQ',
        Icons.equalizer_rounded,
        p.paper,
        onSection == null ? null : () => onSection!(13),
        tooltip: 'Ecualizador',
      ),
      _SleepMenu(
        controller: c,
        builder: (_) => _chipFace(
          context,
          left == null ? 'Dormir' : '${(left.inSeconds / 60).ceil()} min',
          Icons.nightlight_round,
          Slush.yellow,
        ),
      ),
      _chip(
        context,
        inJam ? 'Jam · ${j.peopleCount}' : 'Jam',
        Icons.groups_rounded,
        Slush.mint,
        onSection == null ? null : () => onSection!(9),
        tooltip: 'Jam',
      ),
      _chip(
        context,
        '',
        cassette ? Icons.album_outlined : Icons.sd_card_outlined,
        p.paper,
        onToggleCassette,
        tooltip: cassette ? 'Ver vinilo' : 'Ver casete',
        key: const ValueKey('cassette-toggle'),
      ),
    ];
  }

  /// Portada con el vinilo asomando por detrás (casete: solo la pieza).
  Widget _coverWithDisc(BuildContext context, double cover) {
    if (cassette) {
      // El casete añade 8 + 48 px de transporte bajo el cuerpo (ancho / 1,6): no pasar de `cover`.
      final size = math.min(cover * 1.25, 1.6 * (cover - 56));
      return SizedBox(
        width: cover * 1.3,
        height: cover,
        child: Center(child: recordBuilder(size)),
      );
    }
    return SizedBox(
      width: cover * 1.3,
      height: cover,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: cover * .38,
            top: cover * .04,
            child: recordBuilder(cover * .92),
          ),
          SlushCover(
            track: track,
            side: cover,
            radius: SlushRadius.r32 - 4,
            shadow: true,
          ),
        ],
      ),
    );
  }

  Widget _heroInfo(BuildContext context, double titleSize) {
    final p = context.slush;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag('Ahora suena', p.ink, p.paper),
            _tag(_formatTag, Slush.lime, Slush.ink, mono: true),
            _tag(_source, p.paper, p.ink),
          ],
        ),
        const SizedBox(height: 12),
        _title(context, titleSize),
        const SizedBox(height: 8),
        _artist(context, album: true),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: _actions(context),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, controller.audio]),
    builder: (context, _) => compact ? _mobile(context) : _desktop(context),
  );

  Widget _desktop(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final p = context.slush;
      final dark = _isDark(context);
      final w = box.maxWidth;
      final margin = w < 700 ? 16.0 : 24.0;
      final inner = w - margin * 2 - 4;
      final cover = (inner * .3).clamp(150.0, 250.0);
      final stacked = inner < 600;
      final hero = DecoratedBox(
        decoration: ShapeDecoration(
          color: dark ? p.paper : Slush.lilacHero,
          shadows: p.shadows,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlushRadius.r32),
            side: p.borderSoft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: _coverWithDisc(context, cover)),
                    const SizedBox(height: 16),
                    _heroInfo(context, 32),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _coverWithDisc(context, cover),
                    const SizedBox(width: 24),
                    Expanded(child: _heroInfo(context, w >= 900 ? 44 : 36)),
                  ],
                ),
        ),
      );
      final transport = DecoratedBox(
        decoration: ShapeDecoration(
          color: p.paper,
          shadows: p.shadows,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlushRadius.r32),
            side: p.borderSoft,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Progress(controller: controller),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: _Controls(controller: controller, jam: jam),
              ),
            ],
          ),
        ),
      );
      final lyrics = SlushLyricsCard(controller: controller);
      // Altura holgada y texto normal: la letra absorbe el resto. Si no, la
      // pantalla se desplaza (shortcut: umbral fijo, no medido).
      final fixed =
          box.maxHeight.isFinite &&
          box.maxHeight >= 720 &&
          !stacked &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.3;
      // Sitio para sombras duras (3,4) a la derecha y abajo.
      final pad = EdgeInsets.fromLTRB(margin, 8, margin + 4, 12);
      final body = fixed
          ? Padding(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: 16),
                  Expanded(child: lyrics),
                  const SizedBox(height: 16),
                  transport,
                ],
              ),
            )
          : SingleChildScrollView(
              padding: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hero,
                  const SizedBox(height: 16),
                  SizedBox(height: 380, child: lyrics),
                  const SizedBox(height: 16),
                  transport,
                ],
              ),
            );
      return dark
          ? ColoredBox(
              color: slushScreenColor(
                AccentScope.of(context, controller.accentColor),
                dark: true,
              ),
              child: body,
            )
          : body;
    },
  );

  /// Hoja de cola (asa, título y siguiente): abre la pantalla Cola.
  Widget _queuePeek(BuildContext context) {
    final p = context.slush;
    final c = controller;
    final i = c.queueIndex + 1;
    final next = i > 0 && i < c.queue.length ? c.queue[i] : null;
    return SlushPressable(
      onTap: onSection == null ? null : () => onSection!(5),
      elevation: SlushElevation.none,
      pressedScale: 1,
      radius: SlushRadius.r32,
      minSize: 56,
      semanticLabel: 'Cola de reproducción',
      child: DecoratedBox(
        key: const ValueKey('queue-peek'),
        decoration: ShapeDecoration(
          color: p.paper,
          shape: RoundedRectangleBorder(
            side: p.borderSoft,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(SlushRadius.r32),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: p.ink,
                    shape: const StadiumBorder(),
                  ),
                  child: const SizedBox(width: 44, height: 5),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    c.queue.isEmpty
                        ? 'Cola de reproducción'
                        : 'Cola de reproducción · ${c.queue.length}',
                    style: slushHeadline(18, color: p.ink),
                  ),
                  if (next != null)
                    Text(
                      'Sigue: ${next.title}',
                      key: const ValueKey('next-up-remaining'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.ink2,
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

  Widget _mobile(BuildContext context) {
    final c = controller;
    final p = context.slush;
    final t = track;
    final liked = t != null && c.favoriteIds.contains(t.id);
    final bg = slushScreenColor(
      AccentScope.of(context, c.accentColor),
      dark: _isDark(context),
    );
    Widget circle(IconData icon, VoidCallback? onTap, String tip) =>
        _Round(icon: icon, tooltip: tip, size: SlushControl.bar, onTap: onTap);
    return ColoredBox(
      color: bg,
      child: SlushDotBackdrop(
        child: LayoutBuilder(
          builder: (context, box) {
            final margin = SlushSpacing.margin(box.maxWidth);
            final inner = math.min(box.maxWidth - margin * 2, 460.0);
            final cover =
                (box.maxHeight.isFinite
                        ? math.min(inner, box.maxHeight * .38)
                        : inner)
                    .clamp(200.0, 340.0);
            final body = Padding(
              padding: EdgeInsets.fromLTRB(margin, SlushSpacing.s12, margin, 0),
              child: Center(
                child: SizedBox(
                  width: inner,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          circle(
                            Icons.keyboard_arrow_down_rounded,
                            onBack ?? () => onSection?.call(0),
                            'Volver',
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'REPRODUCIENDO DESDE',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: slushMono(
                                    11,
                                    color: p.ink,
                                    letterSpacing: 1.4,
                                  ),
                                ),
                                Text(
                                  _source,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (b) => circle(
                              Icons.more_horiz_rounded,
                              t == null
                                  ? null
                                  : () {
                                      final box =
                                          b.findRenderObject() as RenderBox;
                                      showSongCard(
                                        context,
                                        c,
                                        t,
                                        box.localToGlobal(
                                          box.size.bottomLeft(Offset.zero),
                                        ),
                                      );
                                    },
                              'Más acciones',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: SlushSpacing.s12),
                      Center(
                        child: cassette
                            ? SizedBox(
                                width: cover,
                                height: cover,
                                child: Center(child: recordBuilder(cover)),
                              )
                            : SizedBox.square(
                                dimension: cover,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned.fill(
                                      child: SlushCover(
                                        track: t,
                                        side: cover,
                                        radius: SlushRadius.r32 - 4,
                                        shadow: true,
                                      ),
                                    ),
                                    Positioned(
                                      top: -8,
                                      right: -4,
                                      child: Transform.rotate(
                                        angle: .1,
                                        child: DecoratedBox(
                                          decoration: ShapeDecoration(
                                            color: Slush.lime,
                                            shadows: p.shadowsFor(
                                              SlushElevation.control,
                                            ),
                                            shape: StadiumBorder(
                                              side: p.border,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 4,
                                            ),
                                            child: Text(
                                              _formatTag,
                                              style: slushMono(
                                                13,
                                                color: Slush.ink,
                                                letterSpacing: .4,
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
                      const SizedBox(height: SlushSpacing.s16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _title(context, 32),
                                const SizedBox(height: 2),
                                _artist(context),
                              ],
                            ),
                          ),
                          const SizedBox(width: SlushSpacing.s8),
                          _Round(
                            icon: liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            tooltip: liked ? 'Quitar de favoritos' : 'Me gusta',
                            fill: Slush.pink,
                            size: SlushControl.bar,
                            onTap: t == null ? null : () => c.toggleFavorite(t),
                          ),
                        ],
                      ),
                      const SizedBox(height: SlushSpacing.s8),
                      SlushLyricsCard(
                        controller: c,
                        snippet: true,
                        onTap: onSection == null ? null : () => onSection!(6),
                      ),
                      const SizedBox(height: SlushSpacing.s8),
                      _Progress(controller: c),
                      const SizedBox(height: SlushSpacing.s8),
                      _Controls(controller: c, jam: jam, mobile: true),
                      const SizedBox(height: SlushSpacing.s16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: SlushSpacing.s8,
                        runSpacing: SlushSpacing.s8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ..._actions(context, labels: false),
                          _chip(
                            context,
                            '',
                            Icons.queue_music_rounded,
                            p.paper,
                            onSection == null ? null : () => onSection!(5),
                            tooltip: 'Cola de reproducción',
                          ),
                        ],
                      ),
                      const SizedBox(height: SlushSpacing.s16),
                    ],
                  ),
                ),
              ),
            );
            // Sin Spacer ni intrínsecos: en pantallas altas la hoja de cola
            // baja al fondo (spaceBetween); en bajas, todo se desplaza.
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: box.maxHeight.isFinite ? box.maxHeight : 0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [body, _queuePeek(context)],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
