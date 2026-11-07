import 'package:flutter/material.dart';

import '../core/models.dart';
import '../dj/coherence.dart';
import '../follow/follow_models.dart';
import '../follow/follow_service.dart';
import 'artwork.dart';
import 'undo_snackbar.dart';

/// «Seguir / Siguiendo». Con [browseId] (ficha de artista de YouTube Music)
/// sigue directo; solo con [name] (reproductor) busca antes al artista.
class FollowButton extends StatelessWidget {
  const FollowButton({
    super.key,
    required this.service,
    required this.name,
    this.browseId,
    this.imageUrl,
  });

  final FollowService service;
  final String name;
  final String? browseId;
  final String? imageUrl;

  FollowedArtist? _current() {
    final key = coherenceNorm(name);
    for (final a in service.artists) {
      if (browseId != null
          ? a.browseId == browseId
          : coherenceNorm(a.name) == key) {
        return a;
      }
    }
    return null;
  }

  Future<void> _toggle(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final current = _current();
    try {
      if (current != null) {
        await service.unfollow(current.browseId);
      } else {
        await service.follow(name, browseId: browseId, imageUrl: imageUrl);
      }
    } catch (error) {
      showUndoSnackBar(
        messenger,
        Text(
          error.toString().replaceFirst(
            RegExp(r'^[A-Za-z]*(Error|Exception):\s*'),
            '',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final following = _current() != null;
        final busy = service.isBusy(browseId ?? name);
        final label = Text(
          following ? 'Siguiendo' : 'Seguir',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        final icon = Icon(
          following ? Icons.check_rounded : Icons.person_add_alt_1_outlined,
          size: 18,
        );
        final onPressed = busy ? null : () => _toggle(context);
        // Densidad estándar: la compacta bajaba el botón a 36 px (< 40 táctil).
        const style = ButtonStyle(visualDensity: VisualDensity.standard);
        return Tooltip(
          message: following
              ? 'Dejar de seguir a $name'
              : 'Seguir a $name y ver sus novedades',
          child: Semantics(
            button: true,
            toggled: following,
            label: following ? 'Siguiendo a $name' : 'Seguir a $name',
            excludeSemantics: true,
            onTap: onPressed,
            child: following
                ? FilledButton.tonalIcon(
                    onPressed: onPressed,
                    style: style,
                    icon: icon,
                    label: label,
                  )
                : OutlinedButton.icon(
                    onPressed: onPressed,
                    style: style,
                    icon: icon,
                    label: label,
                  ),
          ),
        );
      },
    );
  }
}

/// «Novedades de tus artistas» y «Artistas que sigues» (Biblioteca).
class FollowedArtistsSection extends StatelessWidget {
  const FollowedArtistsSection({
    super.key,
    required this.service,
    required this.onOpenArtist,
    required this.onOpenRelease,
    this.showNews = true,
    this.showArtists = true,
  });

  /// La Biblioteca pone las novedades arriba y la lista de seguidos abajo.
  final bool showNews;
  final bool showArtists;

  final FollowService service;
  final ValueChanged<FollowedArtist> onOpenArtist;
  final ValueChanged<NewRelease> onOpenRelease;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final theme = Theme.of(context);
        final muted = theme.colorScheme.onSurfaceVariant;
        final news = showNews ? service.news.take(12).toList() : <NewRelease>[];
        final artists = service.artists;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (news.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Novedades de tus artistas',
                    style: theme.textTheme.titleMedium,
                  ),
                  TextButton(
                    onPressed: service.dismissNews,
                    child: const Text('Marcar como vistas'),
                  ),
                ],
              ),
              for (final release in news)
                ListTile(
                  key: ValueKey('news-${release.id}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Artwork(
                    track: Track(
                      id: 'release:${release.id}',
                      title: release.title,
                      artist: release.artistName,
                      artworkUrl: release.artworkUrl,
                    ),
                    artworkContext: ArtworkContext.thumbnail,
                    radius: 8,
                  ),
                  title: Text(
                    release.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    release.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Abrir ${release.title}',
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: () => onOpenRelease(release),
                  ),
                  onTap: () => onOpenRelease(release),
                ),
              const SizedBox(height: 8),
            ],
            if (showArtists) ...[
              const SizedBox(height: 8),
              Text('Artistas que sigues', style: theme.textTheme.titleMedium),
              if (artists.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Sigue a un artista desde su ficha o desde el reproductor '
                    'y verás aquí sus lanzamientos nuevos.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              for (final artist in artists)
                ListTile(
                  key: ValueKey('followed-${artist.browseId}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Artwork(
                    track: Track(
                      id: 'artist:${artist.browseId}',
                      title: artist.name,
                      artist: artist.name,
                      artworkUrl: artist.imageUrl,
                    ),
                    artworkContext: ArtworkContext.thumbnail,
                    radius: 28,
                  ),
                  title: Text(
                    artist.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: artist.lastReleaseTitle == null
                      ? null
                      : Text(
                          'Último: ${artist.lastReleaseTitle}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: IconButton(
                    tooltip: 'Dejar de seguir a ${artist.name}',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () => service.unfollow(artist.browseId),
                  ),
                  onTap: () => onOpenArtist(artist),
                ),
            ],
          ],
        );
      },
    );
  }
}
