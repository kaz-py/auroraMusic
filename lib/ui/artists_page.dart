import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../follow/follow_service.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/slush_theme.dart';
import '../theme/slush_widgets.dart';
import 'slush/slush_pages.dart';
import 'horizontal_music_row.dart';
import '../theme/modern_widgets.dart';
import 'follow_widgets.dart';
import 'artwork.dart';
import 'studio/studio_components.dart';
import 'track_actions.dart';

/// Browse the artists represented by the tracks supplied by the caller.
class ArtistsPage extends StatefulWidget {
  const ArtistsPage({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onSearch,
    this.controller,
    this.follow,
  });

  /// Si se pasa, la ficha ofrece «Seguir / Siguiendo».
  final FollowService? follow;

  /// Si se pasa, las canciones ofrecen cola/Jam (menú ⋯, clic derecho, atajos).
  final AppController? controller;
  final List<Track> tracks;
  final ValueChanged<Track> onPlay;
  final ValueChanged<String> onSearch;

  @override
  State<ArtistsPage> createState() => _ArtistsPageState();
}

class _ArtistsPageState extends State<ArtistsPage> {
  _Artist? _selectedArtist;

  void _back() => setState(() => _selectedArtist = null);

  List<_Artist> _artists() {
    final groups = <String, List<Track>>{};
    for (final track in widget.tracks) {
      final name = track.artist.trim();
      if (name.isEmpty) continue;
      (groups[name.toLowerCase()] ??= []).add(track);
    }
    final follow = widget.follow;
    // Con seguimiento disponible solo se listan los artistas seguidos, aunque
    // no tengan canciones en la biblioteca.
    final artists =
        follow != null
              ? follow.artists
                    .map(
                      (a) => _Artist(
                        groups[a.name.toLowerCase().trim()] ?? const [],
                        name: a.name.trim(),
                        imageUrl: a.imageUrl,
                      ),
                    )
                    .toList()
              : groups.values.map(_Artist.new).toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return artists;
  }

  @override
  Widget build(BuildContext context) {
    final follow = widget.follow;
    if (follow == null) return _content(context);
    return ListenableBuilder(
      listenable: follow,
      builder: (context, _) => _content(context),
    );
  }

  void _open(_Artist artist) {
    final c = widget.controller;
    if (widget.follow != null && c != null) {
      c.openArtist(artist.name);
    } else if (artist.tracks.isNotEmpty) {
      setState(() => _selectedArtist = artist);
    }
  }

  Widget _content(BuildContext context) {
    final artists = _artists();
    final selected = _selectedArtist;
    if (selected != null) {
      final current = artists
          .where((artist) => artist.key == selected.key)
          .firstOrNull;
      if (current == null) _selectedArtist = null;
      return current == null ? _artistList(artists) : _artistDetail(current);
    }
    return _artistList(artists);
  }

  Widget _artistList(List<_Artist> artists) {
    final slush = isSlush(context);
    if (artists.isEmpty && slush) {
      return SlushEmpty(
        icon: Icons.mic_none_rounded,
        title: widget.follow != null
            ? 'Aún no sigues a ningún artista'
            : 'Todavía no hay artistas',
        message: widget.follow != null
            ? 'Sigue a un artista desde su perfil o desde el reproductor con el botón Seguir.'
            : 'Busca música para encontrar artistas y añadir canciones a tu biblioteca.',
        sticker: 'AÚN NO',
        actionLabel: 'Buscar música',
        onAction: () => widget.onSearch(''),
      );
    }
    if (artists.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (!isSlush(context)) ...[
            Text('Artistas', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 24),
          ],
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                children: [
                  Icon(
                    Icons.mic_none_rounded,
                    size: 48,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.follow != null
                        ? 'Aún no sigues a ningún artista'
                        : 'Todavía no hay artistas',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.follow != null
                        ? 'Sigue a un artista desde su perfil o desde el reproductor con el botón Seguir.'
                        : 'Busca música para encontrar artistas y añadir canciones a tu biblioteca.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => widget.onSearch(''),
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar música'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final modern = isModern(context);
    final brasa = isBrasa(context);
    final count = widget.follow != null
        ? '${artists.length} ${artists.length == 1 ? 'artista que sigues' : 'artistas que sigues'}'
        : '${artists.length} ${artists.length == 1 ? 'artista' : 'artistas'} en tu biblioteca';
    final subtitle = Text(
      count,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (slush) return _slushGrid(artists, count);
    if (brasa) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Artistas',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  subtitle,
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 196,
                mainAxisExtent: 250,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: artists.length,
              itemBuilder: (context, i) {
                final artist = artists[i];
                return BrasaTile(
                  cover: Artwork(
                    track: artist.cover,
                    artworkContext: ArtworkContext.card,
                    radius: 90,
                  ),
                  title: artist.name,
                  subtitle: artist.countLabel,
                  round: true,
                  tooltip: 'Abrir ${artist.name}',
                  onPlay: () => _open(artist),
                );
              },
            ),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: EdgeInsets.all(modern ? 32 : 24),
      itemCount: artists.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: EdgeInsets.only(bottom: modern ? 32 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (modern)
                  const ModernHeadline(before: 'Tus ', emphasis: 'artistas')
                else
                  Text(
                    'Artistas',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                const SizedBox(height: 8),
                subtitle,
              ],
            ),
          );
        }
        final artist = artists[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _ArtistTile(artist: artist, onTap: () => _open(artist)),
        );
      },
    );
  }

  Widget _artistDetail(_Artist artist) {
    final modern = isModern(context);
    final cover = artist.cover;
    if (isBrasa(context)) return _brasaDetail(artist);
    final header = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _selectedArtist = null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Todos los artistas'),
        ),
      ),
      const SizedBox(height: 12),
      Center(
        child: Artwork(
          track: cover,
          artworkContext: ArtworkContext.card,
          radius: 88,
        ),
      ),
      const SizedBox(height: 16),
      if (modern)
        Center(
          child: ModernHeadline(
            before: artist.name,
            size: 40,
            align: TextAlign.center,
          ),
        )
      else
        Text(
          artist.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      const SizedBox(height: 4),
      Text(
        '${artist.tracks.length} ${artist.tracks.length == 1 ? 'canción' : 'canciones'}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      if (widget.follow != null) ...[
        const SizedBox(height: 12),
        Center(
          child: FollowButton(service: widget.follow!, name: artist.name),
        ),
      ],
      SizedBox(height: modern ? 32 : 20),
      if (widget.controller != null) ...[
        TrackBatchButtons(
          controller: widget.controller!,
          tracks: artist.tracks,
        ),
        const SizedBox(height: 8),
      ],
    ];
    // Todas las canciones del artista, construidas bajo demanda.
    return ListView.builder(
      padding: EdgeInsets.all(modern ? 32 : 24),
      itemCount: header.length + artist.tracks.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final track = artist.tracks[i - header.length];
        return _TrackTile(
          track: track,
          controller: widget.controller,
          onPlay: () => widget.onPlay(track),
        );
      },
    );
  }
}

