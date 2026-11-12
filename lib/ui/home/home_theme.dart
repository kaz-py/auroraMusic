import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/recommendations.dart';
import '../../follow/follow_models.dart';
import '../../theme/aurora_tokens.dart';
import '../spotify_match_dialog.dart';
import '../track_actions.dart';
import '../studio/home_introduction.dart';
import 'home_atelier.dart';
import 'home_brasa.dart';
import 'home_modern.dart';
import 'home_slush.dart';

/// Datos y acciones que HomeMusicPage reparte al tema vigente.
///
/// HomeMusicPage conserva el estado y la lógica compartida (recomendaciones,
/// artistas seguidos, reproducir); el tema solo decide la maquetación.
class HomePageData {
  const HomePageData({
    required this.controller,
    required this.onSearch,
    required this.onDownloads,
    required this.onLikes,
    required this.onOpenPlaylist,
    required this.recommendations,
    required this.recommendedTracks,
    required this.personalized,
    required this.followed,
    this.onVinyl,
    this.onSearchQuery,
  });
  final AppController controller;
  final VoidCallback onSearch, onDownloads, onLikes;
  final ValueChanged<MusicPlaylist> onOpenPlaylist;
  final VoidCallback? onVinyl;
  final ValueChanged<String>? onSearchQuery;
  final List<TrackRecommendation> recommendations;
  final List<Track> recommendedTracks;
  final bool personalized;
  final List<FollowedArtist> followed;

  /// Tarjeta de un artista seguido (el tema la pinta vía [HomeGroupCard]).
  Widget followedCard(FollowedArtist a) {
    final c = controller;
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
    return HomeGroupCard(
      title: name,
      tracks: [cover],
      countLabel: 'Artista seguido',
      artist: true,
      tooltip: 'Abrir artista $name',
      onPlay: () => c.openArtist(name),
    );
  }

  /// Reproduce [track]; si espera emparejar con Spotify abre el diálogo.
  Future<void> play(
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

/// Un tema de la portada. Cada tema vive en su `home_<tema>.dart` y es el
/// único dueño de su maquetación, introducción y tarjetas.
abstract class HomeTheme {
  const HomeTheme();

  /// Página completa de Inicio (se construye dentro del ListenableBuilder
  /// de HomeMusicPage).
  Widget buildPage(BuildContext context, HomePageData data);

  /// Cabecera editorial de [StudioHomeIntroduction]; [track] es la pista
  /// destacada (actual, reciente o primera de la biblioteca), si hay.
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  );

  /// Tarjeta de grupo/artista ([cover] ya resuelta, [count] ya formateado).
  Widget groupTile(
    BuildContext context, {
    required Track cover,
    required String title,
    required String count,
    required bool artist,
    required String tooltip,
    required VoidCallback onPlay,
  });

  /// Tarjeta de pista (recomendaciones, descubiertas y colección).
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  });

  /// Tarjeta de "escuchados recientemente".
  Widget recentTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
  });
}

/// Registro de temas de la portada.
const Map<AuroraThemeKind, HomeTheme> homeThemes = {
  AuroraThemeKind.atelier: atelierHome,
  AuroraThemeKind.modern: modernHome,
  AuroraThemeKind.brasa: brasaHome,
  AuroraThemeKind.slush: slushHome,
};

HomeTheme homeThemeFor(AuroraThemeKind kind) => homeThemes[kind]!;

/// Tema de portada vigente en [context].
HomeTheme homeThemeOf(BuildContext context) =>
    homeThemeFor(themeKindOf(context));

class HomeGroupCard extends StatelessWidget {
  const HomeGroupCard({
    super.key,
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
    return homeThemeOf(context).groupTile(
      context,
      cover: cover,
      title: title,
      count: count,
      artist: artist,
      tooltip: tooltip,
      onPlay: onPlay,
    );
  }
}

class HomeTrackCard extends StatelessWidget {
  const HomeTrackCard({
    super.key,
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
    builder: (context, _) => homeThemeOf(context).trackTile(
      context,
      controller: controller,
      track: track,
      actionLabel: actionLabel,
      onPlay: onPlay,
      reason: reason,
    ),
  );
}

class HomeRecentSleeve extends StatelessWidget {
  const HomeRecentSleeve({
    super.key,
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
    builder: (context, _) => homeThemeOf(context).recentTile(
      context,
      controller: controller,
      track: track,
      actionLabel: actionLabel,
      onPlay: onPlay,
    ),
  );
}
