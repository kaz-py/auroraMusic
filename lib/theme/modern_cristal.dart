/// Modern «Cristal y aura»: paleta, tipografía y piezas propias (cristal, aura
/// de portada, onda de búsqueda, chip de señal). Dueño: tema Modern.
///
/// Nada aquí reemplaza a `ModernCard` & co. de `modern_widgets.dart` (los usa
/// también Slush): son piezas nuevas con prefijo `Modern`.
library;

import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../ui/mini_player/cover_backdrop_source.dart';

/// Paleta de Modern (oscura según el prototipo; la clara es su espejo).
@immutable
class Cristal {
  const Cristal._({
    required this.dark,
    required this.canvas,
    required this.glass,
    required this.glassHover,
    required this.border,
    required this.glow,
    required this.text,
    required this.text2,
    required this.text3,
    required this.accent,
    required this.onAccent,
    required this.signal,
    required this.like,
    required this.vu,
    required this.chip,
    required this.onChip,
  });

  final bool dark;

  /// Lienzo casi negro.
  final Color canvas;

  /// Relleno del cristal (blanco 6 %) y su estado activo/hover (10 %).
  final Color glass, glassHover;

  /// Borde del cristal (10 %) y brillo interior superior (7 %).
  final Color border, glow;

  /// Texto principal, secundario y de etiquetas mono.
  final Color text, text2, text3;

  /// Único acento (play, activo, progreso) y la tinta sobre él.
  final Color accent, onAccent;

  /// Menta reservada a la señal (FLAC/DAC) y coral al «me gusta».
  final Color signal, like;

  /// Pico/VU opcional.
  final Color vu;

  /// Chip activo (relleno claro con texto oscuro).
  final Color chip, onChip;

  static const darkPalette = Cristal._(
    dark: true,
    canvas: Color(0xff0b0d12),
    glass: Color(0x0fffffff),
    glassHover: Color(0x1affffff),
    border: Color(0x1affffff),
    glow: Color(0x12ffffff),
    text: Color(0xffe8ecf4),
    text2: Color(0xffa8b0c4),
    text3: Color(0xff8590a8),
    accent: Color(0xff6ea8ff),
    onAccent: Color(0xff06101f),
    signal: Color(0xff86e0c1),
    like: Color(0xffff6b6b),
    vu: Color(0xfff5b544),
    chip: Color(0xffe8ecf4),
    onChip: Color(0xff0b0d12),
  );

  static const lightPalette = Cristal._(
    dark: false,
    canvas: Color(0xfff2f4fa),
    glass: Color(0x0a0b0d12),
    glassHover: Color(0x140b0d12),
    border: Color(0x1a0b0d12),
    glow: Color(0x99ffffff),
    text: Color(0xff0f1422),
    text2: Color(0xff434c63),
    text3: Color(0xff566079),
    accent: Color(0xff2459c9),
    onAccent: Color(0xffffffff),
    signal: Color(0xff0b6b52),
    like: Color(0xffc62828),
    vu: Color(0xff9a5f00),
    chip: Color(0xff0f1422),
    onChip: Color(0xfff2f4fa),
  );

  static Cristal of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? darkPalette
      : lightPalette;

  /// Menta de la señal sobre fondo oscuro o su versión legible sobre claro.
  Color get signalFill => signal.withValues(alpha: .12);
  Color get signalBorder => signal.withValues(alpha: .45);

  /// Píldora activa (acento al 14 %).
  Color get accentSoft => accent.withValues(alpha: .14);

  // --- Tipografía ---------------------------------------------------------

  /// Manrope (variable): UI y títulos. `tracking` en em.
  static TextStyle ui(
    double size, {
    int weight = 600,
    Color? color,
    double? height,
    double tracking = 0,
  }) => TextStyle(
    fontFamily: 'Manrope',
    fontSize: size,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    letterSpacing: size * tracking,
  );

