/// Piezas compartidas del reproductor Brasa (escritorio, móvil y panel).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../lyrics/lyrics_service.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/brasa_widgets.dart';
import 'player_theme.dart';

/// Oyentes conectados de la Jam, o 0 sin Jam.
int brasaJamListeners(JamController? jam) {
  final session = jam?.service;
  if (session == null || !session.connected) return 0;
  return session.participants.where((p) => p.connected).length;
}

/// Origen legible de lo que suena, en versalitas: BIBLIOTECA, JAM o STREAMING.
String brasaSourceLabel(AppController c, Track? track) {
  if (track == null) return 'NADA';
  if (c.jamPlaybackActive) return 'JAM';
  return track.isLocal ? 'BIBLIOTECA' : 'STREAMING';
}

/// «REPRODUCIENDO DESDE BIBLIOTECA · JAM CON 2 PERSONAS».
String brasaStatusLine(AppController c, Track? track, JamController? jam) {
  final listeners = brasaJamListeners(jam);
  final base = track == null
      ? 'NADA SONANDO'
      : 'REPRODUCIENDO DESDE ${brasaSourceLabel(c, track)}';
  if (listeners == 0) return base;
  return '$base · JAM CON $listeners ${listeners == 1 ? 'PERSONA' : 'PERSONAS'}';
}

/// «ÁLBUM · NOMBRE · PISTA 3 DE 9» con lo que haya de metadatos reales.
String? brasaMetaLine(AppController c, Track? track) {
  if (track == null) return null;
  final parts = <String>[
    if ((track.album ?? '').trim().isNotEmpty)
      'ÁLBUM · ${track.album!.trim().toUpperCase()}',
    if (c.queue.length > 1 && c.queueIndex >= 0)
      'PISTA ${c.queueIndex + 1} DE ${c.queue.length}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Códec real de un archivo local (`.flac` → «FLAC»); sin dato, null.
String? brasaCodec(Track? track) {
  final path = track?.localPath;
  if (path == null) return null;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot == path.length - 1) return null;
  const known = {'flac', 'wav', 'mp3', 'm4a', 'ogg', 'opus', 'aac', 'alac'};
  final ext = path.substring(dot + 1).toLowerCase();
  return known.contains(ext) ? ext.toUpperCase() : null;
}

/// Preset del ecualizador activo para el chip «EQ · Cálido», o null si está apagado.
String? brasaEqLabel(AppController c) {
  if (!c.eq.active) return null;
  final name = c.eq.presetName;
  return name == null ? 'EQ' : 'EQ · $name';
}

/// Chip pill. [outline] = contorno ámbar mono (señal técnica). Con [onTap] el
/// área táctil mide al menos 44 de alto sin crecer la pastilla.
class BrasaChip extends StatelessWidget {
  const BrasaChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outline = false,
    this.tooltip,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool outline;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final fg = outline ? Brasa.amber : Brasa.cream;
    final pill = DecoratedBox(
      decoration: ShapeDecoration(
        color: outline ? Colors.transparent : Brasa.ash,
        shape: StadiumBorder(
          side: outline
              ? BorderSide(color: Brasa.amber.withValues(alpha: .6))
              : BorderSide.none,
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: outline
                      ? Brasa.mono(12, color: fg, tracking: .08)
                      : Brasa.sans(13, color: fg, weight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: tooltip ?? label,
      excludeSemantics: true,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(widthFactor: 1, child: pill),
        ),
      ),
    );
  }
}

/// Chip del temporizador de sueño con el menú del controlador.
class BrasaSleepChip extends StatelessWidget {
  const BrasaSleepChip({
    super.key,
    required this.controller,
    this.short = false,
  });
  final AppController controller;

  /// Móvil: solo «23 min».
  final bool short;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final left = controller.sleepRemaining;
      final minutes = left == null ? null : (left.inSeconds / 60).ceil();
      final label = minutes == null
          ? (short ? 'Sueño' : 'Temporizador')
          : (short ? '$minutes min' : 'Temporizador · $minutes min');
      return PopupMenuButton<int>(
        tooltip: 'Temporizador de sueño',
        onSelected: (m) {
          if (m == -1) {
            controller.setSleepAtTrackEnd();
          } else {
            controller.setSleepTimer(m == 0 ? null : Duration(minutes: m));
          }
        },
        itemBuilder: (_) => [
          for (final m in const [15, 30, 45, 60])
            PopupMenuItem(value: m, child: Text('$m minutos')),
          const PopupMenuItem(value: -1, child: Text('Al final de la pista')),
          if (left != null)
            const PopupMenuItem(value: 0, child: Text('Desactivar')),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: BrasaChip(label: label, icon: Icons.timer_outlined),
          ),
        ),
      );
    },
  );
}

