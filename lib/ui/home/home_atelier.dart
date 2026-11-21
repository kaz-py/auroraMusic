/// Dueño: tema Atelier («Papel y tinta»).
///
/// Posee la portada (HomeMusicPage): saludo editorial, secciones numeradas
/// (Nº 01 Seguir escuchando, Nº 02 Tu DJ personal, Nº 03 Recomendaciones) y las
/// tarjetas de estante: portada + título serif + artista, sin cajas.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/recommendations.dart';
import '../../theme/atelier_theme.dart';
import '../artwork.dart';
import '../shell/atelier_widgets.dart';
import '../studio/home_introduction.dart';
import 'home_theme.dart';

/// Atelier («Papel y tinta»): implementación de [HomeTheme].
const HomeTheme atelierHome = AtelierHomeTheme();

class AtelierHomeTheme extends HomeTheme {
  const AtelierHomeTheme();

  @override
  Widget buildPage(BuildContext context, HomePageData d) =>
      _AtelierHome(data: d);

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) => _Greeting(controller: intro.controller, desktop: true);

  @override
  Widget groupTile(
    BuildContext context, {
    required Track cover,
    required String title,
    required String count,
    required bool artist,
    required String tooltip,
    required VoidCallback onPlay,
  }) => _Tile(
    track: cover,
    title: title,
    subtitle: count,
    tooltip: tooltip,
    round: artist,
    onPlay: onPlay,
  );

  @override
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  }) => _Tile(
    track: track,
    title: track.title,
    subtitle: track.artist,
    reason: reason,
    tooltip: track.isPendingSpotifyMatch
        ? 'Elegir audio para ${track.title}'
        : '$actionLabel ${track.title}',
    onPlay: onPlay,
  );

  @override
  Widget recentTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
  }) => _Tile(
    track: track,
    title: track.title,
    subtitle: track.artist,
    tooltip: '$actionLabel ${track.title}',
    onPlay: onPlay,
  );
}

/// Portada + título serif + artista. Ocupa el ancho que le den.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.track,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.onPlay,
    this.reason,
    this.round = false,
  });
  final Track track;
  final String title, subtitle, tooltip;
  final String? reason;
  final bool round;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPlay,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: round
                    ? ClipOval(child: Artwork.fill(track: track))
                    : AtelierCover(track: track),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.serif(19, height: 1.15),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.ui(13, color: t.ink2),
              ),
              if (reason != null) ...[
                const SizedBox(height: 4),
                Text(
                  reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.ui(12, color: t.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _salute(DateTime now) => now.hour < 6
    ? 'Buenas noches'
    : now.hour < 13
    ? 'Buenos días'
    : now.hour < 21
    ? 'Buenas tardes'
    : 'Buenas noches';

/// Saludo grande: «Buenas tardes, *Pablo*.» y una línea con el resumen real
/// de la biblioteca.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.controller, required this.desktop});
  final AppController controller;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final now = studioClock();
    final name = controller.profileName.trim();
    final size = desktop ? 56.0 : 38.0;
    final summary =
        '${controller.tracks.length} canciones · ${controller.playlists.length} listas en tu biblioteca';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (desktop) Text(atelierDateLabel(now), style: t.mono(size: 11)),
        if (desktop) const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: _salute(now)),
              if (name.isNotEmpty) ...[
                const TextSpan(text: ', '),
                TextSpan(
                  text: name,
                  style: t.serif(
                    size,
                    italic: true,
                    color: t.accentText,
                    height: 1.05,
                    letterSpacing: desktop ? -1.1 : -.4,
                  ),
                ),
              ],
              const TextSpan(text: '.'),
            ],
          ),
          style: t.serif(
            size,
            height: 1.05,
            letterSpacing: desktop ? -1.1 : -.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          summary,
          style: t.serif(desktop ? 20 : 17, italic: true, color: t.ink2),
        ),
      ],
    );
  }
}

class _AtelierHome extends StatefulWidget {
  const _AtelierHome({required this.data});
  final HomePageData data;

  @override
  State<_AtelierHome> createState() => _AtelierHomeState();
}

class _AtelierHomeState extends State<_AtelierHome> {
  /// Móvil: filtro de secciones (0 todo, 1 música, 2 DJ, 3 listas).
  int _filter = 0;

