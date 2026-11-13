/// Piezas de la portada Modern «Cristal y aura»: píldoras, cabeceras de
/// sección, tarjeta de estante sin marco, ecualizador animado y tinte de
/// portada. Dueño: tema Modern.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import '../artwork.dart';
import '../mini_player/cover_backdrop_source.dart';

/// Píldora de acción: cristal con borde, acento (relleno azul) o enlace
/// (solo texto acento). 44 px de alto mínimo.
class ModernHomePill extends StatelessWidget {
  const ModernHomePill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.accent = false,
    this.link = false,
    this.busy = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool accent, link, busy;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final fg = accent
        ? c.onAccent
        : link
        ? c.accent
        : c.text;
    Widget pill = Material(
      color: accent
          ? c.accent
          : link
          ? Colors.transparent
          : c.glass,
      shape: StadiumBorder(
        side: accent || link ? BorderSide.none : BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: link ? 8 : 18,
              vertical: 8,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                  )
                else if (icon != null)
                  Icon(icon, size: 18, color: fg),
                if (busy || icon != null) const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Cristal.ui(13.5, weight: 700, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (onTap == null && !busy) pill = Opacity(opacity: .5, child: pill);
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// Título de sección (Manrope 800) con subtítulo y acción a la derecha.
class ModernHomeSection extends StatelessWidget {
  const ModernHomeSection({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.size = 22,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Cristal.ui(
                    size,
                    weight: 800,
                    color: c.text,
                    tracking: -.02,
                    height: 1.2,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Cristal.ui(13, weight: 500, color: c.text3),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// Tarjeta de estante sin marco: la portada es el color. Ocupa el ancho que
/// le den; título y artista debajo.
class ModernHomeTile extends StatelessWidget {
  const ModernHomeTile({
    super.key,
    required this.track,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onPlay,
    this.caption,
    this.round = false,
    this.radius = 16,
  });

  final Track track;
  final String title, subtitle, tooltip;
  final String? caption;
  final VoidCallback onPlay;
  final bool round;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return RepaintBoundary(
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPlay,
              borderRadius: BorderRadius.circular(radius),
              child: LayoutBuilder(
                builder: (context, box) {
                  final side = box.maxWidth.isFinite ? box.maxWidth : 176.0;
                  final corner = round ? side / 2 : radius;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(corner),
                          border: Border.all(color: c.border),
                        ),
                        child: Artwork(
                          track: track,
                          size: side,
                          radius: corner,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Cristal.ui(
                          15,
                          weight: 700,
                          color: c.text,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Cristal.ui(13, weight: 500, color: c.text3),
                      ),
                      if (caption != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          caption!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Cristal.ui(12, weight: 500, color: c.text3),
                        ),
                      ],
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
}

/// Ecualizador de barras del DJ: se mueve solo con [active] y sin
/// «reducir movimiento»; si no, queda quieto.
class ModernHomeEq extends StatefulWidget {
  const ModernHomeEq({
    super.key,
    required this.active,
    this.bars = 14,
    this.height = 44,
  });

  final bool active;
  final int bars;
  final double height;

  @override
  State<ModernHomeEq> createState() => _ModernHomeEqState();
}

class _ModernHomeEqState extends State<ModernHomeEq>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool get _animate =>
      widget.active && !MediaQuery.disableAnimationsOf(context);

  void _sync() {
    if (_animate) {
      if (!_ctl.isAnimating) _ctl.repeat();
    } else {
      _ctl.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ModernHomeEq old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barWidth = 4.0, gap = 4.0;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size(widget.bars * (barWidth + gap) - gap, widget.height),
          painter: _EqPainter(
            _ctl,
            Cristal.of(context).accent,
            modernPeaks('eq-home', widget.bars),
            barWidth,
            gap,
          ),
        ),
      ),
    );
  }
}

class _EqPainter extends CustomPainter {
  _EqPainter(this.t, this.color, this.peaks, this.barWidth, this.gap)
    : super(repaint: t);

  final Animation<double> t;
  final Color color;
  final List<double> peaks;
  final double barWidth, gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var i = 0; i < peaks.length; i++) {
      final wave =
          .5 + .5 * math.sin(2 * math.pi * (t.value + i / peaks.length * 1.7));
      final level = (.25 + .75 * peaks[i]) * (.45 + .55 * wave);
      final h = math.max(4.0, size.height * level);
      final x = i * (barWidth + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, barWidth, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqPainter old) =>
      old.color != color || old.peaks != peaks;
}

/// Entrega a [builder] el color dominante de la portada (o `null` mientras
/// carga o si no hay portada), con la misma caché que el aura del fondo.
class ModernCoverTint extends StatefulWidget {
  const ModernCoverTint({
    super.key,
    required this.track,
    required this.builder,
  });

  final Track track;
  final Widget Function(BuildContext context, Color? tint) builder;

  @override
  State<ModernCoverTint> createState() => _ModernCoverTintState();
}

class _ModernCoverTintState extends State<ModernCoverTint> {
  Color? _tint;
  String? _key;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ModernCoverTint old) {
    super.didUpdateWidget(old);
    if (old.track.id != widget.track.id ||
        old.track.artworkUrl != widget.track.artworkUrl) {
      _resolve();
    }
  }

  void _resolve() {
    final track = widget.track;
    final cache = CoverBackdropCache.shared;
    final key = cache.keyOf(track);
    _key = key;
    _tint = null;
    if (key == null) return;
    final hit = cache.peek(track);
    if (hit != null) {
      _tint = modernAuraColors(hit.samples).$1;
      return;
    }
    cache.load(track).then((data) {
      if (!mounted || _key != key || data == null) return;
      setState(() => _tint = modernAuraColors(data.samples).$1);
    });
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _tint);
}