/// Letra de la pista actual: la carga (LRCLIB/caché) y entrega líneas con
/// tiempos más la activa. Sin letra entrega `[]` (el llamador no pinta nada).
class BrasaLyricsFeed extends StatefulWidget {
  const BrasaLyricsFeed({
    super.key,
    required this.controller,
    required this.builder,
  });
  final AppController controller;
  final Widget Function(BuildContext context, List<LyricLine> lines, int active)
  builder;

  @override
  State<BrasaLyricsFeed> createState() => _BrasaLyricsFeedState();
}

class _BrasaLyricsFeedState extends State<BrasaLyricsFeed> {
  final LyricsService _service = LyricsService();
  LyricsResult? _result;
  String? _id;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _service.dispose();
    super.dispose();
  }

  void _sync() {
    final track = widget.controller.nowTrack;
    if (track?.id == _id) return;
    _id = track?.id;
    _result = null;
    final request = ++_request;
    if (track != null) unawaited(_load(track, request));
    if (mounted) setState(() {});
  }

  Future<void> _load(Track track, int request) async {
    final root = widget.controller.supportDirectory;
    try {
      final raw = await _service.load(track, root);
      if (!mounted || request != _request) return;
      var shown = await _service.adjusted(track, root, raw);
      if (!mounted || request != _request) return;
      setState(() => _result = shown);
      if (raw.kind == LyricsKind.plain) {
        final up = await _service.upgradeToSynced(track, root);
        if (up == null || !mounted || request != _request) return;
        shown = await _service.adjusted(track, root, up);
        if (mounted && request == _request) setState(() => _result = shown);
      }
    } catch (_) {
      // Sin letra: no se pinta nada.
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    if (r == null ||
        (r.kind != LyricsKind.synced && r.kind != LyricsKind.plain)) {
      return widget.builder(context, const [], -1);
    }
    final audio = widget.controller.audio;
    return ListenableBuilder(
      listenable: audio,
      builder: (context, _) {
        final lines = r.kind == LyricsKind.synced
            ? r.lines
            : LyricsService.spreadLines(r.text, audio.duration);
        final active = lines.lastIndexWhere((l) => l.at <= audio.position);
        return widget.builder(context, lines, active);
      },
    );
  }
}

/// Línea de letra con UNA palabra en brasa (la más larga) si [accent].
Widget brasaLyricLine(
  String text,
  TextStyle style, {
  bool accent = false,
  int maxLines = 3,
}) {
  if (!accent) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  final words = text.split(' ');
  var best = -1;
  var bestLen = 3;
  for (var i = 0; i < words.length; i++) {
    final len = words[i]
        .replaceAll(RegExp(r'[^\p{L}]', unicode: true), '')
        .length;
    if (len > bestLen) {
      best = i;
      bestLen = len;
    }
  }
  return Text.rich(
    TextSpan(
      children: [
        for (var i = 0; i < words.length; i++)
          TextSpan(
            text: i < words.length - 1 ? '${words[i]} ' : words[i],
            style: i == best ? const TextStyle(color: Brasa.ember) : null,
          ),
      ],
    ),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

/// Filamento de seek con tiempos mono; busca al soltar.
class BrasaSeekBar extends StatefulWidget {
  const BrasaSeekBar({
    super.key,
    required this.controller,
    required this.liveDuration,
    this.height = 4,
  });
  final AppController controller;
  final Duration Function() liveDuration;
  final double height;

  @override
  State<BrasaSeekBar> createState() => _BrasaSeekBarState();
}

class _BrasaSeekBarState extends State<BrasaSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final time = Brasa.mono(12, color: Brasa.steel, tracking: .04);
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: c.audio,
        builder: (context, _) {
          final duration = widget.liveDuration();
          final max = duration.inMilliseconds;
          final value =
              _drag ?? (max <= 0 ? 0.0 : c.audio.position.inMilliseconds / max);
          final shown = _drag == null
              ? c.audio.position
              : Duration(milliseconds: (max * _drag!).round());
          return Row(
            children: [
              Text(playerTime(shown), style: time),
              const SizedBox(width: 12),
              Expanded(
                child: BrasaFilament(
                  value: value,
                  height: widget.height,
                  hitHeight: 44,
                  onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
                  onChangeEnd: max <= 0
                      ? null
                      : (v) {
                          setState(() => _drag = null);
                          c.seek(Duration(milliseconds: (max * v).round()));
                        },
                ),
              ),
              const SizedBox(width: 12),
              Text(playerTime(duration), style: time),
            ],
          );
        },
      ),
    );
  }
}

