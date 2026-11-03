import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../friends/friends_service.dart';
import '../../jam/jam_controller.dart';
import '../friends_page.dart' show friendsAgo;
import '../mini_player/mini_player_host.dart';
import '../undo_snackbar.dart';
import 'atelier_chat.dart';
import 'brasa_chat.dart';
import 'chat_model.dart';
import 'chat_theme.dart';
import 'modern_chat.dart';
import 'slush_chat.dart';

/// Registro por tema, con la misma detección que el mini reproductor
/// (`MiniPlayerHost.kindOf`: Slush también lleva `ModernMarker`, el orden
/// importa). Cada tema vive en su archivo.
const Map<String, ChatTheme> chatThemes = {
  'atelier': atelierChat,
  'slush': slushChat,
  'modern': modernChat,
  'brasa': brasaChat,
};

ChatTheme chatThemeOf(BuildContext c) => chatThemes[MiniPlayerHost.kindOf(c)]!;

/// Lista de conversaciones (una por amigo). Va dentro del `ListView` de la
/// página de Amigos.
class FriendChatList extends StatelessWidget {
  const FriendChatList({
    super.key,
    required this.friends,
    required this.onOpen,
  });
  final FriendsService friends;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = chatThemeOf(context);
    return Column(
      children: [
        for (final chat in friends.chats)
          KeyedSubtree(
            key: ValueKey('friends-chat-${chat.peer.id}'),
            child: theme.row(
              context,
              chat,
              chatPreview(chat),
              () => onOpen(chat.peer.id),
            ),
          ),
      ],
    );
  }
}

/// Hilo con un amigo: envíos en los dos sentidos y el compositor. Toda la
/// lógica (acciones, envío, «visto», paginación) vive aquí; el tema solo pinta.
class FriendChatThread extends StatefulWidget {
  const FriendChatThread({
    super.key,
    required this.friends,
    required this.peer,
    required this.controller,
    required this.onBack,
    this.jam,
    this.onJoinJam,
  });
  final FriendsService friends;
  final FriendUser peer;
  final AppController controller;
  final JamController? jam;
  final Future<void> Function(String code)? onJoinJam;
  final VoidCallback onBack;

  @override
  State<FriendChatThread> createState() => _FriendChatThreadState();
}

class _FriendChatThreadState extends State<FriendChatThread> {
  final _note = TextEditingController();
  // Propio: el primario vive dentro del NestedScrollView de Slush.
  final _scroll = ScrollController();
  bool _busy = false;
  Timer? _seenTimer;
  Timer? _expiryTimer;
  DateTime? _expiryAt;

  @override
  void initState() {
    super.initState();
    final f = widget.friends, id = widget.peer.id;
    if (f.threadWith(id).isEmpty && f.hasOlderWith(id)) {
      unawaited(f.loadOlderWith(id));
    }
  }

