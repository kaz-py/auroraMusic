/// Dueño: tema Modern.
///
/// Posee la portada (HomeMusicPage: maquetación de la página, introducción editorial y las tarjetas de estante: grupo, pista y reciente).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/modern_widgets.dart';
import '../artwork.dart';
import '../horizontal_music_row.dart';
import '../dj_panel.dart';
import '../playlist_shelf.dart';
import '../studio/home_introduction.dart';
import '../studio/studio_symbols.dart';
import 'home_theme.dart';

/// Modern: implementación de [HomeTheme].
const HomeTheme modernHome = ModernHomeTheme();

class ModernHomeTheme extends HomeTheme {
  const ModernHomeTheme();

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
    final text = MediaQuery.textScalerOf(context);
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
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
              side: BorderSide.none,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
            ),
            ActionChip(
              avatar: const Icon(Icons.favorite_border, size: 18),
              label: const Text('Favoritos'),
              onPressed: onLikes,
              side: BorderSide.none,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow,
            ),
          ],
        ),
        const SizedBox(height: 48),
        if (c.recentTracks.isNotEmpty)
          HorizontalMusicRow(
            key: const ValueKey('home-recent'),
            title: 'Escuchados recientemente',
            subtitle: 'Continúa donde lo dejaste',
            itemWidth: 220,
            itemCount: c.recentTracks.length,
            itemHeight: 238 + text.scale(72),
            itemBuilder: (context, index) => HomeRecentSleeve(
              controller: c,
              track: c.recentTracks[index],
              actionLabel: 'Reanudar',
              onPlay: () =>
                  play(context, c.recentTracks[index], c.recentTracks),
            ),
          ),
        const SizedBox(height: 56),
        if (recommendations.isNotEmpty)
          HorizontalMusicRow(
            key: const ValueKey('home-recommendations'),
            title: 'Para ti',
            subtitle: personalized
                ? 'Basado en tus favoritos, listas y escucha reciente'
                : 'Aún no hay señales personales; elegimos de tu biblioteca',
            itemCount: recommendations.length,
            itemWidth: 220,
            itemHeight: 228 + text.scale(136),
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
        const SizedBox(height: 16),
        DjPanel(controller: c, showRecommendations: false),
        if (c.discoveredRecommendations.isNotEmpty) ...[
          const SizedBox(height: 24),
          HorizontalMusicRow(
            title: 'Encontradas en YouTube',
            subtitle: 'Búsqueda solicitada por ti',
            itemCount: c.discoveredRecommendations.length,
            itemWidth: 220,
            itemHeight: 220 + text.scale(72),
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
        const SizedBox(height: 56),
        if (c.playlists.isNotEmpty) ...[
          PlaylistShelf(
            controller: c,
            horizontal: true,
            onOpen: onOpenPlaylist,
          ),
          const SizedBox(height: 56),
        ],
        if (followed.isNotEmpty) ...[
          HorizontalMusicRow(
            key: const ValueKey('home-artists'),
            title: 'Tus artistas',
            itemCount: followed.length,
            itemWidth: 220,
            itemHeight: 228 + text.scale(120),
            itemBuilder: (context, index) => followedCard(followed[index]),
          ),
          const SizedBox(height: 56),
        ],
        if (c.tracks.isNotEmpty)
          HorizontalMusicRow(
            key: const ValueKey('home-library'),
            title: 'Tu colección',
            subtitle:
                '${c.tracks.length} canciones · ${c.playlists.length} listas',
            itemCount: c.tracks.length,
            itemWidth: 220,
            itemHeight: 220 + text.scale(72),
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
    final width = MediaQuery.sizeOf(context).width;
    // Android/estrecho: sin saludo ni titular, solo el botón.
    final compactModern = width < 600;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!compactModern) ...[
          ModernBadge(studioGreeting(studioClock()), tone: ModernTone.mint),
          const SizedBox(height: 20),
          ModernHeadline(
            before: 'Tu ',
            emphasis: 'música',
            after: ', siempre',
            size: width < 600 ? 40 : 60,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Escucha lo que amas, descubre lo que viene y deja que el DJ siga por ti.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        FilledButton.icon(
          onPressed: intro.onSearch,
          icon: const Icon(StudioSymbols.search),
          label: const Text('Encontrar música'),
        ),
      ],
    );
    if (track == null) return left;
    // Ancho: hero en dos columnas; estrecho: una columna.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 1100
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: left),
                const SizedBox(width: 40),
                Expanded(flex: 6, child: _modernFeature(context, track, intro)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 48),
                _modernFeature(context, track, intro),
              ],
            ),
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
    return ModernHomeTile(
      track: cover,
      title: title,
      subtitle: count,
      round: artist,
      tooltip: tooltip,
      icon: StudioSymbols.playArrow,
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
    return ModernHomeTile(
      track: track,
      title: track.title,
      subtitle: track.artist,
      caption: reason,
      tooltip: track.isPendingSpotifyMatch
          ? 'Elegir audio para ${track.title}'
          : '$actionLabel ${track.title}',
      icon: track.isPendingSpotifyMatch ? Icons.link : StudioSymbols.playArrow,
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
    return ModernHomeTile(
      track: track,
      title: track.title,
      subtitle: track.artist,
      tooltip: '$actionLabel ${track.title}',
      icon: StudioSymbols.playArrow,
      onPlay: onPlay,
    );
  }
}

