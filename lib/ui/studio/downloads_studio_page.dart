import 'dart:async';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../library/local_file_metadata.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../slush/slush_decor.dart';
import '../slush/slush_pages.dart';
import '../artwork.dart';
import '../undo_snackbar.dart';
import 'studio_symbols.dart';

class DownloadsStudioPage extends StatefulWidget {
  const DownloadsStudioPage({super.key, required this.controller});
  final AppController controller;
  @override
  State<DownloadsStudioPage> createState() => _DownloadsStudioPageState();
}

class _DownloadsStudioPageState extends State<DownloadsStudioPage> {
  Map<String, int> _sizes = {};
  String? _sizeSignature;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncSizes);
    _syncSizes();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncSizes);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DownloadsStudioPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncSizes);
      widget.controller.addListener(_syncSizes);
      _sizeSignature = null;
      _syncSizes();
    }
  }

  void _syncSizes() {
    final paths =
        widget.controller.downloads
            .where((j) => j.status == DownloadStatus.completed)
            .map((j) => j.localPath ?? j.track.localPath)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort();
    final signature = widget.controller.downloads
        .map(
          (j) => '${j.id}|${j.localPath ?? j.track.localPath}|${j.status.name}',
        )
        .join('\u0000');
    if (signature == _sizeSignature) return;
    _sizeSignature = signature;
    unawaited(
      localFileSizes(paths).then((sizes) {
        if (mounted && signature == _sizeSignature) {
          setState(() => _sizes = sizes);
        }
      }),
    );
  }

  String _bytes(int size) => size >= 1024 * 1024
      ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
      : size >= 1024
      ? '${(size / 1024).toStringAsFixed(1)} KB'
      : '$size B';
  String _size(DownloadJob job) {
    final size = _sizes[job.localPath ?? job.track.localPath];
    return size == null ? 'No medido' : _bytes(size);
  }

  int _tab = 0;
  String _filter = '';
  void _pending(String feature) => showUndoSnackBar(
    ScaffoldMessenger.maybeOf(context),
    Text('$feature: no implementado todavía.'),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final c = widget.controller;
        final complete = c.downloads
            .where((j) => j.status == DownloadStatus.completed)
            .toList();
        final active = c.downloads
            .where(
              (j) =>
                  j.status == DownloadStatus.queued ||
                  j.status == DownloadStatus.downloading,
            )
            .toList();
        final conflicts = c.downloads
            .where(
              (j) =>
                  j.status == DownloadStatus.failed ||
                  j.status == DownloadStatus.cancelled,
            )
            .toList();
        final rows =
            (_tab == 0
                    ? complete
                    : _tab == 1
                    ? active
                    : conflicts)
                .where(
                  (j) => '${j.track.title} ${j.track.artist} ${_format(j)}'
                      .toLowerCase()
                      .contains(_filter.toLowerCase()),
                )
                .toList();
        // Slush: relleno menta (tema) y etiqueta de tinta; blanco sobre menta no se lee.
        Widget tabChip(int tab, String label) {
          final brasa = isBrasa(context);
          final slush = isSlush(context);
          final modern = isModern(context) && !slush;
          final selected = _tab == tab;
          if (slush) {
            return SlushChip(
              label,
              color: context.slush.paper,
              selected: selected,
              onTap: () => setState(() => _tab = tab),
            );
          }
          return ChoiceChip(
            showCheckmark: !isModern(context) && !brasa,
            selectedColor: brasa
                ? Brasa.cream
                : modern
                ? Tracky.navy
                : null,
            shape: slush
                ? null
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      brasa
                          ? 9999
                          : modern
                          ? 8
                          : 4,
                    ),
                  ),
            label: Text(label),
            selected: selected,
            labelStyle: brasa && selected
                ? const TextStyle(color: Colors.black)
                : modern && selected
                ? const TextStyle(color: Colors.white)
                : null,
            onSelected: (_) => setState(() => _tab = tab),
          );
        }

        final desktop =
            constraints.maxWidth >= 960 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.5;
        return ListView(
          padding: EdgeInsets.all(
            isSlush(context)
                ? SlushSpacing.margin(constraints.maxWidth)
                : constraints.maxWidth < 600
                ? 16
                : 24,
          ),
          children: [
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONSOLA DE DEPÓSITO LOCAL  /  MATRIZ DE BLOQUES DE AUDIO',
                    style: _stamp(color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Depósito Local & Archivo Físico',
                        style: isSlush(context)
                            ? slushHeadline(
                                26,
                                height: 1.15,
                                color: context.slush.ink,
                              )
                            : const TextStyle(
                                fontFamily: 'Newsreader',
                                fontSize: 36,
                                height: 1.2,
                              ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                c.canConfigureDownloadDirectory &&
                                    !c.configuringDownloadDirectory
                                ? c.chooseDownloadDirectory
                                : null,
                            icon: const Icon(
                              StudioSymbols.driveFileMove,
                              size: 18,
                            ),
                            label: Text(
                              c.configuringDownloadDirectory
                                  ? 'Abriendo selector…'
                                  : 'Cambiar carpeta',
                            ),
                          ),
                          FilledButton.icon(
                            style: isSlush(context)
                                ? FilledButton.styleFrom(
                                    backgroundColor: Slush.mint,
                                    foregroundColor: Slush.ink,
                                    minimumSize: const Size(
                                      SlushControl.touch,
                                      SlushControl.touch,
                                    ),
                                    side: context.slush.border,
                                  )
                                : null,
                            onPressed: c.openDownloadDirectory,
                            icon: const Icon(StudioSymbols.folder, size: 18),
                            label: Text(
                              c.canConfigureDownloadDirectory
                                  ? 'Explorador Windows'
                                  : 'Abrir carpeta',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _well(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Carpeta de descargas',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          c.downloadsDirectoryPath,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Los cambios se aplican a las próximas descargas.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _well(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 24,
                          runSpacing: 8,
                          children: [
                            Text(
                              '${_sizes.isEmpty ? 'Tamaño no medido' : '${_bytes(_sizes.values.fold(0, (sum, size) => sum + size))} medidos'} · ${complete.length} archivos descargados',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text('${active.length} en progreso'),
                            Text('${conflicts.length} requieren atención'),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            isSlush(context)
                                ? SlushRadius.pill
                                : isBrasa(context)
                                ? 9999
                                : isModern(context)
                                ? 8
                                : 3,
                          ),
                          child: LinearProgressIndicator(
                            value: c.downloads.isEmpty
                                ? 0
                                : complete.length / c.downloads.length,
                            minHeight: isSlush(context)
                                ? 6
                                : isBrasa(context)
                                ? 4
                                : 10,
                            color: isSlush(context)
                                ? Slush.mint
                                : isBrasa(context)
                                ? Brasa.cream
                                : isModern(context)
                                ? Tracky.mint
                                : Theme.of(
                                    context,
                                  ).colorScheme.primaryContainer,
                            backgroundColor: isSlush(context)
                                ? context.slush.paper
                                : Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHigh,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Archivos de Aurora · Espacio libre y fidelidad de audio no medidos',
                          style: _stamp(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                tabChip(0, 'Descargadas  ${complete.length}'),
                tabChip(1, 'En progreso  ${active.length}'),
                tabChip(2, 'Conflictos / Re-sincronizar  ${conflicts.length}'),
                TextButton.icon(
                  onPressed: c.importFiles,
                  icon: const Icon(StudioSymbols.uploadFile),
                  label: const Text('Importar archivos externos'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: c.importFiles,
                  icon: const Icon(StudioSymbols.findInPage),
                  label: const Text('Escanear nuevos archivos'),
                ),
                const Text('Selecciona los archivos que quieras importar.'),
                OutlinedButton.icon(
                  onPressed: () => _pending('Exportar a USB'),
                  icon: const Icon(StudioSymbols.usb),
                  label: const Text('Exportar a USB · pendiente'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: isSlush(context)
                      ? Slush.orange
                      : isBrasa(context)
                      ? Brasa.accent
                      : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'COLA DE ESCRITURA EN DISCO EN TIEMPO REAL',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No hay descargas pendientes.',
                  style: isSlush(context)
                      ? TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.slush.ink2,
                        )
                      : null,
                ),
              )
            else if (desktop)
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: active
                    .map(
                      (j) => SizedBox(
                        width: (constraints.maxWidth - 64) / 2,
                        child: _downloadCard(j),
                      ),
                    )
                    .toList(),
              )
            else
              ...active.map(_downloadCard),
            const SizedBox(height: 24),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pistas Descargadas Recientemente al Depósito Local',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tab == 0
                        ? 'Archivos disponibles sin conexión. El formato corresponde a la extensión del archivo.'
                        : 'Estado de las descargas de Aurora.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    decoration: isSlush(context)
                        ? const InputDecoration(
                            labelText: 'Filtrar por pista o formato',
                            suffixIcon: Icon(StudioSymbols.search),
                          )
                        : const InputDecoration(
                            labelText: 'Filtrar por pista o formato',
                            suffixIcon: Icon(StudioSymbols.search),
                            border: OutlineInputBorder(),
                          ),
                    onChanged: (value) => setState(() => _filter = value),
                  ),
                  const SizedBox(height: 16),
                  if (rows.isEmpty)
                    isSlush(context)
                        ? SizedBox(
                            height: 340,
                            child: SlushEmpty(
                              icon: Icons.download_outlined,
                              title: c.downloads.isEmpty
                                  ? 'Aún no hay descargas'
                                  : 'Sin resultados',
                              message: c.downloads.isEmpty
                                  ? 'Aún no hay descargas. Elige Descargar audio en el menú de una canción.'
                                  : 'Sin archivos para esta selección.',
                              sticker: 'VACÍO',
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              c.downloads.isEmpty
                                  ? 'Aún no hay descargas. Elige Descargar audio en el menú de una canción.'
                                  : 'Sin archivos para esta selección.',
                            ),
                          )
                  else if (desktop)
                    _table(rows)
                  else
                    ...rows.map(
                      (j) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _downloadCard(j),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Mostrando ${rows.length} de ${c.downloads.length} descargas locales',
                    style: _stamp(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final feature in [
                  'Auditoría CRC & Hash',
                  'Motor de Escritura Directa',
                  'Respaldo Automático',
                ])
                  SizedBox(
                    width: desktop
                        ? (constraints.maxWidth - 80) / 3
                        : double.infinity,
                    child: _panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feature,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'No implementado. Aurora no certifica integridad acústica, escritura directa ni copias de seguridad automáticas.',
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => _pending(feature),
                            child: const Text('Pendiente'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );

  Color _statusColor(DownloadStatus s) => switch (s) {
    DownloadStatus.queued => Slush.lilac,
    DownloadStatus.downloading => Slush.blue,
    DownloadStatus.completed => Slush.mint,
    DownloadStatus.failed => Slush.orange,
    DownloadStatus.cancelled => Slush.yellow,
  };

  /// Slush: fila sin sombra; estado en píldora y progreso de 6 px menta sobre
  /// `inset`.
  Widget _slushRow(DownloadJob job) {
    final p = context.slush;
    return Padding(
      padding: const EdgeInsets.only(bottom: SlushSpacing.s12),
      child: _panel(
        nested: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Artwork(
                  track: job.track,
                  artworkContext: ArtworkContext.thumbnailDetail,
                  radius: SlushRadius.r12,
                ),
                const SizedBox(width: SlushSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.track.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: p.ink,
                        ),
                      ),
                      Text(
                        '${job.track.artist}${job.track.album == null ? '' : ' · ${job.track.album}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: p.ink2,
                        ),
                      ),
                      Text(
                        _format(job),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .5,
                          color: p.ink3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: SlushSpacing.s8),
            SlushPill(_status(job), color: _statusColor(job.status)),
            if (job.status == DownloadStatus.downloading) ...[
              const SizedBox(height: SlushSpacing.s8),
              ClipRRect(
                borderRadius: BorderRadius.circular(SlushRadius.pill),
                child: LinearProgressIndicator(
                  value: job.progress.clamp(0, 1),
                  minHeight: 6,
                  color: Slush.mint,
                  backgroundColor: p.inset,
                ),
              ),
            ],
            if (job.localPath != null) ...[
              const SizedBox(height: SlushSpacing.s8),
              SelectableText(
                'Destino: ${job.localPath}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: p.ink3,
                ),
              ),
            ],
            if (job.error != null) ...[
              const SizedBox(height: SlushSpacing.s8),
              Text(
                job.error!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.error,
                ),
              ),
            ],
            const SizedBox(height: SlushSpacing.s4),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(spacing: SlushSpacing.s4, children: _actions(job)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadCard(DownloadJob job) => isSlush(context)
      ? _slushRow(job)
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Artwork(
                      track: job.track,
                      artworkContext: ArtworkContext.thumbnailDetail,
                      radius: 4,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _format(job),
                            style: _stamp(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          Text(
                            job.track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Newsreader',
                              fontSize: 24,
                            ),
                          ),
                          Text(
                            '${job.track.artist}${job.track.album == null ? '' : ' · ${job.track.album}'}',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _well(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_status(job), style: _stamp()),
                      if (job.status == DownloadStatus.downloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: job.progress.clamp(0, 1),
                          minHeight: isBrasa(context) ? 4 : null,
                          borderRadius: isBrasa(context)
                              ? BorderRadius.circular(9999)
                              : isModern(context)
                              ? BorderRadius.circular(8)
                              : null,
                          color: isBrasa(context)
                              ? Brasa.accent
                              : isModern(context)
                              ? Tracky.mint
                              : Theme.of(context).colorScheme.primaryContainer,
                        ),
                      ],
                      if (job.localPath != null) ...[
                        const SizedBox(height: 8),
                        SelectableText(
                          'Destino: ${job.localPath}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (job.error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          job.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: _actions(job)),
              ],
            ),
          ),
        );

  Widget _table(List<DownloadJob> jobs) => _well(
    child: Column(
      children: [
        _tableRow(const [
          Text('#'),
          Text('PORTADA'),
          Text('TÍTULO DE LA PISTA'),
          Text('ARTISTA'),
          Text('ÁLBUM'),
          Text('FORMATO'),
          Text('TAMAÑO'),
          Text('SUBCARPETA LOCAL'),
          Text('ACCIONES'),
        ], header: true),
        for (final (index, job) in jobs.indexed)
          _tableRow([
            Text((index + 1).toString().padLeft(2, '0')),
            Artwork(
              track: job.track,
              artworkContext: ArtworkContext.thumbnailCompact,
              radius: 4,
            ),
            Text(
              job.track.title,
              style: isSlush(context)
                  ? TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.slush.ink,
                    )
                  : const TextStyle(fontFamily: 'Newsreader', fontSize: 18),
            ),
            Text(job.track.artist),
            Text(job.track.album ?? 'No disponible'),
            Text(_format(job)),
            Text(_size(job)),
            Text(
              job.localPath == null
                  ? 'No disponible'
                  : p.dirname(job.localPath!),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            Wrap(children: _actions(job)),
          ]),
      ],
    ),
  );

  Widget _tableRow(List<Widget> values, {bool header = false}) => Container(
    decoration: BoxDecoration(
      color: header
          ? (isSlush(context)
                ? context.slush.inset
                : Theme.of(context).colorScheme.surfaceContainer)
          : null,
      border: isSlush(context) && !header
          ? Border(
              bottom: BorderSide(
                color: context.slush.divider,
                width: SlushStroke.divider,
              ),
            )
          : null,
    ),
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            flex: [1, 2, 5, 3, 3, 2, 2, 4, 3][i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  fontSize: header ? (isSlush(context) ? 12 : 10) : 13,
                  color: header
                      ? (isSlush(context)
                            ? context.slush.ink2
                            : Theme.of(context).colorScheme.onSurfaceVariant)
                      : null,
                ),
                child: values[i],
              ),
            ),
          ),
      ],
    ),
  );
  ButtonStyle? get _iconStyle => isSlush(context)
      ? IconButton.styleFrom(
          minimumSize: const Size.square(SlushControl.touch),
          foregroundColor: context.slush.ink,
        )
      : null;

  List<Widget> _actions(DownloadJob job) => [
    if (job.status == DownloadStatus.completed)
      IconButton(
        style: _iconStyle,
        tooltip: 'Reproducir ${job.track.title}',
        onPressed: () => widget.controller.playTrack(
          job.track.copyWith(localPath: job.localPath),
        ),
        icon: const Icon(StudioSymbols.playArrow),
      ),
    if (job.status == DownloadStatus.downloading ||
        job.status == DownloadStatus.queued)
      IconButton(
        style: _iconStyle,
        tooltip: 'Cancelar descarga',
        onPressed: () => widget.controller.cancelDownload(job),
        icon: const Icon(Icons.close),
      ),
    if (job.status == DownloadStatus.failed ||
        job.status == DownloadStatus.cancelled)
      IconButton(
        style: _iconStyle,
        tooltip: 'Reintentar descarga',
        onPressed: () => widget.controller.retryDownload(job),
        icon: const Icon(StudioSymbols.restartAlt),
      ),
    if (job.status == DownloadStatus.completed)
      IconButton(
        style: _iconStyle,
        tooltip: 'Eliminar archivo descargado',
        onPressed: () => _delete(job),
        icon: const Icon(StudioSymbols.deleteOutline),
      ),
  ];

  Future<void> _delete(DownloadJob job) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Eliminar descarga'),
        content: Text(
          'Se eliminará el archivo descargado de «${job.track.title}». Tus favoritos y listas se conservarán. Si está reproduciéndose, se detendrá.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar archivo'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.removeDownload(job);
  }

  String _format(DownloadJob job) {
    final path = job.localPath ?? job.track.localPath;
    return path == null || p.extension(path).isEmpty
        ? 'FORMATO NO DISPONIBLE'
        : p.extension(path).substring(1).toUpperCase();
  }

  String _status(DownloadJob j) => switch (j.status) {
    DownloadStatus.queued => 'En espera',
    DownloadStatus.downloading =>
      'Descargando · ${(j.progress * 100).round()} %',
    DownloadStatus.completed => 'Disponible sin conexión',
    DownloadStatus.failed => 'Descarga fallida',
    DownloadStatus.cancelled => 'Cancelada',
  };
  TextStyle _stamp({Color? color}) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: .7,
    color: color,
  );
  Widget _panel({required Widget child, bool nested = false}) {
    if (isSlush(context)) {
      final p = context.slush;
      final narrow = MediaQuery.sizeOf(context).width < Breakpoints.compact;
      return Container(
        padding: EdgeInsets.all(nested || narrow ? 16 : 24),
        decoration: BoxDecoration(
          color: nested ? p.raised : p.paper,
          borderRadius: BorderRadius.circular(
            nested ? SlushRadius.r16 : SlushRadius.r24,
          ),
          border: Border.fromBorderSide(p.borderSoft),
          boxShadow: nested ? null : p.shadows,
        ),
        child: child,
      );
    }
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black, offset: Offset(2, 3))],
      ),
      child: child,
    );
  }

  Widget _well({required Widget child}) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isSlush(context)
          ? context.slush.inset
          : Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(
        isSlush(context) ? SlushRadius.r16 : 4,
      ),
    ),
    child: child,
  );
}
