/// Página de Inicio del tema Modern «Cristal y aura»: saludo, hero, DJ,
/// recomendaciones, descargas recientes y los estantes de siempre.
/// Escritorio (>= 900) y móvil (chips de filtro, sin saludo: lo pinta el
/// chrome). Dueño: tema Modern.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import '../horizontal_music_row.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import '../playlist_shelf.dart';
import '../studio/home_introduction.dart' show studioClock;
import '../track_actions.dart';
import '../artwork.dart';
import 'home_theme.dart';
import 'modern_home_cards.dart';
import 'modern_home_widgets.dart';

enum _Filter { todo, musica, dj, descargas, jam }

extension on _Filter {
  String get label => switch (this) {
    _Filter.todo => 'Todo',
    _Filter.musica => 'Música',
    _Filter.dj => 'DJ',
    _Filter.descargas => 'Descargas',
    _Filter.jam => 'Jam',
  };
}

class ModernHomePage extends StatefulWidget {
  const ModernHomePage({super.key, required this.data});

  final HomePageData data;

  @override
  State<ModernHomePage> createState() => _ModernHomePageState();
}

class _ModernHomePageState extends State<ModernHomePage> {
  _Filter _filter = _Filter.todo;
  bool _allRecs = false;

  HomePageData get d => widget.data;
  AppController get c => d.controller;

  /// Pista del hero: lo que suena (o la Jam), lo último escuchado o la
  /// primera de la biblioteca.
  Track? get _heroTrack {
    bool ok(Track t) => !t.isPendingSpotifyMatch;
    final now = c.nowTrack;
    if (now != null) return now;
    return c.recentTracks.where(ok).firstOrNull ??
        c.tracks.where(ok).firstOrNull;
  }

