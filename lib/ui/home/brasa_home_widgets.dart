/// Dueño: tema Brasa. Piezas visuales de la portada: portada recortada, tarjeta
/// de carril, carril horizontal, chips de filtro, cabecera de sección y botón
/// play «squircle».
library;

import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../artwork.dart';

/// Escala de texto actual aplicada a [size].
double brasaScaled(BuildContext context, double size) =>
    MediaQuery.textScalerOf(context).scale(size);

/// `m:ss` (o `h:mm:ss`) de [d]; vacío si no hay duración.
String brasaClock(Duration d) {
  if (d <= Duration.zero) return '';
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:$s';
  }
  return '${d.inMinutes}:$s';
}

/// Portada que rellena todo el espacio disponible recortándola (cover).
/// [px] es el lado de decodificación: la imagen se baja a ese tamaño.
class BrasaFill extends StatelessWidget {
  const BrasaFill({super.key, required this.track, this.px = 240});
  final Track track;
  final double px;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.cover,
    clipBehavior: Clip.hardEdge,
    child: SizedBox.square(
      dimension: px,
      child: Artwork.fill(track: track, artworkContext: ArtworkContext.card),
    ),
  );
}

/// Portada con proporción [aspect] (ancho/alto) y esquinas [radius].
class BrasaCover extends StatelessWidget {
  const BrasaCover({
    super.key,
    required this.track,
    this.aspect = 1,
    this.radius = 12,
    this.px = 240,
    this.round = false,
  });
  final Track track;
  final double aspect, radius, px;
  final bool round;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspect,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(round ? 999 : radius),
      child: BrasaFill(track: track, px: px),
    ),
  );
}

/// Botón play «squircle» de brasa.
class BrasaPlayButton extends StatelessWidget {
  const BrasaPlayButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.size = 52,
    this.radius = 18,
    this.icon = Icons.play_arrow_rounded,
  });
  final VoidCallback? onPressed;
  final String tooltip;
  final double size, radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Brasa.ember,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * .55, color: Brasa.onEmber),
        ),
      ),
    ),
  );
}

/// Punto de brasa con halo + etiqueta mono en versalitas.
class BrasaCaption extends StatelessWidget {
  const BrasaCaption(this.text, {super.key, this.dot = false, this.color});
  final String text;
  final bool dot;
  final Color? color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (dot)
        Padding(
          padding: const EdgeInsets.only(top: 3, right: 8),
          child: Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Brasa.ember,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Brasa.ember, blurRadius: 8)],
            ),
          ),
        ),
      Flexible(
        child: Text(
          text.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Brasa.mono(
            11,
            color: color ?? Brasa.steel,
            weight: FontWeight.w500,
          ),
        ),
      ),
    ],
  );
}

/// Título de sección (Fraunces) con acción opcional a la derecha.
class BrasaSectionHeader extends StatelessWidget {
  const BrasaSectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.mobile = false,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Brasa.serif(mobile ? 20 : 22, tracking: -.01),
                ),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: Brasa.sans(13, color: Brasa.cloud),
                  ),
                ),
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Filtros de la portada.
enum BrasaHomeFilter {
  all('Todo'),
  music('Música'),
  downloaded('Descargado'),
  hiRes('Hi-Res');

  const BrasaHomeFilter(this.label);
  final String label;

  static const _lossless = ['.flac', '.wav', '.aiff', '.aif', '.alac', '.ape'];

  /// Todo: todo; Música: reproducible; Descargado: archivo local;
  /// Hi-Res: archivo local sin pérdida (sin datos de profundidad/frecuencia).
  bool accepts(Track t) => switch (this) {
    all => true,
    music => !t.isPendingSpotifyMatch,
    downloaded => t.isLocal,
    hiRes =>
      t.isLocal && _lossless.any((e) => t.localPath!.toLowerCase().endsWith(e)),
  };
}

