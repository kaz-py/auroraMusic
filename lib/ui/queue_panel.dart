import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import '../theme/slush_theme.dart';
import '../theme/slush_widgets.dart';
import 'artwork.dart';
import 'track_actions.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    return isSlush(context)
        ? SlushScreen(color: context.slush.screen, title: 'COLA', child: body)
        : body;
  }

  Widget _body(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final modern = isModern(context);
        final playerBody = _CurrentTrack(
          controller: controller,
          track: controller.currentTrack,
        );
        final queueBody = _QueueList(controller: controller, bounded: !narrow);
        final brasa = isBrasa(context);
        final player = brasa
            ? _brasaCard(playerBody)
            : modern
            ? ModernCard(child: playerBody)
            : playerBody;
        final queue = brasa
            ? _brasaCard(queueBody)
            : modern
            ? ModernCard(child: queueBody)
            : queueBody;
        if (narrow) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [player, const SizedBox(height: 28), queue],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 310, child: SingleChildScrollView(child: player)),
              const SizedBox(width: 24),
              Expanded(child: queue),
            ],
          ),
        );
      },
    ),
  );
}

/// Tarjeta Brasa: #17110e, radio 6 y la sombra de tarjeta del tema.
Widget _brasaCard(Widget child) => DecoratedBox(
  decoration: BoxDecoration(
    color: Brasa.obsidian,
    borderRadius: BorderRadius.circular(6),
    boxShadow: Brasa.cardShadow,
  ),
  child: Padding(padding: const EdgeInsets.all(16), child: child),
);

class _CurrentTrack extends StatelessWidget {
  const _CurrentTrack({required this.controller, required this.track});
  final AppController controller;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final audio = controller.audio;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBrasa(context) ? 'Sonando ahora' : 'SONANDO AHORA',
            style: isBrasa(context)
                ? const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Brasa.cream,
                  )
                : Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(height: 14),
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(
                  isBrasa(context) ? 6 : (isModern(context) ? 16 : 8),
                ),
                child: _Artwork(track: track),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            track?.title ?? 'Nada sonando',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 5),
          Text(
            track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isBrasa(context)
                  ? Brasa.steel
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(_time(audio.position)),
              Expanded(
                child: Slider(
                  semanticFormatterCallback: (value) =>
                      'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                  min: 0,
                  max:
                      (audio.duration.inMilliseconds > 0
                              ? audio.duration.inMilliseconds
                              : 1)
                          .toDouble(),
                  value: audio.position.inMilliseconds
                      .clamp(
                        0,
                        audio.duration.inMilliseconds > 0
                            ? audio.duration.inMilliseconds
                            : 1,
                      )
                      .toDouble(),
                  onChanged: track == null || audio.duration <= Duration.zero
                      ? null
                      : (value) => controller.seek(
                          Duration(milliseconds: value.round()),
                        ),
                ),
              ),
              Text(_time(audio.duration)),
            ],
          ),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: track == null ? null : controller.previous,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton.filled(
                  tooltip: audio.isPlaying ? 'Pausar' : 'Reproducir',
                  onPressed: track == null ? null : controller.togglePlayback,
                  style: isBrasa(context)
                      ? IconButton.styleFrom(
                          backgroundColor: Brasa.cream,
                          foregroundColor: Colors.black,
                        )
                      : isModern(context)
                      ? IconButton.styleFrom(
                          backgroundColor: Tracky.mint,
                          foregroundColor: Tracky.navy,
                        )
                      : null,
                  icon: Icon(audio.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: track == null ? null : controller.next,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({required this.controller, required this.bounded});
  final AppController controller;
  final bool bounded;

  @override
  Widget build(BuildContext context) {
    final start = controller.queueIndex < 0 ? 0 : controller.queueIndex + 1;
    final upcoming = controller.queue.skip(start).toList();
    final heading = Row(
      children: [
        Expanded(
          child: Text(
            'A continuación',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
        ),
        Text(
          '${upcoming.length} canciones',
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
    if (!bounded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 12),
          if (upcoming.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('No hay canciones en la cola')),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: upcoming.length,
              onReorder: (oldIndex, newIndex) =>
                  controller.reorderQueue(start + oldIndex, start + newIndex),
              itemBuilder: (context, index) =>
                  _tile(context, upcoming[index], start + index),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 12),
        if (upcoming.isEmpty)
          const Expanded(
            child: Center(child: Text('No hay canciones en la cola')),
          )
        else
          Expanded(
            child: ReorderableListView.builder(
              itemCount: upcoming.length,
              onReorder: (oldIndex, newIndex) =>
                  controller.reorderQueue(start + oldIndex, start + newIndex),
              itemBuilder: (context, index) =>
                  _tile(context, upcoming[index], start + index),
            ),
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, Track track, int queueIndex) =>
      TrackActionsRegion(
        key: ValueKey('$queueIndex:${track.id}'),
        controller: controller,
        track: track,
        extras: [
          (
            label: 'Quitar de la cola',
            run: () => controller.removeFromQueue(queueIndex),
          ),
        ],
        builder: (context, _) => _queueTile(context, track, queueIndex),
      );

  Widget _queueTile(BuildContext context, Track track, int queueIndex) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        shape: isBrasa(context)
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))
            : isModern(context)
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            : null,
        leading: Artwork(
          track: track,
          artworkContext: ArtworkContext.thumbnail,
          radius: isBrasa(context) ? 4 : (isModern(context) ? 8 : 5),
        ),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: isBrasa(context)
              ? const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Brasa.cream,
                )
              : null,
        ),
        subtitle: Text(
          '${controller.autoAddedIds.contains(track.id) ? 'Sugerida · ' : ''}'
          '${track.artist} · ${_time(track.duration)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: isBrasa(context)
              ? const TextStyle(fontSize: 12, color: Brasa.steel)
              : null,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TrackMenuButton(
              controller: controller,
              track: track,
              extras: [
                (
                  label: 'Quitar de la cola',
                  run: () => controller.removeFromQueue(queueIndex),
                ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.drag_handle),
          ],
        ),
        onTap: () => controller.playQueueAt(queueIndex),
      );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.track});
  final Track? track;
  @override
  Widget build(BuildContext context) {
    final item = track;
    if (item != null) {
      return Artwork.fill(track: item, artworkContext: ArtworkContext.player);
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _time(Duration value) =>
    '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
