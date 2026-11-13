/// Dueño: tema Modern.
///
/// Piezas compartidas por el reproductor completo (escritorio y móvil) y por
/// el aside: letras en vivo, chips de cristal, temporizador de sueño y la
/// pintura del disco.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../artwork.dart';
import '../../core/models.dart';
import '../../lyrics/lyrics_service.dart';
import '../../theme/modern_cristal.dart';
import 'player_theme.dart';

/// Colores del vinilo/casete con la paleta Cristal.
PlayerDiscStyle modernDiscStyle(Cristal c) => PlayerDiscStyle(
  disc: const Color(0xff141824),
  label: c.canvas,
  ring: c.accent,
  ringWidth: 2,
  shadow: const [],
  groove: Colors.white,
  grooveHi: .05,
  grooveLo: .02,
  pivot: c.accent,
  arm: c.accent,
  needle: c.accent,
);

// ---------------------------------------------------------------------------
// Letras en vivo
// ---------------------------------------------------------------------------

/// Carga la letra de la pista que suena (sincronizada o repartida en el
/// tiempo) y avisa de la línea activa con cada tick del audio. Sin letra no
/// hay líneas: el llamador decide qué pintar.
class ModernLyricsFeed extends StatefulWidget {
  const ModernLyricsFeed({
    super.key,
    required this.controller,
    required this.builder,
    this.service,
  });

  final AppController controller;
  final Widget Function(BuildContext context, List<LyricLine> lines, int active)
  builder;

  /// Servicio de letras (pruebas); por defecto el de la app.
  final LyricsService? service;

  @override
  State<ModernLyricsFeed> createState() => _ModernLyricsFeedState();
}

class _ModernLyricsFeedState extends State<ModernLyricsFeed> {
  late final LyricsService _service = widget.service ?? LyricsService();
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

/// Vista previa de letras: línea activa grande con halo, el resto al 38 % y
/// máscara de degradado arriba y abajo. Toca para abrir el modo letra.
class ModernLyricsPreview extends StatelessWidget {
  const ModernLyricsPreview({
    super.key,
    required this.controller,
    this.onOpen,
    this.activeSize = 36,
    this.restSize = 28,
    this.before = 2,
    this.after = 3,
    this.empty = const SizedBox.shrink(),
    this.service,
  });

  final AppController controller;
  final VoidCallback? onOpen;
  final double activeSize, restSize;

  /// Líneas visibles antes y después de la activa.
  final int before, after;

  /// Qué pintar sin letra (por defecto nada).
  final Widget empty;