  /// Descargas completadas, la más nueva primero; sin ellas, los archivos
  /// locales de la biblioteca.
  List<Track> get _downloaded {
    final byId = {for (final t in c.tracks) t.id: t};
    final seen = <String>{};
    final out = <Track>[];
    for (final job in c.downloads) {
      if (job.status != DownloadStatus.completed) continue;
      final path = job.localPath ?? byId[job.track.id]?.localPath;
      if (path == null || !seen.add(job.track.id)) continue;
      out.add(byId[job.track.id] ?? job.track.copyWith(localPath: path));
    }
    if (out.isNotEmpty) return out;
    return c.tracks.where((t) => t.isLocal).toList();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 900;
    final margin = mobile ? 16.0 : 32.0;
    final gap = mobile ? 28.0 : 36.0;
    bool on(Set<_Filter> s) => !mobile || s.contains(_filter);

    final hero = _heroTrack;
    final heroBlock = hero == null
        ? ModernHomeEmpty(data: d)
        : ModernHomeHero(data: d, track: hero, compact: mobile);
    final djBlock = ModernHomeDj(controller: c, compact: mobile);

    final blocks = <Widget>[];
    if (mobile) {
      blocks.add(
        _FilterChips(
          selected: _filter,
          onSelect: (f) => setState(() => _filter = f),
        ),
      );
      if (on({_Filter.todo, _Filter.musica, _Filter.jam})) {
        blocks.add(heroBlock);
      }
      if (_filter == _Filter.jam && !c.jamPlaybackActive) {
        blocks.add(const _JamEmpty());
      }
      if (on({_Filter.todo, _Filter.dj})) blocks.add(djBlock);
    } else {
      blocks.add(_Header(data: d));
      blocks.add(
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [heroBlock, const SizedBox(height: 20), djBlock],
              );
            }
            final djWidth = (box.maxWidth * .34).clamp(340.0, 440.0);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: heroBlock),
                const SizedBox(width: 24),
                SizedBox(width: djWidth, child: djBlock),
              ],
            );
          },
        ),
      );
    }
    if (on({_Filter.todo, _Filter.musica})) blocks.add(_recs(mobile));
    if (on({_Filter.todo, _Filter.descargas})) blocks.add(_downloads(mobile));
    if (on({_Filter.todo, _Filter.dj})) {
      blocks.add(ModernHomeDjMore(controller: c));
    }
    if (on({_Filter.todo, _Filter.musica})) blocks.addAll(_shelves(mobile));

    final children = <Widget>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) children.add(SizedBox(height: i == 1 && mobile ? 16 : gap));
      children.add(blocks[i]);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(
        margin,
        mobile ? 8 : 28,
        margin,
        mobile ? 160 : 120,
      ),
      children: children,
    );
  }

  // --- Recomendaciones ----------------------------------------------------

  Widget _recs(bool mobile) {
    final cr = Cristal.of(context);
    final recs = d.recommendations;
    final subtitle = d.personalized
        ? 'Basado en tus favoritos, listas y escucha reciente'
        : 'Aún no hay señales personales; elegimos de tu biblioteca';
    final title = mobile ? 'Recomendaciones' : 'Recomendaciones para ti';
    final link = recs.length > (mobile ? 6 : 8)
        ? ModernHomePill(
            link: mobile,
            label: _allRecs ? 'Ver menos' : 'Ver todo',
            onTap: () => setState(() => _allRecs = !_allRecs),
          )
        : null;
    return Column(
      key: const ValueKey('home-recommendations'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModernHomeSection(
          title: title,
          subtitle: mobile ? null : subtitle,
          trailing: link,
        ),
        const SizedBox(height: 16),
        if (recs.isEmpty)
          Text(
            c.tracks.isEmpty
                ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
            style: Cristal.ui(14, weight: 500, color: cr.text2),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final w = box.maxWidth;
              Widget tile(int i, {double radius = 16}) {
                final r = recs[i];
                return HomeTrackCard(
                  controller: c,
                  track: r.track,
                  reason: r.reason,
                  actionLabel: 'Reproducir',
                  onPlay: () => d.play(
                    context,
                    r.track,
                    d.recommendedTracks,
                    replaceQueue: false,
                  ),
                );
              }

              if (mobile) {
                final item = (w - 12) / 2;
                final shown = _allRecs ? recs.length : math.min(6, recs.length);
                return Wrap(
                  spacing: 12,
                  runSpacing: 20,
                  children: [
                    for (var i = 0; i < shown; i++)
                      SizedBox(width: item, child: tile(i)),
                  ],
                );
              }
              final item = ((w - 7 * 16) / 8).clamp(132.0, 220.0);
              if (_allRecs) {
                return Wrap(
                  spacing: 16,
                  runSpacing: 24,
                  children: [
                    for (var i = 0; i < recs.length; i++)
                      SizedBox(width: item, child: tile(i)),
                  ],
                );
              }
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < math.min(8, recs.length); i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      SizedBox(width: item, child: tile(i)),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  // --- Descargas ----------------------------------------------------------

  Widget _downloads(bool mobile) {
    final cr = Cristal.of(context);
    final items = _downloaded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ModernHomeSection(
          title: 'Descargas recientes',
          subtitle: 'Listas sin conexión',
          trailing: ModernHomePill(
            icon: Icons.download_outlined,
            label: 'Descargas',
            onTap: d.onDownloads,
          ),
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          Text(
            'Aún no hay descargas. Lo que descargues aparecerá aquí, listo para sonar sin conexión.',
            style: Cristal.ui(14, weight: 500, color: cr.text2),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final shown = items.take(mobile ? 5 : 6).toList();
              final narrow = box.maxWidth < 480;
              Widget row(int i) => _DownloadRow(
                index: i + 1,
                track: shown[i],
                controller: c,
                narrow: narrow,
                onTap: () => d.play(context, shown[i], items),
              );
              if (box.maxWidth >= 760) {
                final half = (shown.length + 1) ~/ 2;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        children: [for (var i = 0; i < half; i++) row(i)],
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [
                          for (var i = half; i < shown.length; i++) row(i),
                        ],
                      ),
                    ),
                  ],
                );
              }
              return Column(
                children: [for (var i = 0; i < shown.length; i++) row(i)],
              );
            },
          ),
      ],
    );
  }

  // --- Estantes de siempre -------------------------------------------------

  List<Widget> _shelves(bool mobile) {
    final text = MediaQuery.textScalerOf(context);
    final followed = d.followed;
    const w = 180.0;
    final h = w + 12 + text.scale(76);
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ModernHomePill(
            icon: Icons.favorite_border,
            label: 'Favoritos',
            onTap: d.onLikes,
          ),
        ],
      ),
      if (c.recentTracks.isNotEmpty)
        HorizontalMusicRow(
          key: const ValueKey('home-recent'),
          title: 'Escuchados recientemente',
          subtitle: 'Continúa donde lo dejaste',
          itemWidth: w,
          itemCount: c.recentTracks.length,
          itemHeight: h,
          itemBuilder: (context, i) => HomeRecentSleeve(
            controller: c,
            track: c.recentTracks[i],
            actionLabel: 'Reanudar',
            onPlay: () => d.play(context, c.recentTracks[i], c.recentTracks),
          ),
        ),
      if (c.discoveredRecommendations.isNotEmpty)
        HorizontalMusicRow(
          title: 'Encontradas en YouTube',
          subtitle: 'Búsqueda solicitada por ti',
          itemCount: c.discoveredRecommendations.length,
          itemWidth: w,
          itemHeight: h,
          itemBuilder: (context, i) => HomeTrackCard(
            controller: c,
            track: c.discoveredRecommendations[i],
            actionLabel: 'Reproducir',
            onPlay: () => d.play(
              context,
              c.discoveredRecommendations[i],
              c.discoveredRecommendations,
              replaceQueue: false,
            ),
          ),
        ),
      if (c.playlists.isNotEmpty)
        PlaylistShelf(
          controller: c,
          horizontal: true,
          onOpen: d.onOpenPlaylist,
        ),
      if (followed.isNotEmpty)
        HorizontalMusicRow(
          key: const ValueKey('home-artists'),
          title: 'Tus artistas',
          itemCount: followed.length,
          itemWidth: w,
          itemHeight: h,
          itemBuilder: (context, i) => d.followedCard(followed[i]),
        ),
      if (c.tracks.isNotEmpty)
        HorizontalMusicRow(
          key: const ValueKey('home-library'),
          title: 'Tu colección',
          subtitle:
              '${c.tracks.length} canciones · ${c.playlists.length} listas',
          itemCount: c.tracks.length,
          itemWidth: w,
          itemHeight: h,
          itemBuilder: (context, i) => HomeTrackCard(
            controller: c,
            track: c.tracks[i],
            actionLabel: 'Escuchar',
            onPlay: () => d.play(context, c.tracks[i], c.tracks),
          ),
        ),
    ];
  }
}

