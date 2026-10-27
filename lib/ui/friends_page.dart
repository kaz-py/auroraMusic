import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../friends/friends_providers.dart';
import '../friends/friends_service.dart';
import '../theme/slush_theme.dart';
import 'undo_snackbar.dart';

/// Avatar genérico (silueta tintada con el acento) cuando no hay foto.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({super.key, required this.user, this.size = 40});
  final FriendUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Icon(
      Icons.person,
      size: size * .6,
      color: isSlush(context) ? context.slush.ink : colors.primary,
    );
    final url = user.avatarUrl;
    return Semantics(
      label: 'Avatar de ${user.username}',
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.primary.withValues(alpha: .16),
          border: isSlush(context)
              ? Border.fromBorderSide(context.slush.border)
              : null,
        ),
        child: url == null
            ? fallback
            : Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: (size * 3).round(),
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

String friendsAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} d';
}

void _say(BuildContext context, String text) =>
    showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({
    super.key,
    required this.controller,
    this.onSettings,
    this.onJoinJam,
  });
  final AppController controller;

  /// Une a la Jam con ese código (la resuelve el shell).
  final Future<void> Function(String code)? onJoinJam;

  /// Lleva a Ajustes → Cuenta cuando no hay sesión.
  final VoidCallback? onSettings;

  @override
  ConsumerState<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends ConsumerState<FriendsPage> {
  int _tab = 0;
  final _query = TextEditingController();
  Timer? _debounce;
  Timer? _seenTimer;
  List<FriendUser> _results = const [];
  bool _searching = false;
  int _searchToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _seenTimer?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    final q = text.trim();
    final token = ++_searchToken;
    if (q.length < 3) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      List<FriendUser> found = const [];
      try {
        found = await ref.read(friendsServiceProvider).searchUsers(q);
      } catch (_) {
        if (mounted) _say(context, 'No se pudo buscar. Inténtalo de nuevo.');
      }
      if (mounted && token == _searchToken) {
        setState(() {
          _results = found;
          _searching = false;
        });
      }
    });
  }

  Future<void> _act(Future<String?> Function() run) async {
    final error = await run();
    if (error != null && mounted) _say(context, error);
  }

  /// Marca como vistas las recibidas tras dos segundos en la pestaña.
  void _scheduleSeen(FriendsService f) {
    if (_tab != 2 || f.unseenCount == 0 || _seenTimer?.isActive == true) return;
    _seenTimer = Timer(const Duration(seconds: 2), () {
      if (_tab == 2) {
        f.markSeen([
          for (final i in f.inbox)
            if (!i.seen) i.id,
        ]);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(friendsServiceProvider);
    if (!f.signedIn) return _SignedOut(onSettings: widget.onSettings);
    _scheduleSeen(f);
    final searching = _query.text.trim().length >= 3;
    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth >= 700 ? 24 : 16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(0, 'Amigos'),
              _chip(1, 'Solicitudes', f.incoming.length),
              _chip(2, 'Recibidas', f.unseenCount),
            ],
          ),
          const SizedBox(height: 16),
          if (_tab == 0) ...[
            TextField(
              key: const ValueKey('friends-search'),
              controller: _query,
              onChanged: _onQuery,
              maxLength: 32,
              decoration: InputDecoration(
                hintText: 'Buscar personas por nombre de usuario',
                counterText: '',
                prefixIcon: const Icon(Icons.person_search_outlined),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar búsqueda',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _query.clear();
                          _onQuery('');
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (searching) ..._searchResults(f) else ..._friendRows(f),
          ] else if (_tab == 1)
            ..._requestRows(f)
          else
            ..._inboxRows(f),
        ],
      ),
    );
  }

  Widget _chip(int i, String label, [int badge = 0]) => ChoiceChip(
    key: ValueKey('friends-tab-$i'),
    selected: _tab == i,
    label: Text(badge > 0 ? '$label · $badge' : label),
    onSelected: (_) => setState(() {
      _tab = i;
      _seenTimer?.cancel();
    }),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  );

  List<Widget> _searchResults(FriendsService f) {
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_results.isEmpty) return [_empty('Nadie con ese nombre.')];
    return [
      for (final u in _results)
        _UserRow(
          user: u,
          trailing: switch (f.relationTo(u.id)) {
            'friend' => const Text('Amigos'),
            'sent' => const Text('Enviada'),
            'incoming' => FilledButton.tonal(
              onPressed: () => _act(() async {
                final r = f.incoming.firstWhere((r) => r.user.id == u.id);
                return f.accept(r.id);
              }),
              child: const Text('Aceptar'),
            ),
            _ => FilledButton.tonal(
              key: ValueKey('friends-add-${u.id}'),
              onPressed: () => _act(() => f.sendRequest(u.id)),
              child: const Text('Añadir'),
            ),
          },
        ),
    ];
  }

  List<Widget> _friendRows(FriendsService f) {
    if (f.friends.isEmpty) {
      return [
        _empty(
          'Aún no tienes amigos. Busca a alguien por su nombre de usuario '
          'para enviarle una solicitud.',
        ),
      ];
    }
    return [
      for (final u in f.friends)
        _UserRow(
          user: u,
          trailing: PopupMenuButton<int>(
            tooltip: 'Opciones de ${u.username}',
            onSelected: (_) => _confirmRemove(f, u),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 0, child: Text('Eliminar de amigos')),
            ],
          ),
        ),
    ];
  }

  Future<void> _confirmRemove(FriendsService f, FriendUser u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Eliminar a ${u.username}?'),
        content: const Text(
          'Dejaréis de ser amigos y no podréis enviaros canciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) await _act(() => f.removeFriend(u.id));
  }

  List<Widget> _requestRows(FriendsService f) {
    if (f.incoming.isEmpty && f.outgoing.isEmpty) {
      return [_empty('No tienes solicitudes pendientes.')];
    }
    return [
      for (final r in f.incoming)
        _UserRow(
          user: r.user,
          subtitle: 'Quiere ser tu amigo · ${friendsAgo(r.createdAt)}',
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                key: ValueKey('friends-decline-${r.id}'),
                tooltip: 'Rechazar',
                icon: const Icon(Icons.close),
                onPressed: () => _act(() => f.decline(r.id)),
              ),
              IconButton.filledTonal(
                key: ValueKey('friends-accept-${r.id}'),
                tooltip: 'Aceptar',
                icon: const Icon(Icons.check),
                onPressed: () => _act(() => f.accept(r.id)),
              ),
            ],
          ),
        ),
      for (final r in f.outgoing)
        _UserRow(
          user: r.user,
          subtitle: 'Enviada · ${friendsAgo(r.createdAt)}',
          trailing: TextButton(
            onPressed: () => _act(() => f.cancelRequest(r.id)),
            child: const Text('Cancelar'),
          ),
        ),
    ];
  }

  List<Widget> _inboxRows(FriendsService f) {
    if (f.inbox.isEmpty) {
      return [
        _empty(
          'Aquí aparecerán las canciones, listas e invitaciones que te envíen tus amigos.',
        ),
      ];
    }
    final c = widget.controller;
    return [
      for (final item in f.inbox)
        ListenableBuilder(
          listenable: c,
          builder: (context, _) => switch (item.kind) {
            SharedKind.track => _InboxRow(
              item: item,
              liked: c.favoriteIds.contains(item.track.id),
              onPlay: () => c.playTrack(item.track),
              onQueue: () async {
                await c.addToQueue(item.track);
                if (context.mounted) _say(context, 'Añadida a la cola');
              },
              onLike: () => c.toggleFavorite(item.track),
            ),
            SharedKind.playlist => _InboxCard(
              item: item,
              title: item.playlist!.name,
              subtitle: '${item.playlist!.tracks.length} canciones',
              artworkUrl: item.playlist!.artworkUrl,
              icon: Icons.queue_music,
              actions: [
                IconButton(
                  key: ValueKey('inbox-play-${item.id}'),
                  tooltip: 'Reproducir',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => c.playTrack(
                    item.playlist!.tracks.first,
                    context: item.playlist!.tracks,
                  ),
                ),
                FilledButton.tonalIcon(
                  key: ValueKey('inbox-save-${item.id}'),
                  icon: const Icon(Icons.library_add_outlined, size: 18),
                  label: const Text('Guardar en mi biblioteca'),
                  onPressed: () async {
                    await c.savePlaylistCopy(
                      item.playlist!.name,
                      item.playlist!.tracks,
                    );
                    if (context.mounted) _say(context, 'Lista guardada');
                  },
                ),
              ],
            ),
            SharedKind.jam => _InboxCard(
              item: item,
              title: '${item.from.username} te invita a su Jam',
              subtitle: item.jamExpired()
                  ? 'Invitación caducada'
                  : 'Jam en vivo',
              icon: Icons.groups_outlined,
              actions: [
                if (!item.jamExpired() && widget.onJoinJam != null)
                  FilledButton.icon(
                    key: ValueKey('inbox-join-${item.id}'),
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('Unirse'),
                    onPressed: () => widget.onJoinJam!(item.jamCode!),
                  ),
              ],
            ),
          },
        ),
      if (f.hasMoreInbox)
        Center(
          child: TextButton(
            key: const ValueKey('friends-more'),
            onPressed: f.loadMoreInbox,
            child: const Text('Cargar más'),
          ),
        ),
    ];
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, this.subtitle, this.trailing});
  final FriendUser user;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: FriendAvatar(user: user),
    title: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: trailing,
  );
}

