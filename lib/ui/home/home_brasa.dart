/// Dueño: tema Brasa.
///
/// Posee la portada (HomeMusicPage: maquetación de la página, introducción editorial y las tarjetas de estante: grupo, pista y reciente).
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../artwork.dart';
import '../horizontal_music_row.dart';
import '../dj_panel.dart';
import '../playlist_shelf.dart';
import '../studio/home_introduction.dart';
import '../studio/studio_symbols.dart';
import 'home_theme.dart';

/// Brasa: implementación de [HomeTheme].
const HomeTheme brasaHome = BrasaHomeTheme();

class BrasaHomeTheme extends HomeTheme {
  const BrasaHomeTheme();

  @override
  Widget buildPage(BuildContext context, HomePageData d) {
    final c = d.controller;
    final recommendations = d.recommendations;
    final recommendedTracks = d.recommendedTracks;
    final personalized = d.personalized;
    final followed = d.followed;
    final onSearch = d.onSearch;
    final onSearchQuery = d.onSearchQuery;
    final onVinyl = d.onVinyl;
    final onDownloads = d.onDownloads;
    final onLikes = d.onLikes;
    final onOpenPlaylist = d.onOpenPlaylist;
    final play = d.play;
    final followedCard = d.followedCard;
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
            itemBuilder: (context, index) => HomeRecentSleeve(
              controller: c,
              track: c.recentTracks[index],
              actionLabel: 'Reanudar',
              onPlay: () =>
                  play(context, c.recentTracks[index], c.recentTracks),
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
            itemBuilder: (context, index) => HomeTrackCard(
              controller: c,
              track: recommendations[index].track,
              reason: recommendations[index].reason,
              actionLabel: 'Reproducir',
              onPlay: () => play(
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
            itemBuilder: (context, index) => HomeTrackCard(
              controller: c,
              track: c.discoveredRecommendations[index],
              actionLabel: 'Reproducir',
              onPlay: () => play(
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
            itemBuilder: (context, index) => followedCard(followed[index]),
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
            itemBuilder: (context, index) => HomeTrackCard(
              controller: c,
              track: c.tracks[index],
              actionLabel: 'Escuchar',
              onPlay: () => play(context, c.tracks[index], c.tracks),
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

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) {
    final c = intro.controller;
    final hour = studioClock().hour;
    final greeting = hour < 6
        ? 'Buenas noches'
        : hour < 13
        ? 'Buenos días'
        : hour < 20
        ? 'Buenas tardes'
        : 'Buenas noches';
    final quick = (c.recentTracks.isNotEmpty ? c.recentTracks : c.tracks)
        .where((t) => !t.isPendingSpotifyMatch)
        .take(6)
        .toList();
    final playingId = c.currentTrack?.id;
    Widget tile(Track t) => _BrasaQuickTile(
      track: t,
      playing: t.id == playingId,
      onTap: () => c.playTrack(t, context: quick),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        if (quick.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu historia empieza aquí',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca una canción o abre tus archivos para comenzar.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: intro.onSearch,
                icon: const Icon(StudioSymbols.search),
                label: const Text('Encontrar música'),
              ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, bounds) {
              final cols = bounds.maxWidth >= 480 ? 2 : 1;
              return Column(
                children: [
                  for (var i = 0; i < quick.length; i += cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          for (var j = i; j < i + cols; j++) ...[
                            if (j > i) const SizedBox(width: 8),
                            Expanded(
                              child: j < quick.length
                                  ? tile(quick[j])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  @override
  Widget groupTile(
    BuildContext context, {
    required Track cover,
    required String title,
    required String count,
    required bool artist,
    required String tooltip,
    required VoidCallback onPlay,
  }) {
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

  @override
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  }) {
    return BrasaTile(
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
      icon: track.isPendingSpotifyMatch ? Icons.link : Icons.play_arrow_rounded,
      onPlay: onPlay,
    );
  }

  @override
  Widget recentTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
  }) {
    return BrasaTile(
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
    );
  }
}

class _BrasaQuickTile extends StatelessWidget {
  const _BrasaQuickTile({
    required this.track,
    required this.playing,
    required this.onTap,
  });
  final Track track;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Material(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: Brasa.ash,
        onTap: onTap,
        child: Row(
          children: [
            Artwork(track: track, size: 56, radius: 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: playing ? Brasa.accent : Brasa.cream,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}
