/// Dueño: tema Modern.
///
/// Posee el Modo Vinilo / reproductor completo (sección 4): maquetación y pintura del disco.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../artwork.dart';
import '../follow_widgets.dart';
import '../../theme/modern_widgets.dart';
import 'player_theme.dart';

/// Modern: implementación de [PlayerTheme].
const PlayerTheme modernPlayer = ModernPlayerTheme();

class ModernPlayerTheme extends PlayerTheme {
  const ModernPlayerTheme();

  @override
  double get compactBreakpoint => 760;

  @override
  bool get rebuildsOnAudio => false;

  @override
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) {
    final c = scope.controller;
    final color = Theme.of(context).colorScheme;
    const fg = Colors.white;
    final recordSide = compact
        ? math.min(constraints.maxWidth - 36 - 48, 300.0)
        : math.min(constraints.maxWidth * .32, 340.0);
    final title = (track?.title ?? 'Nada sonando').trim();
    final words = title.split(RegExp(r'\s+'));
    final multi = words.length >= 2;
    final Widget headline = ClipRect(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 36 * 1.1 * 3),
        child: ModernHeadline(
          before: multi
              ? '${words.sublist(0, words.length - 1).join(' ')} '
              : words.first,
          emphasis: multi ? words.last : '',
          size: 36,
          onDark: true,
        ),
      ),
    );
    final artist = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MouseRegion(
          cursor: track == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: track == null ? null : () => c.openArtist(track.artist),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.16,
                  ),
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
        if (track != null)
          IconButton(
            tooltip: c.favoriteIds.contains(track.id)
                ? 'Quitar de favoritos'
                : 'Añadir a favoritos',
            color: c.favoriteIds.contains(track.id)
                ? Tracky.coral
                : Colors.white70,
            onPressed: () => c.toggleFavorite(track),
            icon: Icon(
              c.favoriteIds.contains(track.id)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
            ),
          ),
      ],
    );
    // Modern suma aleatorio y repetir a los lados.
    final extras = track != null;
    final controls = ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (extras)
            IconButton(
              tooltip: 'Aleatorio',
              isSelected: c.shuffle,
              color: c.shuffle ? Tracky.mint : Colors.white54,
              onPressed: () => c.setShuffle(!c.shuffle),
              icon: const Icon(Icons.shuffle_rounded, size: 24),
            ),
          IconButton(
            tooltip: 'Anterior',
            color: fg,
            onPressed: track == null ? null : c.previous,
            icon: const Icon(Icons.skip_previous_rounded, size: 32),
          ),
          SizedBox(width: extras ? 4 : 12),
          FilledButton(
            onPressed: track == null ? null : c.togglePlayback,
            style: FilledButton.styleFrom(
              backgroundColor: Tracky.mint,
              foregroundColor: Tracky.navy,
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
          SizedBox(width: extras ? 4 : 12),
          IconButton(
            tooltip: 'Siguiente',
            color: fg,
            onPressed: track == null ? null : c.next,
            icon: const Icon(Icons.skip_next_rounded, size: 32),
          ),
          if (extras)
            IconButton(
              tooltip: 'Repetir',
              isSelected: c.repeat != RepeatMode.off,
              color: c.repeat == RepeatMode.off ? Colors.white54 : Tracky.mint,
              onPressed: c.cycleRepeat,
              icon: Icon(
                c.repeat == RepeatMode.one
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                size: 24,
              ),
            ),
        ],
      ),
    );
    const timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final progress = RepaintBoundary(
      child: ListenableBuilder(
        listenable: c.audio,
        builder: (context, _) {
          final duration = scope.liveDuration();
          final max = math.max(1, duration.inMilliseconds).toDouble();
          final pos = c.audio.position.inMilliseconds.toDouble().clamp(
            0.0,
            max,
          );
          return Row(
            children: [
              Text(playerTime(c.audio.position), style: timeStyle),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Tracky.mint,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Tracky.coral,
                    overlayColor: Tracky.mint.withValues(alpha: .16),
                  ),
                  child: Slider(
                    semanticFormatterCallback: (value) =>
                        'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                    min: 0,
                    max: max,
                    value: pos,
                    onChanged: duration > Duration.zero
                        ? (value) =>
                              c.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
              ),
              Text(playerTime(duration), style: timeStyle),
            ],
          );
        },
      ),
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headline,
        const SizedBox(height: 10),
        artist,
        const SizedBox(height: 28),
        progress,
        controls,
      ],
    );
    // Modern elige cómo ver la pista: portada sola (por defecto), vinilo o
    // casete.
    final photo = scope.modernPhoto && track != null;
    final record = photo
        ? scope.seekable(
            c,
            math.max(0.0, recordSide),
            Artwork(
              track: track,
              size: math.max(0.0, recordSide),
              radius: 12,
              artworkContext: ArtworkContext.playerDetail,
            ),
          )
        : scope.record(context, c, track, math.max(0.0, recordSide), _style);
    final Widget visual = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        record,
        const SizedBox(height: 16),
        SegmentedButton<int>(
          key: const ValueKey('modern-view-picker'),
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white70,
            selectedForegroundColor: Tracky.navy,
            selectedBackgroundColor: Tracky.mint,
            side: const BorderSide(color: Colors.white24),
          ),
          segments: const [
            ButtonSegment(
              value: 0,
              icon: Icon(Icons.image_outlined),
              tooltip: 'Ver portada',
            ),
            ButtonSegment(
              value: 1,
              icon: Icon(Icons.album_outlined),
              tooltip: 'Ver vinilo',
            ),
            ButtonSegment(
              value: 2,
              icon: Icon(Icons.sd_card_outlined),
              tooltip: 'Ver casete',
            ),
          ],
          selected: {
            if (scope.modernPhoto) 0 else if (scope.cassette) 2 else 1,
          },
          onSelectionChanged: (s) => scope.setModernView(s.first),
        ),
      ],
    );
    final inner = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: visual),
              const SizedBox(height: 24),
              info,
            ],
          )
        : Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 32),
              visual,
            ],
          );
    final Widget feature = ModernCard(
      dark: true,
      feature: true,
      padding: EdgeInsets.all(compact ? 24 : 40),
      child: inner,
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
    final next = ModernCard(child: nextUp);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [feature, const SizedBox(height: 20), next],
          ),
        ),
      ),
    );
  }
}

const PlayerDiscStyle _style = PlayerDiscStyle(
  disc: Color(0xff151b31),
  label: Color(0xff0b1020),
  ring: Tracky.coral,
  ringWidth: 2,
  shadow: [],
  groove: Colors.white,
  grooveHi: .05,
  grooveLo: .02,
  pivot: Tracky.mint,
  arm: Tracky.mint,
  needle: Tracky.mint,
);
