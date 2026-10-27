import 'package:flutter/material.dart';

import '../core/models.dart';

enum PlaylistSort {
  original('Orden de la lista'),
  titleAsc('A-Z'),
  titleDesc('Z-A'),
  artist('Artista'),
  recent('Agregadas recientemente');

  const PlaylistSort(this.label);
  final String label;
}

String _norm(String s) => s.toLowerCase().trim();

/// Pure view over a playlist: text search (title/artist), artist filter, sort.
/// shortcut: "recent" = reverse list order (the model stores no add date;
/// tracks are appended, so it is exact until the user reorders by hand).
List<Track> filterPlaylistTracks(
  List<Track> tracks, {
  String query = '',
  String? artist,
  PlaylistSort sort = PlaylistSort.original,
}) {
  final q = _norm(query);
  final a = artist == null ? null : _norm(artist);
  final out = [
    for (final t in tracks)
      if ((a == null || _norm(t.artist) == a) &&
          (q.isEmpty ||
              _norm(t.title).contains(q) ||
              _norm(t.artist).contains(q)))
        t,
  ];
  int byTitle(Track x, Track y) => _norm(x.title).compareTo(_norm(y.title));
  switch (sort) {
    case PlaylistSort.original:
      break;
    case PlaylistSort.recent:
      return out.reversed.toList();
    case PlaylistSort.titleAsc:
      out.sort(byTitle);
    case PlaylistSort.titleDesc:
      out.sort((x, y) => byTitle(y, x));
    case PlaylistSort.artist:
      out.sort((x, y) {
        final c = _norm(x.artist).compareTo(_norm(y.artist));
        return c != 0 ? c : byTitle(x, y);
      });
  }
  return out;
}

/// Distinct artists in first-seen order.
List<String> playlistArtists(List<Track> tracks) {
  final seen = <String, String>{};
  for (final t in tracks) {
    if (t.artist.trim().isNotEmpty) {
      seen.putIfAbsent(_norm(t.artist), () => t.artist);
    }
  }
  return seen.values.toList();
}

/// Search/sort/artist toolbar plus the body. [builder] gets the visible tracks
/// and whether manual reordering is safe (no filter or sort applied).
class PlaylistDetailTools extends StatefulWidget {
  const PlaylistDetailTools({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.builder,
    this.header,
  });
  final List<Track> tracks;
  final void Function(List<Track> visible) onPlay;
  final Widget Function(List<Track> visible, bool canReorder) builder;

  /// Cabecera de la lista; sigue visible cuando el filtro no deja canciones.
  final Widget? header;

  @override
  State<PlaylistDetailTools> createState() => _PlaylistDetailToolsState();
}

class _PlaylistDetailToolsState extends State<PlaylistDetailTools> {
  String _query = '';
  String? _artist;
  PlaylistSort _sort = PlaylistSort.original;

  @override
  Widget build(BuildContext context) {
    final artists = playlistArtists(widget.tracks);
    // The chosen artist may vanish after removing tracks.
    final artist = artists.any((a) => _norm(a) == _norm(_artist ?? ''))
        ? _artist
        : null;
    final visible = filterPlaylistTracks(
      widget.tracks,
      query: _query,
      artist: artist,
      sort: _sort,
    );
    final plain =
        _query.isEmpty && artist == null && _sort == PlaylistSort.original;
    return LayoutBuilder(
      builder: (context, box) => Column(
        children: [
          // La barra no pasa del 40% del alto disponible y se desplaza.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: box.maxHeight * 0.4),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: visible.isEmpty
                        ? null
                        : () => widget.onPlay(visible),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(plain ? 'Reproducir' : 'Reproducir vista'),
                  ),
                  if (artist != null)
                    OutlinedButton.icon(
                      onPressed: visible.isEmpty
                          ? null
                          : () => widget.onPlay(visible),
                      icon: const Icon(Icons.person),
                      label: Text('Reproducir solo $artist'),
                    ),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar título o artista',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  if (artists.length > 1)
                    PopupMenuButton<String>(
                      tooltip: artist == null
                          ? 'Filtrar por artista'
                          : 'Artista: $artist',
                      onSelected: (v) =>
                          setState(() => _artist = v.isEmpty ? null : v),
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: '', child: Text('Todos')),
                        for (final a in artists)
                          PopupMenuItem(value: a, child: Text(a)),
                      ],
                      icon: Icon(
                        artist == null ? Icons.person_outline : Icons.person,
                      ),
                    ),
                  PopupMenuButton<PlaylistSort>(
                    tooltip: 'Ordenar',
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (_) => [
                      for (final s in PlaylistSort.values)
                        PopupMenuItem(value: s, child: Text(s.label)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.sort, size: 18),
                      label: Text(_sort.label),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? widget.header == null
                      ? const Center(child: Text('Ninguna canción coincide'))
                      : ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            widget.header!,
                            const SizedBox(
                              height: 200,
                              child: Center(
                                child: Text('Ninguna canción coincide'),
                              ),
                            ),
                          ],
                        )
                : widget.builder(visible, plain),
          ),
        ],
      ),
    );
  }
}