  /// Geist Mono: etiquetas en mayúsculas, atajos, tiempos, chips. Cifras
  /// tabulares siempre.
  static TextStyle mono(
    double size, {
    int weight = 500,
    Color? color,
    double tracking = .12,
    double? height,
  }) => TextStyle(
    fontFamily: 'Geist Mono',
    fontSize: size,
    fontWeight: _weight(weight),
    fontVariations: [FontVariation('wght', weight.toDouble())],
    color: color,
    height: height,
    letterSpacing: size * tracking,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static FontWeight _weight(int w) =>
      FontWeight.values[((w ~/ 100) - 1).clamp(0, 8)];
}

/// Sin efectos pesados: movimiento reducido pide fondo plano y sin fundidos.
bool modernReduceEffects(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);

// ---------------------------------------------------------------------------
// Cristal
// ---------------------------------------------------------------------------

/// Superficie de cristal fino: relleno translúcido, borde y brillo interior
/// superior, sin sombra. No usa `BackdropFilter`: sobre el aura (degradados
/// suaves) el desenfoque no se vería y cuesta en gama baja.
class ModernGlass extends StatelessWidget {
  const ModernGlass({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding,
    this.fill,
    this.tint,
    this.border = true,
    this.clip = false,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// Sustituye al relleno estándar (p. ej. `glassHover` para el activo).
  final Color? fill;

  /// Tinte de portada que se mezcla bajo el cristal.
  final Color? tint;
  final bool border;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final shape = BorderRadius.circular(radius);
    Widget body = padding == null
        ? child
        : Padding(padding: padding!, child: child);
    if (clip) body = ClipRRect(borderRadius: shape, child: body);
    return CustomPaint(
      foregroundPainter: _GlowPainter(radius, c.glow, c.border, border),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill ?? c.glass,
          borderRadius: shape,
          gradient: tint == null
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint!.withValues(alpha: .28),
                    tint!.withValues(alpha: .06),
                  ],
                ),
        ),
        child: body,
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.radius, this.glow, this.border, this.drawBorder);
  final double radius;
  final Color glow, border;
  final bool drawBorder;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.5);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    if (drawBorder) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = border,
      );
    }
    canvas.drawRRect(
      rrect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [glow, glow.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.radius != radius ||
      old.glow != glow ||
      old.border != border ||
      old.drawBorder != drawBorder;
}

// ---------------------------------------------------------------------------
// Aura de portada
// ---------------------------------------------------------------------------

/// Dos colores de aura a partir de las muestras (8×8) de la portada: el más
/// vivo y el siguiente de tono distinto (o el más oscuro). Puro y probable.
(Color, Color) modernAuraColors(List<Color> samples) {
  if (samples.isEmpty) return (_auraA, _auraB);
  double score(HSLColor h) =>
      h.saturation * (1 - (h.lightness - .5).abs() * 1.4).clamp(.05, 1.0);
  final hsl = [for (final s in samples) HSLColor.fromColor(s)];
  var best = 0;
  for (var i = 1; i < hsl.length; i++) {
    if (score(hsl[i]) > score(hsl[best])) best = i;
  }
  final a = hsl[best];
  int? second;
  for (var i = 0; i < hsl.length; i++) {
    final d = (hsl[i].hue - a.hue).abs();
    if (math.min(d, 360 - d) < 45) continue;
    if (second == null || score(hsl[i]) > score(hsl[second])) second = i;
  }
  final b = second == null
      ? a.withHue((a.hue + 150) % 360).withLightness(.28)
      : hsl[second];
  Color norm(HSLColor h) => h
      .withSaturation(h.saturation.clamp(.35, .9))
      .withLightness(h.lightness.clamp(.3, .6))
      .toColor();
  return (norm(a), norm(b));
}

const _auraA = Color(0xff3a6aa8);
const _auraB = Color(0xff4a2f78);

/// Fondo a ventana completa: lienzo oscuro + dos manchas de color de la
/// portada. Una sola capa (degradados, sin desenfoque en vivo) y animada solo
/// al cambiar de pista.
class ModernAura extends StatefulWidget {
  const ModernAura({super.key, required this.track, required this.child});

  final Track? track;
  final Widget child;

  @override
  State<ModernAura> createState() => _ModernAuraState();
}

class _ModernAuraState extends State<ModernAura> {
  (Color, Color) _colors = (_auraA, _auraB);
  String? _key;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ModernAura old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.track?.artworkUrl != widget.track?.artworkUrl) {
      _resolve();
    }
  }

  void _resolve() {
    final track = widget.track;
    final cache = CoverBackdropCache.shared;
    final key = track == null ? null : cache.keyOf(track);
    _key = key;
    if (track == null || key == null) {
      _colors = (_auraA, _auraB);
      return;
    }
    final hit = cache.peek(track);
    if (hit != null) {
      _colors = modernAuraColors(hit.samples);
      return;
    }
    cache.load(track).then((data) {
      if (!mounted || _key != key) return;
      setState(
        () => _colors = data == null
            ? (_auraA, _auraB)
            : modernAuraColors(data.samples),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final instant = modernReduceEffects(context);
    return TweenAnimationBuilder<_AuraPair>(
      tween: _AuraTween(end: _AuraPair(_colors.$1, _colors.$2)),
      duration: instant ? Duration.zero : const Duration(milliseconds: 700),
      builder: (context, pair, child) => Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _AuraPainter(pair.a, pair.b, c.canvas, c.dark),
            ),
          ),
          child!,
        ],
      ),
      child: widget.child,
    );
  }
}

