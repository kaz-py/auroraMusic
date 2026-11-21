import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../import/spotify_import.dart';

/// De dónde se importa: un enlace público o un archivo de datos de Spotify.
class SpotifyImportSource {
  const SpotifyImportSource.link(String this.link) : file = false;
  const SpotifyImportSource.file() : link = null, file = true;
  final String? link;
  final bool file;
}

class SpotifyImportSourceDialog extends StatefulWidget {
  const SpotifyImportSourceDialog({super.key});

  static Future<SpotifyImportSource?> show(BuildContext context) =>
      showDialog<SpotifyImportSource>(
        context: context,
        builder: (_) => const SpotifyImportSourceDialog(),
      );

  @override
  State<SpotifyImportSourceDialog> createState() =>
      _SpotifyImportSourceDialogState();
}

class _SpotifyImportSourceDialogState extends State<SpotifyImportSourceDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty) Navigator.pop(context, SpotifyImportSource.link(text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Importar de Spotify'),
    scrollable: true,
    content: SizedBox(
      width: math.min(MediaQuery.sizeOf(context).width * .78, 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pega el enlace de una playlist, álbum, artista o canción públicos '
            '(open.spotify.com/playlist/…). No hace falta iniciar sesión. '
            'Sin sesión Spotify deja leer hasta 100 canciones por lista; el '
            'audio no se importa, cada canción se empareja con YouTube.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('spotify-link-field'),
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Enlace de Spotify',
              hintText: 'https://open.spotify.com/playlist/…',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 16),
          const Text(
            'Para tus listas privadas o «Canciones que te gustan»: exporta tus '
            'datos desde Spotify → Cuenta → Privacidad y elige el archivo.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      TextButton(
        key: const ValueKey('spotify-pick-file'),
        onPressed: () =>
            Navigator.pop(context, const SpotifyImportSource.file()),
        child: const Text('Elegir archivo'),
      ),
      FilledButton(
        key: const ValueKey('spotify-import-link'),
        onPressed: _submit,
        child: const Text('Importar enlace'),
      ),
    ],
  );
}

class SpotifyImportDialog extends StatefulWidget {
  const SpotifyImportDialog({
    super.key,
    required this.result,
    required this.onImport,
  });

  final SpotifyImportResult result;
  final Future<bool> Function(List<SpotifyImportPlaylist>) onImport;

  static Future<void> show(
    BuildContext context, {
    required SpotifyImportResult result,
    required Future<bool> Function(List<SpotifyImportPlaylist>) onImport,
  }) => showDialog<void>(
    context: context,
    builder: (_) => SpotifyImportDialog(result: result, onImport: onImport),
  );

  @override
  State<SpotifyImportDialog> createState() => _SpotifyImportDialogState();
}

class _SpotifyImportDialogState extends State<SpotifyImportDialog> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.result.playlists.length; i++) i,
  };
  bool _importing = false;
  String? _importError;

  @override
  Widget build(BuildContext context) {
    final playlists = widget.result.playlists;
    final theme = Theme.of(context);
    final compactText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return AlertDialog(
      title: const Text('Importar listas de Spotify'),
      scrollable: true,
      content: SizedBox(
        width: math.min(MediaQuery.sizeOf(context).width * .78, 520),
        height: math.min(
          MediaQuery.sizeOf(context).height * (compactText ? .3 : .45),
          360,
        ),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Text(
                'Elige qué listas importar. Se copian los nombres y datos de las canciones; el audio no se importa.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (playlists.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('No se encontraron canciones importables.'),
                ),
              )
            else
              SliverList.builder(
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(index),
                    onChanged: _importing
                        ? null
                        : (selected) => setState(() {
                            if (selected == true) {
                              _selected.add(index);
                            } else {
                              _selected.remove(index);
                            }
                          }),
                    title: Text(
                      playlist.name.isEmpty
                          ? 'Lista sin nombre'
                          : playlist.name,
                    ),
                    subtitle: Text(
                      '${playlist.tracks.length} ${playlist.tracks.length == 1 ? 'canción' : 'canciones'}',
                    ),
                  );
                },
              ),
            if (widget.result.skipped > 0) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Text(
                  '${widget.result.skipped} elementos omitidos (podcasts, archivos locales o datos incompletos).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (_importError != null) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverToBoxAdapter(
                child: Text(
                  _importError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _importing || _selected.isEmpty
              ? null
              : () async {
                  setState(() => _importing = true);
                  final selected = [
                    for (var i = 0; i < playlists.length; i++)
                      if (_selected.contains(i)) playlists[i],
                  ];
                  try {
                    final imported = await widget.onImport(selected);
                    if (context.mounted && imported) Navigator.pop(context);
                    if (mounted && !imported) {
                      setState(
                        () => _importError =
                            'No se pudo guardar la importación. Inténtalo de nuevo.',
                      );
                    }
                  } finally {
                    if (mounted) setState(() => _importing = false);
                  }
                },
          child: _importing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  'Importar ${_selected.length} '
                  '${_selected.length == 1 ? 'lista' : 'listas'}',
                ),
        ),
      ],
    );
  }
}
