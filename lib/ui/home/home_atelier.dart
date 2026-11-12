/// Dueño: tema Atelier Sonoro (sin marca).
///
/// Posee la portada (HomeMusicPage: maquetación de la página, introducción editorial y las tarjetas de estante: grupo, pista y reciente).
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../artwork.dart';
import '../horizontal_music_row.dart';
import '../dj_panel.dart';
import '../playlist_shelf.dart';
import '../studio/home_introduction.dart';
import '../studio/studio_components.dart';
import '../studio/studio_symbols.dart';
import 'home_theme.dart';

/// Atelier Sonoro (sin marca): implementación de [HomeTheme].
const HomeTheme atelierHome = AtelierHomeTheme();

class AtelierHomeTheme extends HomeTheme {
  const AtelierHomeTheme();

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
        final recentWidth = bounds.maxWidth >= 560
            ? (bounds.maxWidth - 64) / 2
            : 260.0;
        return ListView(
          padding: const EdgeInsets.all(24),
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
                ),
                ActionChip(
                  avatar: const Icon(Icons.favorite_border, size: 18),
                  label: const Text('Favoritos'),
                  onPressed: onLikes,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (c.recentTracks.isNotEmpty)
              HorizontalMusicRow(
                key: const ValueKey('home-recent'),
                title: 'Escuchados recientemente',
                subtitle: 'Continúa donde lo dejaste',
                itemWidth: recentWidth,
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
            const SizedBox(height: 28),
            if (recommendations.isNotEmpty)
              HorizontalMusicRow(
                key: const ValueKey('home-recommendations'),
                title: 'Para ti',
                subtitle: personalized
                    ? 'Basado en tus favoritos, listas y escucha reciente'
                    : 'Aún no hay señales personales; elegimos de tu biblioteca',
                itemCount: recommendations.length,
                itemWidth: 200,
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
                itemWidth: 200,
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
            const SizedBox(height: 28),
            if (c.playlists.isNotEmpty) ...[
              PlaylistShelf(
                controller: c,
                horizontal: true,
                onOpen: onOpenPlaylist,
              ),
              const SizedBox(height: 28),
            ],
            if (followed.isNotEmpty) ...[
              HorizontalMusicRow(
                key: const ValueKey('home-artists'),
                title: 'Tus artistas',
                itemCount: followed.length,
                itemWidth: 200,
                itemHeight: 228 + text.scale(120),
                itemBuilder: (context, index) => followedCard(followed[index]),
              ),
              const SizedBox(height: 28),
            ],
            if (c.tracks.isNotEmpty)
              HorizontalMusicRow(
                key: const ValueKey('home-library'),
                title: 'Tu colección',
                subtitle:
                    '${c.tracks.length} canciones · ${c.playlists.length} listas',
                itemCount: c.tracks.length,
                itemWidth: 200,
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
      },
    );
  }

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            StudioStamp(
              '● CALIBRACIÓN DE SEÑAL · VÁLVULAS CALIENTES',
              color: colors.primary,
            ),
            const StudioStamp('LATENCIA DAC: NO MEDIDA // MOTOR AURORA'),
          ],
        ),
        const SizedBox(height: 16),
        const StudioGreetingRow(),
        const SizedBox(height: 8),
        Text(
          'La resonancia del recinto está optimizada a 432Hz. El flujo analógico simula la atenuación natural de cinta magnética Studer A800.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.tertiary),
        ),
        const SizedBox(height: 4),
        const StudioStamp(
          'TEXTO DE REFERENCIA · SIMULACIÓN ANALÓGICA PENDIENTE',
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _mood(
                context,
                StudioSymbols.waterDrop,
                'Tarde Lluviosa',
                () => showStudioPending(context, 'Ánimos de escucha'),
              ),
              _mood(
                context,
                StudioSymbols.graphicEq,
                'Cinta Magnética',
                () => showStudioPending(context, 'Simulación de cinta'),
              ),
              _mood(context, StudioSymbols.nightlife, 'Improvisación Jazz', () {
                _searchMood(intro, 'jazz');
              }),
              _mood(
                context,
                StudioSymbols.psychology,
                'Enfoque Profundo',
                () => showStudioPending(context, 'Perfil de enfoque'),
              ),
              _mood(context, StudioSymbols.acUnit, 'Acústica Nórdica', () {
                _searchMood(intro, 'acústica nórdica');
              }),
            ],
          ),
        ),
        const SizedBox(height: 36),
        if (track != null)
          _master(context, intro, track)
        else
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
                const SizedBox(height: 20),
                Text(
                  'Tu historia empieza aquí',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Busca una canción o abre tus archivos para comenzar.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: intro.onSearch,
                  icon: const Icon(StudioSymbols.search),
                  label: const Text('ENCONTRAR MÚSICA'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 40),
        const StudioStamp('CAJA DE DISCOS // ROTACIÓN RECIENTE'),
        const SizedBox(height: 4),
        Text(
          'Crate Digger: Archivos en Rotación',
          style: Theme.of(context).textTheme.headlineSmall,
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

  @override
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  }) {
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
                  reason,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
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
    return Material(
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
    );
  }
}

