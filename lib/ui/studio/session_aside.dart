import 'package:flutter/material.dart';
import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../artwork.dart';
import '../jam/jam_flows.dart';
import '../jam/jam_add_sheet.dart';
import '../jam/jam_qr_code.dart';
import '../jam/jam_widgets.dart';
import '../right_panel/right_panel_theme.dart';
import 'equalizer_panel.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

class StudioSessionAside extends StatelessWidget {
  const StudioSessionAside({
    super.key,
    required this.controller,
    required this.onJam,
    required this.onQueue,
    this.jam,
    this.onStartJam,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onJam, onQueue;
  final VoidCallback? onStartJam;
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final session = jam?.service;
    final connected = session?.connected == true;
    final colors = Theme.of(context).colorScheme;
    final personal = c.queue.skip(c.queueIndex + 1).take(3).toList();
    final shared = connected
        ? session!.queue
              .where((e) => e.id != jam!.bridge.currentEntryId)
              .take(3)
              .toList()
        : null;
    final theme = rightPanelThemeOf(context);
    final panel = theme.asidePanel;
    final titleFont = theme.asideTitleFont;
    final titleWeight = theme.asideTitleWeight;
    return SizedBox(
      width: 340,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 24, 24),
        children: [
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 10,
                      color: connected
                          ? colors.primaryContainer
                          : colors.outline,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        connected
                            ? 'Sesión Compartida Activa'
                            : 'Sesión Compartida',
                        style: TextStyle(
                          fontFamily: titleFont,
                          fontSize: 16,
                          fontWeight: titleWeight,
                        ),
                      ),
                    ),
                    StudioStamp(
                      connected
                          ? '${session!.participants.where((p) => p.connected).length} OYENTES'
                          : 'SIN JAM',
                      filled: true,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  connected
                      ? 'Todos pueden añadir canciones a la cola. Invita con el QR o el código.'
                      : 'Escuchen juntos: inicia una Jam y comparte el QR. Cada quien añade sus canciones.',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                StudioPanel(
                  recessed: true,
                  padding: const EdgeInsets.all(16),
                  child: connected && session?.invite != null && session!.isHost
                      ? Row(
                          children: [
                            JamQrCode(data: session.invite!.encode(), size: 96),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const StudioStamp('ENLACE DIRECTO WEBSOCKET'),
                                  const SizedBox(height: 8),
                                  Text(
                                    session.invite!.endpoint,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Acceso temporal en el QR',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        showJamInviteSheet(context, jam!),
                                    icon: const Icon(
                                      StudioSymbols.share,
                                      size: 14,
                                    ),
                                    label: const Text(
                                      'Invitar',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              StudioSymbols.wifiTethering,
                              size: 40,
                              color: colors.primary,
                            ),
                            const SizedBox(height: 12),
                            if (connected) ...[
                              JamAvatarStack(
                                names: [
                                  for (final p in session!.participants)
                                    if (p.connected) p.name,
                                ],
                                size: 28,
                                max: 6,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${jam!.roleLabel} · ${jam!.modeLabel}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () =>
                                        showJamInviteSheet(context, jam!),
                                    icon: const Icon(
                                      StudioSymbols.share,
                                      size: 16,
                                    ),
                                    label: const Text('Invitar'),
                                  ),
                                  TextButton.icon(
                                    onPressed: jam!.canAdd
                                        ? () => showJamAddSheet(context, jam!)
                                        : null,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Añadir música'),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Text(
                                'Aún no hay una Jam activa.',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: onStartJam ?? onJam,
                                icon: const Icon(
                                  StudioSymbols.groups,
                                  size: 16,
                                ),
                                label: const Text('Iniciar una Jam'),
                              ),
                              TextButton(
                                onPressed: onJam,
                                child: const Text('Unirme con un código'),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                StudioStamp(
                  connected
                      ? (session!.mode.name == 'synchronized'
                            ? 'MODO: REPRODUCCIÓN SINCRONIZADA'
                            : 'MODO: COLA COMPARTIDA')
                      : 'SESIÓN TEMPORAL EN TU RED LOCAL',
                ),
              ],
            ),
          ),
          SizedBox(height: theme.asideSectionGap),
          panel(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(StudioSymbols.queueMusic, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'En Cola (Próximas ${shared?.length ?? personal.length})',
                        style: TextStyle(
                          fontFamily: titleFont,
                          fontSize: 16,
                          fontWeight: theme.asideQueueTitleWeight,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: onQueue,
                      child: const Text(
                        'Ver todo',
                        style: TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if ((shared?.isEmpty ?? personal.isEmpty))
                  const Text(
                    'La cola está vacía',
                    style: TextStyle(fontSize: 12),
                  ),
                if (shared != null)
                  for (final (index, entry) in shared.indexed)
                    _queueItem(
                      context,
                      Track(
                        id: entry.track.key,
                        title: entry.track.title,
                        artist: entry.track.artist,
                        artworkUrl: entry.track.artworkUrl,
                        duration: Duration(
                          milliseconds: entry.track.durationMs,
                        ),
                      ),
                      index,
                      'Por ${session!.participantName(entry.addedBy)}',
                      onJam,
                    )
                else
                  for (final (index, track) in personal.indexed)
                    _queueItem(
                      context,
                      track,
                      index,
                      track.artist,
                      () => c.playQueueAt(c.queue.indexOf(track)),
                    ),
              ],
            ),
          ),
          SizedBox(height: theme.asideSectionGap),
          panel(EqualizerPanel(controller: c)),
        ],
      ),
    );
  }

  Widget _queueItem(
    BuildContext context,
    Track track,
    int index,
    String subtitle,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: action,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              StudioStamp((index + 1).toString().padLeft(2, '0')),
              const SizedBox(width: 8),
              Artwork(
                track: track,
                artworkContext: ArtworkContext.thumbnailCompact,
                radius: 2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StudioStamp(
                track.duration > Duration.zero
                    ? studioTime(track.duration)
                    : '—',
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
