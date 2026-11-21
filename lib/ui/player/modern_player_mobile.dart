/// Dueño: tema Modern.
///
/// Reproductor completo compacto (móvil y ventanas estrechas): cabecera, portada,
/// título, onda de búsqueda, transporte, utilidades y hoja de letras.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import '../follow_widgets.dart';
import '../mini_player/song_card.dart';
import '../studio/equalizer_panel.dart';
import '../studio/studio_transport.dart' show transportJamAudio;
import 'modern_player_parts.dart';
import 'player_theme.dart';

const _tile = 48.0;

Widget buildModernMobilePlayer(
  BuildContext context,
  PlayerScope scope,
  Track? track,
  BoxConstraints constraints,
) {
  final c = scope.controller;
  return ListenableBuilder(
    listenable: Listenable.merge([c, c.eq, if (scope.jam != null) scope.jam!]),
    builder: (context, _) {
      final jamAudio = transportJamAudio(c, scope.jam);
      final shown = jamAudio ? (c.nowTrack ?? track) : track;
      return _MobilePlayer(
        scope: scope,
        track: shown,
        jamAudio: jamAudio,
        constraints: constraints,
      );
    },
  );
}

class _MobilePlayer extends StatelessWidget {
  const _MobilePlayer({
    required this.scope,
    required this.track,
    required this.jamAudio,
    required this.constraints,
  });

  final PlayerScope scope;
  final Track? track;
  final bool jamAudio;
  final BoxConstraints constraints;

  AppController get c => scope.controller;

  void _go(int section) => scope.onSection?.call(section);

  void _back() {
    if (scope.onBack != null) {
      scope.onBack!();
    } else {
      _go(0);
    }
  }

