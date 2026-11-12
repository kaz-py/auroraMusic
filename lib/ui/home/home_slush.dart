/// Dueño: tema Slush.
///
/// Posee la portada (HomeMusicPage: maquetación de la página, introducción editorial y las tarjetas de estante: grupo, pista y reciente). El SlushHome de escritorio vive en `ui/slush/slush_home.dart`.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../artwork.dart';
import '../horizontal_music_row.dart';
import '../dj_panel.dart';
import '../playlist_shelf.dart';
import '../slush/slush_decor.dart';
import '../slush/slush_home.dart';
import '../slush/slush_mobile.dart';
import '../studio/home_introduction.dart';
import '../studio/studio_symbols.dart';
import 'home_theme.dart';

/// Slush: implementación de [HomeTheme].
const HomeTheme slushHome = SlushHomeTheme();

class SlushHomeTheme extends HomeTheme {
  const SlushHomeTheme();

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
    return LayoutBuilder(
      builder: (context, bounds) {
        final width = bounds.maxWidth;
        final compact = width < 600;
        var i = 0;
        final gap = SlushSpacing.sectionGap(width);
        Widget band(Widget child) => Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: SlushBand(
            tone: SlushBand.tones[i++ % SlushBand.tones.length],
            padding: EdgeInsets.all(
              compact ? SlushSpacing.s16 : SlushSpacing.s24,
            ),
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
                  itemBuilder: (context, index) => HomeRecentSleeve(
                    controller: c,
                    track: c.recentTracks[index],
                    actionLabel: 'Reanudar',
                    onPlay: () =>
                        play(context, c.recentTracks[index], c.recentTracks),
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
                      followedCard(followed[index]),
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
                  itemBuilder: (context, index) => HomeTrackCard(
                    controller: c,
                    track: c.tracks[index],
                    actionLabel: 'Escuchar',
                    onPlay: () => play(context, c.tracks[index], c.tracks),
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
      },
    );
  }

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) {
    return SlushHome(controller: intro.controller, onSearch: intro.onSearch);
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
    return _SlushTile(
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
    return _SlushTile(
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
    return _SlushTile(
      track: track,
      title: track.title,
      subtitle: track.artist,
      tooltip: '$actionLabel ${track.title}',
      icon: StudioSymbols.playArrow,
      onPlay: onPlay,
    );
  }
}

/// Tarjeta de estante de Slush (inicialmente idéntica a la de Modern): portada radio 12, título Inter 600, play menta.
class _SlushTile extends StatelessWidget {
  const _SlushTile({
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