Widget _modernFeature(
  BuildContext context,
  Track track,
  StudioHomeIntroduction intro,
) {
  final c = intro.controller;
  final onVinyl = intro.onVinyl;
  final albumTracks = track.album?.trim().isNotEmpty == true
      ? c.tracks
            .where(
              (t) =>
                  t.album == track.album &&
                  t.artist == track.artist &&
                  !t.isPendingSpotifyMatch,
            )
            .toList()
      : [track];
  final title = track.album?.trim().isNotEmpty == true
      ? track.album!
      : track.title;
  final still = MediaQuery.disableAnimationsOf(context);
  return RepaintBoundary(
    child: ModernCard(
      dark: true,
      feature: true,
      padding: const EdgeInsets.all(28),
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 560;
          final cover = Transform.rotate(
            angle: still ? 0 : -5 * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Artwork(
                track: track,
                artworkContext: ArtworkContext.card,
                radius: 12,
              ),
            ),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ModernBadge('Seguir escuchando', tone: ModernTone.butter),
              const SizedBox(height: 16),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Bagel Fat One',
                  fontSize: 32,
                  height: 1.15,
                  letterSpacing: .96,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${track.artist} · ${albumTracks.length} pistas',
                style: const TextStyle(color: Color(0xffb4b7c4)),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Tracky.navy,
                    ),
                    onPressed: c.jamPlaybackActive
                        ? null
                        : () => c.playTrack(track, context: albumTracks),
                    icon: const Icon(StudioSymbols.playArrow, size: 18),
                    label: Text(
                      track.album == null
                          ? 'Reproducir selección'
                          : 'Reproducir pistas disponibles',
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0x66ffffff)),
                    ),
                    onPressed: c.jamPlaybackActive
                        ? null
                        : () async {
                            if (c.currentTrack?.id != track.id) {
                              await c.playTrack(track, context: albumTracks);
                            }
                            if (context.mounted) onVinyl();
                          },
                    icon: const Icon(StudioSymbols.album, size: 18),
                    label: const Text('Girar en Modo Vinilo'),
                  ),
                  IconButton(
                    tooltip: 'Guardar en favoritos',
                    color: Colors.white,
                    onPressed: () => c.toggleFavorite(track),
                    icon: Icon(
                      c.favoriteIds.contains(track.id)
                          ? StudioSymbols.favorite
                          : StudioSymbols.bookmarkAdd,
                    ),
                  ),
                ],
              ),
            ],
          );
          return wide
              ? Row(
                  children: [
                    Expanded(child: info),
                    const SizedBox(width: 32),
                    cover,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: cover),
                    const SizedBox(height: 24),
                    info,
                  ],
                );
        },
      ),
    ),
  );
}

/// Tarjeta Modern de estante: portada radio 12, título Inter 600, play menta.
class ModernHomeTile extends StatelessWidget {
  const ModernHomeTile({
    super.key,
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