  String get _source => jamAudio
      ? 'Jam'
      : track == null
      ? 'Nada sonando'
      : track!.isLocal
      ? 'Biblioteca'
      : 'Streaming';

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    final t = track;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 800.0;
    // 296 de prototipo; cede alto (cabecera, título, onda, transporte, 5
    // utilidades y la hoja de letras suman ~540) para que todo quepa sin scroll.
    final side = math.max(
      math.min(256.0, width - 48),
      math.min(296.0, math.min(width - 48, height - 540)),
    );
    final photo = scope.modernPhoto && t != null;
    final Widget cover = photo
        ? scope.seekable(c, side, ModernCover(track: t, size: side))
        : scope.record(context, c, t, side, modernDiscStyle(p));
    final scroll = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, p),
          const SizedBox(height: 12),
          Center(child: cover),
          const SizedBox(height: 24),
          _titleBlock(context, p),
          const SizedBox(height: 16),
          _seek(context, p),
          const SizedBox(height: 16),
          _transport(context, p),
          const SizedBox(height: 12),
          _utilities(context, p),
        ],
      ),
    );
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Expanded(child: scroll),
          _LyricsSheet(
            controller: c,
            maxHeight: height * .36,
            onOpen: scope.onSection == null ? null : () => _go(6),
          ),
        ],
      ),
    );
  }

  // ---- Cabecera -----------------------------------------------------------

  Widget _header(BuildContext context, Cristal p) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Volver',
          constraints: const BoxConstraints.tightFor(
            width: _tile,
            height: _tile,
          ),
          color: p.text,
          onPressed: _back,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
        ),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ModernLabel('Reproduciendo desde'),
              Text(
                _source,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Cristal.ui(15, weight: 600, color: p.text),
              ),
            ],
          ),
        ),
        Builder(
          builder: (b) => IconButton(
            tooltip: 'Más acciones',
            constraints: const BoxConstraints.tightFor(
              width: _tile,
              height: _tile,
            ),
            color: p.text,
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: track == null
                ? null
                : () {
                    final box = b.findRenderObject()! as RenderBox;
                    showSongCard(
                      context,
                      c,
                      track!,
                      box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                      openQueue: () => _go(5),
                      extras: [
                        (
                          label: 'Ver artista',
                          icon: Icons.person_outline_rounded,
                          run: () => c.openArtist(track!.artist),
                        ),
                        (
                          label: 'Ver portada',
                          icon: Icons.image_outlined,
                          run: () => scope.setModernView(0),
                        ),
                        (
                          label: 'Ver vinilo',
                          icon: Icons.album_outlined,
                          run: () => scope.setModernView(1),
                        ),
                        (
                          label: 'Ver casete',
                          icon: Icons.album_rounded,
                          run: () => scope.setModernView(2),
                        ),
                      ],
                    );
                  },
          ),
        ),
      ],
    ),
  );

  // ---- Título -------------------------------------------------------------

  Widget _titleBlock(BuildContext context, Cristal p) {
    final t = track;
    final fav = t != null && c.favoriteIds.contains(t.id);
    // Con texto grande o ancho justo el chip baja a su propia línea.
    final stack =
        MediaQuery.textScalerOf(context).scale(10) > 13 ||
        constraints.maxWidth < 340;
    final chip = t == null
        ? const SizedBox.shrink()
        : ModernSignalChip(label: modernFormatLabel(t));
    final name = primaryArtist(t?.artist ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t?.title ?? 'Nada sonando',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Cristal.ui(
                      28,
                      weight: 800,
                      color: p.text,
                      tracking: -.03,
                      height: 1.12,
                    ),
                  ),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      InkWell(
                        onTap: t == null ? null : () => c.openArtist(t.artist),
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1,
                            child: Text(
                              t?.artist ?? 'Elige una canción de tu biblioteca',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Cristal.ui(
                                15,
                                weight: 500,
                                color: p.text2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (scope.follow != null && t != null && name.isNotEmpty)
                        FollowButton(service: scope.follow!, name: name),
                    ],
                  ),
                ],
              ),
            ),
            if (!stack && t != null) ...[
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 6), child: chip),
            ],
            if (t != null)
              IconButton(
                tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
                constraints: const BoxConstraints.tightFor(
                  width: _tile,
                  height: _tile,
                ),
                color: fav ? p.like : p.text2,
                onPressed: () => c.toggleFavorite(t),
                icon: Icon(
                  fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 26,
                ),
              ),
          ],
        ),
        if (stack && t != null)
          Align(alignment: Alignment.centerLeft, child: chip),
      ],
    );
  }

  // ---- Onda de búsqueda ---------------------------------------------------

  Widget _seek(BuildContext context, Cristal p) {
    final t = track;
    final timeStyle = Cristal.mono(12, color: p.text3, tracking: .04);
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: c.audio,
        builder: (context, _) {
          final duration = scope.liveDuration();
          final ms = math.max(1, duration.inMilliseconds);
          final pos = c.audio.position.inMilliseconds.clamp(0, ms);
          final canSeek = t != null && duration > Duration.zero && !jamAudio;
          final left = Duration(milliseconds: ms - pos);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ModernWaveSeekBar(
                progress: pos / ms,
                seed: t?.id ?? '',
                height: 44,
                barWidth: 3,
                gap: 2.5,
                semanticsLabel: 'Posición de la pista',
                onSeek: canSeek
                    ? (f) => c.seek(Duration(milliseconds: (f * ms).round()))
                    : null,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(playerTime(c.audio.position), style: timeStyle),
                  Text('-${playerTime(left)}', style: timeStyle),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // ---- Transporte ---------------------------------------------------------

  Widget _transport(BuildContext context, Cristal p) {
    final t = track;
    final jam = scope.jam;
    final j = jamAudio ? jam! : null;
    final votes = j?.service.rules.votes ?? false;
    final playEnabled = j != null ? j.canPause : t != null;
    final VoidCallback? onPlay = !playEnabled
        ? null
        : j != null
        ? j.togglePlayback
        : c.togglePlayback;
    final VoidCallback? onNext = j == null
        ? (t == null ? null : c.next)
        : (!j.canSkip && !votes)
        ? null
        : (j.canSkip ? j.next : j.service.voteSkip);
    final VoidCallback? onPrev = t == null || j != null ? null : c.previous;
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final playing = c.audio.isPlaying;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _TransportTile(
              tooltip: 'Aleatorio',
              icon: Icons.shuffle_rounded,
              active: c.shuffle,
              onTap: t == null ? null : () => c.setShuffle(!c.shuffle),
            ),
            _TransportTile(
              tooltip: j != null ? 'No disponible en una Jam' : 'Anterior',
              icon: Icons.skip_previous_rounded,
              size: 34,
              strong: true,
              onTap: onPrev,
            ),
            Tooltip(
              message: j != null && !playEnabled
                  ? 'Lo controla ${j.hostName}'
                  : (playing ? 'Pausar' : 'Reproducir'),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: onPlay == null
                      ? p.accent.withValues(alpha: .4)
                      : p.accent,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: onPlay == null
                      ? null
                      : [
                          BoxShadow(
                            color: p.accent.withValues(alpha: .38),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: onPlay,
                    child: SizedBox.square(
                      dimension: 72,
                      child: c.busy && j == null
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: p.onAccent,
                              ),
                            )
                          : Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 38,
                              color: p.onAccent,
                            ),
                    ),
                  ),
                ),
              ),
            ),
            _TransportTile(
              tooltip: j != null && j.canSkip
                  ? 'Siguiente'
                  : j != null
                  ? (votes ? 'Votar para saltar' : 'Lo controla ${j.hostName}')
                  : 'Siguiente',
              icon: j != null && !j.canSkip && votes
                  ? Icons.how_to_vote_outlined
                  : Icons.skip_next_rounded,
              size: 34,
              strong: true,
              onTap: onNext,
            ),
            _TransportTile(
              tooltip: 'Repetir',
              icon: c.repeat == RepeatMode.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              active: c.repeat != RepeatMode.off,
              onTap: t == null ? null : c.cycleRepeat,
            ),
          ],
        );
      },
    );
  }

  // ---- Utilidades ---------------------------------------------------------

  Widget _utilities(BuildContext context, Cristal p) {
    final sleep = modernSleepShort(c);
    final inJam = scope.jam?.active == true;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Utility(
          icon: Icons.lyrics_outlined,
          label: 'Letras',
          active: true,
          onTap: scope.onSection == null ? null : () => _go(6),
        ),
        _Utility(
          icon: Icons.equalizer_rounded,
          label: 'EQ',
          active: c.eq.active,
          onTap: c.eq.supported ? () => showEqualizerSheet(context, c) : null,
        ),
        _Utility(
          icon: Icons.bedtime_outlined,
          label: sleep ?? 'Sueño',
          active: sleep != null,
          onTap: () => showModernSleepSheet(context, c),
        ),
        _Utility(
          icon: Icons.groups_outlined,
          label: 'Jam',
          active: inJam,
          onTap: scope.onSection == null ? null : () => _go(9),
        ),
        _Utility(
          icon: Icons.queue_music_rounded,
          label: 'Cola',
          onTap: scope.onSection == null ? null : () => _go(5),
        ),
      ],
    );
  }
}