/// Botón icono de transporte (≥48).
class BrasaIconButton extends StatelessWidget {
  const BrasaIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 24,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
    color: active ? Brasa.ember : Brasa.cream,
    disabledColor: Brasa.steel,
    icon: Icon(icon, size: size),
  );
}

/// Play/pausa: squircle de brasa.
class BrasaPlayButton extends StatelessWidget {
  const BrasaPlayButton({super.key, required this.controller, this.size = 76});
  final AppController controller;
  final double size;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller.audio,
    builder: (context, _) {
      final playing = controller.audio.isPlaying;
      final enabled = controller.currentTrack != null;
      return Semantics(
        button: true,
        label: playing ? 'Pausar' : 'Reproducir',
        excludeSemantics: true,
        child: Material(
          color: enabled ? Brasa.ember : Brasa.surface3,
          borderRadius: BorderRadius.circular(size * .3),
          child: InkWell(
            borderRadius: BorderRadius.circular(size * .3),
            onTap: enabled ? controller.togglePlayback : null,
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: size * .5,
                color: enabled ? Brasa.onEmber : Brasa.steel,
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Fila de transporte: aleatorio, anterior, play, siguiente, repetir.
class BrasaTransport extends StatelessWidget {
  const BrasaTransport({
    super.key,
    required this.controller,
    this.playSize = 76,
    this.spread = true,
  });
  final AppController controller;
  final double playSize;

  /// true: reparte (móvil); false: agrupa centrado (escritorio).
  final bool spread;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final has = c.currentTrack != null;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final repeatIcon = c.repeat == RepeatMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded;
        final items = [
          BrasaIconButton(
            icon: Icons.shuffle_rounded,
            tooltip: 'Aleatorio',
            active: c.shuffle,
            onPressed: has ? () => c.setShuffle(!c.shuffle) : null,
          ),
          BrasaIconButton(
            icon: Icons.skip_previous_rounded,
            tooltip: 'Anterior',
            size: 32,
            onPressed: has ? c.previous : null,
          ),
          BrasaPlayButton(controller: c, size: playSize),
          BrasaIconButton(
            icon: Icons.skip_next_rounded,
            tooltip: 'Siguiente',
            size: 32,
            onPressed: has ? c.next : null,
          ),
          BrasaIconButton(
            icon: repeatIcon,
            tooltip: 'Repetir',
            active: c.repeat != RepeatMode.off,
            onPressed: has ? c.cycleRepeat : null,
          ),
        ];
        return Row(
          mainAxisAlignment: spread
              ? MainAxisAlignment.spaceBetween
              : MainAxisAlignment.center,
          children: [
            for (final (i, w) in items.indexed) ...[
              if (!spread && i > 0) const SizedBox(width: 8),
              w,
            ],
          ],
        );
      },
    );
  }
}

/// Corazón de favoritos de la pista.
class BrasaHeart extends StatelessWidget {
  const BrasaHeart({super.key, required this.controller, required this.track});
  final AppController controller;
  final Track? track;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final t = track;
      final liked = t != null && controller.favoriteIds.contains(t.id);
      return IconButton(
        tooltip: liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: t == null ? null : () => controller.toggleFavorite(t),
        color: liked ? Brasa.ember : Brasa.cloud,
        icon: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 24,
        ),
      );
    },
  );
}