  bool _show(int group) => _filter == 0 || _filter == group;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final c = d.controller;
    return LayoutBuilder(
      builder: (context, box) {
        final desktop = box.maxWidth >= 720;
        final pad = desktop ? 48.0 : 20.0;
        final inner = box.maxWidth - 2 * pad;
        final split = inner >= 900;
        final hero = _hero(context, d);
        final recs = d.recommendations;
        final dj = _djSection(
          context,
          d,
          recs.take(4).toList(),
          mobile: !desktop,
        );
        final forYou = recs.length > 4
            ? recs.skip(4).map((r) => (r.track, r.reason)).toList()
            : [for (final tr in c.tracks.take(6)) (tr, null as String?)];
        var n = 0;
        int next() => ++n;
        final sections = <Widget>[
          if (_show(1) && _show(2) && split)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: hero(next())),
                const SizedBox(width: 48),
                Expanded(flex: 5, child: dj(next())),
              ],
            )
          else ...[
            if (_show(1)) hero(next()),
            if (_show(2)) dj(next()),
          ],
          if (_show(2) && forYou.isNotEmpty)
            _Section(
              number: next(),
              title: 'Recomendaciones para ti',
              trailing: d.personalized ? 'ACTUALIZADO HOY' : null,
              child: _Editorial(
                key: const ValueKey('home-recommendations'),
                data: d,
                items: forYou,
              ),
            ),
          if (_show(1) && c.recentTracks.isNotEmpty)
            _Section(
              number: next(),
              title: 'Escuchados recientemente',
              trailing: 'CONTINÚA DONDE LO DEJASTE',
              child: _Shelf(
                key: const ValueKey('home-recent'),
                count: c.recentTracks.length,
                builder: (i) => HomeRecentSleeve(
                  controller: c,
                  track: c.recentTracks[i],
                  actionLabel: 'Reanudar',
                  onPlay: () =>
                      d.play(context, c.recentTracks[i], c.recentTracks),
                ),
              ),
            ),
          if (_show(3) && c.playlists.isNotEmpty)
            _Section(
              number: next(),
              title: 'Tus listas',
              child: _Shelf(
                key: const ValueKey('home-playlists'),
                count: c.playlists.length,
                builder: (i) => _PlaylistTile(
                  controller: c,
                  playlist: c.playlists[i],
                  onOpen: d.onOpenPlaylist,
                ),
              ),
            ),
          if (_show(1) && d.followed.isNotEmpty)
            _Section(
              number: next(),
              title: 'Tus artistas',
              child: _Shelf(
                key: const ValueKey('home-artists'),
                count: d.followed.length,
                builder: (i) => d.followedCard(d.followed[i]),
              ),
            ),
          if (_show(1) && c.discoveredRecommendations.isNotEmpty)
            _Section(
              number: next(),
              title: 'Encontradas en YouTube',
              trailing: 'BÚSQUEDA SOLICITADA POR TI',
              child: _Shelf(
                count: c.discoveredRecommendations.length,
                builder: (i) => HomeTrackCard(
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
            ),
          if (_show(1) && c.tracks.isNotEmpty)
            _Section(
              number: next(),
              title: 'Tu colección',
              trailing:
                  '${c.tracks.length} CANCIONES · ${c.playlists.length} LISTAS',
              child: _Shelf(
                key: const ValueKey('home-library'),
                count: c.tracks.length,
                builder: (i) => HomeTrackCard(
                  controller: c,
                  track: c.tracks[i],
                  actionLabel: 'Escuchar',
                  onPlay: () => d.play(context, c.tracks[i], c.tracks),
                ),
              ),
            ),
        ];
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, desktop ? 8 : 16, pad, 32),
          children: [
            _Greeting(controller: c, desktop: desktop),
            const SizedBox(height: 16),
            if (desktop) _quickLinks(context, d) else _filters(context),
            const SizedBox(height: 24),
            for (final s in sections) ...[s, const SizedBox(height: 32)],
            if (c.tracks.isEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: c.importFiles,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir música a tu biblioteca'),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _quickLinks(BuildContext context, HomePageData d) {
    final t = AtelierTokens.of(context);
    Widget link(IconData icon, String label, VoidCallback onTap) =>
        OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: t.ink,
            side: BorderSide(color: t.rule),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2),
            ),
            textStyle: t.mono(size: 12),
          ),
          icon: Icon(icon, size: 16),
          label: Text(label),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        link(Icons.download_outlined, 'DESCARGAS LOCALES', d.onDownloads),
        link(Icons.favorite_border, 'FAVORITOS', d.onLikes),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    final t = AtelierTokens.of(context);
    const labels = ['TODO', 'MÚSICA', 'DJ', 'LISTAS'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < labels.length; i++)
          Semantics(
            button: true,
            selected: _filter == i,
            child: InkWell(
              onTap: () => setState(() => _filter = i),
              child: IntrinsicWidth(
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    minWidth: 44,
                  ),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: _filter == i ? t.ink : Colors.transparent,
                    border: Border.all(color: _filter == i ? t.ink : t.rule),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Text(
                    labels[i],
                    style: t.mono(
                      size: 12,
                      color: _filter == i ? t.paper : t.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Nº «Seguir escuchando».
  Widget Function(int) _hero(BuildContext context, HomePageData d) {
    final c = d.controller;
    final track =
        c.nowTrack ?? c.recentTracks.firstOrNull ?? c.tracks.firstOrNull;
    return (n) => _Section(
      number: n,
      title: 'Seguir escuchando',
      trailing: c.recentTracks.isEmpty ? null : 'HISTORIAL',
      child: track == null ? _EmptyHero(data: d) : _Hero(data: d, track: track),
    );
  }

  Widget Function(int) _djSection(
    BuildContext context,
    HomePageData d,
    List<TrackRecommendation> recs, {
    required bool mobile,
  }) {
    final c = d.controller;
    final items = recs;
    return (n) => _Section(
      number: n,
      title: 'Tu DJ personal',
      subtitle: items.isEmpty
          ? null
          : d.personalized
          ? 'Basado en tus favoritos, listas y escucha reciente'
          : 'Aún no hay señales personales; elegimos de tu biblioteca',
      child: items.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                c.tracks.isEmpty
                    ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                    : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
                style: AtelierTokens.of(
                  context,
                ).ui(14, color: AtelierTokens.of(context).ink2),
              ),
            )
          : mobile
          ? _Shelf(
              key: const ValueKey('home-dj'),
              count: items.length,
              builder: (i) => _Tile(
                track: items[i].track,
                title: items[i].track.title,
                subtitle: items[i].reason,
                tooltip: 'Reproducir ${items[i].track.title}',
                onPlay: () => d.play(
                  context,
                  items[i].track,
                  d.recommendedTracks,
                  replaceQueue: false,
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _DjRow(
                    number: i + 1,
                    track: items[i].track,
                    meta: items[i].reason,
                    onTap: () => d.play(
                      context,
                      items[i].track,
                      d.recommendedTracks,
                      replaceQueue: false,
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Cabecera numerada + contenido.
class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.child,
    this.trailing,
    this.subtitle,
  });
  final int number;
  final String title;
  final String? trailing;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AtelierSectionHead(number: number, title: title, trailing: trailing),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: t.ui(13, color: t.ink2)),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.data});
  final HomePageData data;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tu historia empieza aquí', style: t.serif(32)),
        const SizedBox(height: 8),
        Text(
          'Busca una canción o abre tus archivos para comenzar.',
          style: t.ui(14, color: t.ink2),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: data.onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Encontrar música'),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.data, required this.track});
  final HomePageData data;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final c = data.controller;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final current = c.nowTrack?.id == track.id;
        final duration = current && c.audio.duration > Duration.zero
            ? c.audio.duration
            : track.duration;
        final position = current ? c.audio.position : Duration.zero;
        final progress = duration > Duration.zero
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;
        final playing = current && c.audio.isPlaying;
        final format = atelierFormat(track);
        final album = track.album?.trim();
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (album != null && album.isNotEmpty)
              Text(
                'ÁLBUM · ${album.toUpperCase()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.mono(size: 11),
              ),
            const SizedBox(height: 6),
            Text(
              track.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: t.serif(38, height: 1.08, letterSpacing: -.5),
            ),
            const SizedBox(height: 4),
            Text(
              track.artist,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.serif(18, italic: true, color: t.ink2),
            ),
            const SizedBox(height: 16),
            if (duration > Duration.zero) ...[
              Text(
                current
                    ? '-${atelierClock(duration - position)} RESTANTES'
                    : atelierClock(duration),
                style: t.mono(size: 11),
              ),
              AtelierLine(
                progress: progress,
                onSeek: current
                    ? (f) => c.seek(
                        Duration(
                          milliseconds: (duration.inMilliseconds * f).round(),
                        ),
                      )
                    : null,
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: c.jamPlaybackActive
                      ? null
                      : () => current
                            ? c.togglePlayback()
                            : data.play(
                                context,
                                track,
                                c.recentTracks.isNotEmpty
                                    ? c.recentTracks
                                    : c.tracks,
                              ),
                  icon: Icon(
                    playing ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                  label: Text(playing ? 'Pausar' : 'Reanudar'),
                ),
                OutlinedButton.icon(
                  onPressed: c.jamPlaybackActive
                      ? null
                      : () => c.addToQueue(track),
                  icon: const Icon(Icons.playlist_add, size: 20),
                  label: const Text('Añadir a la cola'),
                ),
                if (format != null) AtelierFormatChip(format),
              ],
            ),
          ],
        );
        return LayoutBuilder(
          builder: (context, box) {
            final row = box.maxWidth >= 340 && scale <= 1.3;
            final cover = row
                ? (box.maxWidth * (box.maxWidth > 560 ? .42 : .46)).clamp(
                    120.0,
                    300.0,
                  )
                : math.min(box.maxWidth, 320.0);
            final art = AtelierCover(track: track, size: cover);
            return row
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      art,
                      SizedBox(width: box.maxWidth > 560 ? 24 : 16),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [art, const SizedBox(height: 16), info],
                  );
          },
        );
      },
    );
  }
}

