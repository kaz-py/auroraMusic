import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../core/models.dart';
import '../theme/slush_theme.dart';

class OfflineSettingsPanel extends StatelessWidget {
  const OfflineSettingsPanel({
    super.key,
    required this.controller,
    required this.onManage,
    required this.onSearch,
  });
  final AppController controller;
  final VoidCallback onManage, onSearch;

  Future<void> _chooseTrack(BuildContext context) async {
    final tracks = <String, Track>{
      for (final track in [
        ...controller.tracks,
        ...controller.recentTracks,
        ...controller.searchResults,
      ])
        if (controller.canDownloadTrack(track)) track.id: track,
    }.values.toList();
    if (tracks.isEmpty) {
      onSearch();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _OfflineTrackPicker(
        tracks: tracks,
        onDownload: controller.downloadTrack,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Descargar guarda una copia para escuchar sin conexión. Solo se inicia cuando lo solicitas; reproducir una canción no añade una descarga.',
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: () => _chooseTrack(context),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Descargar una canción'),
          ),
          OutlinedButton.icon(
            onPressed: onManage,
            icon: const Icon(Icons.offline_pin_outlined),
            label: const Text('Gestionar descargas'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${controller.downloads.where((job) => job.status == DownloadStatus.completed).length} canciones descargadas · Puedes ver el progreso, cancelar y reproducir archivos locales en Descargas.',
      ),
    ],
  );
}

class _OfflineTrackPicker extends StatefulWidget {
  const _OfflineTrackPicker({required this.tracks, required this.onDownload});
  final List<Track> tracks;
  final Future<void> Function(Track) onDownload;
  @override
  State<_OfflineTrackPicker> createState() => _OfflineTrackPickerState();
}

class _OfflineTrackPickerState extends State<_OfflineTrackPicker> {
  String query = '';
  bool submitting = false;
  @override
  Widget build(BuildContext context) {
    final matches = widget.tracks
        .where(
          (track) => '${track.title} ${track.artist}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    final slush = isSlush(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: slush ? 560 : double.infinity,
            maxHeight: MediaQuery.sizeOf(context).height * .65,
          ),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Descargar para escuchar sin conexión',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Filtrar canciones',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: matches.isEmpty
                      ? Center(
                          child: Text(
                            'No hay canciones que coincidan.',
                            style: slush
                                ? TextStyle(color: context.slush.ink2)
                                : null,
                          ),
                        )
                      : ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final track = matches[index];
                            return ListTile(
                              minTileHeight: 56,
                              title: Text(track.title),
                              subtitle: Text(
                                track.artist,
                                style: slush
                                    ? TextStyle(color: context.slush.ink2)
                                    : null,
                              ),
                              trailing: const Icon(Icons.download_outlined),
                              enabled: !submitting,
                              onTap: () async {
                                setState(() => submitting = true);
                                await widget.onDownload(track);
                                if (context.mounted) Navigator.pop(context);
                              },
                            );
                          },
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