/// Saludo de escritorio: «Buenas noches, Pablo», resumen real, búsqueda y
/// temporizador de sueño (solo si está activo).
class _Header extends StatelessWidget {
  const _Header({required this.data});

  final HomePageData data;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    final c = data.controller;
    final local = c.tracks.where((t) => t.isLocal).length;
    final summary = c.tracks.isEmpty
        ? 'Tu biblioteca está vacía · empieza buscando música'
        : local == 0
        ? '${c.tracks.length} canciones en tu biblioteca · tu música lista'
        : '$local ${local == 1 ? 'canción local' : 'canciones locales'} · tu música lista';
    final sleep = c.sleepRemaining;
    final minutes = sleep == null ? 0 : (sleep.inSeconds / 60).ceil();
    final actions = Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 280,
          child: Material(
            color: cr.glass,
            shape: StadiumBorder(side: BorderSide(color: cr.border)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: data.onSearch,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: cr.text2),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Buscar…',
                          style: Cristal.ui(14, weight: 500, color: cr.text2),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (sleep != null)
          Semantics(
            label: 'Temporizador de sueño',
            child: ModernGlass(
              radius: 999,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bedtime_outlined, size: 16, color: cr.text2),
                  const SizedBox(width: 8),
                  Text(
                    minutes < 1 ? 'Dormir · <1 min' : 'Dormir · $minutes min',
                    style: Cristal.ui(13, weight: 600, color: cr.text),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
    final greeting = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            modernGreeting(studioClock(), c.profileName),
            style: Cristal.ui(
              34,
              weight: 800,
              color: cr.text,
              tracking: -.03,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(summary, style: Cristal.ui(15, weight: 500, color: cr.text2)),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 760
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [greeting, const SizedBox(height: 16), actions],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: greeting),
                const SizedBox(width: 24),
                actions,
              ],
            ),
    );
  }
}

