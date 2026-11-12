import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../follow/follow_models.dart';
import '../follow/follow_service.dart';
import 'home/home_theme.dart';

/// Inicio. Conserva el estado y la lógica compartida; la maquetación de cada
/// tema vive en `ui/home/home_<tema>.dart` (ver [HomeTheme]).
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
      // Solo los artistas que el usuario sigue (no los deducidos de la biblioteca).
      final followed = follow?.artists ?? const <FollowedArtist>[];
      return homeThemeOf(context).buildPage(
        context,
        HomePageData(
          controller: c,
          onSearch: onSearch,
          onDownloads: onDownloads,
          onLikes: onLikes,
          onOpenPlaylist: onOpenPlaylist,
          onVinyl: onVinyl,
          onSearchQuery: onSearchQuery,
          recommendations: recommendations,
          recommendedTracks: recommendedTracks,
          personalized: personalized,
          followed: followed,
        ),
      );
    },
  );
}
