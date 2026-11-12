/// Dueño: tema Atelier Sonoro (sin marca).
///
/// Posee el Modo Vinilo / reproductor completo (sección 4): maquetación y pintura del disco.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../artwork.dart';
import '../follow_widgets.dart';
import 'player_theme.dart';

/// Atelier Sonoro (sin marca): implementación de [PlayerTheme].
const PlayerTheme atelierPlayer = AtelierPlayerTheme();

class AtelierPlayerTheme extends PlayerTheme {
  const AtelierPlayerTheme();

  @override
  double get compactBreakpoint => 760;

  @override
  bool get rebuildsOnAudio => true;

  @override
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) {
    final c = scope.controller;
    final duration = c.audio.duration > Duration.zero
        ? c.audio.duration
        : track?.duration ?? Duration.zero;
    final pos = c.audio.position.inMilliseconds.clamp(
      0,
      math.max(0, duration.inMilliseconds),
    );
    final color = Theme.of(context).colorScheme;
    final artSize = compact
        ? ArtworkContext.vinylCompact.constrain(
            BoxConstraints(maxWidth: math.max(0.0, constraints.maxWidth - 36)),
          )
        : math
              .min(
                (constraints.maxWidth - 300) * .58,
                constraints.maxHeight - 48,
              )
              .clamp(0.0, ArtworkContext.vinyl.size);
    final record = scope.record(
      context,
      c,
      track,
      artSize,
      PlayerDiscStyle(
        disc: const Color(0xff171514),
        label: color.surfaceContainerHighest,
        ring: Colors.white24,
        ringWidth: 1,
        shadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 26,
            offset: Offset(0, 12),
          ),
        ],
        groove: Colors.white,
        grooveHi: .065,
        grooveLo: .025,
        pivot: color.outline,
        arm: color.outlineVariant,
        needle: color.primary,
      ),
    );
    final metadata = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          track?.title ?? 'Nada sonando',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            MouseRegion(
              cursor: track == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: track == null ? null : () => c.openArtist(track.artist),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: 1,
                    child: Text(
                      track?.artist ??
                          'Elige una canci\u00f3n de tu biblioteca',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: color.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            if (scope.follow != null &&
                track != null &&
                primaryArtist(track.artist).isNotEmpty)
              FollowButton(
                service: scope.follow!,
                name: primaryArtist(track.artist),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Text(
              playerTime(c.audio.position),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            Expanded(
              child: Slider(
                semanticFormatterCallback: (value) =>
                    'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                min: 0,
                max: math.max(1, duration.inMilliseconds).toDouble(),
                value: pos.toDouble().clamp(
                  0,
                  math.max(1, duration.inMilliseconds).toDouble(),
                ),
                onChanged: duration > Duration.zero
                    ? (value) => c.seek(Duration(milliseconds: value.round()))
                    : null,
              ),
            ),
            Text(
              playerTime(duration),
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Aleatorio',
              isSelected: c.shuffle,
              color: c.shuffle ? color.primary : color.onSurfaceVariant,
              onPressed: track == null ? null : () => c.setShuffle(!c.shuffle),
              icon: const Icon(Icons.shuffle_rounded, size: 24),
            ),
            IconButton(
              tooltip: 'Anterior',
              onPressed: track == null ? null : c.previous,
              icon: const Icon(Icons.skip_previous_rounded, size: 32),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: track == null ? null : c.togglePlayback,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(18),
              ),
              child: Icon(
                c.audio.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 32,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Siguiente',
              onPressed: track == null ? null : c.next,
              icon: const Icon(Icons.skip_next_rounded, size: 32),
            ),
          ],
        ),
      ],
    );
    final nextTracks = c.queue.skip(c.queueIndex + 1).take(3).toList();
    final nextUp = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A CONTINUACIÓN',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color.primary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        if (nextTracks.isEmpty)
          Text(
            'La cola está vacía',
            style: TextStyle(color: color.onSurfaceVariant),
          )
        else
          for (var i = 0; i < nextTracks.length; i++)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Artwork(
                track: nextTracks[i],
                artworkContext: ArtworkContext.thumbnailCompact,
                radius: 5,
              ),
              title: Text(
                nextTracks[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                nextTracks[i].artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => c.playQueueAt(c.queueIndex + i + 1),
            ),
      ],
    );
    if (compact) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: record),
            const SizedBox(height: 20),
            metadata,
            const SizedBox(height: 24),
            nextUp,
          ],
        ),
      );
    }
    final compositionWidth = math.min(constraints.maxWidth - 48, 1100.0);
    final contextWidth = math.min(300.0, compositionWidth - 460);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: compositionWidth,
          child: Row(
            children: [
              SizedBox(
                width: contextWidth,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'EDICIÓN DE LA BIBLIOTECA',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: color.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      metadata,
                      const SizedBox(height: 20),
                      nextUp,
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 40),
              Expanded(child: Center(child: record)),
            ],
          ),
        ),
      ),
    );
  }
}