  /// Servicio de letras (pruebas); por defecto el de la app.
  final LyricsService? service;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final instant = modernReduceEffects(context);
    return ModernLyricsFeed(
      controller: controller,
      service: service,
      builder: (context, lines, active) {
        if (lines.isEmpty) return empty;
        final center = active < 0 ? 0 : active;
        final from = (center - before).clamp(0, lines.length - 1);
        final to = (center + after + 1).clamp(0, lines.length);
        final shown = [
          for (var i = from; i < to; i++)
            if (lines[i].text.trim().isNotEmpty) i,
        ];
        final column = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in shown)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: AnimatedDefaultTextStyle(
                  duration: instant
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  style: i == active
                      ? Cristal.ui(
                          activeSize,
                          weight: 800,
                          color: c.dark ? Colors.white : c.text,
                          tracking: -.03,
                          height: 1.15,
                        ).copyWith(
                          shadows: [
                            Shadow(
                              color: c.accent.withValues(alpha: .45),
                              blurRadius: 28,
                            ),
                          ],
                        )
                      : Cristal.ui(
                          restSize,
                          weight: 800,
                          color: c.text.withValues(alpha: .38),
                          tracking: -.03,
                          height: 1.15,
                        ),
                  child: Text(
                    lines[i].text.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        );
        final centered = LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: box.maxHeight.isFinite ? box.maxHeight : 0,
              ),
              child: Center(child: column),
            ),
          ),
        );
        final masked = ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black,
              Colors.black,
              Colors.transparent,
            ],
            stops: [0, .18, .82, 1],
          ).createShader(rect),
          child: centered,
        );
        return Semantics(
          button: onOpen != null,
          label: 'Abrir el modo letra',
          child: ExcludeSemantics(
            child: MouseRegion(
              cursor: onOpen == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onOpen,
                child: masked,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Temporizador de sueño
// ---------------------------------------------------------------------------

/// «Apagado en N min» si hay temporizador; null si no.
String? modernSleepLabel(AppController c) {
  final left = c.sleepRemaining;
  if (left == null) return null;
  return 'Apagado en ${(left.inSeconds / 60).ceil()} min';
}

/// Minutos restantes («25 min») o null: etiqueta corta del móvil.
String? modernSleepShort(AppController c) {
  final left = c.sleepRemaining;
  if (left == null) return null;
  return '${(left.inSeconds / 60).ceil()} min';
}

/// Cuenta atrás «25:00» en mono para el aside.
String modernSleepClock(Duration left) {
  final s = left.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Hoja con los mismos plazos que el menú del shell (15/30/45/60, desactivar)
/// más «Al terminar la pista».
Future<void> showModernSleepSheet(BuildContext context, AppController c) {
  final p = Cristal.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: p.dark ? const Color(0xff12151d) : p.canvas,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) {
      Widget option(
        IconData icon,
        String label,
        VoidCallback run, {
        bool selected = false,
      }) => ListTile(
        minTileHeight: 52,
        leading: Icon(icon, color: selected ? p.accent : p.text2),
        title: Text(
          label,
          style: Cristal.ui(
            15,
            weight: 600,
            color: selected ? p.accent : p.text,
          ),
        ),
        onTap: () {
          run();
          Navigator.pop(sheet);
        },
      );
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(
                  'Temporizador de sueño',
                  style: Cristal.ui(
                    22,
                    weight: 800,
                    color: p.text,
                    tracking: -.02,
                  ),
                ),
              ),
              for (final minutes in const [15, 30, 45, 60])
                option(
                  Icons.bedtime_outlined,
                  '$minutes minutos',
                  () => c.setSleepTimer(Duration(minutes: minutes)),
                ),
              option(
                Icons.skip_next_rounded,
                'Al terminar la pista',
                c.setSleepAtTrackEnd,
              ),
              if (c.sleepRemaining != null)
                option(
                  Icons.alarm_off_rounded,
                  'Desactivar',
                  () => c.setSleepTimer(null),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Chip de cristal
// ---------------------------------------------------------------------------

/// Píldora de cristal pulsable (EQ, temporizador). Pastilla de 32 dentro de un
/// área táctil de 40; el texto envuelve si el escalado es grande.
class ModernGlassChip extends StatelessWidget {
  const ModernGlassChip({
    super.key,
    required this.label,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final fg = active ? c.accent : c.text2;
    Widget chip = InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Center(
          widthFactor: 1,
          child: ModernGlass(
            radius: 999,
            fill: active ? c.accentSoft : null,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Cristal.ui(13, weight: 600, color: fg),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) chip = Tooltip(message: tooltip!, child: chip);
    return Material(type: MaterialType.transparency, child: chip);
  }
}

/// Portada grande: radio propio y la única sombra del reproductor
/// (`0 18px 40px -12px #0009`).
class ModernCover extends StatelessWidget {
  const ModernCover({
    super.key,
    required this.track,
    required this.size,
    this.radius = 32,
  });

  final Track track;
  final double size, radius;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          offset: Offset(0, 18),
          blurRadius: 40,
          spreadRadius: -12,
        ),
      ],
    ),
    child: Artwork(
      track: track,
      size: size,
      radius: radius,
      artworkContext: ArtworkContext.playerDetail,
    ),
  );
}
