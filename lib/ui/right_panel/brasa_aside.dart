/// Panel derecho de Brasa (340, radio 24, tonal, sin borde): pestañas
/// Cola / Ahora suena / Letras y tarjeta de Jam al pie. La lista de cola
/// también alimenta la hoja de cola del reproductor móvil.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_service.dart';
import '../../theme/brasa_theme.dart';
import '../artwork.dart';
import '../jam/jam_widgets.dart';
import '../player/brasa_player_parts.dart';
import '../player/player_theme.dart';
import '../studio/equalizer_panel.dart';
import '../track_actions.dart';

/// Superficie del panel: un punto más clara que el lienzo.
const _panel = Color(0xff1c1510);

class BrasaAside extends StatefulWidget {
  const BrasaAside({
    super.key,
    required this.controller,
    this.jam,
    required this.onStartJam,
    required this.onJam,
    required this.onQueue,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onStartJam, onJam, onQueue;

  @override
  State<BrasaAside> createState() => _BrasaAsideState();
}

class _BrasaAsideState extends State<BrasaAside> {
  int _tab = 0;

  Duration _liveDuration() {
    final c = widget.controller;
    return c.audio.duration > Duration.zero
        ? c.audio.duration
        : c.currentTrack?.duration ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    const tabs = ['Cola', 'Ahora suena', 'Letras'];
    final body = switch (_tab) {
      0 => BrasaQueueList(
        controller: c,
        jam: widget.jam,
        onJam: widget.onJam,
        onViewAll: widget.onQueue,
      ),
      1 => _NowPlayingTab(controller: c, liveDuration: _liveDuration),
      _ => _LyricsTab(controller: c),
    };
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Brasa.obsidian,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    for (final (i, label) in tabs.indexed)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: _tab == i,
                          label: label,
                          excludeSemantics: true,
                          child: Material(
                            color: _tab == i
                                ? Brasa.surface3
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () => setState(() => _tab = i),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 44,
                                ),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    child: Text(
                                      label,
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Brasa.sans(
                                        13,
                                        weight: FontWeight.w500,
                                        color: _tab == i
                                            ? Brasa.cream
                                            : Brasa.cloud,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: body),
            const SizedBox(height: 8),
            _JamFooter(
              jam: widget.jam,
              onJam: widget.onJam,
              onStartJam: widget.onStartJam,
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      width: 340,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 24, 24),
        child: LayoutBuilder(
          builder: (context, box) => box.hasBoundedHeight
              ? panel
              : SizedBox(height: 640, child: panel),
        ),
      ),
    );
  }
}

/// Tarjeta de Jam al pie: «Jam activo · N oyentes» o acción de iniciar.
class _JamFooter extends StatelessWidget {
  const _JamFooter({
    required this.jam,
    required this.onJam,
    required this.onStartJam,
  });
  final JamController? jam;
  final VoidCallback onJam, onStartJam;

  @override
  Widget build(BuildContext context) {
    final j = jam;
    if (j == null) return _card(context, null);
    return ListenableBuilder(
      listenable: j,
      builder: (context, _) => _card(context, j.service),
    );
  }

