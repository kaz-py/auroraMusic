import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../playlist_views/playlist_cover.dart';
import '../playlist_views/playlist_photo_menu.dart';
import '../playlist_views/playlist_view_mode.dart';

const _display = 'Bricolage Grotesque';

/// Colores vivos que se repiten en tarjetas y píldoras.
const slushPalette = [
  Slush.mint,
  Slush.lilac,
  Slush.yellow,
  Color(0xffa9d0ff),
  Color(0xffffb48a),
];

/// Fondo plano de pantalla: [base] aclarado (u oscurecido, en oscuro) y teñido
/// con el color de portada.
Color slushTone(BuildContext context, Color base) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final tint = dark
      ? Colors.black
      : Colors.white; // destino del lerp: negro (oscuro) o blanco (claro)
  return Color.lerp(
    Color.lerp(base, tint, dark ? .80 : .55)!,
    theme.colorScheme.surface,
    .25,
  )!;
}

/// Titular de página: 96 (>= 900), 64 (600-899), 40 (< 600); 1 línea, sin
/// escalar más de 1,3 (ya es enorme). El contorno de 1,5 px lo da la misma
/// tinta del texto.
class SlushTitle extends StatelessWidget {
  const SlushTitle(this.title, {super.key, required this.width});
  final String title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final font = width >= Breakpoints.medium
        ? 96.0
        : width >= Breakpoints.compact
        ? 64.0
        : 40.0;
    final ink = context.slush.ink;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Semantics(
        header: true,
        label: title,
        child: ExcludeSemantics(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              title,
              maxLines: 1,
              style: TextStyle(
                fontFamily: _display,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                fontSize: font,
                height: .95,
                letterSpacing: -font * .02,
                color: ink,
                shadows: [
                  for (final o in const [
                    Offset(1.5, 0),
                    Offset(-1.5, 0),
                    Offset(0, 1.5),
                    Offset(0, -1.5),
                  ])
                    Shadow(color: ink, offset: o),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pantalla Slush con titular gigante, pegatina, píldoras de estado y el
/// contenido en una tarjeta de papel con borde y sombra dura (o suelto, si
/// [card] es falso y ya trae sus propias tarjetas).
class SlushPage extends StatelessWidget {
  const SlushPage({
    super.key,
    required this.color,
    required this.title,
    required this.sticker,
    required this.child,
    this.pills = const [],
    this.card = true,
  });
  final Color color;
  final String title;
  final String sticker;
  final List<String> pills;
  final bool card;
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: color,
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final wide = w >= Breakpoints.compact;
        final pad = SlushSpacing.margin(MediaQuery.sizeOf(context).width);
        final header = <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? 16 : 12, pad, 8),
            child: Row(
              children: [
                Expanded(child: SlushTitle(title, width: w)),
                // Sin pegatina decorativa en 360; una sola en cabecera.
                if (w >= Breakpoints.phoneLarge - 12) ...[
                  const SizedBox(width: SlushSpacing.s8),
                  SlushSticker(
                    sticker,
                    size: w >= Breakpoints.medium
                        ? 92
                        : w >= Breakpoints.compact
                        ? 72
                        : 52,
                    color: slushPalette[title.length % slushPalette.length],
                  ),
                ],
              ],
            ),
          ),
          if (pills.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
              child: Wrap(
                spacing: SlushSpacing.s8,
                runSpacing: SlushSpacing.s8,
                children: [
                  for (var i = 0; i < pills.length; i++)
                    SlushPill(
                      pills[i],
                      color: i == 0
                          ? context.slush.paper
                          : slushPalette[(i + 1) % slushPalette.length],
                    ),
                ],
              ),
            ),
        ];
        // La sombra dura (3,4) cabe en el margen: mismo margen a ambos lados.
        final body = card
            ? Padding(
                padding: EdgeInsets.fromLTRB(pad, 4, pad, 16),
                child: SlushCard(child: child),
              )
            : child;
        // El titular se va con el scroll del contenido a cualquier ancho; cada
        // pantalla empieza arriba (la clave evita heredar el desplazamiento).
        return NestedScrollView(
          key: ValueKey(title),
          headerSliverBuilder: (_, _) => [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: header,
              ),
            ),
          ],
          body: Builder(
            builder: (ctx) => PrimaryScrollController(
              controller: PrimaryScrollController.of(ctx),
              automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
              child: body,
            ),
          ),
        );
      },
    ),
  );
}