class _InboxRow extends StatelessWidget {
  const _InboxRow({
    required this.item,
    required this.liked,
    required this.onPlay,
    required this.onQueue,
    required this.onLike,
  });
  final SharedItem item;
  final bool liked;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = item.track;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(user: item.from, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${item.from.username} · ${friendsAgo(item.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
              if (!item.seen)
                Semantics(
                  label: 'Nueva',
                  child: Icon(
                    Icons.circle,
                    size: 10,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    Text(
                      t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reproducir',
                icon: const Icon(Icons.play_arrow),
                onPressed: onPlay,
              ),
              IconButton(
                tooltip: 'Añadir a la cola',
                icon: const Icon(Icons.queue_music),
                onPressed: onQueue,
              ),
              IconButton(
                tooltip: liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border),
                onPressed: onLike,
              ),
            ],
          ),
          if (item.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '«${item.note}»',
                style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}

/// Fila de la bandeja para listas e invitaciones a Jam.
class _InboxCard extends StatelessWidget {
  const _InboxCard({
    required this.item,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actions,
    this.artworkUrl,
  });
  final SharedItem item;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final IconData icon;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final art = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: artworkUrl == null
            ? ColoredBox(
                color: colors.primary.withValues(alpha: .16),
                child: Icon(icon, color: colors.primary),
              )
            : Image.network(
                artworkUrl!,
                fit: BoxFit.cover,
                cacheWidth: 168,
                errorBuilder: (_, _, _) => ColoredBox(
                  color: colors.primary.withValues(alpha: .16),
                  child: Icon(icon, color: colors.primary),
                ),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FriendAvatar(user: item.from, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${item.from.username} · ${friendsAgo(item.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium,
                ),
              ),
              if (!item.seen)
                Semantics(
                  label: 'Nueva',
                  child: Icon(Icons.circle, size: 10, color: colors.primary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              art,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    Text(subtitle, style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
            ),
          if (item.note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '«${item.note}»',
                style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({this.onSettings});
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        key: const ValueKey('friends-signin-hint'),
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.people_outline, size: 48),
          const SizedBox(height: 12),
          Text(
            'Crea una cuenta para añadir amigos y enviarles canciones.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Ve a Ajustes → Cuenta.', textAlign: TextAlign.center),
          if (onSettings != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onSettings,
              child: const Text('Abrir Ajustes'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Amigos solo si hay sesión; se reconstruye al iniciar/cerrar sesión. Sin
/// ProviderScope (p. ej. widgets aislados) no muestra nada.
class FriendsGate extends StatelessWidget {
  const FriendsGate({super.key, required this.builder});
  final Widget Function(BuildContext context, FriendsService friends) builder;

  @override
  Widget build(BuildContext context) {
    try {
      ProviderScope.containerOf(context, listen: false);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return Consumer(
      builder: (context, ref, _) {
        final f = ref.watch(friendsServiceProvider);
        return f.signedIn ? builder(context, f) : const SizedBox.shrink();
      },
    );
  }
}

/// Botón de icono «Enviar a un amigo» para reproductores y barras.
class SendToFriendButton extends StatelessWidget {
  const SendToFriendButton({
    super.key,
    required this.track,
    this.size,
    this.color,
  });
  final Track? track;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null || t.isLocal) return const SizedBox.shrink();
    return FriendsGate(
      builder: (context, f) => IconButton(
        key: const ValueKey('send-to-friend'),
        tooltip: 'Enviar a un amigo',
        iconSize: size,
        color: color,
        onPressed: () => showSendToFriendSheet(context, f, t),
        icon: const Icon(Icons.send_outlined),
      ),
    );
  }
}

/// Hoja para elegir a qué amigo enviar [track], con nota opcional.
Future<void> showSendToFriendSheet(
  BuildContext context,
  FriendsService friends,
  Track track,
) => showSendSheet(
  context,
  friends,
  title: 'Enviar «${track.title}»',
  send: (id, note) => friends.shareTrack(id, track, note: note),
);

/// Envía una copia de la lista [name] con [tracks] a un amigo.
Future<void> showSendPlaylistSheet(
  BuildContext context,
  FriendsService friends,
  String name,
  List<Track> tracks,
) => showSendSheet(
  context,
  friends,
  title: 'Enviar la lista «$name»',
  send: (id, note) => friends.sharePlaylist(id, name, tracks, note: note),
);

/// Invita a un amigo a la Jam con [code].
Future<void> showInviteFriendToJamSheet(
  BuildContext context,
  FriendsService friends,
  String code,
) => showSendSheet(
  context,
  friends,
  title: 'Invitar a tu Jam',
  withNote: false,
  confirmation: (name) => 'Invitación enviada a $name',
  send: (id, _) => friends.shareJamInvite(id, code),
);

/// Selector de amigo común a canciones, listas e invitaciones.
Future<void> showSendSheet(
  BuildContext context,
  FriendsService friends, {
  required String title,
  required Future<String?> Function(String friendId, String? note) send,
  bool withNote = true,
  String Function(String name)? confirmation,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      final note = TextEditingController();
      return Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(sheet).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(sheet).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (withNote)
              TextField(
                key: const ValueKey('share-note'),
                controller: note,
                maxLength: 200,
                decoration: const InputDecoration(hintText: 'Nota (opcional)'),
              ),
            if (friends.friends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aún no tienes amigos a quienes enviar.'),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in friends.friends)
                      ListTile(
                        key: ValueKey('share-to-${u.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: FriendAvatar(user: u),
                        title: Text(u.username),
                        trailing: const Icon(Icons.send_outlined),
                        onTap: () async {
                          Navigator.pop(sheet);
                          final error = await send(u.id, note.text);
                          showUndoSnackBar(
                            messenger,
                            Text(
                              error ??
                                  confirmation?.call(u.username) ??
                                  'Enviada a ${u.username}',
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}
