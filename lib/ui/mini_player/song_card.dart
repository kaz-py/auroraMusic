import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/slush_theme.dart';
import '../artwork.dart';
import '../studio/studio_components.dart';
import '../track_actions.dart';

/// Acción extra de la tarjeta (las de la canción vienen de
/// `TrackActions.menuItems`).
typedef SongCardAction = ({String label, IconData icon, VoidCallback run});

const double _kCardWidth = 360;

/// Tarjeta de la canción que suena: se abre al pulsar la portada o el título
/// del mini (escritorio). Portada y título arriba y todas las acciones de la
/// canción (a continuación, cola, Jam, favorito, compartir, enviar a un amigo,
/// añadir a una lista) más las [extras] en una rejilla de teselas; cada una
/// cierra la tarjeta y actúa. Se ancla sobre [anchor] (el punto de la pantalla
/// donde se pulsó), abriéndose hacia arriba porque la barra va abajo.
Future<void> showSongCard(
  BuildContext context,
  AppController controller,
  Track track,
  Offset anchor, {
  List<SongCardAction> extras = const [],
}) {
  final actions = TrackActions(context, controller);
  final items = <SongCardAction>[
    for (final i in actions.menuItems(track))
      (label: i.label, icon: i.icon, run: i.run),
    ...extras,
  ];
  // Motivos de las desactivadas (p. ej. «el anfitrión no permite añadir»).
  final reasons = <String, String?>{
    for (final i in actions.menuItems(track)) i.label: i.disabledReason,
  };
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar la tarjeta de la canción',
    barrierColor: Colors.transparent,
    transitionDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180),
    pageBuilder: (dialog, _, _) =>
        _SongCard(track: track, anchor: anchor, items: items, reasons: reasons),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: const Offset(0, .03),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _SongCard extends StatelessWidget {
  const _SongCard({
    required this.track,
    required this.anchor,
    required this.items,
    required this.reasons,
  });

  final Track track;
  final Offset anchor;
  final List<SongCardAction> items;
  final Map<String, String?> reasons;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(_kCardWidth, size.width - 24);
    final left = anchor.dx
        .clamp(12.0, math.max(12.0, size.width - width - 12))
        .toDouble();
    // La tarjeta crece hacia arriba desde el borde superior de la barra.
    final bottom = (size.height - anchor.dy + 8)
        .clamp(12.0, size.height)
        .toDouble();
    final look = _Look.of(context);
    return Stack(
      children: [
        Positioned(
          left: left,
          bottom: bottom,
          width: width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: size.height - bottom - 12),
            child: DecoratedBox(
              // Relleno y sombra con la forma de la tarjeta (la sombra dura de
              // Slush no puede pintarse como un rectángulo).
              decoration: ShapeDecoration(
                color: look.fill,
                shape: look.shape,
                shadows: look.shadows,
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: look.shape,
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(track: track, look: look),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final item in items)
                            _Tile(
                              item: item,
                              reason: reasons[item.label],
                              look: look,
                              width: (width - 28 - 16) / 3,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Aspecto de la tarjeta por tema.
class _Look {
  const _Look({
    required this.fill,
    required this.shape,
    required this.ink,
    required this.sub,
    required this.tile,
    required this.accent,
    this.shadows = const [],
  });

  final Color fill, ink, sub, tile, accent;
  final ShapeBorder shape;
  final List<BoxShadow> shadows;

  static _Look of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (isSlush(context)) {
      final p = context.slush;
      return _Look(
        fill: p.paper,
        ink: p.ink,
        sub: p.ink2,
        tile: p.inset,
        accent: Slush.mint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlushRadius.r24),
          side: p.border,
        ),
        shadows: p.shadows,
      );
    }
    if (isBrasa(context)) {
      return _Look(
        fill: Brasa.obsidian,
        ink: Brasa.cream,
        sub: Brasa.cloud,
        tile: Brasa.graphite,
        accent: Brasa.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Colors.white.withValues(alpha: .08)),
        ),
        shadows: Brasa.cardShadow,
      );
    }
    if (isModern(context)) {
      return _Look(
        fill: scheme.surfaceContainerLow,
        ink: scheme.onSurface,
        sub: scheme.onSurfaceVariant,
        tile: scheme.surfaceContainerHigh,
        accent: scheme.tertiary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .5)),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: scheme.brightness == Brightness.dark ? .38 : .12,
            ),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      );
    }
    return _Look(
      fill: scheme.surfaceContainerLow,
      ink: scheme.onSurface,
      sub: scheme.onSurfaceVariant,
      tile: scheme.surfaceContainerHigh,
      accent: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: StudioPalette.sleeve,
        side: BorderSide(color: scheme.outlineVariant),
      ),
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(
            alpha: scheme.brightness == Brightness.dark ? .38 : .12,
          ),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.track, required this.look});
  final Track track;
  final _Look look;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Artwork(
          track: track,
          size: 64,
          artworkContext: ArtworkContext.thumbnailDetail,
          radius: 10,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium?.copyWith(
                  color: look.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(color: look.sub),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.reason,
    required this.look,
    required this.width,
  });

  final SongCardAction item;
  final String? reason;
  final _Look look;
  final double width;

  @override
  Widget build(BuildContext context) {
    final enabled = reason == null;
    final tile = Semantics(
      button: true,
      enabled: enabled,
      label: item.label,
      excludeSemantics: true,
      child: Material(
        color: look.tile,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled
              ? () {
                  Navigator.of(context).pop();
                  // Tras cerrar la tarjeta: así el menú o la hoja que abra
                  // la acción no se apila bajo ella.
                  scheduleMicrotask(item.run);
                }
              : null,
          child: Opacity(
            opacity: enabled ? 1 : .4,
            child: SizedBox(
              width: width,
              height: 88,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: look.accent.withValues(alpha: .18),
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(
                        dimension: 36,
                        child: Icon(item.icon, size: 20, color: look.ink),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: look.ink,
                          height: 1.15,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return reason == null ? tile : Tooltip(message: reason!, child: tile);
  }
}