  @override
  void dispose() {
    _seenTimer?.cancel();
    _expiryTimer?.cancel();
    _note.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _say(String text) {
    if (!mounted) return;
    showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));
  }

  /// Marca como vistos los recibidos tras dos segundos con el hilo abierto.
  void _scheduleSeen(List<SharedItem> thread) {
    if (_seenTimer?.isActive == true) return;
    final ids = [
      for (final i in thread)
        if (!i.mine && !i.seen) i.id,
    ];
    if (ids.isEmpty) return;
    _seenTimer = Timer(
      const Duration(seconds: 2),
      () => widget.friends.markSeen(ids),
    );
  }

  /// Una invitación que caduca con el hilo abierto desaparece sola.
  void _scheduleExpiry(List<SharedItem> thread) {
    DateTime? next;
    for (final i in thread) {
      if (i.kind != SharedKind.jam) continue;
      final at = i.createdAt.add(jamInviteTtl);
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next == _expiryAt) return;
    _expiryAt = next;
    _expiryTimer?.cancel();
    _expiryTimer = null;
    if (next == null) return;
    final wait = next.difference(DateTime.now());
    _expiryTimer = Timer(
      (wait.isNegative ? Duration.zero : wait) + const Duration(seconds: 1),
      () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _send(Future<String?> Function() run) async {
    setState(() => _busy = true);
    try {
      final error = await run();
      if (!mounted) return;
      if (error != null) {
        _say(error);
      } else {
        _note.clear();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<ChatAction> _composerActions() {
    final t = widget.controller.nowTrack;
    final jam = widget.jam;
    final f = widget.friends, id = widget.peer.id;
    return [
      ChatAction(
        key: const ValueKey('chat-send-now'),
        icon: Icons.send_outlined,
        label: 'Enviar lo que suena',
        primary: true,
        onTap: t == null || t.isLocal || _busy
            ? null
            : () => _send(() => f.shareTrack(id, t, note: _note.text)),
      ),
      // Misma condición que `JamInviteFriendButton`.
      if (jam != null && jam.active && jam.service.invite?.isRemote == true)
        ChatAction(
          key: const ValueKey('chat-invite-jam'),
          icon: Icons.groups_outlined,
          label: 'Invitar a mi Jam',
          onTap: _busy
              ? null
              : () =>
                    _send(() => f.shareJamInvite(id, jam.service.invite!.code)),
        ),
    ];
  }

  ChatEntry _entry(SharedItem i) {
    final c = widget.controller;
    final time = friendsAgo(i.createdAt);
    switch (i.kind) {
      case SharedKind.track:
        final t = i.track;
        final liked = c.favoriteIds.contains(t.id);
        return ChatEntry(
          item: i,
          title: t.title,
          subtitle: t.artist,
          kindLabel: 'Canción',
          icon: Icons.music_note,
          time: time,
          artworkUrl: t.artworkUrl,
          actions: [
            ChatAction(
              key: ValueKey('chat-play-${i.id}'),
              icon: Icons.play_arrow,
              label: 'Reproducir',
              primary: true,
              onTap: () => c.playTrack(t),
            ),
            ChatAction(
              key: ValueKey('chat-queue-${i.id}'),
              icon: Icons.queue_music,
              label: 'Añadir a la cola',
              onTap: () async {
                await c.addToQueue(t);
                _say('Añadida a la cola');
              },
            ),
            ChatAction(
              key: ValueKey('chat-like-${i.id}'),
              icon: liked ? Icons.favorite : Icons.favorite_border,
              label: liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
              onTap: () => c.toggleFavorite(t),
            ),
          ],
        );
      case SharedKind.playlist:
        final p = i.playlist!;
        return ChatEntry(
          item: i,
          title: p.name,
          subtitle: '${p.tracks.length} canciones',
          kindLabel: 'Lista',
          icon: Icons.queue_music,
          time: time,
          artworkUrl: p.artworkUrl,
          actions: [
            ChatAction(
              key: ValueKey('chat-play-${i.id}'),
              icon: Icons.play_arrow,
              label: 'Reproducir',
              primary: true,
              onTap: p.tracks.isEmpty
                  ? null
                  : () => c.playTrack(p.tracks.first, context: p.tracks),
            ),
            if (!i.mine)
              ChatAction(
                key: ValueKey('chat-save-${i.id}'),
                icon: Icons.library_add_outlined,
                label: 'Guardar en mi biblioteca',
                onTap: () async {
                  await c.savePlaylistCopy(p.name, p.tracks);
                  _say('Lista guardada');
                },
              ),
          ],
        );
      case SharedKind.jam:
        final join = widget.onJoinJam;
        return ChatEntry(
          item: i,
          title: i.mine
              ? 'Invitación a tu Jam'
              : '${widget.peer.username} te invita a su Jam',
          subtitle: 'Jam en vivo',
          kindLabel: 'Jam',
          icon: Icons.groups_outlined,
          time: time,
          actions: [
            if (!i.mine && join != null)
              ChatAction(
                key: ValueKey('chat-join-${i.id}'),
                icon: Icons.login,
                label: 'Unirse',
                primary: true,
                onTap: () => join(i.jamCode!),
              ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = chatThemeOf(context);
    final f = widget.friends, id = widget.peer.id;
    return ListenableBuilder(
      listenable: Listenable.merge([f, widget.controller, ?widget.jam]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, box) {
          final thread = f.threadWith(id);
          final older = f.hasOlderWith(id);
          _scheduleSeen(thread);
          _scheduleExpiry(thread);
          final maxBubble = math.min(440.0, box.maxWidth * .8);
          return Column(
            children: [
              theme.header(context, widget.peer, widget.onBack),
              Expanded(
                child: thread.isEmpty && !older
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Aún no os habéis enviado nada. Envía lo que suena o invita a tu Jam.',
                            key: ValueKey('chat-empty'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                        children: [
                          for (final item in thread)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Align(
                                alignment: item.mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxBubble,
                                  ),
                                  child: KeyedSubtree(
                                    key: ValueKey('chat-item-${item.id}'),
                                    child: theme.bubble(context, _entry(item)),
                                  ),
                                ),
                              ),
                            ),
                          // Lista invertida: el último hijo queda arriba.
                          if (older)
                            Center(
                              child: TextButton(
                                key: const ValueKey('chat-older'),
                                onPressed: () => f.loadOlderWith(id),
                                child: const Text('Cargar anteriores'),
                              ),
                            ),
                        ],
                      ),
              ),
              theme.composer(
                context,
                ChatComposerData(
                  note: _note,
                  actions: _composerActions(),
                  busy: _busy,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