  Widget _card(BuildContext context, JamService? session) {
    final connected = session != null && session.connected;
    final names = connected
        ? <String>[
            for (final p in session.participants)
              if (p.connected) p.name,
          ]
        : const <String>[];
    final label = connected
        ? 'Jam activo · ${names.length} ${names.length == 1 ? 'oyente' : 'oyentes'}'
        : 'Iniciar una Jam';
    return Material(
      color: Brasa.ash,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: connected ? onJam : onStartJam,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    if (connected)
                      JamAvatarStack(names: names, size: 24, max: 3)
                    else
                      const Icon(
                        Icons.group_add_outlined,
                        size: 22,
                        color: Brasa.ember,
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.sans(13, weight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!connected)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onJam,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Unirme con un código',
                      style: Brasa.sans(13, color: Brasa.amber),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _label(String text, {String? trailing}) => Padding(
  padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
  child: Row(
    children: [
      Expanded(child: Text(text, style: Brasa.mono(11))),
      if (trailing != null) Text(trailing, style: Brasa.mono(11)),
    ],
  ),
);

/// Cola: «SONANDO AHORA» + «A CONTINUACIÓN» (reordenable, quitar con
/// deslizar o menú contextual) o la cola compartida de la Jam activa.
class BrasaQueueList extends StatelessWidget {
  const BrasaQueueList({
    super.key,
    required this.controller,
    this.jam,
    required this.onJam,
    this.onViewAll,
    this.scrollController,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onJam;

  /// Si se pasa, «Ver todo» abre la página de cola completa.
  final VoidCallback? onViewAll;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, ?jam]),
      builder: (context, _) {
        final session = jam?.service;
        final connected = session?.connected == true;
        final current = c.currentTrack;
        final start = c.queueIndex < 0 ? 0 : c.queueIndex + 1;
        final upcoming = c.queue.skip(start).toList();
        final shared = connected
            ? session!.queue
                  .where((e) => e.id != jam!.bridge.currentEntryId)
                  .toList()
            : null;
        final count = shared?.length ?? upcoming.length;
        return CustomScrollView(
          controller: scrollController,
          slivers: [
            SliverToBoxAdapter(child: _label('SONANDO AHORA')),
            if (current != null)
              SliverToBoxAdapter(
                child: _QueueRow(track: current, now: true, onTap: null),
              ),
            SliverToBoxAdapter(
              child: _label(
                connected ? 'COLA COMPARTIDA' : 'A CONTINUACIÓN',
                trailing: count > 0 ? '$count' : null,
              ),
            ),
            if (count == 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'La cola está vacía',
                    style: Brasa.sans(13, color: Brasa.cloud),
                  ),
                ),
              )
            else if (shared != null)
              SliverList.builder(
                itemCount: shared.length,
                itemBuilder: (context, i) {
                  final e = shared[i];
                  return _QueueRow(
                    track: Track(
                      id: e.track.key,
                      title: e.track.title,
                      artist: e.track.artist,
                      artworkUrl: e.track.artworkUrl,
                      duration: Duration(milliseconds: e.track.durationMs),
                    ),
                    now: false,
                    subtitle: 'Por ${session!.participantName(e.addedBy)}',
                    onTap: onJam,
                  );
                },
              )
            else
              SliverReorderableList(
                itemCount: upcoming.length,
                onReorder: (o, n) => c.reorderQueue(start + o, start + n),
                itemBuilder: (context, i) {
                  final track = upcoming[i];
                  final qi = start + i;
                  return Dismissible(
                    key: ValueKey('brasa-q$qi:${track.id}'),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => c.removeFromQueue(qi),
                    background: const ColoredBox(
                      color: Brasa.surface3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: EdgeInsets.only(right: 16),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Brasa.cream,
                          ),
                        ),
                      ),
                    ),
                    child: TrackActionsRegion(
                      controller: c,
                      track: track,
                      extras: [
                        (
                          label: 'Quitar de la cola',
                          run: () => c.removeFromQueue(qi),
                        ),
                      ],
                      builder: (context, _) => _QueueRow(
                        track: track,
                        now: false,
                        subtitle: c.autoAddedIds.contains(track.id)
                            ? 'Sugerida · ${track.artist}'
                            : null,
                        onTap: () => c.playQueueAt(qi),
                        dragIndex: i,
                      ),
                    ),
                  );
                },
              ),
            if (onViewAll != null && count > 0)
              SliverToBoxAdapter(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: onViewAll,
                    child: Text(
                      'Ver todo',
                      style: Brasa.sans(13, color: Brasa.amber),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.now,
    required this.onTap,
    this.subtitle,
    this.dragIndex,
  });
  final Track track;
  final bool now;
  final VoidCallback? onTap;
  final String? subtitle;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final d = track.duration;
    return Material(
      color: now ? Brasa.graphite : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Artwork(
                  track: track,
                  artworkContext: ArtworkContext.thumbnail,
                  size: 44,
                  radius: 8,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.sans(
                          14,
                          weight: FontWeight.w500,
                          color: now ? Brasa.ember : Brasa.cream,
                        ),
                      ),
                      Text(
                        subtitle ?? track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.sans(12, color: Brasa.cloud),
                      ),
                    ],
                  ),
                ),
                if (d > Duration.zero) ...[
                  const SizedBox(width: 8),
                  Text(playerTime(d), style: Brasa.mono(12, tracking: .04)),
                ],
                if (dragIndex != null)
                  ReorderableDragStartListener(
                    index: dragIndex!,
                    child: const SizedBox(
                      width: 32,
                      height: 44,
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 20,
                        color: Brasa.steel,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pestaña «Ahora suena»: portada, título, seek, transporte y ecualizador.
class _NowPlayingTab extends StatelessWidget {
  const _NowPlayingTab({required this.controller, required this.liveDuration});
  final AppController controller;
  final Duration Function() liveDuration;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final t = c.currentTrack;
        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (t != null)
              Center(
                child: Artwork(
                  track: t,
                  artworkContext: ArtworkContext.player,
                  size: 260,
                  radius: 12,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              t?.title ?? 'Nada sonando',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brasa.serif(24, height: 1.1),
            ),
            const SizedBox(height: 4),
            Text(
              t?.artist ?? 'Elige una canción de tu biblioteca',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brasa.sans(14, color: Brasa.cloud),
            ),
            const SizedBox(height: 8),
            BrasaSeekBar(controller: c, liveDuration: liveDuration),
            BrasaTransport(controller: c, playSize: 56),
            const SizedBox(height: 16),
            EqualizerPanel(controller: c),
          ],
        );
      },
    );
  }
}

/// Pestaña «Letras»: las líneas alrededor de la activa, con una palabra en brasa.
class _LyricsTab extends StatelessWidget {
  const _LyricsTab({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) => BrasaLyricsFeed(
    controller: controller,
    builder: (context, lines, active) {
      if (lines.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Sin letra para esta pista',
              textAlign: TextAlign.center,
              style: Brasa.sans(14, color: Brasa.cloud),
            ),
          ),
        );
      }
      final from = active < 3 ? 0 : active - 3;
      final to = from + 14 > lines.length ? lines.length : from + 14;
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          for (var i = from; i < to; i++)
            if (lines[i].text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: brasaLyricLine(
                  lines[i].text,
                  i == active
                      ? Brasa.serif(26, height: 1.15)
                      : Brasa.serif(
                          20,
                          height: 1.15,
                          color: Brasa.cream.withValues(alpha: .4),
                        ),
                  accent: i == active,
                  maxLines: 4,
                ),
              ),
        ],
      );
    },
  );
}

/// Hoja de cola del móvil (arrastrable) con la misma lista que el panel.
Future<void> showBrasaQueueSheet(
  BuildContext context, {
  required AppController controller,
  JamController? jam,
  required VoidCallback onJam,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (sheetContext) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .65,
    minChildSize: .35,
    maxChildSize: .95,
    builder: (context, scroll) => DecoratedBox(
      decoration: const BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Brasa.steel,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: BrasaQueueList(
                controller: controller,
                jam: jam,
                onJam: () {
                  Navigator.of(sheetContext).pop();
                  onJam();
                },
                scrollController: scroll,
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