/// Botón de transporte de 48 dp; activo = tile de cristal con icono acento.
class _TransportTile extends StatelessWidget {
  const _TransportTile({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.strong = false,
    this.size = 24,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active, strong;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    final color = onTap == null
        ? p.text3.withValues(alpha: .5)
        : active
        ? p.accent
        : (strong ? p.text : p.text2);
    return Semantics(
      button: true,
      selected: active,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? p.glassHover : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox.square(
              dimension: _tile,
              child: Icon(icon, size: size, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// Utilidad con icono y etiqueta (Letras, EQ, temporizador, Jam, Cola).
class _Utility extends StatelessWidget {
  const _Utility({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    final color = onTap == null
        ? p.text3.withValues(alpha: .5)
        : active
        ? p.accent
        : p.text2;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 24, color: color),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: Cristal.ui(12, weight: 600, color: color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja de letras con asa: línea actual y la siguiente; un toque o arrastrar
/// hacia arriba abre el modo letra.
class _LyricsSheet extends StatelessWidget {
  const _LyricsSheet({
    required this.controller,
    required this.maxHeight,
    required this.onOpen,
  });

  final AppController controller;
  final double maxHeight;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    return Semantics(
      button: onOpen != null,
      label: 'Abrir el modo letra',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        onVerticalDragEnd: onOpen == null
            ? null
            : (d) {
                if ((d.primaryVelocity ?? 0) < -150) onOpen!();
              },
        child: ModernGlass(
          radius: 24,
          fill: p.dark ? const Color(0xff0f121a) : p.canvas,
          padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: math.max(96, maxHeight)),
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: p.text.withValues(alpha: .3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    ModernLyricsFeed(
                      controller: controller,
                      builder: (context, lines, active) {
                        final now = active >= 0 && active < lines.length
                            ? lines[active].text.trim()
                            : '';
                        final nextIndex = active + 1;
                        final next = nextIndex >= 0 && nextIndex < lines.length
                            ? lines[nextIndex].text.trim()
                            : '';
                        if (lines.isEmpty) {
                          return Text(
                            'Letras',
                            style: Cristal.ui(
                              20,
                              weight: 800,
                              color: p.text,
                              tracking: -.02,
                            ),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              now.isEmpty ? '♪' : now,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Cristal.ui(
                                22,
                                weight: 800,
                                color: p.dark ? Colors.white : p.text,
                                tracking: -.03,
                                height: 1.2,
                              ),
                            ),
                            if (next.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                next,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Cristal.ui(
                                  17,
                                  weight: 800,
                                  color: p.text.withValues(alpha: .38),
                                  tracking: -.02,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