/// Chips de filtro móviles: desplazables, 40 px de alto.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelect});

  final _Filter selected;
  final ValueChanged<_Filter> onSelect;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final f in _Filter.values) ...[
            if (f != _Filter.todo) const SizedBox(width: 8),
            Semantics(
              button: true,
              selected: f == selected,
              child: Material(
                color: f == selected ? cr.chip : cr.glass,
                shape: StadiumBorder(
                  side: f == selected
                      ? BorderSide.none
                      : BorderSide(color: cr.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(f),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 40,
                      minWidth: 48,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          f.label,
                          style: Cristal.ui(
                            14,
                            weight: 700,
                            color: f == selected ? cr.onChip : cr.text2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _JamEmpty extends StatelessWidget {
  const _JamEmpty();

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    return ModernGlass(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ModernLabel('Jam'),
          const SizedBox(height: 8),
          Text(
            'No hay ninguna Jam en curso',
            style: Cristal.ui(
              20,
              weight: 800,
              color: cr.text,
              tracking: -.02,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Crea una sesión o únete a la de un amigo desde la sección Jam y escuchen lo mismo a la vez.',
            style: Cristal.ui(14, weight: 500, color: cr.text2),
          ),
        ],
      ),
    );
  }
}

/// Fila de la lista de descargas: índice, portada 40, título/artista,
/// formato y duración.
class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.index,
    required this.track,
    required this.controller,
    required this.narrow,
    required this.onTap,
  });

  final int index;
  final Track track;
  final AppController controller;
  final bool narrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cr = Cristal.of(context);
    final chip = ModernSignalChip(
      label: modernFormatLabel(track),
      led: false,
      size: 10,
    );
    final time = track.duration > Duration.zero
        ? miniClock(track.duration)
        : '';
    return TrackActionsRegion(
      controller: controller,
      track: track,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cr.border)),
        ),
        child: Tooltip(
          message: 'Reproducir ${track.title}',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Row(
                  children: [
                    if (!narrow)
                      SizedBox(
                        width: 28,
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          style: Cristal.mono(11, color: cr.text3, tracking: 0),
                        ),
                      ),
                    SizedBox.square(
                      dimension: 40,
                      child: Artwork(track: track, size: 40, radius: 8),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Cristal.ui(
                              14.5,
                              weight: 700,
                              color: cr.text,
                            ),
                          ),
                          if (narrow)
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cristal.ui(
                                    13,
                                    weight: 500,
                                    color: cr.text3,
                                  ),
                                ),
                                chip,
                              ],
                            )
                          else
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Cristal.ui(
                                13,
                                weight: 500,
                                color: cr.text3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!narrow) ...[const SizedBox(width: 12), chip],
                    if (time.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Text(
                        time,
                        style: Cristal.mono(12.5, color: cr.text2, tracking: 0),
                      ),
                    ],
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
