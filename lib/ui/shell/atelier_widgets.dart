/// Piezas compartidas del tema Atelier («Papel y tinta»): sello de formato,
/// cabeceras numeradas, portada con sombra de contacto, línea con rombo y la
/// hoja del temporizador. Dueño: tema Atelier.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/atelier_theme.dart';
import '../artwork.dart';

/// Formato de audio que se puede afirmar de [track]: extensión del archivo
/// local, `STREAM` si viene de una fuente remota, `null` sin pista.
String? atelierFormat(Track? track) {
  if (track == null) return null;
  final path = track.localPath;
  if (path == null || path.isEmpty) return 'STREAM';
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return 'LOCAL';
  return path.substring(dot + 1).toUpperCase();
}

/// Formatos sin pérdida (el sello dice «SIN PÉRDIDA» solo con ellos).
bool atelierLossless(String? format) =>
    const {'FLAC', 'WAV', 'ALAC', 'AIFF', 'APE', 'WV'}.contains(format);

const _days = [
  'LUNES',
  'MARTES',
  'MIÉRCOLES',
  'JUEVES',
  'VIERNES',
  'SÁBADO',
  'DOMINGO',
];
const _months = [
  'ENERO',
  'FEBRERO',
  'MARZO',
  'ABRIL',
  'MAYO',
  'JUNIO',
  'JULIO',
  'AGOSTO',
  'SEPTIEMBRE',
  'OCTUBRE',
  'NOVIEMBRE',
  'DICIEMBRE',
];

/// «JUEVES 12 DE NOVIEMBRE · 17:42» (o «JUE 12 NOV» con [short]).
String atelierDateLabel(DateTime d, {bool short = false}) {
  final day = _days[d.weekday - 1], month = _months[d.month - 1];
  if (short) return '${day.substring(0, 3)} ${d.day} ${month.substring(0, 3)}';
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$day ${d.day} DE $month · $hh:$mm';
}

/// `m:ss` (`h:mm:ss`).
String atelierClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final tail = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$tail' : '$m:$tail';
}

/// Cadena `Nº 01`.
String atelierNumber(int n) => 'Nº ${n.toString().padLeft(2, '0')}';

/// Chip de formato: borde terracota 1 px, mono, radio 2.
class AtelierFormatChip extends StatelessWidget {
  const AtelierFormatChip(this.format, {super.key, this.size = 11});
  final String format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: t.accent),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        format,
        maxLines: 1,
        style: t.mono(size: size, color: t.accentText),
      ),
    );
  }
}

/// Cabecera de sección: filete de tinta 1 px, número mono terracota, título
/// serif y, a la derecha, una acción o etiqueta mono.
class AtelierSectionHead extends StatelessWidget {
  const AtelierSectionHead({
    super.key,
    required this.number,
    required this.title,
    this.trailing,
    this.onTrailing,
    this.size = 22,
  });
  final int? number;
  final String title;
  final String? trailing;
  final VoidCallback? onTrailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final trail = trailing == null
        ? null
        : onTrailing == null
        ? Text(trailing!, style: t.mono(size: 11))
        : InkWell(
            onTap: onTrailing,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 1,
                child: Text(
                  trailing!,
                  style: t.mono(size: 11, color: t.accentText),
                ),
              ),
            ),
          );
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.ink)),
      ),
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 2,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (number != null) ...[
                Text(
                  atelierNumber(number!),
                  style: t.mono(size: 11, color: t.accentText),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.serif(size),
                ),
              ),
            ],
          ),
          ?trail,
        ],
      ),
    );
  }
}

/// Portada de Atelier: radio 2, borde 1 px a 14 % de tinta y sombra de
/// contacto. Con [size] nulo ocupa el cuadrado que le den.
class AtelierCover extends StatelessWidget {
  const AtelierCover({
    super.key,
    required this.track,
    this.size,
    this.shadow = true,
  });
  final Track track;
  final double? size;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final art = size == null
        ? Artwork.fill(track: track, radius: 2)
        : Artwork(track: track, size: size, radius: 2);
    final box = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: t.ink.withValues(alpha: .14)),
      ),
      child: art,
    );
    final framed = shadow
        ? DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.dark ? .5 : .30),
                  blurRadius: 18,
                  spreadRadius: -12,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: box,
          )
        : box;
    return size == null
        ? framed
        : SizedBox.square(dimension: size, child: framed);
  }
}

/// Línea de progreso de Atelier: 1 px de filete, relleno terracota de 2 px y
/// rombo de 8 px. Con [onSeek] se puede tocar y arrastrar.
class AtelierLine extends StatelessWidget {
  const AtelierLine({
    super.key,
    required this.progress,
    this.onSeek,
    this.height = 20,
    this.semanticLabel = 'Posición',
  });
  final double progress;
  final ValueChanged<double>? onSeek;
  final double height;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final value = progress.clamp(0.0, 1.0);
    final paint = CustomPaint(
      size: Size.fromHeight(height),
      painter: _LinePainter(value, t.rule, t.accent),
    );
    if (onSeek == null) return SizedBox(height: height, child: paint);
    return LayoutBuilder(
      builder: (context, box) {
        void at(Offset p) =>
            onSeek!((p.dx / math.max(1, box.maxWidth)).clamp(0.0, 1.0));
        return Semantics(
          label: semanticLabel,
          value: '${(value * 100).round()} %',
          increasedValue: '${((value + .05).clamp(0.0, 1.0) * 100).round()} %',
          decreasedValue: '${((value - .05).clamp(0.0, 1.0) * 100).round()} %',
          onIncrease: () => onSeek!((value + .05).clamp(0.0, 1.0)),
          onDecrease: () => onSeek!((value - .05).clamp(0.0, 1.0)),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapUp: (d) => at(d.localPosition),
              onHorizontalDragUpdate: (d) => at(d.localPosition),
              child: SizedBox(height: math.max(height, 24), child: paint),
            ),
          ),
        );
      },
    );
  }
}

