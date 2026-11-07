import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../friends/friends_providers.dart';
import '../friends/friends_service.dart';
import '../theme/slush_theme.dart';
import '../theme/slush_widgets.dart';
import 'slush/slush_decor.dart';
import 'slush/slush_pages.dart';
import 'undo_snackbar.dart';
import '../jam/jam_controller.dart';
import 'friends_chat/friend_chat_views.dart';

/// Avatar genérico (silueta tintada con el acento) cuando no hay foto.
class FriendAvatar extends StatelessWidget {
  const FriendAvatar({super.key, required this.user, this.size = 40});
  final FriendUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slush = isSlush(context);
    final fallback = Icon(
      Icons.person,
      size: size * .6,
      color: slush ? Slush.ink : colors.primary,
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
          color: slush ? Slush.lilac : colors.primary.withValues(alpha: .16),
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

/// Botón primario Slush: menta con tinta y contorno de control, 44 mínimo.
ButtonStyle? _mint(BuildContext context) => isSlush(context)
    ? FilledButton.styleFrom(
        backgroundColor: Slush.mint,
        foregroundColor: Slush.ink,
        minimumSize: const Size(SlushControl.touch, SlushControl.touch),
        side: context.slush.border,
      )
    : null;

class FriendsPage extends ConsumerStatefulWidget {
  const FriendsPage({
    super.key,
    required this.controller,
    required this.openChat,
    this.onSettings,
    this.onJoinJam,
    this.jam,
  });
  final AppController controller;

  /// Id del amigo con el chat abierto; `null`, la lista. Lo comparte el shell
  /// (avisos y «atrás»).
  final ValueNotifier<String?> openChat;

  /// Jam en curso, para invitar desde el chat.
  final JamController? jam;

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
  List<FriendUser> _results = const [];
  bool _searching = false;
  int _searchToken = 0;

  @override
  void initState() {
    super.initState();
    // Abrir un chat desde fuera (aviso, botón de un amigo) lleva a «Chats».
    if (widget.openChat.value != null) _tab = 2;
    widget.openChat.addListener(_onOpenChat);
  }

  void _onOpenChat() {
    if (widget.openChat.value != null && _tab != 2) setState(() => _tab = 2);
  }

  @override
  void dispose() {
    widget.openChat.removeListener(_onOpenChat);
    _debounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(friendsServiceProvider);
    if (!f.signedIn) return _SignedOut(onSettings: widget.onSettings);
    return ValueListenableBuilder<String?>(
      valueListenable: widget.openChat,
      builder: (context, openId, _) {
        final peer = openId == null
            ? null
            : f.friends.where((u) => u.id == openId).firstOrNull;
        if (openId != null && peer == null && !f.loading) {
          // Ya no es amigo (con la carga hecha): se vuelve a la lista.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && widget.openChat.value == openId) {
              widget.openChat.value = null;
            }
          });
        }
        if (peer == null) return _list(f);
        return FriendChatThread(
          key: ValueKey('chat-thread-${peer.id}'),
          friends: f,
          peer: peer,
          controller: widget.controller,
          jam: widget.jam,
          onJoinJam: widget.onJoinJam,
          onBack: () => widget.openChat.value = null,
        );
      },
    );
  }

  Widget _list(FriendsService f) {
    final searching = _query.text.trim().length >= 3;
    return LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(
          isSlush(context)
              ? SlushSpacing.margin(box.maxWidth)
              : box.maxWidth >= 700
              ? 24
              : 16,
        ),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(0, 'Amigos'),
              _chip(1, 'Solicitudes', f.incoming.length),
              _chip(2, 'Chats', f.unseenCount),
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
          else if (f.friends.isEmpty)
            _empty(
              'Añade amigos para empezar a chatear.',
              title: 'Sin chats',
              icon: Icons.forum_outlined,
            )
          else
            FriendChatList(
              friends: f,
              onOpen: (id) => widget.openChat.value = id,
            ),
        ],
      ),
    );
  }

  Widget _chip(int i, String label, [int badge = 0]) {
    final text = badge > 0 ? '$label · $badge' : label;
    void select() => setState(() => _tab = i);
    if (isSlush(context)) {
      return SlushChip(
        text,
        key: ValueKey('friends-tab-$i'),
        color: context.slush.paper,
        selected: _tab == i,
        onTap: select,
      );
    }
    return ChoiceChip(
      key: ValueKey('friends-tab-$i'),
      selected: _tab == i,
      label: Text(text),
      onSelected: (_) => select(),
    );
  }

  Widget _empty(
    String text, {
    String title = 'Nada por aquí',
    IconData icon = Icons.people_outline,
  }) {
    if (isSlush(context)) {
      final h = (MediaQuery.sizeOf(context).height * .6).clamp(320.0, 520.0);
      return SizedBox(
        height: h,
        child: SlushEmpty(
          icon: icon,
          title: title,
          message: text,
          sticker: 'VACÍO',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  List<Widget> _searchResults(FriendsService f) {
    if (_searching) {
      return const [
        Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_results.isEmpty) {
      return [
        _empty(
          'Nadie con ese nombre.',
          title: 'Sin resultados',
          icon: Icons.person_search_outlined,
        ),
      ];
    }
    return [
      for (final u in _results)
        _UserRow(
          user: u,
          trailing: switch (f.relationTo(u.id)) {
            'friend' =>
              isSlush(context)
                  ? const SlushPill('Amigos', color: Slush.lilac)
                  : const Text('Amigos'),
            'sent' =>
              isSlush(context)
                  ? const SlushPill('Enviada', color: Slush.yellow)
                  : const Text('Enviada'),
            'incoming' => FilledButton.tonal(
              style: _mint(context),
              onPressed: () => _act(() async {
                final r = f.incoming.firstWhere((r) => r.user.id == u.id);
                return f.accept(r.id);
              }),
              child: const Text('Aceptar'),
            ),
            _ => FilledButton.tonal(
              key: ValueKey('friends-add-${u.id}'),
              style: _mint(context),
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
          title: 'Aún sin amigos',
        ),
      ];
    }
    return [
      for (final u in f.friends)
        _UserRow(
          user: u,
          onTap: () => widget.openChat.value = u.id,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: ValueKey('friends-open-chat-${u.id}'),
                tooltip: 'Abrir chat',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => widget.openChat.value = u.id,
              ),
              PopupMenuButton<int>(
                tooltip: 'Opciones de ${u.username}',
                onSelected: (_) => _confirmRemove(f, u),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0, child: Text('Eliminar de amigos')),
                ],
              ),
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
      return [
        _empty(
          'No tienes solicitudes pendientes.',
          title: 'Sin solicitudes',
          icon: Icons.mark_email_unread_outlined,
        ),
      ];
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
                style: isSlush(context)
                    ? IconButton.styleFrom(
                        backgroundColor: Slush.mint,
                        foregroundColor: Slush.ink,
                        side: context.slush.border,
                      )
                    : null,
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
}

class _UserRow extends StatelessWidget {
  const _UserRow({
    required this.user,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final FriendUser user;
  final String? subtitle;
  final Widget? trailing;

  /// Pulsar en cualquier parte de la fila (los botones del final actúan solos).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (isSlush(context)) {
      final p = context.slush;
      return DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: p.divider, width: SlushStroke.divider),
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: SlushSpacing.s8),
              child: Row(
                children: [
                  FriendAvatar(user: user, size: 44),
                  const SizedBox(width: SlushSpacing.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: p.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: p.ink2,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: SlushSpacing.s8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: FriendAvatar(user: user),
      title: Text(user.username, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({this.onSettings});
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    if (isSlush(context)) {
      return KeyedSubtree(
        key: const ValueKey('friends-signin-hint'),
        child: SlushEmpty(
          icon: Icons.people_outline,
          title: 'Crea una cuenta para añadir amigos',
          message:
              'Crea una cuenta para añadir amigos y enviarles canciones. Ve a Ajustes → Cuenta.',
          sticker: 'AÚN NO',
          actionLabel: onSettings == null ? null : 'Abrir Ajustes',
          onAction: onSettings,
        ),
      );
    }
    return Center(
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
