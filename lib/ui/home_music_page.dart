import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../dj/recommendations.dart';
import '../follow/follow_models.dart';
import '../follow/follow_service.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import '../theme/slush_theme.dart';
import 'artwork.dart';
import 'slush/slush_decor.dart';
import 'slush/slush_mobile.dart';
import 'studio/home_introduction.dart';
import 'studio/studio_components.dart';
import 'studio/studio_symbols.dart';
import 'dj_panel.dart';
import 'horizontal_music_row.dart';
import 'track_actions.dart';
import 'playlist_shelf.dart';
import 'spotify_match_dialog.dart';

class HomeMusicPage extends StatelessWidget {
  const HomeMusicPage({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onDownloads,
    required this.onLikes,
    required this.onOpenPlaylist,
    this.onVinyl,
    this.onSearchQuery,
    this.follow,
  });
  final AppController controller;
  final VoidCallback onSearch, onDownloads, onLikes;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final VoidCallback? onVinyl;
  final ValueChanged<String>? onSearchQuery;
  final FollowService? follow;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, follow]),
    builder: (context, _) {
      final c = controller;
      final recommendations = c.recommendations;
      final recommendedTracks = recommendations.map((r) => r.track).toList();
      final libraryIds = c.tracks.map((t) => t.id).toSet();
      final personalized =
          c.favoriteIds.any(libraryIds.contains) ||
          c.playlists.any((p) => p.trackIds.any(libraryIds.contains)) ||
          c.recentTracks.isNotEmpty;
      final text = MediaQuery.textScalerOf(context);
      final modern = isModern(context);
      final gap = modern ? 56.0 : 28.0;
      // Solo los artistas que el usuario sigue (no los deducidos de la biblioteca).
      final followed = follow?.artists ?? const <FollowedArtist>[];
      if (isBrasa(context)) {
        return _brasa(
          context,
          c,
          recommendations,
          recommendedTracks,
          personalized,
          followed,
        );
      }
      return LayoutBuilder(
        builder: (context, bounds) {
          if (isSlush(context)) {
            return _slush(
              context,
              c,
              bounds.maxWidth,
              recommendations,
              recommendedTracks,
              personalized,
              followed,
            );
          }
          final recentWidth = modern
              ? 220.0
              : bounds.maxWidth >= 560
              ? (bounds.maxWidth - 64) / 2
              : 260.0;
          return ListView(
            padding: EdgeInsets.all(modern ? 32 : 24),
            children: [
              if (isSlush(context) && bounds.maxWidth < 600)
                SlushMobileHome(controller: c, onSearch: onSearch)
              else ...[
                StudioHomeIntroduction(
                  controller: c,
                  onSearch: onSearch,
                  onSearchQuery: onSearchQuery,
                  onVinyl: onVinyl ?? onSearch,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Descargas locales'),
                      onPressed: onDownloads,
                      side: modern ? BorderSide.none : null,
                      backgroundColor: modern
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : null,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.favorite_border, size: 18),
                      label: const Text('Favoritos'),
                      onPressed: onLikes,
                      side: modern ? BorderSide.none : null,
                      backgroundColor: modern
                          ? Theme.of(context).colorScheme.surfaceContainerLow
                          : null,
                    ),
                  ],
                ),
                SizedBox(height: modern ? 48 : 24),
                if (c.recentTracks.isNotEmpty)
                  HorizontalMusicRow(
                    key: const ValueKey('home-recent'),
                    title: isSlush(context)
                        ? 'Hace poco'
                        : 'Escuchados recientemente',
                    subtitle: 'Continúa donde lo dejaste',
                    itemWidth: recentWidth,
                    itemCount: c.recentTracks.length,
                    itemHeight: 238 + text.scale(72),
                    itemBuilder: (context, index) => _RecentSleeve(
                      controller: c,
                      track: c.recentTracks[index],
                      actionLabel: 'Reanudar',
                      onPlay: () =>
                          _play(context, c.recentTracks[index], c.recentTracks),
                    ),
                  ),
              ],
              SizedBox(height: gap),
              if (recommendations.isNotEmpty)
                HorizontalMusicRow(
                  key: const ValueKey('home-recommendations'),
                  title: 'Para ti',
                  subtitle: personalized
                      ? 'Basado en tus favoritos, listas y escucha reciente'
                      : 'Aún no hay señales personales; elegimos de tu biblioteca',
                  itemCount: recommendations.length,
                  itemWidth: modern ? 220 : 200,
                  itemHeight: 228 + text.scale(136),
                  itemBuilder: (context, index) => _TrackCard(
                    controller: c,
                    track: recommendations[index].track,
                    reason: recommendations[index].reason,
                    actionLabel: 'Reproducir',
                    onPlay: () => _play(
                      context,
                      recommendations[index].track,
                      recommendedTracks,
                      replaceQueue: false,
                    ),
                  ),
                )
              else ...[
                Text('Para ti', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  c.tracks.isEmpty
                      ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                      : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
                ),
              ],
              const SizedBox(height: 16),
              DjPanel(controller: c, showRecommendations: false),
              if (c.discoveredRecommendations.isNotEmpty) ...[
                const SizedBox(height: 24),
                HorizontalMusicRow(
                  title: 'Encontradas en YouTube',
                  subtitle: 'Búsqueda solicitada por ti',
                  itemCount: c.discoveredRecommendations.length,
                  itemWidth: modern ? 220 : 200,
                  itemHeight: 220 + text.scale(72),
                  itemBuilder: (context, index) => _TrackCard(
                    controller: c,
                    track: c.discoveredRecommendations[index],
                    actionLabel: 'Reproducir',
                    onPlay: () => _play(
                      context,
                      c.discoveredRecommendations[index],
                      c.discoveredRecommendations,
                      replaceQueue: false,
                    ),
                  ),
                ),
              ],
              SizedBox(height: gap),
              if (c.playlists.isNotEmpty) ...[
                PlaylistShelf(
                  controller: c,
                  horizontal: true,
                  onOpen: onOpenPlaylist,
                ),
                SizedBox(height: gap),
              ],
              if (followed.isNotEmpty) ...[
                HorizontalMusicRow(
                  key: const ValueKey('home-artists'),
                  title: 'Tus artistas',
                  itemCount: followed.length,
                  itemWidth: modern ? 220 : 200,
                  itemHeight: 228 + text.scale(120),
                  itemBuilder: (context, index) =>
                      _followedCard(c, followed[index]),
                ),
                SizedBox(height: gap),
              ],
              if (c.tracks.isNotEmpty)
                HorizontalMusicRow(
                  key: const ValueKey('home-library'),
                  title: 'Tu colección',
                  subtitle:
                      '${c.tracks.length} canciones · ${c.playlists.length} listas',
                  itemCount: c.tracks.length,
                  itemWidth: modern ? 220 : 200,
                  itemHeight: 220 + text.scale(72),
                  itemBuilder: (context, index) => _TrackCard(
                    controller: c,
                    track: c.tracks[index],
                    actionLabel: 'Escuchar',
                    onPlay: () => _play(context, c.tracks[index], c.tracks),
                  ),
                )
              else
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
    },
  );

  /// Slush: bandas de color planas alternadas, encabezados enormes y espacio
  /// final para que la barra inferior no tape nada.
  Widget _slush(
    BuildContext context,
    AppController c,
    double width,
    List<TrackRecommendation> recommendations,
    List<Track> recommendedTracks,
    bool personalized,
    List<FollowedArtist> followed,
  ) {
    final text = MediaQuery.textScalerOf(context);
    final compact = width < 600;
    var i = 0;
    final gap = SlushSpacing.sectionGap(width);
    Widget band(Widget child) => Padding(
      padding: EdgeInsets.only(bottom: gap),
      child: SlushBand(
        tone: SlushBand.tones[i++ % SlushBand.tones.length],
        padding: EdgeInsets.all(compact ? SlushSpacing.s16 : SlushSpacing.s24),
        // Builder: el tema se toma DENTRO de la banda (claro en vivo, incluso
        // en oscuro); copiar el de fuera dejaba el texto crema sobre menta.
        child: Builder(
          builder: (ctx) {
            final inner = Theme.of(ctx);
            return Theme(
              data: inner.copyWith(
                textTheme: inner.textTheme.copyWith(
                  titleLarge: const TextStyle(
                    fontFamily: 'Bagel Fat One',
                    fontSize: 22,
                    height: 1.2,
                    color: Slush.ink,
                  ),
                ),
              ),
              child: child,
            );
          },
        ),
      ),
    );
    final itemW = width >= Breakpoints.large ? 240.0 : 200.0;
    final margin = SlushSpacing.margin(width);
    return ListView(
      padding: EdgeInsets.fromLTRB(margin, compact ? 8 : 24, margin, 140),
      children: [
        if (compact)
          SlushMobileHome(controller: c, onSearch: onSearch)
        else ...[
          StudioHomeIntroduction(
            controller: c,
            onSearch: onSearch,
            onSearchQuery: onSearchQuery,
            onVinyl: onVinyl ?? onSearch,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              SlushChip('TODO', selected: true, onTap: () {}),
              SlushChip(
                'DESCARGAS LOCALES',
                icon: Icons.download_outlined,
                color: Slush.yellow,
                onTap: onDownloads,
              ),
              SlushChip(
                'FAVORITOS',
                icon: Icons.favorite_border,
                color: Slush.mint,
                onTap: onLikes,
              ),
            ],
          ),
        ],
        SizedBox(height: gap),
        if (c.recentTracks.isNotEmpty && !compact)
          band(
            HorizontalMusicRow(
              key: const ValueKey('home-recent'),
              title: 'Hace poco',
              subtitle: 'Continúa donde lo dejaste',
              itemWidth: 260,
              itemCount: c.recentTracks.length,
              itemHeight: 238 + text.scale(72),
              itemBuilder: (context, index) => _RecentSleeve(
                controller: c,
                track: c.recentTracks[index],
                actionLabel: 'Reanudar',
                onPlay: () =>
                    _play(context, c.recentTracks[index], c.recentTracks),
              ),
            ),
          ),
        band(
          recommendations.isNotEmpty
              ? HorizontalMusicRow(
                  key: const ValueKey('home-recommendations'),
                  title: 'Para ti',
                  subtitle: personalized
                      ? 'Basado en tus favoritos, listas y escucha reciente'
                      : 'Aún no hay señales personales; elegimos de tu biblioteca',
                  itemCount: recommendations.length,
                  itemWidth: itemW,
                  itemHeight: 228 + text.scale(136),
                  itemBuilder: (context, index) => _TrackCard(
                    controller: c,
                    track: recommendations[index].track,
                    reason: recommendations[index].reason,
                    actionLabel: 'Reproducir',
                    onPlay: () => _play(
                      context,
                      recommendations[index].track,
                      recommendedTracks,
                      replaceQueue: false,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Para ti',
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Slush.ink),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.tracks.isEmpty
                          ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                          : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
                      style: const TextStyle(
                        color: Slush.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
        band(DjPanel(controller: c, showRecommendations: false)),
        if (c.discoveredRecommendations.isNotEmpty)
          band(
            HorizontalMusicRow(
              title: 'Encontradas en YouTube',
              subtitle: 'Búsqueda solicitada por ti',
              itemCount: c.discoveredRecommendations.length,
              itemWidth: itemW,
              itemHeight: 220 + text.scale(72),
              itemBuilder: (context, index) => _TrackCard(
                controller: c,
                track: c.discoveredRecommendations[index],
                actionLabel: 'Reproducir',
                onPlay: () => _play(
                  context,
                  c.discoveredRecommendations[index],
                  c.discoveredRecommendations,
                  replaceQueue: false,
                ),
              ),
            ),
          ),
        if (c.playlists.isNotEmpty)
          band(
            PlaylistShelf(
              controller: c,
              horizontal: true,
              onOpen: onOpenPlaylist,
            ),
          ),
        if (followed.isNotEmpty)
          band(
            HorizontalMusicRow(
              key: const ValueKey('home-artists'),
              title: 'Tus artistas',
              itemCount: followed.length,
              itemWidth: itemW,
              itemHeight: 228 + text.scale(120),
              itemBuilder: (context, index) =>
                  _followedCard(c, followed[index]),
            ),
          ),
        if (c.tracks.isNotEmpty)
          band(
            HorizontalMusicRow(
              key: const ValueKey('home-library'),
              title: 'Tu colección',
              subtitle:
                  '${c.tracks.length} canciones · ${c.playlists.length} listas',
              itemCount: c.tracks.length,
              itemWidth: itemW,
              itemHeight: 220 + text.scale(72),
              itemBuilder: (context, index) => _TrackCard(
                controller: c,
                track: c.tracks[index],
                actionLabel: 'Escuchar',
                onPlay: () => _play(context, c.tracks[index], c.tracks),
              ),
            ),
          )
        else
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
  }

  Widget _brasa(
    BuildContext context,
    AppController c,
    List<TrackRecommendation> recommendations,
    List<Track> recommendedTracks,
    bool personalized,
    List<FollowedArtist> followed,
  ) {
    const gap = SizedBox(height: 32);
    Widget chip(String label, IconData icon, VoidCallback? onTap) => ActionChip(
      avatar: Icon(
        icon,
        size: 18,
        color: onTap == null ? Colors.black : Brasa.cream,
      ),
      label: Text(label),
      onPressed: onTap ?? () {},
      side: BorderSide.none,
      shape: const StadiumBorder(),
      backgroundColor: onTap == null ? Brasa.cream : Brasa.graphite,
      labelStyle: TextStyle(
        color: onTap == null ? Colors.black : Brasa.cream,
        fontWeight: FontWeight.w600,
      ),
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        StudioHomeIntroduction(
          controller: c,
          onSearch: onSearch,
          onSearchQuery: onSearchQuery,
          onVinyl: onVinyl ?? onSearch,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('Todo', Icons.home_outlined, null),
            chip('Descargas locales', Icons.download_outlined, onDownloads),
            chip('Favoritos', Icons.favorite_border, onLikes),
          ],
        ),
        gap,
        if (c.recentTracks.isNotEmpty) ...[
          HorizontalMusicRow(
            key: const ValueKey('home-recent'),
            title: 'Escuchados recientemente',
            subtitle: 'Continúa donde lo dejaste',
            itemCount: c.recentTracks.length,
            itemHeight: 0,
            itemBuilder: (context, index) => _RecentSleeve(
              controller: c,
              track: c.recentTracks[index],
              actionLabel: 'Reanudar',
              onPlay: () =>
                  _play(context, c.recentTracks[index], c.recentTracks),
            ),
          ),
          gap,
        ],
        if (recommendations.isNotEmpty)
          HorizontalMusicRow(
            key: const ValueKey('home-recommendations'),
            title: 'Para ti',
            subtitle: personalized
                ? 'Basado en tus favoritos, listas y escucha reciente'
                : 'Aún no hay señales personales; elegimos de tu biblioteca',
            itemCount: recommendations.length,
            itemHeight: 0,
            itemBuilder: (context, index) => _TrackCard(
              controller: c,
              track: recommendations[index].track,
              reason: recommendations[index].reason,
              actionLabel: 'Reproducir',
              onPlay: () => _play(
                context,
                recommendations[index].track,
                recommendedTracks,
                replaceQueue: false,
              ),
            ),
          )
        else ...[
          Text('Para ti', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            c.tracks.isEmpty
                ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
          ),
        ],
        gap,
        DjPanel(controller: c, showRecommendations: false),
        if (c.discoveredRecommendations.isNotEmpty) ...[
          gap,
          HorizontalMusicRow(
            title: 'Encontradas en YouTube',
            subtitle: 'Búsqueda solicitada por ti',
            itemCount: c.discoveredRecommendations.length,
            itemHeight: 0,
            itemBuilder: (context, index) => _TrackCard(
              controller: c,
              track: c.discoveredRecommendations[index],
              actionLabel: 'Reproducir',
              onPlay: () => _play(
                context,
                c.discoveredRecommendations[index],
                c.discoveredRecommendations,
                replaceQueue: false,
              ),
            ),
          ),
        ],
        if (c.playlists.isNotEmpty) ...[
          gap,
          PlaylistShelf(
            controller: c,
            horizontal: true,
            onOpen: onOpenPlaylist,
          ),
        ],
        if (followed.isNotEmpty) ...[
          gap,
          HorizontalMusicRow(
            key: const ValueKey('home-artists'),
            title: 'Tus artistas',
            itemCount: followed.length,
            itemHeight: 0,
            itemBuilder: (context, index) => _followedCard(c, followed[index]),
          ),
        ],
        gap,
        if (c.tracks.isNotEmpty)
          HorizontalMusicRow(
            key: const ValueKey('home-library'),
            title: 'Tu colección',
            subtitle:
                '${c.tracks.length} canciones · ${c.playlists.length} listas',
            itemCount: c.tracks.length,
            itemHeight: 0,
            itemBuilder: (context, index) => _TrackCard(
              controller: c,
              track: c.tracks[index],
              actionLabel: 'Escuchar',
              onPlay: () => _play(context, c.tracks[index], c.tracks),
            ),
          )
        else
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
  }

  Widget _followedCard(AppController c, FollowedArtist a) {
    final name = a.name.trim();
    final key = name.toLowerCase();
    final own = c.tracks
        .where((t) => t.artist.trim().toLowerCase() == key)
        .where((t) => t.artworkUrl?.isNotEmpty == true)
        .firstOrNull;
    final cover = a.imageUrl?.isNotEmpty == true
        ? Track(
            id: 'follow:$key',
            title: name,
            artist: name,
            artworkUrl: a.imageUrl,
          )
        : own ?? Track(id: 'follow:$key', title: name, artist: name);
    return _GroupCard(
      title: name,
      tracks: [cover],
      countLabel: 'Artista seguido',
      artist: true,
      tooltip: 'Abrir artista $name',
      onPlay: () => c.openArtist(name),
    );
  }

  Future<void> _play(
    BuildContext context,
    Track track,
    List<Track> tracks, {
    bool replaceQueue = true,
  }) => track.isPendingSpotifyMatch
      ? SpotifyMatchDialog.show(
          context,
          track: track,
          onSearch: () => controller.findSpotifyMatches(track),
          onSave: (match, {required play}) =>
              controller.matchSpotifyTrack(track.id, match, play: play),
        )
      : controller.playTrack(
          track,
          context: tracks,
          replaceQueue: replaceQueue,
        );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.tracks,
    required this.tooltip,
    required this.onPlay,
    this.countLabel,
    this.artist = false,
  });
  final String title, tooltip;
  final String? countLabel;
  final List<Track> tracks;
  final VoidCallback onPlay;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    final cover =
        tracks
            .where((track) => track.artworkUrl?.isNotEmpty == true)
            .firstOrNull ??
        tracks.first;
    final count =
        countLabel ??
        '${tracks.length} ${tracks.length == 1 ? 'canción' : 'canciones'}';
    if (isBrasa(context)) {
      return BrasaTile(
        cover: Artwork(
          track: cover,
          artworkContext: ArtworkContext.card,
          radius: artist ? 90 : 6,
        ),
        title: title,
        subtitle: count,
        round: artist,
        tooltip: tooltip,
        onPlay: onPlay,
      );
    }
    if (isModern(context)) {
      return _ModernTile(
        track: cover,
        title: title,
        subtitle: count,
        round: artist,
        tooltip: tooltip,
        icon: StudioSymbols.playArrow,
        onPlay: onPlay,
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: StudioPalette.of(context),
      child: InkWell(
        borderRadius: StudioPalette.of(context),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Artwork(
                    track: cover,
                    artworkContext: ArtworkContext.card,
                    radius: artist ? 88 : 2,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: IconButton.filled(
                      tooltip: tooltip,
                      onPressed: onPlay,
                      icon: const Icon(StudioSymbols.playArrow),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Newsreader',
                  fontSize: 24,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                count,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  const _TrackCard({
    required this.controller,
    required this.track,
    required this.actionLabel,
    required this.onPlay,
    this.reason,
  });
  final AppController controller;
  final Track track;
  final String actionLabel;
  final VoidCallback onPlay;
  final String? reason;

  @override
  Widget build(BuildContext context) => TrackActionsRegion(
    controller: controller,
    track: track,
    builder: (context, _) => isBrasa(context)
        ? BrasaTile(
            cover: Artwork(
              track: track,
              artworkContext: ArtworkContext.card,
              radius: 6,
            ),
            title: track.title,
            subtitle: track.artist,
            caption: reason,
            playing: controller.currentTrack?.id == track.id,
            tooltip: track.isPendingSpotifyMatch
                ? 'Elegir audio para ${track.title}'
                : '$actionLabel ${track.title}',
            icon: track.isPendingSpotifyMatch
                ? Icons.link
                : Icons.play_arrow_rounded,
            onPlay: onPlay,
          )
        : isModern(context)
        ? _ModernTile(
            track: track,
            title: track.title,
            subtitle: track.artist,
            caption: reason,
            tooltip: track.isPendingSpotifyMatch
                ? 'Elegir audio para ${track.title}'
                : '$actionLabel ${track.title}',
            icon: track.isPendingSpotifyMatch
                ? Icons.link
                : StudioSymbols.playArrow,
            onPlay: onPlay,
          )
        : Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: StudioPalette.of(context),
            child: InkWell(
              borderRadius: StudioPalette.of(context),
              onTap: onPlay,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Stack(
                      children: [
                        Artwork(
                          track: track,
                          artworkContext: ArtworkContext.card,
                          radius: 2,
                        ),
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: IconButton.filled(
                            tooltip: track.isPendingSpotifyMatch
                                ? 'Elegir audio para ${track.title}'
                                : '$actionLabel ${track.title}',
                            onPressed: onPlay,
                            icon: Icon(
                              track.isPendingSpotifyMatch
                                  ? Icons.link
                                  : StudioSymbols.playArrow,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 24,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (reason != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        reason!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
  );
}

class _RecentSleeve extends StatelessWidget {
  const _RecentSleeve({
    required this.controller,
    required this.track,
    required this.actionLabel,
    required this.onPlay,
  });
  final AppController controller;
  final Track track;
  final String actionLabel;
  final VoidCallback onPlay;
  @override
  Widget build(BuildContext context) => TrackActionsRegion(
    controller: controller,
    track: track,
    builder: (context, _) => isBrasa(context)
        ? BrasaTile(
            cover: Artwork(
              track: track,
              artworkContext: ArtworkContext.card,
              radius: 6,
            ),
            title: track.title,
            subtitle: track.artist,
            playing: controller.currentTrack?.id == track.id,
            tooltip: '$actionLabel ${track.title}',
            onPlay: onPlay,
          )
        : isModern(context)
        ? _ModernTile(
            track: track,
            title: track.title,
            subtitle: track.artist,
            tooltip: '$actionLabel ${track.title}',
            icon: StudioSymbols.playArrow,
            onPlay: onPlay,
          )
        : Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: StudioPalette.of(context),
            child: InkWell(
              borderRadius: StudioPalette.of(context),
              onTap: onPlay,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Center(
                            child: Artwork(
                              track: track,
                              artworkContext: ArtworkContext.cardDetail,
                              radius: 2,
                            ),
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton.filled(
                              tooltip: '$actionLabel ${track.title}',
                              onPressed: onPlay,
                              icon: const Icon(StudioSymbols.playArrow),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 24,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}

/// Tarjeta Modern de estante: portada radio 12, título Inter 600, play menta.
class _ModernTile extends StatelessWidget {
  const _ModernTile({
    required this.track,
    required this.title,
    required this.subtitle,
    required this.tooltip,
    required this.icon,
    required this.onPlay,
    this.caption,
    this.round = false,
  });
  final Track track;
  final String title, subtitle, tooltip;
  final String? caption;
  final IconData icon;
  final VoidCallback onPlay;
  final bool round;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: ModernCard(
        onTap: onPlay,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Artwork(
                  track: track,
                  artworkContext: ArtworkContext.card,
                  radius: round ? 88 : 12,
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Tooltip(
                    message: tooltip,
                    child: Material(
                      color: Tracky.mint,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onPlay,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(icon, size: 22, color: Tracky.navy),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 1.25,
                letterSpacing: -.16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
