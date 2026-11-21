/// Dueño: tema Atelier («Papel y tinta»).
///
/// Posee el reproductor completo (sección 4): una página de revista en
/// escritorio (portada, sello de calidad, cadena de señal, ficha mono) y la
/// pantalla de pulgar en móvil (controles abajo, play «squircle»).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/atelier_theme.dart';
import '../follow_widgets.dart';
import '../mini_player/song_card.dart';
import '../shell/atelier_widgets.dart';
import 'modern_player_parts.dart' show ModernLyricsFeed;
import 'player_theme.dart';

/// Atelier («Papel y tinta»): implementación de [PlayerTheme].
const PlayerTheme atelierPlayer = AtelierPlayerTheme();

class AtelierPlayerTheme extends PlayerTheme {
  const AtelierPlayerTheme();

  @override
  double get compactBreakpoint => 760;

  @override
  bool get rebuildsOnAudio => true;

  @override
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) => compact
      ? _Mobile(scope: scope, track: track)
      : _Desktop(scope: scope, track: track, constraints: constraints);
}

/// Duración, posición y fracción del audio actual.
({Duration duration, Duration position, double max, double value}) _timing(
  AppController c,
  Track? track,
) {
  final duration = c.audio.duration > Duration.zero
      ? c.audio.duration
      : track?.duration ?? Duration.zero;
  final max = math.max(1, duration.inMilliseconds).toDouble();
  final value = c.audio.position.inMilliseconds.toDouble().clamp(0.0, max);
  return (
    duration: duration,
    position: c.audio.position,
    max: max,
    value: value,
  );
}

Widget _seek(BuildContext context, AppController c, Track? track) {
  final t = AtelierTokens.of(context);
  final m = _timing(c, track);
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          semanticFormatterCallback: (value) =>
              'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
          min: 0,
          max: m.max,
          value: m.value,
          onChanged: m.duration > Duration.zero
              ? (v) => c.seek(Duration(milliseconds: v.round()))
              : null,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(playerTime(m.position), style: t.mono(size: 11)),
            Text(
              m.duration > Duration.zero
                  ? '-${playerTime(m.duration - m.position)}'
                  : '--:--',
              style: t.mono(size: 11),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Aleatorio · anterior · play · siguiente · repetir.
Widget _transport(
  BuildContext context,
  AppController c,
  Track? track, {
  required double play,
  required bool squircle,
}) {
  final t = AtelierTokens.of(context);
  final playing = c.audio.isPlaying;
  final radius = squircle ? (playing ? play / 2 : play * .3) : play / 2;
  final gap = squircle ? 12.0 : 8.0;
  IconButton icon(
    String tip,
    IconData data,
    VoidCallback? onTap, {
    bool on = false,
    double size = 26,
  }) => IconButton(
    tooltip: tip,
    isSelected: on,
    onPressed: onTap,
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    color: on ? t.accentText : t.ink,
    icon: Icon(data, size: size),
  );
  // En móviles de 320 px la fila (296 dp) no cabe: se encoge en vez de desbordar.
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        icon(
          'Aleatorio',
          Icons.shuffle_rounded,
          track == null ? null : () => c.setShuffle(!c.shuffle),
          on: c.shuffle,
          size: 24,
        ),
        icon(
          'Anterior',
          Icons.skip_previous_rounded,
          track == null ? null : c.previous,
          size: 32,
        ),
        SizedBox(width: gap),
        Tooltip(
          message: playing ? 'Pausar' : 'Reproducir',
          child: Material(
            color: track == null ? t.accent.withValues(alpha: .4) : t.accent,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: track == null ? null : c.togglePlayback,
              child: SizedBox.square(
                dimension: play,
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: play * .5,
                  color: t.onAccent,
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: gap),
        icon(
          'Siguiente',
          Icons.skip_next_rounded,
          track == null ? null : c.next,
          size: 32,
        ),
        icon(
          'Repetir',
          c.repeat == RepeatMode.one
              ? Icons.repeat_one_rounded
              : Icons.repeat_rounded,
          track == null ? null : c.cycleRepeat,
          on: c.repeat != RepeatMode.off,
          size: 24,
        ),
      ],
    ),
  );
}

Widget _artistLine(
  BuildContext context,
  PlayerScope scope,
  Track? track, {
  double size = 20,
}) {
  final t = AtelierTokens.of(context);
  final c = scope.controller;
  return Wrap(
    spacing: 12,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      MouseRegion(
        cursor: track == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: track == null ? null : () => c.openArtist(track.artist),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text(
                track == null
                    ? 'Elige una canción de tu biblioteca'
                    : [
                        track.artist,
                        if (track.album?.trim().isNotEmpty == true)
                          track.album!.trim(),
                      ].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.serif(size, italic: true, color: t.ink2),
              ),
            ),
          ),
        ),
      ),
      if (scope.follow != null &&
          track != null &&
          primaryArtist(track.artist).isNotEmpty)
        FollowButton(service: scope.follow!, name: primaryArtist(track.artist)),
    ],
  );
}

