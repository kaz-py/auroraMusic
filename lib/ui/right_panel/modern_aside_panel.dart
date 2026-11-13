/// Dueño: tema Modern.
///
/// Panel derecho del reproductor (escritorio ancho): pestañas Cola / Ahora
/// suena / Letras, cola con los gestos de siempre (tocar, arrastrar para
/// reordenar, menú y clic derecho para quitar) y tarjeta de Jam y sueño.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_models.dart';
import '../../theme/modern_cristal.dart';
import '../artwork.dart';
import '../jam/jam_widgets.dart';
import '../player/modern_player_parts.dart';
import '../shell/shell_chrome.dart';
import '../track_actions.dart';

class ModernAside extends StatefulWidget {
  const ModernAside({super.key, required this.scope});

  final ShellScope scope;

  @override
  State<ModernAside> createState() => _ModernAsideState();
}

class _ModernAsideState extends State<ModernAside> {
  int _tab = 0;

  ShellScope get scope => widget.scope;
  AppController get c => scope.controller;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    return SizedBox(
      width: 372,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        child: ListenableBuilder(
          listenable: Listenable.merge([c, if (scope.jam != null) scope.jam!]),
          builder: (context, _) => ModernGlass(
            radius: 24,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _tabs(p),
                const SizedBox(height: 12),
                Expanded(child: _body(context, p)),
                const SizedBox(height: 12),
                _footer(context, p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Pestañas -----------------------------------------------------------

  Widget _tabs(Cristal p) {
    const names = ['Cola', 'Ahora suena', 'Letras'];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.dark ? const Color(0x33000000) : p.glass,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (var i = 0; i < names.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _tab == i,
                  label: names[i],
                  excludeSemantics: true,
                  child: Material(
                    color: _tab == i ? p.glassHover : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() => _tab = i),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 40),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                names[i],
                                maxLines: 1,
                                style: Cristal.ui(
                                  13.5,
                                  weight: 600,
                                  color: _tab == i ? p.text : p.text2,
                                ),
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
    );
  }

  Widget _body(BuildContext context, Cristal p) => switch (_tab) {
    0 => _queue(context, p),
    1 => _nowPlaying(context, p),
    _ => ModernLyricsPreview(
      controller: c,
      activeSize: 24,
      restSize: 19,
      onOpen: () => scope.onNavigate(6),
      empty: Center(
        child: Text(
          'No hay letra para esta pista.',
          textAlign: TextAlign.center,
          style: Cristal.ui(14, weight: 500, color: p.text3),
        ),
      ),
    ),
  };

  // ---- Cola ---------------------------------------------------------------

  Widget _queue(BuildContext context, Cristal p) {
    final session = scope.jam?.service;
    final shared = session?.connected == true
        ? session!.queue
              .where((e) => e.id != scope.jam!.bridge.currentEntryId)
              .toList()
        : null;
    final start = c.queueIndex < 0 ? 0 : c.queueIndex + 1;
    final upcoming = c.queue.skip(start).toList();
    final count = shared?.length ?? upcoming.length;
    final current = c.currentTrack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(child: ModernLabel('A continuación · $count')),
              if (shared == null && upcoming.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(_clear()),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: Cristal.ui(13, weight: 600),
                  ),
                  child: const Text('Vaciar'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (shared == null && current != null)
          _Row(
            track: current,
            current: true,
            onTap: () => c.playQueueAt(c.queueIndex),
          ),
        Expanded(
          child: shared != null
              ? _sharedList(shared, p)
              : upcoming.isEmpty
              ? Center(
                  child: Text(
                    'La cola está vacía',
                    style: Cristal.ui(14, weight: 500, color: p.text3),
                  ),
                )
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: EdgeInsets.zero,
                  itemCount: upcoming.length,
                  onReorder: (oldIndex, newIndex) =>
                      c.reorderQueue(start + oldIndex, start + newIndex),
                  itemBuilder: (context, index) {
                    final queueIndex = start + index;
                    final track = upcoming[index];
                    return ReorderableDragStartListener(
                      key: ValueKey('$queueIndex:${track.id}'),
                      index: index,
                      child: TrackActionsRegion(
                        controller: c,
                        track: track,
                        extras: [
                          (
                            label: 'Quitar de la cola',
                            run: () => c.removeFromQueue(queueIndex),
                          ),
                        ],
                        builder: (context, _) => _Row(
                          track: track,
                          onTap: () => c.playQueueAt(queueIndex),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _sharedList(List<JamQueueEntry> entries, Cristal p) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'La cola está vacía',
          style: Cristal.ui(14, weight: 500, color: p.text3),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final entry in entries)
          _Row(
            track: Track(
              id: entry.track.key,
              title: entry.track.title,
              artist: entry.track.artist,
              artworkUrl: entry.track.artworkUrl,
              duration: Duration(milliseconds: entry.track.durationMs),
            ),
            subtitle:
                'Por ${scope.jam!.service.participantName(entry.addedBy)}',
            onTap: scope.onOpenJamPanel,
          ),
      ],
    );
  }

  Future<void> _clear() async {
    for (var i = c.queue.length - 1; i > c.queueIndex; i--) {
      await c.removeFromQueue(i);
    }
  }

  // ---- Ahora suena --------------------------------------------------------

  Widget _nowPlaying(BuildContext context, Cristal p) {
    final t = c.nowTrack;
    if (t == null) {
      return Center(
        child: Text(
          'Nada sonando',
          style: Cristal.ui(14, weight: 500, color: p.text3),
        ),
      );
    }
    final album = t.album?.trim();
    return LayoutBuilder(
      builder: (context, box) {
        final side = box.maxWidth.clamp(120.0, 300.0);
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ModernCover(track: t, size: side, radius: 24),
              ),
              const SizedBox(height: 20),
              Text(
                t.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Cristal.ui(
                  22,
                  weight: 800,
                  color: p.text,
                  tracking: -.03,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.artist,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Cristal.ui(15, weight: 500, color: p.text2),
              ),
              if (album != null && album.isNotEmpty)
                Text(
                  album,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Cristal.ui(13, weight: 500, color: p.text3),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ModernSignalChip(label: modernFormatLabel(t)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- Pie: Jam y sueño ---------------------------------------------------

  Widget _footer(BuildContext context, Cristal p) {
    final jam = scope.jam;
    final live = scope.jamOn && jam != null;
    final left = c.sleepRemaining;
    return ModernGlass(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FooterRow(
            icon: Icons.groups_outlined,
            label: live
                ? 'Jam · ${jam.peopleCount} ${jam.peopleCount == 1 ? 'conectado' : 'conectados'}'
                : 'Iniciar Jam',
            tooltip: live ? 'Abrir la Jam' : 'Iniciar una Jam',
            onTap: live ? scope.onOpenJamPanel : scope.onStartJam,
            trailing: live ? const ModernSignalChip(label: 'EN VIVO') : null,
          ),
          _FooterRow(
            icon: Icons.bedtime_outlined,
            label: 'Temporizador de sueño',
            tooltip: 'Temporizador de sueño',
            onTap: () => showModernSleepSheet(context, c),
            trailing: Text(
              left == null ? 'Apagado' : modernSleepClock(left),
              style: Cristal.mono(
                left == null ? 12 : 13,
                weight: 600,
                color: left == null ? p.text3 : p.text,
                tracking: .04,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de la cola: portada 40 r8, título, artista y duración mono. La actual
/// va teñida de acento al 14 % con el título en acento.
class _Row extends StatelessWidget {
  const _Row({
    required this.track,
    required this.onTap,
    this.current = false,
    this.subtitle,
  });

  final Track track;
  final VoidCallback onTap;
  final bool current;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    final duration = track.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: current ? p.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Artwork(
                    track: track,
                    size: 40,
                    radius: 8,
                    artworkContext: ArtworkContext.thumbnailCompact,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Cristal.ui(
                            14,
                            weight: 700,
                            color: current ? p.accent : p.text,
                          ),
                        ),
                        Text(
                          subtitle ?? track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Cristal.ui(12.5, weight: 500, color: p.text2),
                        ),
                      ],
                    ),
                  ),
                  if (current) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.play_arrow_rounded, size: 18, color: p.accent),
                  ],
                  if (duration > Duration.zero) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: Cristal.mono(12, color: p.text3, tracking: .02),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label, tooltip;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                Icon(icon, size: 18, color: p.text2),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Cristal.ui(13.5, weight: 500, color: p.text2),
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