/// Tarjeta de papel con contorno, esquinas grandes y sombra dura. Contenedor:
/// borde suave en oscuro (la jerarquía la dan los controles).
class SlushCard extends StatelessWidget {
  const SlushCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final shape = RoundedRectangleBorder(
      side: p.borderSoft,
      borderRadius: BorderRadius.circular(SlushRadius.r24),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: p.shadowsFor(SlushElevation.card),
      ),
      child: Material(
        color: p.paper,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// Estado vacío: icono en círculo con pegatina, título, cuerpo y, si hay
/// salida, una acción primaria (menta). Centrado en el alto disponible y con
/// scroll si el texto crece. [warning] cambia «VACÍO» por «OJO» naranja.
class SlushEmpty extends StatelessWidget {
  const SlushEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.sticker,
    this.warning = false,
  });
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? sticker;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 168,
            height: 136,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: -.08,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Slush.lilac,
                      shape: CircleBorder(side: p.border),
                      shadows: p.shadowsFor(SlushElevation.card),
                    ),
                    child: SizedBox.square(
                      dimension: 104,
                      child: Icon(icon, size: 52, color: Slush.ink),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: ExcludeSemantics(
                    child: SlushSticker(
                      sticker ?? (warning ? 'OJO' : 'VACÍO'),
                      size: 72,
                      angle: .25,
                      color: warning ? Slush.orange : Slush.yellow,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SlushSpacing.s16),
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _display,
                fontWeight: FontWeight.w800,
                fontVariations: const [FontVariation('wght', 800)],
                fontSize: 26,
                height: 1.15,
                letterSpacing: -.26,
                color: p.ink,
              ),
            ),
          ),
          const SizedBox(height: SlushSpacing.s12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 15,
              height: 1.5,
              color: p.ink2,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: SlushSpacing.s24),
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.all(SlushSpacing.s24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.hasBoundedHeight
                ? (box.maxHeight - SlushSpacing.s48).clamp(0.0, double.infinity)
                : 0,
            minWidth: box.maxWidth - SlushSpacing.s48 < 0
                ? 0
                : box.maxWidth - SlushSpacing.s48,
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// Fila grande «Me gusta» de la biblioteca.
class SlushLikesCard extends StatelessWidget {
  const SlushLikesCard({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SlushTile(
    color: Slush.pink,
    onTap: onTap,
    semantics: 'Me gusta',
    child: Row(
      children: [
        const Icon(Icons.favorite, size: 36, color: Slush.ink),
        const SizedBox(width: SlushSpacing.s16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: const Text(
                  'Me gusta',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _display,
                    fontWeight: FontWeight.w800,
                    fontVariations: [FontVariation('wght', 800)],
                    fontSize: 26,
                    height: 1.15,
                    color: Slush.ink,
                  ),
                ),
              ),
              const SizedBox(height: SlushSpacing.s4),
              SlushPill('$count canciones', color: context.slush.paper),
            ],
          ),
        ),
        const SizedBox(width: SlushSpacing.s8),
        const Icon(Icons.chevron_right, color: Slush.ink),
      ],
    ),
  );
}

/// Tarjeta de color pulsable (hundido al pulsar, hover y foco).
class _SlushTile extends StatelessWidget {
  const _SlushTile({
    required this.color,
    required this.onTap,
    required this.child,
    required this.semantics,
    this.radius = SlushRadius.r24,
    this.padding = SlushSpacing.s16,
  });
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final String semantics;
  final double radius;
  final double padding;

  @override
  Widget build(BuildContext context) => SlushPressable(
    onTap: onTap,
    radius: radius,
    elevation: SlushElevation.card,
    pressedScale: .99,
    child: Semantics(
      button: true,
      label: semantics,
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: color,
            shape: RoundedRectangleBorder(
              side: context.slush.border,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child: Padding(padding: EdgeInsets.all(padding), child: child),
        ),
      ),
    ),
  );
}

/// Rejilla de playlists: tarjetas de colores con portada, nombre y píldora.
/// Columnas por ancho: 2 (< 600), 3, 4, 5-7.
class SlushPlaylistGrid extends StatelessWidget {
  const SlushPlaylistGrid({
    super.key,
    required this.controller,
    required this.playlists,
    required this.onOpen,
  });
  final AppController controller;
  final List<MusicPlaylist> playlists;
  final ValueChanged<MusicPlaylist> onOpen;

  /// Padding interno de la tarjeta (el contorno de 2 px lo pinta encima).
  static const _pad = SlushSpacing.s12;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = SlushSpacing.s16;
      final minTile = box.maxWidth < 700
          ? 160.0
          : box.maxWidth < 1100
          ? 180.0
          : 230.0;
      // El margen de 4 px a la derecha deja sitio a la sombra dura.
      final avail = box.maxWidth - 4;
      final cols = ((avail + gap) / (minTile + gap)).floor().clamp(2, 7);
      final w = (avail - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (var i = 0; i < playlists.length; i++)
            SizedBox(
              width: w,
              child: PlaylistPhotoMenu(
                controller: controller,
                playlist: playlists[i],
                child: _SlushTile(
                  color: slushPalette[i % slushPalette.length],
                  radius: SlushRadius.r24,
                  padding: _pad,
                  semantics: 'Abrir ${playlists[i].name}',
                  onTap: () => onOpen(playlists[i]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(context.slush.border),
                          borderRadius: BorderRadius.circular(SlushRadius.r12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: PlaylistCover(
                            playlist: playlists[i],
                            tracks: playlistCoverTracks(
                              controller,
                              playlists[i],
                            ),
                            size: w - _pad * 2 - 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: SlushSpacing.s12),
                      Text(
                        playlists[i].name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.25,
                          color: Slush.ink,
                        ),
                      ),
                      const SizedBox(height: SlushSpacing.s8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: SlushPill(
                          '${playlists[i].trackIds.length} canciones',
                          color: context.slush.paper,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
