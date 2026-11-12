import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/modern_widgets.dart';
import '../brand/aurora_logo.dart';
import '../mini_player/song_card.dart';
import 'shell_chrome.dart';
import 'shell_sections.dart';

/// Cabecera de página compartida (título de sección + acciones + menú «Más
/// vistas» en móvil). [modern] activa el titular de Modern/Slush;
/// [playerMoreActions] muestra «Más acciones» en el reproductor móvil.
class ShellHeaderBar extends StatelessWidget {
  const ShellHeaderBar({
    super.key,
    required this.scope,
    required this.modern,
    this.playerMoreActions = true,
  });
  final ShellScope scope;
  final bool modern, playerMoreActions;

  Widget _modernTitle(String title) {
    final words = title.split(' ');
    final (before, emphasis) = scope.section == 0 && scope.playlist == null
        ? ('Tu ', 'música')
        : scope.playlist != null || words.length < 2
        ? (title, '')
        : ('${words.sublist(0, words.length - 1).join(' ')} ', words.last);
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ModernHeadline(before: before, emphasis: emphasis, size: 28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    final rail = scope.rail;
    return Padding(
      padding: rail
          ? EdgeInsets.fromLTRB(32, modern ? 28 : 18, 32, modern ? 20 : 12)
          : const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          if (!rail) ...[const AuroraLogo(size: 28), const SizedBox(width: 10)],
          Expanded(
            child: !rail && modern
                ? const SizedBox.shrink()
                : modern
                ? _modernTitle(
                    (scope.playlist == null
                            ? null
                            : c.playlists
                                  .where((p) => p.id == scope.playlist!.id)
                                  .firstOrNull
                                  ?.name) ??
                        shellSectionTitles[scope.section]!,
                  )
                : Text(
                    (scope.playlist == null
                            ? null
                            : c.playlists
                                  .where((p) => p.id == scope.playlist!.id)
                                  .firstOrNull
                                  ?.name) ??
                        shellSectionTitles[scope.section]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          if (rail)
            IconButton(
              tooltip: 'Importar archivos de audio',
              onPressed: c.ready ? c.importFiles : null,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          if (scope.section != 1)
            IconButton(
              tooltip: 'Buscar música',
              onPressed: () => scope.onNavigate(1),
              icon: const Icon(Icons.search),
            ),
          if (!rail)
            IconButton(
              tooltip: 'Ajustes',
              onPressed: () => scope.onNavigate(7),
              icon: const Icon(Icons.tune),
            ),
          if (!rail &&
              scope.section == 4 &&
              playerMoreActions &&
              c.nowTrack != null)
            Builder(
              builder: (b) => IconButton(
                tooltip: 'Más acciones',
                icon: const Icon(Icons.more_vert_rounded),
                onPressed: () {
                  final box = b.findRenderObject() as RenderBox;
                  showSongCard(
                    context,
                    c,
                    c.nowTrack!,
                    box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                    openQueue: () => scope.onNavigate(5),
                  );
                },
              ),
            ),
          if (!rail)
            PopupMenuButton<int>(
              tooltip: 'Más vistas',
              icon: Badge(
                isLabelVisible: scope.friendsBadge > 0,
                label: Text('${scope.friendsBadge}'),
                child: const Icon(Icons.more_horiz),
              ),
              onSelected: (v) => v == -1
                  ? (c.ready ? c.importFiles() : null)
                  : scope.onNavigate(v),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: -1,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.create_new_folder_outlined),
                    title: Text('Importar archivos'),
                  ),
                ),
                PopupMenuItem(
                  value: 12,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.mic_none_rounded),
                    title: Text('Artistas'),
                  ),
                ),
                PopupMenuItem(
                  value: 11,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.video_file_outlined),
                    title: Text('Descargar vídeos'),
                  ),
                ),
                PopupMenuItem(
                  value: 9,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.groups_outlined),
                    title: Text('Jam'),
                  ),
                ),
                if (supabaseServicesEnabled)
                  PopupMenuItem(
                    value: 14,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Badge(
                        isLabelVisible: scope.friendsBadge > 0,
                        label: Text('${scope.friendsBadge}'),
                        child: const Icon(Icons.people_outline),
                      ),
                      title: const Text('Amigos'),
                    ),
                  ),
                PopupMenuItem(
                  value: 4,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.album_outlined),
                    title: Text('Modo Vinilo'),
                  ),
                ),
                PopupMenuItem(
                  value: 5,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.queue_music),
                    title: Text('Cola de reproducción'),
                  ),
                ),
                PopupMenuItem(
                  value: 6,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lyrics_outlined),
                    title: Text('Letras'),
                  ),
                ),
                PopupMenuItem(
                  value: 13,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.equalizer),
                    title: Text('Ecualizador'),
                  ),
                ),
              ],
            ),
          if (rail)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: modern
                  ? ModernBadge(scope.shortcuts.labelOf(ShortcutId.searchFocus))
                  : Text(
                      scope.shortcuts.labelOf(ShortcutId.searchFocus),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
