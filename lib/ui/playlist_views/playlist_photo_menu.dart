import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../friends/friends_providers.dart';
import '../../friends/friends_service.dart';
import '../friends_page.dart';
import '../undo_snackbar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks de [playlist] resueltos en la biblioteca.
List<Track> playlistTracksOf(AppController c, MusicPlaylist playlist) {
  final byId = {for (final t in c.tracks) t.id: t};
  return [
    for (final id in playlist.trackIds)
      if (byId[id] != null) byId[id]!,
  ];
}

/// Botón «Enviar a un amigo» para el encabezado de una playlist.
class PlaylistSendButton extends StatelessWidget {
  const PlaylistSendButton({
    super.key,
    required this.controller,
    required this.playlist,
  });
  final AppController controller;
  final MusicPlaylist playlist;

  @override
  Widget build(BuildContext context) => FriendsGate(
    builder: (context, f) => OutlinedButton.icon(
      key: const ValueKey('playlist-send-friend'),
      onPressed: () => showSendPlaylistSheet(
        context,
        f,
        playlist.name,
        playlistTracksOf(controller, playlist),
      ),
      icon: const Icon(Icons.send_outlined),
      label: const Text('Enviar a un amigo'),
    ),
  );
}

/// Abre el selector y avisa con un SnackBar si falla; lo usan todos los puntos de entrada.
Future<void> changePlaylistPhoto(
  BuildContext context,
  AppController controller,
  MusicPlaylist playlist,
) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final error = await controller.pickPlaylistPhoto(playlist);
  if (error != null) showUndoSnackBar(messenger, Text(error));
}

/// Menú «Cambiar foto» / «Quitar foto» en la posición indicada.
Future<void> showPlaylistPhotoMenu(
  BuildContext context,
  AppController controller,
  MusicPlaylist playlist,
  Offset globalPosition,
) async {
  final latest =
      controller.playlists
          .where((item) => item.id == playlist.id)
          .firstOrNull ??
      playlist;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final friends = _signedInFriends(context);
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      globalPosition & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      const PopupMenuItem(
        value: 'change',
        child: ListTile(
          leading: Icon(Icons.photo_camera_outlined),
          title: Text('Cambiar foto'),
        ),
      ),
      if (latest.photoPath != null)
        const PopupMenuItem(
          value: 'remove',
          child: ListTile(
            leading: Icon(Icons.hide_image_outlined),
            title: Text('Quitar foto'),
          ),
        ),
      if (friends != null)
        const PopupMenuItem(
          value: 'send',
          child: ListTile(
            leading: Icon(Icons.send_outlined),
            title: Text('Enviar a un amigo'),
          ),
        ),
    ],
  );
  if (!context.mounted) return;
  if (choice == 'change') {
    await changePlaylistPhoto(context, controller, latest);
  } else if (choice == 'remove') {
    await controller.setPlaylistPhoto(latest, null);
  } else if (choice == 'send' && friends != null) {
    await showSendPlaylistSheet(
      context,
      friends,
      latest.name,
      playlistTracksOf(controller, latest),
    );
  }
}

FriendsService? _signedInFriends(BuildContext context) {
  try {
    final f = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(friendsServiceProvider);
    return f.signedIn ? f : null;
  } catch (_) {
    return null;
  }
}

/// Añade clic derecho y pulsación larga a [child] sin alterar su aspecto.
class PlaylistPhotoMenu extends StatelessWidget {
  const PlaylistPhotoMenu({
    super.key,
    required this.controller,
    required this.playlist,
    required this.child,
  });
  final AppController controller;
  final MusicPlaylist playlist;
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapUp: (d) =>
        showPlaylistPhotoMenu(context, controller, playlist, d.globalPosition),
    onLongPressStart: (d) =>
        showPlaylistPhotoMenu(context, controller, playlist, d.globalPosition),
    child: child,
  );
}