@immutable
class _AuraPair {
  const _AuraPair(this.a, this.b);
  final Color a, b;
}

class _AuraTween extends Tween<_AuraPair> {
  _AuraTween({required _AuraPair super.end}) : super(begin: end);

  @override
  _AuraPair lerp(double t) => _AuraPair(
    Color.lerp(begin!.a, end!.a, t)!,
    Color.lerp(begin!.b, end!.b, t)!,
  );
}

class _AuraPainter extends CustomPainter {
  _AuraPainter(this.a, this.b, this.canvas, this.dark);
  final Color a, b, canvas;
  final bool dark;

  @override
  void paint(Canvas c, Size size) {
    final rect = Offset.zero & size;
    c.drawRect(rect, Paint()..color = canvas);
    final r = size.longestSide;
    void blob(Offset at, double radius, Color color, double alpha) {
      c.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: alpha * .4),
              color.withValues(alpha: 0),
            ],
            stops: const [0, .5, 1],
          ).createShader(Rect.fromCircle(center: at, radius: radius)),
      );
    }

    final k = dark ? 1.0 : .55;
    blob(Offset(size.width * .18, size.height * .02), r * .62, a, .46 * k);
    blob(Offset(size.width * .92, size.height * .98), r * .55, b, .34 * k);
    // Velo para legibilidad: más cargado hacia abajo.
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            canvas.withValues(alpha: .15),
            canvas.withValues(alpha: .55),
          ],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_AuraPainter old) =>
      old.a != a || old.b != b || old.canvas != canvas || old.dark != dark;
}

// ---------------------------------------------------------------------------
// Señal
// ---------------------------------------------------------------------------

/// Etiqueta de formato de una pista: extensión del archivo local en
/// mayúsculas (FLAC, MP3…) o `STREAM` si no hay archivo. No se inventan
/// profundidad ni frecuencia de muestreo que la app no conoce.
String modernFormatLabel(Track track) {
  final path = track.localPath;
  if (path == null) return 'STREAM';
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot >= path.length - 1) return 'LOCAL';
  final ext = path.substring(dot + 1).toUpperCase();
  return ext.length > 5 ? 'LOCAL' : ext;
}

