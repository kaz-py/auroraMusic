import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../theme/slush_theme.dart';
import '../artwork.dart';
import '../undo_snackbar.dart';
import 'jam_session_panel.dart';
import 'jam_widgets.dart';

Future<void> showJamAddSheet(BuildContext context, JamController jam) {
  final height = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: jamSheetShape(context),
    constraints: BoxConstraints(maxWidth: 640, maxHeight: height * .9),
    builder: (_) => JamAddSheet(jam: jam),
  );
}

/// «Añadir a la Jam»: recomendado para el grupo, búsqueda, playlists y favoritos.
class JamAddSheet extends StatefulWidget {
  const JamAddSheet({super.key, required this.jam});
  final JamController jam;
  @override
  State<JamAddSheet> createState() => _JamAddSheetState();
}

class _JamAddSheetState extends State<JamAddSheet> {
  final _query = TextEditingController();
  JamController get jam => widget.jam;

  @override
  void initState() {
    super.initState();
    jam.refreshSuggestions();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _say(String text) =>
      showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));

  void _addOne(Track t) {
    final ok = jam.addTracks([t]);
    _say(
      ok ? '«${t.title}» añadida a la Jam.' : jam.error ?? 'No se pudo añadir.',
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 4,
    child: AnimatedBuilder(
      animation: jam,
      builder: (context, _) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Añadir a la Jam',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          if (!jam.canAdd)
            Padding(
              padding: const EdgeInsets.all(16),
              child: jamNotice(
                context,
                jam.error ??
                    'Ahora mismo no puedes añadir canciones a esta Jam.',
                Icons.lock_outline,
              ),
            ),
          _progress(context),
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Recomendado'),
              Tab(text: 'Buscar'),
              Tab(text: 'Mis playlists'),
              Tab(text: 'Favoritos y recientes'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _recommended(context),
                _search(context),
                _playlists(context),
                _library(context),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _progress(
    BuildContext context,
  ) => ValueListenableBuilder<JamAddProgress>(
    valueListenable: jam.addProgress,
    builder: (context, p, _) {
      if (!p.running && p.message == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.running) ...[
              LinearProgressIndicator(
                value: p.total > 0 ? p.done / p.total : null,
              ),
              const SizedBox(height: 4),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.running
                        ? 'Añadiendo ${p.done} de ${p.total}… (por lotes, para no saturar la Jam)'
                        : p.message!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (p.running)
                  TextButton(
                    onPressed: jam.cancelAdd,
                    child: const Text('Cancelar'),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _empty(String text, IconData icon, {Widget? action}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    ),
  );

  Widget _recommended(BuildContext context) {
    final items = jam.groupSuggestions;
    if (items.isEmpty) {
      return _empty(
        'Aún no hay recomendaciones. Cuando haya más gente, Aurora mezcla lo que le gusta a cada quien.',
        Icons.auto_awesome,
        action: OutlinedButton.icon(
          onPressed: jam.refreshSuggestions,
          icon: const Icon(Icons.refresh),
          label: const Text('Buscar recomendaciones'),
        ),
      );
    }
    return ListView(
      children: [
        for (final s in items)
          ListTile(
            leading: Artwork(
              track: jamTrackAsTrack(s.track),
              artworkContext: ArtworkContext.thumbnail,
              radius: isSlush(context) ? SlushRadius.r8 : 4,
            ),
            title: Text(
              s.track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Row(
              children: [
                JamAvatar(
                  name: s.forName,
                  size: 18,
                  image: jam.avatarOf(s.forId),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${s.track.artist} · ${s.reason}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              tooltip: 'Añadir ${s.track.title} a la cola',
              onPressed: jam.canAdd ? () => jam.addSuggestion(s) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ),
      ],
    );
  }

  Widget _trackTile(Track t) => ListTile(
    leading: Artwork(
      track: t,
      artworkContext: ArtworkContext.thumbnail,
      radius: isSlush(context) ? SlushRadius.r8 : 4,
    ),
    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: IconButton(
      tooltip: 'Añadir ${t.title} a la Jam',
      onPressed: jam.canAdd ? () => _addOne(t) : null,
      icon: const Icon(Icons.add_circle_outline),
    ),
  );

  Widget _search(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _query,
          textInputAction: TextInputAction.search,
          onSubmitted: jam.search,
          decoration: InputDecoration(
            labelText: 'Buscar canciones',
            hintText: 'Título, artista o álbum',
            suffixIcon: IconButton(
              tooltip: 'Buscar',
              onPressed: jam.searching ? null : () => jam.search(_query.text),
              icon: const Icon(Icons.search),
            ),
          ),
        ),
      ),
      if (jam.searching) const LinearProgressIndicator(),
      Expanded(
        child: jam.results.isEmpty
            ? _empty(
                jam.searching
                    ? 'Buscando…'
                    : _query.text.trim().isEmpty
                    ? 'Escribe lo que quieras escuchar y pulsa Intro.'
                    : 'No encontramos canciones para esa búsqueda.',
                Icons.search,
              )
            : ListView(children: [for (final t in jam.results) _trackTile(t)]),
      ),
    ],
  );

  Widget _playlists(BuildContext context) {
    final lists = jam.app.playlists;
    if (lists.isEmpty) {
      return _empty(
        'Aún no tienes playlists. Crea una desde tu biblioteca y podrás meterla entera en la Jam.',
        Icons.library_music_outlined,
      );
    }
    return ListView(
      children: [for (final p in lists) _playlistTile(context, p)],
    );
  }

  Widget _playlistTile(BuildContext context, MusicPlaylist p) {
    final byId = {for (final t in jam.app.tracks) t.id: t};
    final tracks = [
      for (final id in p.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
    final busy = jam.addProgress.value.running;
    void run(JamAddMode mode, String label) {
      jam.addPlaylist(p, mode: mode);
      _say('$label: «${p.name}»');
    }

    return ExpansionTile(
      leading: const Icon(Icons.queue_music),
      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${tracks.length} canciones'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tracks.isEmpty)
          const Text('Esta playlist no tiene canciones disponibles.')
        else ...[
          for (final t in tracks.take(5))
            Text(
              '• ${t.title} — ${t.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          if (tracks.length > 5)
            Text(
              'y ${tracks.length - 5} más',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 4),
          Text(
            tracks.length > 5
                ? 'Se añadirán por lotes y se respetan los topes de la Jam.'
                : 'Se respetan los topes de la Jam.',
            style: TextStyle(
              fontSize: isSlush(context) ? 12 : 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: !jam.canAdd || busy
                    ? null
                    : () => run(JamAddMode.end, 'Añadiendo al final'),
                icon: const Icon(Icons.playlist_add),
                label: const Text('Añadir al final'),
              ),
              if (jam.isHost)
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(JamAddMode.playNow, 'Reproduciendo'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Reproducir ahora'),
                ),
              OutlinedButton.icon(
                onPressed: !jam.canAdd || busy
                    ? null
                    : () => run(JamAddMode.shuffle, 'Mezclando'),
                icon: const Icon(Icons.shuffle),
                label: const Text('Mezclar'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _library(BuildContext context) {
    final byId = {for (final t in jam.app.tracks) t.id: t};
    final favorites = [
      for (final id in jam.app.favoriteIds)
        if (byId[id] != null) byId[id]!,
    ];
    final recents = jam.app.recentTracks.take(30).toList();
    if (favorites.isEmpty && recents.isEmpty) {
      return _empty(
        'Todavía no hay favoritos ni reproducciones recientes. Escucha algo y volverá aquí.',
        Icons.history,
      );
    }
    Widget head(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(t, style: Theme.of(context).textTheme.titleSmall),
    );
    return ListView(
      children: [
        if (favorites.isNotEmpty) ...[
          head('Favoritos'),
          for (final t in favorites.take(30)) _trackTile(t),
        ],
        if (recents.isNotEmpty) ...[
          head('Recientes'),
          for (final t in recents) _trackTile(t),
        ],
      ],
    );
  }
}
