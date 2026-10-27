import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../playlist_views/playlist_cover.dart';
import '../playlist_views/playlist_photo_menu.dart';
import '../playlist_views/playlist_view_mode.dart';

const _display = 'Bagel Fat One';

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
  final tint = dark ? Colors.black : Colors.white; // sobre color vivo
  return Color.lerp(
    Color.lerp(base, tint, dark ? .80 : .55)!,
    theme.colorScheme.surface,
    .25,
  )!;
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
        final wide = box.maxWidth >= 700;
        final pad = wide ? 28.0 : 16.0;
        final font = wide ? 96.0 : 40.0;
        final header = <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(pad, wide ? 16 : 10, pad, 6),
            child: Row(
              children: [
                Expanded(
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
                            fontSize: font,
                            height: .95,
                            letterSpacing: -font * .02,
                            color: context.slush.ink,
                            shadows: [
                              for (final o in const [
                                Offset(2, 0),
                                Offset(-2, 0),
                                Offset(0, 2),
                                Offset(0, -2),
                              ])
                                Shadow(color: context.slush.ink, offset: o),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (box.maxWidth >= 360) ...[
                  const SizedBox(width: 8),
                  SlushSticker(
                    sticker,
                    size: wide ? 92 : 48,
                    color: slushPalette[title.length % slushPalette.length],
                  ),
                ],
              ],
            ),
          ),
          if (pills.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, 0, pad, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
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
        final body = card
            ? Padding(
                padding: EdgeInsets.fromLTRB(pad, 6, pad + 4, 12),
                child: SlushCard(child: child),
              )
            : child;
        if (!wide) {
          // En el teléfono el titular se va con el scroll del contenido; cada
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
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            Expanded(child: body),
          ],
        );
      },
    ),
  );
}

/// Tarjeta de papel con contorno, esquinas grandes y sombra dura.
class SlushCard extends StatelessWidget {
  const SlushCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      side: context.slush.border,
      borderRadius: const BorderRadius.all(Radius.circular(24)),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: context.slush.shadows),
      child: Material(
        color: context.slush.paper,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// Estado vacío: icono en pegatina y texto grande en lugar de espacio en blanco.
class SlushEmpty extends StatelessWidget {
  const SlushEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 150,
              height: 130,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Transform.rotate(
                    angle: -.08,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: Slush.lilac,
                        shape: CircleBorder(side: context.slush.border),
                        shadows: context.slush.shadows,
                      ),
                      child: SizedBox.square(
                        dimension: 104,
                        child: Icon(icon, size: 52, color: Slush.ink),
                      ),
                    ),
                  ),
                  const Positioned(
                    right: 0,
                    top: 0,
                    child: SlushSticker('OJO', size: 58, angle: .25),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _display,
                fontSize: 30,
                height: 1.05,
                color: context.slush.ink,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                height: 1.5,
                color: context.slush.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Fila grande «Me gusta» de la biblioteca.
class SlushLikesCard extends StatelessWidget {
  const SlushLikesCard({super.key, required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _SlushTile(
    color: const Color(0xffff9ec4),
    onTap: onTap,
    semantics: 'Me gusta',
    child: Row(
      children: [
        const Icon(Icons.favorite, size: 36, color: Slush.ink),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Me gusta',
            style: TextStyle(
              fontFamily: _display,
              fontSize: 26,
              color: Slush.ink,
            ),
          ),
        ),
        SlushPill('$count canciones', color: context.slush.paper),
        const SizedBox(width: 8),
        const Icon(Icons.chevron_right, color: Slush.ink),
      ],
    ),
  );
}

class _SlushTile extends StatelessWidget {
  const _SlushTile({
    required this.color,
    required this.onTap,
    required this.child,
    required this.semantics,
    this.radius = 24,
  });
  final Color color;
  final VoidCallback onTap;
  final Widget child;
  final String semantics;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      side: context.slush.border,
      borderRadius: BorderRadius.circular(radius),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: context.slush.shadows),
      child: Material(
        color: color,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: semantics,
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
        ),
      ),
    );
  }
}

/// Rejilla de playlists: tarjetas de colores con portada, nombre y píldora.
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

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 18.0;
      final cols = (box.maxWidth / 210).floor().clamp(2, 8);
      final w = (box.maxWidth - 4 - gap * (cols - 1)) / cols;
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
                  radius: 22,
                  semantics: 'Abrir ${playlists[i].name}',
                  onTap: () => onOpen(playlists[i]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.fromBorderSide(context.slush.border),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: PlaylistCover(
                            playlist: playlists[i],
                            tracks: playlistCoverTracks(
                              controller,
                              playlists[i],
                            ),
                            size: w - 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        playlists[i].name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          height: 1.15,
                          color: Slush.ink,
                        ),
                      ),
                      const SizedBox(height: 6),
                      SlushPill(
                        '${playlists[i].trackIds.length} canciones',
                        color: context.slush.paper,
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
