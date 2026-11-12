import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'artwork.dart';
import 'right_panel/right_panel_theme.dart';
import 'track_actions.dart';

class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return rightPanelThemeOf(context).wrapQueue(context, _body(context));
  }

  Widget _body(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final theme = rightPanelThemeOf(context);
        final playerBody = _CurrentTrack(
          controller: controller,
          track: controller.currentTrack,
        );
        final queueBody = _QueueList(controller: controller, bounded: !narrow);
        final player = theme.queueCard(playerBody);
        final queue = theme.queueCard(queueBody);
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

class _CurrentTrack extends StatelessWidget {
  const _CurrentTrack({required this.controller, required this.track});
  final AppController controller;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final audio = controller.audio;
    final theme = rightPanelThemeOf(context);
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(theme.nowPlayingLabel, style: theme.nowPlayingStyle(context)),
          const SizedBox(height: 14),
          Center(
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(theme.currentArtRadius),
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
            style: theme.artistStyle(context),
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
                  style: theme.playButtonStyle,
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

  Widget _queueTile(BuildContext context, Track track, int queueIndex) {
    final theme = rightPanelThemeOf(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      shape: theme.tileShape,
      leading: Artwork(
        track: track,
        artworkContext: ArtworkContext.thumbnail,
        radius: theme.tileArtRadius,
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.tileTitleStyle,
      ),
      subtitle: Text(
        '${controller.autoAddedIds.contains(track.id) ? 'Sugerida · ' : ''}'
        '${track.artist} · ${_time(track.duration)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.tileSubtitleStyle,
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
