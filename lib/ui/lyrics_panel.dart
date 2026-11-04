import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../jam/jam_controller.dart';
import '../lyrics/lyrics_service.dart';
import '../shortcuts/shortcut_service.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import '../theme/slush_theme.dart';
import 'artwork.dart';
import 'lyrics_brasa.dart';
import 'lyrics_modern.dart';
import 'studio/studio_symbols.dart';
import 'studio/studio_transport.dart';

String _formatTime(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

Future<void> showLyrics(BuildContext context, AppController controller) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .86,
      child: LyricsPanel(controller: controller),
    ),
  );
}

class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.controller,
    this.service,
    this.onClose,
    this.jam,
    this.shortcuts,
  });
  final AppController controller;
  // Mismos permisos y rutas que la barra inferior cuando hay una Jam.
  final JamController? jam;
  final ShortcutService? shortcuts;
  final LyricsService? service;
  final VoidCallback? onClose;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  late final LyricsService _service = widget.service ?? LyricsService();
  LyricsResult? _result;
  String? _error;
  bool _loading = false;
  String? _trackId;
  int _request = 0;
  int _lastActive = -1;
  int _offsetMs = 0;
  int _mode = 0;
  int _typeface = 0;
  int _size = 1;
  static const _sizes = [.8, 1.0, 1.25];
  Duration? _scrubPosition;
  String? _scrubTrackId;
  final Map<int, GlobalKey> _lineKeys = {};
  final _scroll = ScrollController();
  bool _firstReveal = true;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  void _changed() {
    final track = widget.controller.nowTrack;
    if (track?.id == _trackId) return;
    _trackId = track?.id;
    _request++;
    _lastActive = -1;
    _offsetMs = 0;
    _scrubPosition = null;
    _scrubTrackId = null;
    _lineKeys.clear();
    _loading = false;
    _result = null;
    _error = null;
    if (track != null) {
      unawaited(_load(track));
      unawaited(
        _service.readOffset(track, widget.controller.supportDirectory).then((
          v,
        ) {
          if (mounted && _trackId == track.id && v != 0) {
            setState(() {
              _offsetMs = v;
              _lastActive = -1;
            });
          }
        }),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _load(Track track, {bool force = false}) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.load(
        track,
        widget.controller.supportDirectory,
        force: force,
        onInterim: (cached) {
          if (mounted &&
              request == _request &&
              widget.controller.nowTrack?.id == track.id) {
            setState(() {
              _result = cached;
              _loading = false;
            });
          }
        },
      );
      if (!mounted ||
          request != _request ||
          widget.controller.nowTrack?.id != track.id) {
        return;
      }
      setState(() => _result = result);
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.controller.nowTrack?.id == track.id) {
        setState(() => _error = 'No se pudieron cargar las letras.');
      }
    } finally {
      if (mounted &&
          request == _request &&
          widget.controller.nowTrack?.id == track.id) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copy() async {
    final r = _result;
    final text = r == null
        ? ''
        : r.kind == LyricsKind.synced
        ? r.lines.map((l) => l.text).join('\n')
        : r.text;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Letra copiada.')));
    }
  }

  void _setOffset(int ms) {
    setState(() {
      _offsetMs = ms;
      _lastActive = -1;
    });
    final track = widget.controller.nowTrack;
    if (track != null) {
      unawaited(
        _service.saveOffset(track, widget.controller.supportDirectory, ms),
      );
    }
  }

  Future<void> _pickOther() async {
    final track = widget.controller.nowTrack;
    if (track == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    var found = const <LyricsCandidate>[];
    try {
      found = await _service.candidates(track);
    } catch (_) {
      if (mounted && request == _request) {
        _error = 'No se pudo buscar otras letras.';
      }
    }
    if (!mounted || request != _request) return;
    setState(() => _loading = false);
    if (_error != null) return;
    if (found.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No hay otras letras para esta pista.')),
      );
      return;
    }
    final choice = await showDialog<LyricsCandidate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Buscar otra letra'),
        children: [
          for (final c in found.take(12))
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(c),
              child: Text(
                '${c.title} · ${c.artist}\n'
                '${c.seconds > 0 ? _formatTime(Duration(seconds: c.seconds)) : '--:--'} · '
                '${c.synced ? 'sincronizada' : 'texto plano'} · ${c.source}',
              ),
            ),
        ],
      ),
    );
    if (choice == null || !mounted || request != _request) return;
    final result = await _service.choose(
      track,
      widget.controller.supportDirectory,
      choice,
    );
    if (mounted && widget.controller.nowTrack?.id == track.id) {
      setState(() => _result = result);
    }
  }

  Future<void> _import() async {
    final track = widget.controller.nowTrack;
    if (track == null) return;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.importFile(
        track,
        widget.controller.supportDirectory,
      );
      if (mounted &&
          request == _request &&
          widget.controller.nowTrack?.id == track.id &&
          result != null) {
        setState(() => _result = result);
      }
    } catch (_) {
      if (mounted &&
          request == _request &&
          widget.controller.nowTrack?.id == track.id) {
        setState(() => _error = 'No se pudo importar el archivo.');
      }
    } finally {
      if (mounted &&
          request == _request &&
          widget.controller.nowTrack?.id == track.id) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scrubPosition = null;
    _scrubTrackId = null;
    _scroll.dispose();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.controller.nowTrack;
    final media = MediaQuery.of(context);
    final lines = _result?.lines ?? const <LyricLine>[];
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= Breakpoints.medium;
        final colors = Theme.of(context).colorScheme;
        final header = Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 10),
              child: Text(
                'Letras',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Importar archivo LRC o TXT',
              onPressed: _loading ? null : _import,
              icon: const Icon(StudioSymbols.uploadFile),
            ),
            IconButton(
              tooltip: 'Copiar letra',
              onPressed: _copy,
              icon: const Icon(Icons.copy_outlined),
            ),
            IconButton(
              tooltip: 'Letra más pequeña',
              onPressed: _size > 0 ? () => setState(() => _size--) : null,
              icon: const Icon(Icons.text_decrease),
            ),
            IconButton(
              tooltip: 'Letra más grande',
              onPressed: _size < 2 ? () => setState(() => _size++) : null,
              icon: const Icon(Icons.text_increase),
            ),
            if (!desktop)
              IconButton(
                tooltip: 'Ajustes de letras',
                onPressed: _showOptions,
                icon: const Icon(StudioSymbols.tune),
              ),
            TextButton.icon(
              onPressed:
                  widget.onClose ?? () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Volver'),
            ),
          ],
        );
        final lyrics = Expanded(
          child: ListenableBuilder(
            listenable: widget.controller.audio,
            builder: (context, _) {
              final position = widget.controller.audio.position;
              final active = lines.lastIndexWhere(
                (line) =>
                    line.at.inMilliseconds <=
                    position.inMilliseconds + _offsetMs,
              );
              return LayoutBuilder(
                builder: (context, box) {
                  final scale = MediaQuery.textScalerOf(context).scale(1);
                  // Escritorio sin altura para letra + opciones + transporte
                  // (ventana baja o texto grande): todo se desplaza y la letra
                  // conserva 240 px. shortcut: umbral estimado, no medido.
                  final scroll =
                      desktop && box.maxHeight < 530 + 300 * (scale - 1);
                  Widget place(Widget w) => scroll
                      ? SizedBox(height: 240, child: w)
                      : Expanded(child: w);
                  final column = Column(
                    mainAxisSize: scroll ? MainAxisSize.min : MainAxisSize.max,
                    children: [
                      place(
                        Container(
                          decoration: isBrasa(context)
                              ? const BoxDecoration()
                              : isModern(context)
                              ? modernLyricsBackdrop(context)
                              : BoxDecoration(
                                  color: colors.surfaceContainerLowest,
                                  border: Border(
                                    left: BorderSide(
                                      color: colors.outlineVariant,
                                    ),
                                    right: BorderSide(
                                      color: colors.outlineVariant,
                                    ),
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black,
                                      offset: Offset(3, 4),
                                    ),
                                  ],
                                ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (desktop && !isBrasa(context))
                                Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 16,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        isBrasa(context)
                                            ? (_result?.kind ==
                                                      LyricsKind.synced
                                                  ? 'Letras sincronizadas'
                                                  : 'Estudio de letras')
                                            : _result?.kind == LyricsKind.synced
                                            ? 'LETRAS SINCRONIZADAS'
                                            : 'ESTUDIO DE LETRAS',
                                        style: TextStyle(
                                          fontSize: 12,
                                          letterSpacing: isBrasa(context)
                                              ? 0
                                              : .8,
                                          // Modern: el degradado tinta el fondo con
                                          // el acento; onSurface mantiene 3:1.
                                          color: isModern(context)
                                              ? colors.onSurface
                                              : colors.onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        isBrasa(context)
                                            ? _sourceLabel()
                                            : _sourceLabel().toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isBrasa(context)
                                              ? Brasa.steel
                                              : colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Expanded(
                                child: _body(
                                  track,
                                  lines,
                                  active,
                                  position,
                                  media,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (desktop)
                        Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: _options(),
                        ),
                      _playbackControls(),
                    ],
                  );
                  return scroll ? SingleChildScrollView(child: column) : column;
                },
              );
            },
          ),
        );
        if (desktop) {
          final leftWidth = (constraints.maxWidth * .40).clamp(310.0, 470.0);
          // Slush: el escritorio (puntero fino) no escala más de 1,3 para que
          // cabezal, opciones y transporte quepan sin desborde.
          return MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  header,
                  const SizedBox(height: 28),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: leftWidth,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (track != null) ...[
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: isBrasa(context)
                                        ? const BoxDecoration(
                                            color: Brasa.obsidian,
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(6),
                                            ),
                                            boxShadow: Brasa.cardShadow,
                                          )
                                        : isSlush(context)
                                        ? BoxDecoration(
                                            color: context.slush.paper,
                                            borderRadius: BorderRadius.circular(
                                              SlushRadius.r24,
                                            ),
                                            border: Border.fromBorderSide(
                                              context.slush.borderSoft,
                                            ),
                                          )
                                        : isModern(context)
                                        ? BoxDecoration(
                                            color: colors.surfaceContainerLow,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: Tracky.warmShadow,
                                          )
                                        : BoxDecoration(
                                            color: colors.surfaceContainerLow,
                                            border: Border.all(
                                              color: colors.outlineVariant,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black,
                                                offset: Offset(3, 4),
                                              ),
                                            ],
                                          ),
                                    child: Artwork(
                                      track: track,
                                      artworkContext:
                                          ArtworkContext.playerDetail,
                                      radius: isBrasa(context)
                                          ? 6
                                          : (isModern(context) ? 8 : 4),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    track.title,
                                    style: isBrasa(context)
                                        ? const TextStyle(
                                            fontFamily: 'Inter',
                                            fontSize: 24,
                                            fontWeight: FontWeight.w700,
                                            height: 1.2,
                                            color: Brasa.cream,
                                          )
                                        : isModern(context)
                                        ? const TextStyle(
                                            fontFamily: 'Bagel Fat One',
                                            fontSize: 32,
                                            letterSpacing: 32 * .03,
                                            height: 1.15,
                                          )
                                        : const TextStyle(
                                            fontFamily: 'Newsreader',
                                            fontSize: 36,
                                            height: 1.12,
                                          ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    '${track.artist}${track.album == null ? '' : ' · ${track.album}'}',
                                    style: TextStyle(
                                      fontSize: isBrasa(context) ? 14 : 18,
                                      color: isBrasa(context)
                                          ? Brasa.cloud
                                          : colors.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                ],
                                Text(
                                  'MODALIDAD DE VISUALIZACIÓN',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _modes(),
                                const SizedBox(height: 24),
                                _noteBox(
                                  context,
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'NOTA DE PRODUCCIÓN & POÉTICA',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: colors.primary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'No hay notas de producción disponibles en los metadatos de esta pista.',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 30),
                        lyrics,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final page = Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Column(
            children: [
              header,
              if (track != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Artwork(
                        track: track,
                        artworkContext: ArtworkContext.thumbnailDetail,
                        radius: isSlush(context) ? SlushRadius.r8 : 4,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '${track.title}\n${track.artist}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ),
              lyrics,
            ],
          ),
        );
        // Con texto muy grande cabecera y controles no caben: se desplaza.
        if (isSlush(context) ||
            MediaQuery.textScalerOf(context).scale(14) <= 18) {
          return page;
        }
        return SingleChildScrollView(
          child: SizedBox(
            height: math.max(constraints.maxHeight, 760),
            child: page,
          ),
        );
      },
    );
  }

  Widget _noteBox(BuildContext context, Widget child) => isBrasa(context)
      ? Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Brasa.obsidian,
            borderRadius: BorderRadius.circular(6),
            boxShadow: Brasa.cardShadow,
          ),
          child: child,
        )
      : isModern(context)
      ? ModernCard(child: child)
      : Container(
          padding: const EdgeInsets.all(16),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: child,
        );

  String _sourceLabel() {
    final r = _result;
    if (r == null || r.kind == LyricsKind.notFound) return 'Sin letra';
    final kind = r.kind == LyricsKind.synced ? 'sincronizada' : 'texto plano';
    final saved = r.fromCache ? ' · guardada' : '';
    return r.source.isEmpty ? '$kind$saved' : '${r.source} · $kind$saved';
  }

  Widget _modes({VoidCallback? refresh}) => Wrap(
    spacing: 4,
    runSpacing: 4,
    children: [
      for (var i = 0; i < 3; i++)
        ChoiceChip(
          shape: isSlush(context)
              ? null
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          label: Text(['Sincronizada', 'Tradicional', 'Traducción'][i]),
          selected: _mode == i,
          onSelected: (_) {
            setState(() {
              _mode = i;
              _lastActive = -1;
            });
            refresh?.call();
          },
        ),
    ],
  );

  Widget _options({VoidCallback? refresh, bool includeModes = false}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (includeModes) _modes(refresh: refresh),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('SINCRONÍA OFFSET:'),
          OutlinedButton(
            onPressed: () {
              _setOffset(_offsetMs - 500);
              refresh?.call();
            },
            child: const Text('-0.5s'),
          ),
          Text(
            '${_offsetMs >= 0 ? '+' : ''}${(_offsetMs / 1000).toStringAsFixed(2)}s',
          ),
          OutlinedButton(
            onPressed: () {
              _setOffset(_offsetMs + 500);
              refresh?.call();
            },
            child: const Text('+0.5s'),
          ),
          IconButton(
            tooltip: 'Restablecer sincronía',
            onPressed: () {
              _setOffset(0);
              refresh?.call();
            },
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      const Text(
        'Ajuste manual, recordado para esta pista.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('TIPOGRAFÍA:'),
          for (var i = 0; i < 3; i++)
            ChoiceChip(
              shape: isSlush(context)
                  ? null
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
              label: Text(['Serif Editorial', 'Grotesca', 'Máquina'][i]),
              selected: _typeface == i,
              onSelected: (_) {
                setState(() => _typeface = i);
                refresh?.call();
              },
            ),
          TextButton.icon(
            onPressed: _loading ? null : _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('Cargar .LRC / .TXT'),
          ),
        ],
      ),
    ],
  );

  void _showOptions() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => StatefulBuilder(
      builder: (context, update) => SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _options(includeModes: true, refresh: () => update(() {})),
      ),
    ),
  );

  String? _hint(ShortcutId id) => widget.shortcuts?.labelOf(id);

  Widget _playbackControls() {
    final controller = widget.controller;
    final audio = controller.audio;
    final duration = audio.duration;
    final length = duration.inMilliseconds;
    final position = (_scrubPosition ?? audio.position).inMilliseconds
        .clamp(0, length > 0 ? length : 0)
        .toDouble();
    final volume = audio.volume.clamp(0.0, 1.0);
    final enabled = controller.nowTrack != null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(_formatTime(audio.position)),
              Expanded(
                child: Semantics(
                  label: 'Posición de reproducción',
                  child: Slider(
                    value: position,
                    max: length > 0 ? length.toDouble() : 1,
                    onChangeStart: enabled && length > 0
                        ? (_) => _scrubTrackId = controller.nowTrack?.id
                        : null,
                    onChanged: enabled && length > 0
                        ? (value) {
                            if (_scrubTrackId != controller.nowTrack?.id) {
                              return;
                            }
                            setState(
                              () => _scrubPosition = Duration(
                                milliseconds: value.round(),
                              ),
                            );
                          }
                        : null,
                    onChangeEnd: enabled && length > 0
                        ? (value) {
                            final trackId = _scrubTrackId;
                            _scrubTrackId = null;
                            _scrubPosition = null;
                            if (trackId == controller.nowTrack?.id) {
                              unawaited(
                                controller.seek(
                                  Duration(milliseconds: value.round()),
                                ),
                              );
                            }
                            if (mounted) setState(() {});
                          }
                        : null,
                  ),
                ),
              ),
              Text(_formatTime(duration)),
            ],
          ),
          Row(
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([controller, ?widget.jam]),
                builder: (context, _) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TransportPreviousButton(
                      controller: controller,
                      jam: widget.jam,
                      size: 24,
                      shortcut: _hint(ShortcutId.previous),
                    ),
                    TransportPlayButton(
                      controller: controller,
                      jam: widget.jam,
                      shortcut: _hint(ShortcutId.playPause),
                    ),
                    TransportNextButton(
                      controller: controller,
                      jam: widget.jam,
                      size: 24,
                      shortcut: _hint(ShortcutId.next),
                    ),
                    TransportEqualizerButton(
                      controller: controller,
                      shortcut: _hint(ShortcutId.equalizer),
                      size: 22,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: volume == 0 ? 'Activar sonido' : 'Silenciar',
                onPressed: enabled
                    ? () => controller.setVolume(volume == 0 ? .7 : 0)
                    : null,
                icon: Icon(
                  volume == 0
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
              ),
              Expanded(
                child: Semantics(
                  label: 'Volumen',
                  child: Slider(
                    value: volume,
                    onChanged: enabled ? controller.setVolume : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _body(
    Track? track,
    List<LyricLine> lines,
    int active,
    Duration pos,
    MediaQueryData media,
  ) {
    if (track == null) {
      return const Center(child: Text('No hay una pista en reproducción.'));
    }
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(semanticsLabel: 'Cargando letras'),
            SizedBox(height: 12),
            Text('Buscando letra…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return _message(_error!, retry: () => _load(track, force: true));
    }
    if (_mode == 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Traducción pendiente; no disponible.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final result = _result;
    if (result == null || result.kind == LyricsKind.notFound) {
      return _message(
        'Sin letra disponible',
        retry: () => _load(track, force: true),
        other: _pickOther,
      );
    }
    if (result.kind == LyricsKind.instrumental) {
      return const Center(child: Text('Pista instrumental'));
    }
    if (result.kind == LyricsKind.plain || _mode == 1) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (result.kind == LyricsKind.plain)
              Text(
                'Estas letras no tienen marcas de tiempo.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            SelectableText(
              result.kind == LyricsKind.synced
                  ? result.lines.map((line) => line.text).join('\n')
                  : result.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: isBrasa(context)
                    ? 'Inter'
                    : const [
                        'Newsreader',
                        'Plus Jakarta Sans',
                        'monospace',
                      ][_typeface],
                fontSize: 24 * _sizes[_size],
                height: 1.65,
              ),
            ),
          ],
        ),
      );
    }
    void seekTo(LyricLine l) => widget.controller.seek(
      Duration(
        milliseconds: (l.at.inMilliseconds - _offsetMs).clamp(0, 1 << 60),
      ),
    );
    if (isBrasa(context)) {
      return BrasaLyricsList(
        key: ValueKey(track.id),
        lines: lines,
        active: active,
        onSeek: seekTo,
        fontFamily: _typeface == 2 ? 'monospace' : 'Inter',
        animate: !media.disableAnimations,
      );
    }
    if (active >= 0 && active != _lastActive) {
      _lastActive = active;
      final instant = _firstReveal;
      _firstReveal = false;
      final slush = isSlush(context);
      void reveal({int tries = 1}) {
        final target = _lineKeys[active]?.currentContext;
        if (!mounted) return;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: instant || media.disableAnimations
                ? Duration.zero
                : Duration(milliseconds: slush ? 280 : 220),
            curve: slush ? SlushMotion.drawer : Curves.easeOut,
            alignment: .5,
          );
        } else if (tries > 0 && _scroll.hasClients) {
          // La lista es perezosa: la línea aún no existe, así que saltamos a
          // su zona aproximada (Slush: proporcional a la extensión medida,
          // con alturas variables) y reintentamos al construirse.
          final max = _scroll.position.maxScrollExtent;
          final guess = slush
              ? max * active / (lines.length > 1 ? lines.length - 1 : 1)
              : active * 56.0;
          _scroll.jumpTo(guess.clamp(0.0, max));
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => reveal(tries: tries - 1),
          );
        }
      }

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => reveal(tries: slush ? 4 : 1),
      );
    }
    if (isModern(context)) {
      return ModernLyricsList(
        key: ValueKey(track.id),
        lines: lines,
        active: active,
        keyFor: (i) => _lineKeys.putIfAbsent(i, GlobalKey.new),
        onSeek: seekTo,
        fontFamily: _typeface == 2 ? 'monospace' : 'Inter',
        animate: !media.disableAnimations,
        controller: isSlush(context) ? _scroll : null,
      );
    }
    return ListView.builder(
      key: ValueKey(track.id),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: lines.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
            child: Text(
              'Toca un verso para ir a ese momento',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final lineIndex = index - 1;
        final key = _lineKeys.putIfAbsent(lineIndex, GlobalKey.new);
        final highlighted = lineIndex == active;
        final line = lines[lineIndex];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Semantics(
            key: key,
            liveRegion: highlighted,
            label: '${_formatTime(line.at)} ${line.text}',
            child: Container(
              decoration: isBrasa(context)
                  ? null
                  : isModern(context)
                  ? BoxDecoration(
                      color: highlighted
                          ? Tracky.mint.withValues(alpha: .35)
                          : null,
                      borderRadius: BorderRadius.circular(12),
                    )
                  : BoxDecoration(
                      border: Border(
                        left: BorderSide(
                          width: highlighted ? 6 : 0,
                          color: highlighted
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.transparent,
                        ),
                      ),
                    ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => widget.controller.seek(
                    Duration(
                      milliseconds: (line.at.inMilliseconds - _offsetMs).clamp(
                        0,
                        1 << 60,
                      ),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 44,
                            child: Text(
                              _formatTime(line.at),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: isBrasa(context)
                                  ? Alignment.centerLeft
                                  : Alignment.center,
                              child: AnimatedDefaultTextStyle(
                                duration: media.disableAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                style: isBrasa(context)
                                    ? TextStyle(
                                        fontFamily: _typeface == 2
                                            ? 'monospace'
                                            : 'Inter',
                                        fontSize: 28,
                                        height: 1.35,
                                        fontWeight: FontWeight.w700,
                                        color: highlighted
                                            ? Brasa.cream
                                            : Brasa.steel,
                                      )
                                    : isModern(context)
                                    ? TextStyle(
                                        fontFamily: _typeface == 2
                                            ? 'monospace'
                                            : 'Inter',
                                        fontSize: highlighted ? 34 : 26,
                                        height: 1.4,
                                        letterSpacing: -.01 * 30,
                                        fontWeight: highlighted
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: highlighted
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurface
                                            : isSlush(context)
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant
                                            : Tracky.slate,
                                      )
                                    : TextStyle(
                                        fontFamily: [
                                          'Newsreader',
                                          'Plus Jakarta Sans',
                                          'monospace',
                                        ][_typeface],
                                        fontSize: highlighted ? 38 : 28,
                                        fontStyle: highlighted
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        height: 1.45,
                                        fontWeight: highlighted
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        color: highlighted
                                            ? Theme.of(
                                                context,
                                              ).colorScheme.primary
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                      ),
                                child: Text(
                                  line.text,
                                  textAlign: TextAlign.left,
                                ),
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
          ),
        );
      },
    );
  }

  Widget _message(
    String value, {
    required VoidCallback retry,
    VoidCallback? other,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: retry,
                icon: const Icon(StudioSymbols.restartAlt),
                label: const Text('Reintentar'),
              ),
              if (other != null)
                TextButton.icon(
                  onPressed: other,
                  icon: const Icon(Icons.manage_search),
                  label: const Text('Buscar otra letra'),
                ),
              TextButton.icon(
                onPressed: _import,
                icon: const Icon(StudioSymbols.uploadFile),
                label: const Text('Importar LRC o TXT'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