extension on _ArtistsPageState {
  /// Slush: rejilla circular de 3/4/5/7 columnas según el ancho.
  Widget _slushGrid(List<_Artist> artists, String count) {
    final p = context.slush;
    final ts = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final margin = SlushSpacing.margin(w);
        final side = w > 1440 ? (w - 1440) / 2 + margin : margin;
        final cols = w >= Breakpoints.large
            ? 7
            : w >= Breakpoints.medium
            ? 5
            : w >= Breakpoints.compact
            ? 4
            : 3;
        final gap = w < Breakpoints.compact ? SlushSpacing.s8 : 16.0;
        final cell = (w - side * 2 - gap * (cols - 1)) / cols;
        // avatar + nombre (2 líneas) + recuento, con relleno de 8 en la tarjeta.
        final extent =
            cell + 8 + ts.scale(14) * 1.25 * 2 + ts.scale(12) * 1.3 + 8;
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, SlushSpacing.s16),
              sliver: SliverToBoxAdapter(
                child: Text(
                  count,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: p.ink2,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, SlushSpacing.s24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisExtent: extent,
                  crossAxisSpacing: gap,
                  mainAxisSpacing: gap,
                ),
                itemCount: artists.length,
                itemBuilder: (context, i) => _SlushArtistTile(
                  artist: artists[i],
                  onTap: () => _open(artists[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on _ArtistsPageState {
  /// Perfil Brasa: cabecera grande, play ámbar y todas las canciones en filas.
  Widget _brasaDetail(_Artist artist) {
    final c = widget.controller;
    final tracks = artist.tracks;
    final head = <Widget>[
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Todos los artistas'),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 24,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Artwork(
            track: artist.cover,
            artworkContext: ArtworkContext.card,
            radius: 90,
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  artist.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 48,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    color: Brasa.cream,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}',
                  style: const TextStyle(fontSize: 14, color: Brasa.cloud),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (tracks.isNotEmpty)
            Tooltip(
              message: 'Reproducir ${artist.name}',
              child: Material(
                color: Brasa.accent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => widget.onPlay(tracks.first),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      size: 32,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ),
          if (widget.follow != null)
            FollowButton(service: widget.follow!, name: artist.name),
          if (c != null) TrackBatchButtons(controller: c, tracks: tracks),
        ],
      ),
      const SizedBox(height: 24),
    ];
    // Todas las canciones, construidas bajo demanda.
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: head.length + tracks.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final n = i - head.length;
        return _BrasaTrackRow(
          index: n + 1,
          track: tracks[n],
          controller: c,
          onPlay: () => widget.onPlay(tracks[n]),
        );
      },
    );
  }
}

class _BrasaTrackRow extends StatelessWidget {
  const _BrasaTrackRow({
    required this.index,
    required this.track,
    required this.onPlay,
    this.controller,
  });
  final int index;
  final Track track;
  final VoidCallback onPlay;
  final AppController? controller;

