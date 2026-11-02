import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../dj/recommendations.dart';

class DjFiltersPanel extends StatelessWidget {
  const DjFiltersPanel({super.key, required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final filters = controller.djFilters;
    final artists =
        controller.tracks
            .map((t) => t.artist)
            .where((a) => a.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final genres =
        controller.tracks
            .expand((t) => t.genres)
            .where((g) => g.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: const Icon(Icons.filter_list),
      title: const Text('Personalizar el DJ'),
      subtitle: Text(
        '${filters.artists.length + filters.trackIds.length + filters.genres.length + filters.excludedArtists.length + filters.excludedTrackIds.length + filters.excludedGenres.length} filtros activos',
      ),
      childrenPadding: const EdgeInsets.all(8),
      children: [
        const Text(
          'El DJ combina los filtros. Sin selección, incluye toda tu biblioteca. Las canciones ya en cola se mantienen.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.person_outline),
              label: const Text('Artistas'),
              onPressed: () async {
                final selected = await choose(context, 'Artistas del DJ', {
                  for (final a in artists) a: a,
                }, filters.artists);
                if (selected != null) {
                  await controller.setDjFilters(
                    DjFilters(
                      excludedArtists: filters.excludedArtists,
                      excludedTrackIds: filters.excludedTrackIds,
                      excludedGenres: filters.excludedGenres,
                      artists: selected,
                      trackIds: filters.trackIds,
                      genres: filters.genres,
                    ),
                  );
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.music_note_outlined),
              label: const Text('Canciones'),
              onPressed: () async {
                final selected = await choose(context, 'Canciones del DJ', {
                  for (final t in controller.tracks)
                    t.id: '${t.title} · ${t.artist}',
                }, filters.trackIds);
                if (selected != null) {
                  await controller.setDjFilters(
                    DjFilters(
                      excludedArtists: filters.excludedArtists,
                      excludedTrackIds: filters.excludedTrackIds,
                      excludedGenres: filters.excludedGenres,
                      artists: filters.artists,
                      trackIds: selected,
                      genres: filters.genres,
                    ),
                  );
                }
              },
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.category_outlined),
              label: const Text('Géneros'),
              onPressed: genres.isEmpty
                  ? null
                  : () async {
                      final selected = await choose(context, 'Géneros del DJ', {
                        for (final g in genres) g: g,
                      }, filters.genres);
                      if (selected != null) {
                        await controller.setDjFilters(
                          DjFilters(
                            excludedArtists: filters.excludedArtists,
                            excludedTrackIds: filters.excludedTrackIds,
                            excludedGenres: filters.excludedGenres,
                            artists: filters.artists,
                            trackIds: filters.trackIds,
                            genres: selected,
                          ),
                        );
                      }
                    },
            ),
            TextButton(
              onPressed: () => controller.setDjFilters(const DjFilters()),
              child: const Text('Quitar filtros'),
            ),
          ],
        ),
        if (genres.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Tu biblioteca todavía no tiene géneros. Solo usamos los metadatos disponibles.',
            ),
          ),
      ],
    );
  }

  static Future<List<String>?> choose(
    BuildContext context,
    String title,
    Map<String, String> options,
    List<String> current,
  ) {
    final selected = current.toSet();
    return showDialog<List<String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: SizedBox(
            width: 420,
            height: math.min(320, MediaQuery.sizeOf(context).height * .5),
            child: options.isEmpty
                ? const Center(
                    child: Text('Añade canciones para elegir tus filtros.'),
                  )
                : ListView(
                    children: options.entries
                        .map(
                          (entry) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value),
                            value: selected.contains(entry.key),
                            onChanged: (value) => setState(
                              () => value == true
                                  ? selected.add(entry.key)
                                  : selected.remove(entry.key),
                            ),
                          ),
                        )
                        .toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selected.toList()),
              child: const Text('Aplicar filtros'),
            ),
          ],
        ),
      ),
    );
  }
}
