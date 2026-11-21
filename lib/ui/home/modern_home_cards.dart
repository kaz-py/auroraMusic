/// Tarjetas principales de la portada Modern: «Seguir escuchando», DJ
/// personal, estado vacío y ajustes del DJ. Dueño: tema Modern.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/dj_modes.dart';
import '../../theme/modern_cristal.dart';
import '../artwork.dart';
import '../dj_filters_panel.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import 'home_theme.dart';
import 'modern_home_widgets.dart';

const _coverShadow = [
  BoxShadow(
    color: Color(0x99000000),
    blurRadius: 40,
    offset: Offset(0, 18),
    spreadRadius: -12,
  ),
];

/// Hero «Seguir escuchando»: portada, título, onda de búsqueda y play.
class ModernHomeHero extends StatelessWidget {
  const ModernHomeHero({
    super.key,
    required this.data,
    required this.track,
    required this.compact,
  });

  final HomePageData data;
  final Track track;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = data.controller;
    final scaled = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final queue = c.tracks.any((t) => t.id == track.id)
        ? c.tracks
        : <Track>[track];
    return RepaintBoundary(
      child: ModernCoverTint(
        track: track,
        builder: (context, tint) => ModernGlass(
          radius: 24,
          tint: tint,
          padding: EdgeInsets.all(compact ? 16 : 24),
          child: LayoutBuilder(
            builder: (context, box) {
              final stacked = box.maxWidth < 280 || (compact && scaled);
              final side = stacked
                  ? (box.maxWidth < 200 ? box.maxWidth : 200.0)
                  : compact
                  ? 120.0
                  : 156.0;
              final cover = DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _coverShadow,
                ),
                child: Artwork(track: track, size: side, radius: 16),
              );
              final info = _HeroInfo(
                data: data,
                track: track,
                queue: queue,
                compact: compact,
              );
              return stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [cover, const SizedBox(height: 16), info],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        cover,
                        SizedBox(width: compact ? 16 : 24),
                        Expanded(child: info),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }
}

class _HeroInfo extends StatelessWidget {
  const _HeroInfo({
    required this.data,
    required this.track,
    required this.queue,
    required this.compact,
  });

  final HomePageData data;
  final Track track;
  final List<Track> queue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = data.controller;
    final cr = Cristal.of(context);
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final jam = c.jamPlaybackActive;
        final current = c.nowTrack?.id == track.id;
        final playing = current && c.audio.isPlaying;
        final length = current && c.audio.duration > Duration.zero
            ? c.audio.duration
            : track.duration;
        final position = current ? c.audio.position : Duration.zero;
        final progress = length > Duration.zero
            ? (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        final canSeek = current && !jam && length > Duration.zero;
        final album = track.album?.trim() ?? '';
        final subtitle = compact
            ? [
                track.artist,
                if (length > Duration.zero)
                  '${miniClock(position)} / ${miniClock(length)}',
              ].join(' · ')
            : [
                track.artist,
                if (album.isNotEmpty) album,
                if (current) playing ? 'Ahora suena' : 'En pausa',
              ].join(' · ');

        void toggle() {
          if (current) {
            unawaited(c.togglePlayback());
          } else {
            unawaited(data.play(context, track, queue));
          }
        }

        final play = Tooltip(
          message: playing ? 'Pausar' : 'Reproducir ${track.title}',
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: cr.accent.withValues(alpha: .4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                  spreadRadius: -6,
                ),
              ],
            ),
            child: Material(
              color: cr.accent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: jam ? null : toggle,
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 28,
                    color: cr.onAccent,
                  ),
                ),
              ),
            ),
          ),
        );
        final vinyl = data.onVinyl;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const ModernLabel('Seguir escuchando'),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Cristal.ui(
                compact ? 24 : 34,
                weight: 800,
                color: cr.text,
                tracking: -.03,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Cristal.ui(
                compact ? 14 : 15,
                weight: 500,
                color: cr.text2,
              ),
            ),
            SizedBox(height: compact ? 14 : 16),
            if (!compact) ...[
              Row(
                children: [
                  Text(
                    miniClock(position),
                    style: Cristal.mono(11.5, color: cr.text3, tracking: 0),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ModernWaveSeekBar(
                      progress: progress,
                      seed: track.id,
                      height: 36,
                      onSeek: canSeek
                          ? (f) => unawaited(
                              c.seek(
                                Duration(
                                  milliseconds: (length.inMilliseconds * f)
                                      .round(),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    miniClock(length),
                    style: Cristal.mono(11.5, color: cr.text3, tracking: 0),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                play,
                if (vinyl != null && !compact)
                  ModernHomePill(
                    label: 'Modo Vinilo',
                    icon: Icons.album_outlined,
                    onTap: jam
                        ? null
                        : () async {
                            if (!current) {
                              await c.playTrack(track, context: queue);
                            }
                            if (context.mounted) vinyl();
                          },
                  ),
                ModernSignalChip(label: modernFormatLabel(track)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Biblioteca vacía: invitación a añadir o buscar música.
class ModernHomeEmpty extends StatelessWidget {
  const ModernHomeEmpty({super.key, required this.data});

  final HomePageData data;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    return ModernGlass(
      radius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModernLabel('Empieza aquí'),
          const SizedBox(height: 8),
          Text(
            'Tu biblioteca está vacía',
            style: Cristal.ui(
              28,
              weight: 800,
              color: cr.text,
              tracking: -.03,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Añade archivos de música o busca una canción: aquí verás lo último que escuchaste.',
            style: Cristal.ui(15, weight: 500, color: cr.text2),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              ModernHomePill(
                accent: true,
                icon: Icons.add,
                label: 'Añadir música a tu biblioteca',
                onTap: data.controller.importFiles,
              ),
              ModernHomePill(
                icon: Icons.search,
                label: 'Buscar música',
                onTap: data.onSearch,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// DJ personal: ecualizador, estado, modos y arranque. Todo el trabajo es
/// del controlador (`startDjSession`, `setDjMode`, `stopPersonalDj`).
class ModernHomeDj extends StatefulWidget {
  const ModernHomeDj({
    super.key,
    required this.controller,
    required this.compact,
  });

  final AppController controller;
  final bool compact;

  @override
  State<ModernHomeDj> createState() => _ModernHomeDjState();
}

class _ModernHomeDjState extends State<ModernHomeDj> {
  bool _starting = false;
  bool _failed = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    final c = widget.controller;
    final ok = await c.startDjSession(
      includeDiscovery: c.personalDjIncludeDiscovery,
    );
    if (mounted) {
      setState(() {
        _starting = false;
        _failed = !ok;
      });
    }
  }

  static String _mode(DjMode m) => switch (m) {
    DjMode.discover => 'Descubrir',
    DjMode.relax => 'Calma',
    DjMode.energy => 'Energía',
    DjMode.mood => 'Ánimo',
  };

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    final compact = widget.compact;
    final scaled = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        final active = c.personalDjActive;
        final jam = c.jamPlaybackActive;
        final next = c.personalDjNextReason;
        final note = jam
            ? 'Hay una Jam en curso: el DJ queda en pausa hasta que termine.'
            : _failed && !active
            ? 'No hay con qué empezar: añade música a tu biblioteca, busca una canción o revisa tu conexión.'
            : active && c.personalDjError != null
            ? 'El DJ seguirá con tu biblioteca: ${c.personalDjError}'
            : null;
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: ModernLabel('DJ personal', color: cr.accent)),
                if (active) ModernLabel('En vivo', color: cr.text2),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tu mezcla personal',
              style: Cristal.ui(
                compact ? 18 : 22,
                weight: 800,
                color: cr.text,
                tracking: -.02,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                active ? 'DJ activo · ${c.djMode.label}' : 'DJ detenido',
                key: const ValueKey('dj-status'),
                style: Cristal.ui(
                  13,
                  weight: 600,
                  color: active ? cr.signal : cr.text2,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              active
                  ? (next == null
                        ? 'La cola no termina: el DJ sigue sumando canciones.'
                        : 'A continuación: $next')
                  : 'Sesión sin fin con tu perfil, tus favoritos y recomendaciones.',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Cristal.ui(13, weight: 500, color: cr.text2),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in DjMode.values)
                  _ModeChip(
                    label: _mode(mode),
                    selected: c.djMode == mode,
                    onTap: () => unawaited(c.setDjMode(mode)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            ModernHomePill(
              key: const ValueKey('dj-toggle'),
              accent: true,
              icon: Icons.auto_awesome,
              busy: _starting,
              label: _starting
                  ? 'Preparando el DJ…'
                  : active
                  ? 'Detener DJ'
                  : 'Iniciar DJ',
              onTap: _starting || jam
                  ? null
                  : active
                  ? c.stopPersonalDj
                  : _start,
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note, style: Cristal.ui(12.5, weight: 500, color: cr.like)),
            ],
          ],
        );
        return ModernGlass(
          radius: 24,
          padding: EdgeInsets.all(compact ? 16 : 20),
          child: LayoutBuilder(
            builder: (context, box) {
              final eq = ModernHomeEq(active: active);
              if (compact && box.maxWidth >= 300 && !scaled) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    eq,
                    const SizedBox(width: 16),
                    Expanded(child: body),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [eq, const SizedBox(height: 14), body],
              );
            },
          ),
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? cr.chip : cr.glass,
        shape: StadiumBorder(
          side: selected ? BorderSide.none : BorderSide(color: cr.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Cristal.ui(
                  13,
                  weight: 700,
                  color: selected ? cr.onChip : cr.text2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ajustes del DJ que no caben en la tarjeta: novedades de YouTube,
/// actualizar/descubrir y filtros.
class ModernHomeDjMore extends StatelessWidget {
  const ModernHomeDjMore({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final busy = c.discoveringRecommendations;
        return ModernGlass(
          radius: 24,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModernLabel('Afinar el DJ'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Incluir novedades de YouTube',
                  style: Cristal.ui(14, weight: 700, color: cr.text),
                ),
                subtitle: Text(
                  'Hasta 2 búsquedas por recarga, guiadas por tu perfil.',
                  style: Cristal.ui(12.5, weight: 500, color: cr.text3),
                ),
                value: c.personalDjIncludeDiscovery,
                onChanged: c.setPersonalDjIncludeDiscovery,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ModernHomePill(
                    icon: Icons.refresh,
                    label: 'Actualizar recomendaciones',
                    onTap: c.refreshRecommendations,
                  ),
                  ModernHomePill(
                    icon: Icons.travel_explore,
                    busy: busy,
                    label: busy
                        ? 'Buscando en YouTube…'
                        : c.discoveredRecommendations.isEmpty
                        ? 'Descubrir en YouTube'
                        : 'Actualizar descubrimiento',
                    onTap: busy || !c.canDiscoverRecommendations
                        ? null
                        : c.discoverRecommendations,
                  ),
                ],
              ),
              if (c.recommendationDiscoveryError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'No se pudo buscar: ${c.recommendationDiscoveryError}',
                    style: Cristal.ui(12.5, weight: 500, color: cr.like),
                  ),
                ),
              const SizedBox(height: 8),
              DjFiltersPanel(controller: c),
            ],
          ),
        );
      },
    );
  }
}