  @override
  Widget build(BuildContext context) {
    final playing = controller?.currentTrack?.id == track.id;
    final d = track.duration;
    final time =
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    Widget row(BuildContext context, bool hot) => Tooltip(
      message: 'Reproducir ${track.title}',
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          hoverColor: Brasa.graphite,
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    '$index',
                    style: TextStyle(
                      fontSize: 14,
                      color: playing ? Brasa.accent : Brasa.steel,
                    ),
                  ),
                ),
                Artwork(track: track, size: 40, radius: 4),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: playing ? Brasa.accent : Brasa.cream,
                    ),
                  ),
                ),
                Text(
                  time,
                  style: const TextStyle(fontSize: 14, color: Brasa.steel),
                ),
                if (controller != null)
                  TrackMenuButton(
                    controller: controller!,
                    track: track,
                    quickAdd: true,
                    quickAddVisible: hot,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return RepaintBoundary(
      child: controller == null
          ? row(context, true)
          : TrackActionsRegion(
              controller: controller!,
              track: track,
              builder: row,
            ),
    );
  }
}

class _Artist {
  _Artist(this.tracks, {String? name, this.imageUrl}) : _name = name;

  final List<Track> tracks;
  final String? _name;
  final String? imageUrl;
  String get name => _name ?? tracks.first.artist.trim();

  /// Foto del artista seguido o, si no hay, la portada de una canción suya.
  Track get cover {
    if (imageUrl?.isNotEmpty == true) {
      return Track(
        id: 'follow:$key',
        title: name,
        artist: name,
        artworkUrl: imageUrl,
      );
    }
    return tracks.where((t) => t.artworkUrl?.isNotEmpty == true).firstOrNull ??
        tracks.firstOrNull ??
        Track(id: 'follow:$key', title: name, artist: name);
  }

  String get countLabel => tracks.isEmpty
      ? 'Siguiendo'
      : '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}';
  String get key => name.toLowerCase();
}

/// Slush: avatar circular con borde `line`, nombre 1-2 líneas centrado y
/// recuento. Hover/pulsado = solo capa de color (sin escala ni sombra).
class _SlushArtistTile extends StatelessWidget {
  const _SlushArtistTile({required this.artist, required this.onTap});

  final _Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return Tooltip(
      message: 'Abrir ${artist.name}',
      child: SlushPressable(
        onTap: onTap,
        radius: SlushRadius.r24,
        elevation: SlushElevation.none,
        pressedScale: 1,
        minSize: 0,
        semanticLabel: 'Abrir ${artist.name}',
        child: Padding(
          padding: const EdgeInsets.all(SlushSpacing.s8),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final d = box.maxWidth;
                  return DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.fromBorderSide(p.border),
                    ),
                    child: Artwork(
                      track: artist.cover,
                      artworkContext: ArtworkContext.card,
                      size: d,
                      radius: d / 2,
                    ),
                  );
                },
              ),
              const SizedBox(height: SlushSpacing.s8),
              Text(
                artist.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                  color: p.ink,
                ),
              ),
              Text(
                artist.countLabel,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: p.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistTile extends StatelessWidget {
  const _ArtistTile({required this.artist, required this.onTap});

  final _Artist artist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cover = artist.cover;
    if (isModern(context)) {
      return ModernCard(
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Artwork(
              track: cover,
              artworkContext: ArtworkContext.thumbnailDetail,
              radius: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    artist.countLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: StudioPalette.of(context),
      child: InkWell(
        onTap: onTap,
        borderRadius: StudioPalette.of(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Artwork(
                track: cover,
                artworkContext: ArtworkContext.thumbnailDetail,
                radius: 32,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      artist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      artist.countLabel,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.onPlay,
    this.controller,
  });

  final AppController? controller;
  final Track track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final modern = isModern(context);
    final playIcon = modern
        ? Icon(Icons.play_arrow_rounded, color: Tracky.navy)
        : const Icon(Icons.play_arrow_rounded);
    final playStyle = modern
        ? IconButton.styleFrom(
            backgroundColor: Tracky.mint,
            hoverColor: Tracky.mint.withValues(alpha: .7),
          )
        : null;
    Widget tile(BuildContext context, bool hot) => ListTile(
      shape: modern
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
          : null,
      hoverColor: modern
          ? Theme.of(context).colorScheme.surfaceContainerLow
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Artwork(
        track: track,
        artworkContext: ArtworkContext.thumbnail,
        radius: 4,
      ),
      title: Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (track.album?.trim().isNotEmpty == true) track.album!.trim(),
          _duration(track.duration),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: controller == null
          ? IconButton(
              tooltip: 'Reproducir ${track.title}',
              onPressed: onPlay,
              style: playStyle,
              icon: playIcon,
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Reproducir ${track.title}',
                  onPressed: onPlay,
                  style: playStyle,
                  icon: playIcon,
                ),
                TrackMenuButton(
                  controller: controller!,
                  track: track,
                  quickAdd: true,
                  quickAddVisible: hot,
                ),
              ],
            ),
      onTap: onPlay,
    );
    return controller == null
        ? tile(context, true)
        : TrackActionsRegion(
            controller: controller!,
            track: track,
            builder: tile,
          );
  }

  String _duration(Duration duration) =>
      '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';
}
