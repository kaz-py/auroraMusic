import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../core/models.dart';
import '../theme/modern_theme.dart';
import '../theme/slush_theme.dart';
import 'artwork_cache.dart';

/// Logical artwork dimensions shared by every music surface.
enum ArtworkContext {
  thumbnail(48),
  thumbnailCompact(40),
  thumbnailDetail(64),
  transport(56),
  card(176),
  cardCompact(136),
  cardDetail(210),
  detail(120),
  mosaic(68),
  player(330),
  playerCompact(280),
  playerDetail(436),
  sleeve(300),
  vinyl(420),
  vinylCompact(360);

  const ArtworkContext(this.size);
  final double size;

  double constrain(BoxConstraints constraints) =>
      math.min(size, math.min(constraints.maxWidth, constraints.maxHeight));
}

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.track,
    this.artworkContext = ArtworkContext.thumbnail,
    double? size,
    this.radius = 12,
  }) : assert(size == null || (size > 0 && size < double.infinity)),
       _size = size,
       _fill = false;

  /// Use inside an already bounded square, such as a circular vinyl label.
  const Artwork.fill({
    super.key,
    required this.track,
    this.artworkContext = ArtworkContext.vinyl,
    this.radius = 0,
  }) : _size = null,
       _fill = true;

  final Track track;
  final ArtworkContext artworkContext;
  final double? _size;
  final bool _fill;
  final double radius;

  // Kept for callers that inspect or explicitly override the nominal size.
  double get size => _size ?? artworkContext.size;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final bound = math.min(constraints.maxWidth, constraints.maxHeight);
      final side = _fill && bound.isFinite
          ? bound
          : _size == null
          ? artworkContext.constrain(constraints)
          : math.min(size, bound);
      final colors = Theme.of(context).colorScheme;
      // Slush/Modern: primary al 10 % se funde con el fondo (vinilo oscuro,
      // tarjeta blanca) y el icono primary queda sin contraste: fondo opaco
      // y tinta del tema.
      final slush = isSlush(context) || isModern(context);
      final placeholder = Container(
        color: slush
            ? colors.surfaceContainerHigh
            : colors.primary.withValues(alpha: .10),
        child: Center(
          child: Icon(
            Icons.music_note_rounded,
            size: side * .35,
            color: slush ? colors.onSurface : colors.primary,
          ),
        ),
      );
      final cacheWidth = math.max(
        1,
        (side * MediaQuery.devicePixelRatioOf(context)).ceil(),
      );
      final url = track.artworkUrl?.trim();
      return Align(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox.square(
          dimension: side,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: url == null || url.isEmpty
                  ? placeholder
                  : url.startsWith('asset:')
                  ? Image.asset(
                      url.substring(6),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      cacheWidth: cacheWidth,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => placeholder,
                      frameBuilder: (_, image, frame, synchronous) =>
                          synchronous || frame != null ? image : placeholder,
                    )
                  : Image(
                      // Caché en disco + resolución acorde al tamaño pintado.
                      image: ResizeImage(
                        CachedArtworkImage(
                          upgradeArtworkUrl(url, cacheWidth.toDouble()),
                        ),
                        width: cacheWidth,
                      ),
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      alignment: Alignment.center,
                      excludeFromSemantics: true,
                      errorBuilder: (_, _, _) => placeholder,
                      frameBuilder: (_, image, frame, synchronous) =>
                          synchronous || frame != null ? image : placeholder,
                    ),
            ),
          ),
        ),
      );
    },
  );
}