Widget _mood(
  BuildContext context,
  IconData icon,
  String label,
  VoidCallback action,
) => Padding(
  padding: const EdgeInsets.only(right: 4, bottom: 4),
  child: TextButton.icon(
    style: TextButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),
    onPressed: action,
    icon: Icon(icon, size: 16),
    label: Text(label),
  ),
);

void _searchMood(StudioHomeIntroduction intro, String query) {
  if (intro.onSearchQuery != null) {
    intro.onSearchQuery!(query);
  } else {
    intro.onSearch();
    intro.controller.search(query);
  }
}

Widget _master(
  BuildContext context,
  StudioHomeIntroduction intro,
  Track track,
) {
  final c = intro.controller;
  final colors = Theme.of(context).colorScheme;
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
  final info = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StudioStamp(track.artist.toUpperCase(), color: colors.primary),
      const SizedBox(height: 8),
      Text(
        track.album?.trim().isNotEmpty == true ? track.album! : track.title,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 16),
      StudioPanel(
        recessed: true,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notas de producción y edición',
              style: TextStyle(
                fontFamily: 'Newsreader',
                fontStyle: FontStyle.italic,
                fontSize: 18,
                color: colors.tertiary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Aurora todavía no dispone de notas de estudio para esta selección.',
            ),
            const SizedBox(height: 16),
            StudioStamp(
              '${albumTracks.length} PISTAS // ${track.isLocal ? 'ARCHIVO LOCAL' : 'FUENTE DE AUDIO EXISTENTE'}',
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: c.jamPlaybackActive
            ? null
            : () => c.playTrack(track, context: albumTracks),
        icon: const Icon(StudioSymbols.playArrow, size: 18),
        label: Text(
          track.album == null
              ? 'REPRODUCIR SELECCIÓN'
              : 'REPRODUCIR PISTAS DISPONIBLES',
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: c.jamPlaybackActive
                ? null
                : () async {
                    if (c.currentTrack?.id != track.id) {
                      await c.playTrack(track, context: albumTracks);
                    }
                    if (context.mounted) intro.onVinyl();
                  },
            icon: const Icon(StudioSymbols.album, size: 18),
            label: const Text('Girar en Modo Vinilo'),
          ),
          IconButton.filledTonal(
            tooltip: 'Guardar en favoritos',
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
  return StudioPanel(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(StudioSymbols.verified, color: colors.primary, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 560;
            final sleeve = Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: StudioPalette.of(context),
                    boxShadow: const [
                      BoxShadow(color: Colors.black, offset: Offset(4, 6)),
                    ],
                  ),
                  child: Artwork.fill(
                    track: track,
                    artworkContext: ArtworkContext.sleeve,
                    radius: 8,
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: StudioStamp(
                    track.isLocal
                        ? 'ARCHIVO LOCAL'
                        : 'METADATOS · AUDIO EXTERNO',
                    filled: true,
                  ),
                ),
              ],
            );
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(width: constraints.maxWidth * .4, child: sleeve),
                      const SizedBox(width: 24),
                      Expanded(child: info),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: SizedBox(
                          width: ArtworkContext.sleeve.constrain(constraints),
                          child: sleeve,
                        ),
                      ),
                      const SizedBox(height: 28),
                      info,
                    ],
                  );
          },
        ),
      ],
    ),
  );
}
