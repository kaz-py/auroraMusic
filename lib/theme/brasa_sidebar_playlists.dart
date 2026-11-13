import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../ui/playlist_views/playlist_cover.dart';
import '../ui/playlist_views/playlist_photo_menu.dart';
import '../ui/playlist_views/playlist_view_mode.dart';
import 'brasa_theme.dart';
import 'brasa_widgets.dart';

/// Muestras de color de las listas (brasa, ámbar, óxido, arcilla).
const _swatches = [
  Brasa.ember,
  Brasa.amber,
  Color(0xffb3401f),
  Color(0xff9c7b5c),
];

/// Sección «ÁNIMOS & COLECCIONES» de la sidebar Brasa: etiqueta con punto de
/// brasa y botón de crear, buscador (solo con listas suficientes) y una fila
/// por lista con su muestra de color (o su foto). No hace scroll propio: va
/// dentro de la lista de la sidebar.
class BrasaSidebarPlaylists extends StatefulWidget {
  const BrasaSidebarPlaylists({
    super.key,
    required this.controller,
    required this.onPlaylist,
    this.onCreate,
  });
  final AppController controller;
  final ValueChanged<MusicPlaylist> onPlaylist;
  final VoidCallback? onCreate;

  @override
  State<BrasaSidebarPlaylists> createState() => _BrasaSidebarPlaylistsState();
}

class _BrasaSidebarPlaylistsState extends State<BrasaSidebarPlaylists> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = [...widget.controller.playlists];
    // «Me gusta» siempre primero.
    all.sort((a, b) {
      int rank(MusicPlaylist p) =>
          p.name.trim().toLowerCase() == 'me gusta' ? 0 : 1;
      return rank(a).compareTo(rank(b));
    });
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((p) => p.name.toLowerCase().contains(q)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrasaSectionLabel(
          'Ánimos & colecciones',
          trailing: widget.onCreate == null
              ? null
              : IconButton(
                  tooltip: 'Crear lista',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onCreate,
                  icon: const Icon(Icons.add, size: 20, color: Brasa.cloud),
                ),
        ),
        if (all.length > 5)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              style: Brasa.sans(13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar en listas',
                hintStyle: Brasa.sans(13, color: Brasa.steel),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Brasa.steel,
                ),
                filled: true,
                fillColor: Brasa.graphite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              all.isEmpty ? 'Aún no hay listas' : 'Sin resultados',
              style: Brasa.sans(12, color: Brasa.steel),
            ),
          )
        else
          for (final p in list)
            PlaylistPhotoMenu(
              controller: widget.controller,
              playlist: p,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  hoverColor: Brasa.graphite,
                  onTap: () => widget.onPlaylist(p),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          _Swatch(
                            playlist: p,
                            controller: widget.controller,
                            color:
                                _swatches[p.id.hashCode.abs() %
                                    _swatches.length],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Brasa.sans(
                                14,
                                weight: FontWeight.w500,
                                color: Brasa.cloud,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

/// Muestra de 26 px: foto de la lista si la tiene, si no un color.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.playlist,
    required this.controller,
    required this.color,
  });
  final MusicPlaylist playlist;
  final AppController controller;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (playlist.photoPath == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const SizedBox.square(dimension: 26),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: PlaylistCover(
        playlist: playlist,
        tracks: playlistCoverTracks(controller, playlist),
        size: 26,
      ),
    );
  }
}
