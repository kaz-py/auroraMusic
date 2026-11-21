import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import 'slush_home.dart';

/// Inicio móvil de Slush: chips de ánimo, «Seguir escuchando» (cuadrícula de
/// 2 columnas), tarjeta «DJ personal» y «Para ti esta noche». El saludo y el
/// avatar los pinta la cabecera del shell.
class SlushMobileHome extends StatefulWidget {
  const SlushMobileHome({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final AppController controller;
  final VoidCallback onSearch;

  @override
  State<SlushMobileHome> createState() => _SlushMobileHomeState();
}

class _SlushMobileHomeState extends State<SlushMobileHome> {
  int _mood = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = context.slush;
    final mix = c.recommendations.map((r) => r.track).toList();
    final pool = mix.isNotEmpty
        ? mix
        : c.tracks.where((t) => !t.isPendingSpotifyMatch).toList();
    final recent = (c.recentTracks.isNotEmpty ? c.recentTracks : c.tracks)
        .where((t) => !t.isPendingSpotifyMatch)
        .take(4)
        .toList();
    final shown = slushMoodTracks(pool, _mood).take(12).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SlushMoodChips(
          scroll: true,
          selected: _mood,
          onSelected: (i) => setState(() => _mood = i),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                'Seguir escuchando',
                style: slushHeadline(24, color: p.ink),
              ),
            ),
            TextButton(
              onPressed: widget.onSearch,
              style: TextButton.styleFrom(
                foregroundColor: p.ink2,
                minimumSize: const Size(48, SlushControl.touch),
              ),
              child: const Text(
                'Ver todo',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Text(
            'Aquí aparecerá lo que escuches.',
            style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final itemW = (box.maxWidth - 12 - 4) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 14,
                children: [
                  for (final t in recent)
                    SizedBox(
                      width: itemW,
                      child: _RecentPill(
                        track: t,
                        onTap: () => c.playTrack(t, context: recent),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        SlushDjCard(controller: c, count: pool.length, compact: true),
        const SizedBox(height: 28),
        Text('Para ti esta noche', style: slushHeadline(24, color: p.ink)),
        const SizedBox(height: 14),
        if (shown.isEmpty)
          Text(
            c.tracks.isEmpty
                ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                : 'Ninguna pista encaja con este ánimo todavía.',
            style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(right: 8, bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, t) in shown.indexed) ...[
                  if (i > 0) const SizedBox(width: 16),
                  SlushCoverTile(
                    track: t,
                    width: 150,
                    radius: 28,
                    onTap: () => c.playTrack(t, context: shown),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Píldora de papel de «Seguir escuchando»: portada de 52 y título.
class _RecentPill extends StatelessWidget {
  const _RecentPill({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return SlushPressable(
      onTap: onTap,
      radius: 28,
      elevation: SlushElevation.card,
      semanticLabel: 'Reproducir ${track.title}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(28),
          border: Border.fromBorderSide(p.borderSoft),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              SlushCover(track: track, side: 52, radius: 14),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: slushHeadline(15, height: 1.15, color: p.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