class _LinePainter extends CustomPainter {
  const _LinePainter(this.progress, this.rule, this.fill);
  final double progress;
  final Color rule, fill;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const r = 4.5;
    final x = r + progress * math.max(0, size.width - 2 * r);
    canvas.drawRect(
      Rect.fromLTWH(0, y - .5, size.width, 1),
      Paint()..color = rule,
    );
    canvas.drawRect(Rect.fromLTRB(0, y - 1, x, y + 1), Paint()..color = fill);
    final path = Path()
      ..moveTo(x, y - r)
      ..lineTo(x + r, y)
      ..lineTo(x, y + r)
      ..lineTo(x - r, y)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.progress != progress || old.rule != rule || old.fill != fill;
}

/// Sello circular de calidad: texto en arco y formato al centro.
class AtelierSeal extends StatelessWidget {
  const AtelierSeal({super.key, required this.format, this.size = 98});
  final String format;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final lossless = atelierLossless(format);
    return Semantics(
      label: lossless ? 'Sin pérdida, $format' : 'Formato $format',
      child: ExcludeSemantics(
        child: Transform.rotate(
          angle: -.2,
          child: SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _SealPainter(
                ring: lossless
                    ? 'SIN PÉRDIDA · SIN PÉRDIDA · '
                    : 'AURORA · FORMATO · ',
                format: format,
                color: t.accentText,
                fill: t.paper,
                ring2: t.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({
    required this.ring,
    required this.format,
    required this.color,
    required this.fill,
    required this.ring2,
  });
  final String ring, format;
  final Color color, fill, ring2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r - 1, Paint()..color = fill.withValues(alpha: .92));
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = ring2;
    canvas.drawCircle(c, r - 1.5, stroke);
    canvas.drawCircle(c, r * .66, stroke..strokeWidth = 1);
    // Texto en arco.
    final chars = ring.characters.toList();
    final step = 2 * math.pi / chars.length;
    final style = TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontSize: r * .15,
      color: color,
      fontWeight: FontWeight.w500,
    );
    for (var i = 0; i < chars.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: chars[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(i * step);
      tp.paint(canvas, Offset(-tp.width / 2, -(r * .83) - tp.height / 2));
      canvas.restore();
    }
    // Se encoge hasta caber en una línea dentro del aro interior.
    var fmtSize = r * .4;
    late TextPainter fmt;
    do {
      fmt = TextPainter(
        text: TextSpan(
          text: format,
          style: TextStyle(
            fontFamily: 'Newsreader',
            fontStyle: FontStyle.italic,
            fontSize: fmtSize,
            color: color,
          ),
        ),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      fmtSize -= r * .02;
    } while (fmt.width > r * 1.15 && fmtSize > r * .12);
    fmt.paint(canvas, c - Offset(fmt.width / 2, fmt.height / 2));
  }

  @override
  bool shouldRepaint(_SealPainter old) =>
      old.ring != ring || old.format != format || old.color != color;
}

/// Borde discontinuo (chip de carpeta).
class AtelierDashedBox extends StatelessWidget {
  const AtelierDashedBox({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return CustomPaint(
      foregroundPainter: _DashPainter(color ?? t.rule),
      child: child,
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRect(Rect.fromLTWH(.5, .5, size.width - 1, size.height - 1));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 6) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 3, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Hoja «Temporizador de sueño».
Future<void> showAtelierSleepSheet(
  BuildContext context,
  AppController controller,
) async {
  final value = await showModalBottomSheet<int>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) {
      final t = AtelierTokens.of(context);
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text('Temporizador de sueño', style: t.serif(24)),
            ),
            for (final minutes in const [0, 15, 30, 45, 60, -1])
              ListTile(
                minTileHeight: 48,
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(
                  minutes == 0
                      ? 'Desactivar'
                      : minutes < 0
                      ? 'Al terminar la pista'
                      : '$minutes minutos',
                ),
                onTap: () => Navigator.pop(context, minutes),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
  if (value == null) return;
  if (value < 0) {
    controller.setSleepAtTrackEnd();
  } else {
    controller.setSleepTimer(value == 0 ? null : Duration(minutes: value));
  }
}

/// Resumen del temporizador activo («28 min») o `null`.
String? atelierSleepLabel(AppController c) {
  final left = c.sleepRemaining;
  if (left == null) return null;
  final minutes = (left.inSeconds / 60).ceil();
  return '$minutes min';
}