/// Título con la última palabra en cursiva terracota (ritmo de revista).
Widget _title(BuildContext context, Track? track, double size) {
  final t = AtelierTokens.of(context);
  final text = track?.title ?? 'Nada sonando';
  final cut = text.trim().lastIndexOf(' ');
  final head = cut > 0 ? text.substring(0, cut + 1) : '';
  final tail = cut > 0 ? text.substring(cut + 1) : text;
  return Semantics(
    header: true,
    label: text,
    child: ExcludeSemantics(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: head),
            TextSpan(
              text: tail,
              style: t.serif(
                size,
                italic: true,
                color: t.accentText,
                height: 1.05,
                letterSpacing: -size * .015,
              ),
            ),
          ],
        ),
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: t.serif(size, height: 1.05, letterSpacing: -size * .015),
      ),
    ),
  );
}

class _Desktop extends StatelessWidget {
  const _Desktop({
    required this.scope,
    required this.track,
    required this.constraints,
  });
  final PlayerScope scope;
  final Track? track;
  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final c = scope.controller;
    final format = atelierFormat(track);
    final inner = constraints.maxWidth - 96;
    final cover = (inner * .4).clamp(220.0, 420.0);
    final number = c.queue.isEmpty
        ? ''
        : ' · Nº ${(c.queueIndex + 1).toString().padLeft(2, '0')} DE ${c.queue.length}';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(48, 8, 48, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            children: [
              Text(
                'AHORA SUENA$number${track == null ? '' : ' · ${track!.title.toUpperCase()}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.mono(size: 11),
              ),
              if (track != null)
                OutlinedButton.icon(
                  onPressed: () => scope.onSection?.call(6),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.ink,
                    side: BorderSide(color: t.rule),
                    textStyle: t.mono(size: 11),
                  ),
                  icon: const Icon(Icons.lyrics_outlined, size: 16),
                  label: const Text('LETRAS SINCRONIZADAS'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: cover,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        scope.seekable(
                          c,
                          cover,
                          track == null
                              ? SizedBox.square(
                                  dimension: cover,
                                  child: ColoredBox(color: t.panel2),
                                )
                              : AtelierCover(track: track!, size: cover),
                        ),
                        if (format != null)
                          Positioned(
                            right: -28,
                            bottom: -34,
                            child: AtelierSeal(format: format),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      track == null
                          ? ''
                          : 'FIG. 1 — «${(track!.album?.trim().isNotEmpty == true ? track!.album! : track!.title).toUpperCase()}»',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.mono(size: 10.5),
                    ),
                    const SizedBox(height: 28),
                    Container(height: 1, color: t.ink),
                    const SizedBox(height: 10),
                    Text(
                      'CADENA DE SEÑAL',
                      style: t.mono(size: 10.5, color: t.accentText),
                    ),
                    const SizedBox(height: 6),
                    _chain(t, '01', 'Archivo', format ?? '—'),
                    _chain(
                      t,
                      '02',
                      'Ecualizador',
                      c.eq.active ? 'Activo' : 'Desactivado',
                    ),
                    _chain(t, '03', 'Salida', 'Motor Aurora'),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(context, track, 56),
                    const SizedBox(height: 8),
                    _artistLine(context, scope, track),
                    const SizedBox(height: 12),
                    Container(height: 1, color: t.ink),
                    const SizedBox(height: 10),
                    _ficha(t, c, track, format),
                    const SizedBox(height: 12),
                    Container(height: 1, color: t.rule),
                    const SizedBox(height: 16),
                    _seek(context, c, track),
                    _transport(context, c, track, play: 56, squircle: false),
                    const SizedBox(height: 20),
                    _Lyrics(scope: scope, compact: false),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chain(AtelierTokens t, String n, String label, String value) =>
      Container(
        constraints: const BoxConstraints(minHeight: 32),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(n, style: t.mono(size: 10.5, color: t.accentText)),
            ),
            Expanded(
              child: Text(label, style: t.ui(13.5, color: t.ink2)),
            ),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.ui(13.5, weight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _ficha(
    AtelierTokens t,
    AppController c,
    Track? track,
    String? format,
  ) {
    final rows = <(String, String)>[
      if (c.queue.isNotEmpty)
        (
          'PISTA',
          '${(c.queueIndex + 1).toString().padLeft(2, '0')} / ${c.queue.length}',
        ),
      if (format != null) ('FORMATO', format),
      if (track != null)
        ('ORIGEN', track.isLocal ? 'ARCHIVO LOCAL' : 'FUENTE REMOTA'),
      if (track != null && track.duration > Duration.zero)
        ('DURACIÓN', playerTime(track.duration)),
    ];
    return Wrap(
      spacing: 32,
      runSpacing: 6,
      children: [
        for (final (k, v) in rows)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(k, style: t.mono(size: 10.5)),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.mono(size: 11, color: t.ink),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _Mobile extends StatelessWidget {
  const _Mobile({required this.scope, required this.track});
  final PlayerScope scope;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final c = scope.controller;
    final format = atelierFormat(track);
    final liked = track != null && c.favoriteIds.contains(track!.id);
    final next = c.queue.skip(c.queueIndex + 1).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Volver',
                        onPressed:
                            scope.onBack ?? () => scope.onSection?.call(0),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              'REPRODUCIENDO DESDE',
                              style: t.mono(size: 11),
                            ),
                            Text(
                              track == null
                                  ? 'Aurora'
                                  : (track!.album?.trim().isNotEmpty == true
                                        ? track!.album!.trim()
                                        : 'Biblioteca'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.serif(16),
                            ),
                          ],
                        ),
                      ),
                      Builder(
                        builder: (b) => IconButton(
                          tooltip: 'Más acciones',
                          onPressed: track == null
                              ? null
                              : () {
                                  final rb = b.findRenderObject() as RenderBox;
                                  showSongCard(
                                    context,
                                    c,
                                    track!,
                                    rb.localToGlobal(
                                      rb.size.bottomLeft(Offset.zero),
                                    ),
                                    openQueue: () => scope.onSection?.call(5),
                                  );
                                },
                          icon: const Icon(Icons.more_horiz),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Builder(
                      builder: (context) {
                        final side = math.min(318.0, box.maxWidth - 48);
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            scope.seekable(
                              c,
                              side,
                              track == null
                                  ? SizedBox.square(
                                      dimension: side,
                                      child: ColoredBox(color: t.panel2),
                                    )
                                  : AtelierCover(track: track!, size: side),
                            ),
                            if (format != null)
                              Positioned(
                                left: -8,
                                bottom: -14,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(color: t.paper),
                                  child: AtelierFormatChip(format, size: 12),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _title(context, track, 30)),
                      IconButton(
                        tooltip: liked
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                        onPressed: track == null
                            ? null
                            : () => c.toggleFavorite(track!),
                        color: t.accentText,
                        icon: Icon(
                          liked ? Icons.favorite : Icons.favorite_border,
                        ),
                      ),
                    ],
                  ),
                  _artistLine(context, scope, track, size: 18),
                  _Lyrics(scope: scope, compact: true),
                  const SizedBox(height: 8),
                  _seek(context, c, track),
                  _transport(context, c, track, play: 80, squircle: true),
                  const SizedBox(height: 8),
                  Container(height: 1, color: t.rule),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: [
                      _action(
                        t,
                        Icons.equalizer,
                        'EQ',
                        () => scope.onSection?.call(13),
                      ),
                      _action(
                        t,
                        Icons.schedule,
                        atelierSleepLabel(c) ?? 'Sueño',
                        () => showAtelierSleepSheet(context, c),
                      ),
                      _action(
                        t,
                        Icons.groups_outlined,
                        'Jam',
                        () => scope.onSection?.call(9),
                      ),
                      _action(
                        t,
                        Icons.lyrics_outlined,
                        'Letra',
                        () => scope.onSection?.call(6),
                      ),
                      _action(
                        t,
                        Icons.queue_music,
                        'Cola',
                        () => scope.onSection?.call(5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Abrir la cola',
                    child: InkWell(
                      onTap: () => scope.onSection?.call(5),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: t.ink)),
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                'COLA · ${c.queue.length} PISTAS',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.mono(size: 11),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                next == null
                                    ? ''
                                    : 'SIGUIENTE: ${next.title.toUpperCase()}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: t.mono(size: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _action(
    AtelierTokens t,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: t.ink),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, style: t.ui(12, weight: FontWeight.w500)),
        ],
      ),
    ),
  );
}

/// Extracto de la letra sincronizada: línea activa en cursiva con marcador
/// terracota al 22 % y el resto atenuado. Sin letra no pinta nada (móvil) o
/// lo dice (escritorio). Un toque abre el modo letra.
class _Lyrics extends StatelessWidget {
  const _Lyrics({required this.scope, required this.compact});
  final PlayerScope scope;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final size = compact ? 20.0 : 26.0;
    return ModernLyricsFeed(
      controller: scope.controller,
      builder: (context, lines, active) {
        if (lines.isEmpty) {
          return compact
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Sin letra sincronizada para esta pista.',
                    style: t.ui(13, color: t.ink2),
                  ),
                );
        }
        final from = math.max(0, active - (compact ? 0 : 1));
        final shown = lines.skip(from).take(compact ? 2 : 5).toList();
        return Semantics(
          button: true,
          label: 'Abrir el modo letra',
          child: InkWell(
            onTap: () => scope.onSection?.call(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!compact) ...[
                    Text(
                      'LETRA · ${atelierClock(scope.controller.audio.position)}',
                      style: t.mono(size: 11),
                    ),
                    const SizedBox(height: 6),
                  ],
                  for (final (i, line) in shown.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text.rich(
                        TextSpan(
                          text: line.text,
                          style: from + i == active
                              ? t
                                    .serif(size * 1.15, italic: true)
                                    .copyWith(
                                      backgroundColor: t.accent.withValues(
                                        alpha: .22,
                                      ),
                                    )
                              : t.serif(
                                  size,
                                  color: t.ink.withValues(alpha: .55),
                                ),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