class _DjRow extends StatelessWidget {
  const _DjRow({
    required this.number,
    required this.track,
    required this.meta,
    required this.onTap,
  });
  final int number;
  final Track track;
  final String meta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Semantics(
      button: true,
      label: 'Reproducir ${track.title}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: t.mono(size: 11, color: t.accentText),
                ),
              ),
              AtelierCover(track: track, size: 48, shadow: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.serif(18),
                    ),
                    Text(
                      '${track.artist} · $meta',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.ui(12.5, color: t.ink2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow, size: 18, color: t.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ritmo editorial: una portada grande y varias pequeñas alineadas a la base.
class _Editorial extends StatelessWidget {
  const _Editorial({super.key, required this.data, required this.items});
  final HomePageData data;
  final List<(Track, String?)> items;

  @override
  Widget build(BuildContext context) {
    final c = data.controller;
    final tracks = [for (final (tr, _) in items) tr];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 24),
            SizedBox(
              width: i == 0 ? 220 : 160,
              child: HomeTrackCard(
                controller: c,
                track: item.$1,
                reason: i == 0 ? item.$2 : null,
                actionLabel: 'Reproducir',
                onPlay: () =>
                    data.play(context, item.$1, tracks, replaceQueue: false),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fila horizontal de tarjetas de 168 px (altura por contenido).
class _Shelf extends StatelessWidget {
  const _Shelf({super.key, required this.count, required this.builder});
  final int count;
  final Widget Function(int index) builder;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return SizedBox(
      height: 168 + 96 * scale.clamp(1.0, 2.0),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 20),
        itemBuilder: (context, i) => SizedBox(width: 168, child: builder(i)),
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  const _PlaylistTile({
    required this.controller,
    required this.playlist,
    required this.onOpen,
  });
  final AppController controller;
  final MusicPlaylist playlist;
  final ValueChanged<MusicPlaylist> onOpen;

  @override
  Widget build(BuildContext context) {
    final ids = playlist.trackIds.toSet();
    final first = controller.tracks
        .where((t) => ids.contains(t.id) && t.artworkUrl?.isNotEmpty == true)
        .firstOrNull;
    final n = playlist.trackIds.length;
    return _Tile(
      track:
          first ??
          Track(id: 'pl:${playlist.id}', title: playlist.name, artist: ''),
      title: playlist.name,
      subtitle: '$n ${n == 1 ? 'canción' : 'canciones'}',
      tooltip: 'Abrir lista ${playlist.name}',
      onPlay: () => onOpen(playlist),
    );
  }
}