/// Chips de filtro: pill de 32 (36 en móvil), activo relleno de brasa; la zona
/// táctil es de al menos 44 en móvil.
class BrasaFilterChips extends StatelessWidget {
  const BrasaFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.mobile = false,
    this.alignment = WrapAlignment.start,
  });
  final BrasaHomeFilter selected;
  final ValueChanged<BrasaHomeFilter> onChanged;
  final bool mobile;
  final WrapAlignment alignment;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    spacing: 8,
    runSpacing: mobile ? 0 : 8,
    children: [
      for (final f in BrasaHomeFilter.values)
        BrasaChip(
          label: f.label,
          active: f == selected,
          mobile: mobile,
          onTap: () => onChanged(f),
        ),
    ],
  );
}

/// Chip pill de Brasa (activo = brasa con texto sobre brasa).
class BrasaChip extends StatelessWidget {
  const BrasaChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.mobile = false,
  });
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final bool mobile;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: mobile ? 4 : 0),
        child: Container(
          constraints: BoxConstraints(minHeight: mobile ? 36 : 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: active ? Brasa.ember : Brasa.ash,
            shape: const StadiumBorder(),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: Brasa.sans(
                13,
                color: active ? Brasa.onEmber : Brasa.cream,
                weight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Tarjeta de carril: portada (apaisada 2:1, cuadrada o redonda), título y
/// subtítulo. Alto total conocido vía [heightFor] para los carriles.
class BrasaCoverCard extends StatelessWidget {
  const BrasaCoverCard({
    super.key,
    required this.cover,
    required this.title,
    required this.tooltip,
    required this.onTap,
    this.subtitle,
    this.aspect = 2,
    this.round = false,
    this.playing = false,
  });
  final Track cover;
  final String title, tooltip;
  final String? subtitle;
  final double aspect;
  final bool round, playing;
  final VoidCallback onTap;

  /// Alto de la tarjeta para una portada de [coverHeight].
  static double heightFor(BuildContext context, double coverHeight) =>
      coverHeight +
      10 +
      brasaScaled(context, 14 * 1.3) +
      brasaScaled(context, 13 * 1.3) +
      8;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    excludeSemantics: true,
    onTap: onTap,
    child: Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            BrasaCover(
              track: cover,
              aspect: round ? 1 : aspect,
              radius: 14,
              round: round,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Brasa.sans(
                14,
                color: playing ? Brasa.ember : Brasa.cream,
                weight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Brasa.sans(13, color: Brasa.cloud, height: 1.3),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Carril horizontal con cabecera serif y flechas (escritorio). Sin alto
/// fijo propio: [itemHeight] lo calcula quien lo usa con la escala de texto.
class BrasaShelf extends StatefulWidget {
  const BrasaShelf({
    super.key,
    required this.title,
    required this.count,
    required this.itemBuilder,
    required this.itemWidth,
    required this.itemHeight,
    this.pad = 40,
    this.gap = 16,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final int count;
  final IndexedWidgetBuilder itemBuilder;
  final double itemWidth, itemHeight, pad, gap;

  @override
  State<BrasaShelf> createState() => _BrasaShelfState();
}

class _BrasaShelfState extends State<BrasaShelf> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _move(double delta) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final target = (_scroll.offset + delta).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final viewport = box.maxWidth - widget.pad * 2;
      final overflow =
          widget.count * (widget.itemWidth + widget.gap) - widget.gap >
          viewport + 1;
      final arrows = overflow && widget.pad >= 40;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.pad),
            child: BrasaSectionHeader(
              widget.title,
              subtitle: widget.subtitle,
              mobile: widget.pad < 40,
              trailing: arrows
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Anterior en ${widget.title}',
                          color: Brasa.cloud,
                          onPressed: () => _move(-viewport * .8),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Siguiente en ${widget.title}',
                          color: Brasa.cloud,
                          onPressed: () => _move(viewport * .8),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    )
                  : null,
            ),
          ),
          ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
              dragDevices: {
                ...ScrollConfiguration.of(context).dragDevices,
                PointerDeviceKind.mouse,
              },
            ),
            child: SizedBox(
              height: widget.itemHeight,
              child: ListView.separated(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: widget.pad),
                itemCount: widget.count,
                separatorBuilder: (_, _) => SizedBox(width: widget.gap),
                itemBuilder: (context, i) => SizedBox(
                  width: widget.itemWidth,
                  child: widget.itemBuilder(context, i),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
