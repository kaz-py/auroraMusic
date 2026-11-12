/// Dueño: tema Brasa.
///
/// Posee el Modo Vinilo / reproductor completo (sección 4): maquetación y pintura del disco.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../artwork.dart';
import '../follow_widgets.dart';
import '../../theme/brasa_theme.dart';
import 'player_theme.dart';

/// Brasa: implementación de [PlayerTheme].
const PlayerTheme brasaPlayer = BrasaPlayerTheme();

class BrasaPlayerTheme extends PlayerTheme {
  const BrasaPlayerTheme();

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
    const fg = Brasa.cream;
    final recordSide = compact
        ? math.min(constraints.maxWidth - 36 - 48, 300.0)
        : math.min(constraints.maxWidth * .32, 340.0);
    final title = (track?.title ?? 'Nada sonando').trim();
    final Widget headline = Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontFamily: 'Inter',
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: Brasa.cream,
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
                    fontFamily: 'Inter',
                    color: Brasa.cloud,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
      ],
    );
    // En Brasa solo los tres botones de siempre más aleatorio.
    final brasaShuffle = track != null;
    final controls = ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (brasaShuffle)
            IconButton(
              tooltip: 'Aleatorio',
              isSelected: c.shuffle,
              color: c.shuffle ? Brasa.accent : Brasa.cloud,
              onPressed: () => c.setShuffle(!c.shuffle),
              icon: const Icon(Icons.shuffle_rounded, size: 24),
            ),
          IconButton(
            tooltip: 'Anterior',
            color: fg,
            onPressed: track == null ? null : c.previous,
            icon: const Icon(Icons.skip_previous_rounded, size: 32),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: track == null ? null : c.togglePlayback,
            style: FilledButton.styleFrom(
              backgroundColor: Brasa.cream,
              foregroundColor: Colors.black,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
            child: Icon(
              c.audio.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Siguiente',
            color: fg,
            onPressed: track == null ? null : c.next,
            icon: const Icon(Icons.skip_next_rounded, size: 32),
          ),
        ],
      ),
    );
    const timeStyle = TextStyle(
      fontFamily: 'Inter',
      color: Brasa.steel,
      fontSize: 11,
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
                    trackHeight: 4,
                    activeTrackColor: Brasa.cream,
                    inactiveTrackColor: Brasa.ash,
                    thumbColor: Brasa.cream,
                    overlayColor: Brasa.cream.withValues(alpha: .16),
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
        const SizedBox(height: 6),
        artist,
        const SizedBox(height: 20),
        progress,
        controls,
      ],
    );
    // Brasa conserva su disco.
    final visual = scope.record(
      context,
      c,
      track,
      math.max(0.0, recordSide),
      _style,
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
              visual,
              const SizedBox(width: 32),
              Expanded(child: info),
            ],
          );
    final Widget feature = DecoratedBox(
      decoration: BoxDecoration(
        color: Brasa.obsidian,
        borderRadius: BorderRadius.circular(6),
        boxShadow: Brasa.cardShadow,
      ),
      child: Padding(padding: const EdgeInsets.all(24), child: inner),
    );
    final next = _brasaNext(context, c, track);
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

PlayerDiscStyle get _style => PlayerDiscStyle(
  disc: Brasa.void_,
  label: Brasa.graphite,
  ring: Brasa.accent,
  ringWidth: 2,
  shadow: [],
  groove: Brasa.graphite,
  grooveHi: 1,
  grooveLo: .55,
  pivot: Brasa.cream,
  arm: Brasa.cream,
  needle: Brasa.cream,
);

/// «A continuación» de Brasa: lista compacta con la pista actual en ámbar.
Widget _brasaNext(BuildContext context, AppController c, Track? current) {
  final upcoming = c.queue.skip(c.queueIndex + 1).take(5).toList();
  Widget row(Track t, bool now, VoidCallback? onTap) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Artwork(
            track: t,
            artworkContext: ArtworkContext.thumbnailCompact,
            radius: 4,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: now ? Brasa.accent : Brasa.cream,
                  ),
                ),
                Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Brasa.steel,
                  ),
                ),
              ],
            ),
          ),
          if (now) Icon(Icons.graphic_eq, size: 16, color: Brasa.accent),
        ],
      ),
    ),
  );
  return DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.obsidian,
      borderRadius: BorderRadius.circular(6),
      boxShadow: Brasa.cardShadow,
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'A continuación',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Brasa.cream,
            ),
          ),
          const SizedBox(height: 8),
          if (current != null) row(current, true, null),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'La cola está vacía',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  color: Brasa.steel,
                ),
              ),
            )
          else
            for (var i = 0; i < upcoming.length; i++)
              row(
                upcoming[i],
                false,
                () => c.playQueueAt(c.queueIndex + i + 1),
              ),
        ],
      ),
    ),
  );
}