/// Chip de señal (menta + mono) con LED: fidelidad visible en cada pantalla.
class ModernSignalChip extends StatelessWidget {
  const ModernSignalChip({
    super.key,
    required this.label,
    this.led = true,
    this.size = 10.5,
  });

  final String label;
  final bool led;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.signalFill,
        border: Border.all(color: c.signalBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (led) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.signal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cristal.mono(
                  size,
                  weight: 600,
                  color: c.signal,
                  tracking: .06,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etiqueta mono en mayúsculas (10,5 px, tracking .12em).
class ModernLabel extends StatelessWidget {
  const ModernLabel(this.text, {super.key, this.color, this.size = 10.5});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Cristal.mono(size, color: color ?? Cristal.of(context).text3),
  );
}

// ---------------------------------------------------------------------------
// Onda de búsqueda
// ---------------------------------------------------------------------------

final _peakCache = <String, List<double>>{};

/// Picos 0..1 deterministas por pista (hash FNV del id): la app no analiza el
/// audio, así que la onda es una pseudo-onda estable, la misma cada vez.
List<double> modernPeaks(String seed, int count) {
  final base = _peakCache.remove(seed) ?? _generate(seed);
  _peakCache[seed] = base;
  while (_peakCache.length > 24) {
    _peakCache.remove(_peakCache.keys.first);
  }
  if (count == base.length) return base;
  return [
    for (var i = 0; i < count; i++)
      base[(i * base.length / math.max(1, count)).floor().clamp(
        0,
        base.length - 1,
      )],
  ];
}

const _peakBase = 256;

List<double> _generate(String seed) {
  var h = 0x811c9dc5;
  for (final u in seed.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xffffffff;
  }
  final rnd = math.Random(h);
  final p1 = rnd.nextDouble() * math.pi * 2;
  final p2 = rnd.nextDouble() * math.pi * 2;
  final f1 = 2 + rnd.nextInt(3), f2 = 7 + rnd.nextInt(5);
  return [
    for (var i = 0; i < _peakBase; i++)
      () {
        final t = i / _peakBase;
        final env =
            .55 +
            .25 * math.sin(t * math.pi * f1 + p1) +
            .12 * math.sin(t * math.pi * f2 + p2);
        final edge = math.min(1.0, math.min(t, 1 - t) * 14 + .35);
        return ((env + (rnd.nextDouble() - .5) * .5) * edge).clamp(.08, 1.0);
      }(),
  ];
}

/// Barra de búsqueda en forma de onda: azul = reproducido, resto blanco 24 %.
/// Sustituye al slider. Arrastrar o tocar mueve la posición; `onSeek` solo se
/// llama al soltar (no por fotograma). Sin `onSeek` es solo visual.
class ModernWaveSeekBar extends StatefulWidget {
  const ModernWaveSeekBar({
    super.key,
    required this.progress,
    required this.seed,
    this.onSeek,
    this.height = 32,
    this.barWidth = 3,
    this.gap = 2,
    this.peaks,
    this.semanticsLabel = 'Posición de la pista',
    this.activeColor,
    this.restColor,
  });

  /// 0..1.
  final double progress;

  /// Identificador de la pista (semilla de la pseudo-onda).
  final String seed;
  final ValueChanged<double>? onSeek;
  final double height, barWidth, gap;

  /// Picos reales si existen; si no, los deterministas de [seed].
  final List<double>? peaks;
  final String semanticsLabel;
  final Color? activeColor, restColor;

  @override
  State<ModernWaveSeekBar> createState() => _ModernWaveSeekBarState();
}

class _ModernWaveSeekBarState extends State<ModernWaveSeekBar> {
  double? _drag;

  double _fraction(double dx, double width) =>
      width <= 0 ? 0 : (dx / width).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final seek = widget.onSeek;
    final value = (_drag ?? widget.progress).clamp(0.0, 1.0);
    return Semantics(
      slider: true,
      label: widget.semanticsLabel,
      value: '${(value * 100).round()} %',
      increasedValue: '${((value + .05).clamp(0.0, 1.0) * 100).round()} %',
      decreasedValue: '${((value - .05).clamp(0.0, 1.0) * 100).round()} %',
      onIncrease: seek == null
          ? null
          : () => seek((widget.progress + .05).clamp(0.0, 1.0)),
      onDecrease: seek == null
          ? null
          : () => seek((widget.progress - .05).clamp(0.0, 1.0)),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = box.maxWidth.isFinite ? box.maxWidth : 240.0;
            final n = math.max(
              8,
              ((width + widget.gap) / (widget.barWidth + widget.gap)).floor(),
            );
            final peaks = widget.peaks != null && widget.peaks!.length == n
                ? widget.peaks!
                : modernPeaks(widget.seed, n);
            return MouseRegion(
              cursor: seek == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: seek == null
                    ? null
                    : (d) => seek(_fraction(d.localPosition.dx, width)),
                onHorizontalDragStart: seek == null
                    ? null
                    : (d) => setState(
                        () => _drag = _fraction(d.localPosition.dx, width),
                      ),
                onHorizontalDragUpdate: seek == null
                    ? null
                    : (d) => setState(
                        () => _drag = _fraction(d.localPosition.dx, width),
                      ),
                onHorizontalDragEnd: seek == null
                    ? null
                    : (_) {
                        final v = _drag;
                        setState(() => _drag = null);
                        if (v != null) seek(v);
                      },
                onHorizontalDragCancel: seek == null
                    ? null
                    : () => setState(() => _drag = null),
                child: SizedBox(
                  height: widget.height,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _WavePainter(
                      peaks: peaks,
                      value: value,
                      barWidth: widget.barWidth,
                      gap: widget.gap,
                      active: widget.activeColor ?? c.accent,
                      rest:
                          widget.restColor ??
                          c.text.withValues(alpha: c.dark ? .24 : .2),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.peaks,
    required this.value,
    required this.barWidth,
    required this.gap,
    required this.active,
    required this.rest,
  });

  final List<double> peaks;
  final double value, barWidth, gap;
  final Color active, rest;

  @override
  void paint(Canvas canvas, Size size) {
    final n = peaks.length;
    final step = n <= 1 ? 0.0 : (size.width - barWidth) / (n - 1);
    final paint = Paint();
    final cut = value * n;
    for (var i = 0; i < n; i++) {
      final h = math.max(barWidth, peaks[i] * size.height);
      final x = i * step;
      paint.color = i < cut ? active : rest;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, (size.height - h) / 2, barWidth, h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.value != value ||
      old.peaks != peaks ||
      old.active != active ||
      old.rest != rest ||
      old.barWidth != barWidth;
}

// ---------------------------------------------------------------------------
// Saludo
// ---------------------------------------------------------------------------

/// «Buenas noches, Pablo» (sin nombre: solo el saludo).
String modernGreeting(DateTime now, String name) {
  final h = now.hour;
  final base = h >= 6 && h < 13
      ? 'Buenos días'
      : h >= 13 && h < 20
      ? 'Buenas tardes'
      : 'Buenas noches';
  final n = name.trim();
  return n.isEmpty ? base : '$base, $n';
}

/// «JUEVES · NOCHE» (etiqueta mono sobre el saludo móvil).
String modernDayPart(DateTime now) {
  const days = [
    'LUNES',
    'MARTES',
    'MIÉRCOLES',
    'JUEVES',
    'VIERNES',
    'SÁBADO',
    'DOMINGO',
  ];
  final h = now.hour;
  final part = h >= 6 && h < 13
      ? 'MAÑANA'
      : h >= 13 && h < 20
      ? 'TARDE'
      : 'NOCHE';
  return '${days[now.weekday - 1]} · $part';
}
