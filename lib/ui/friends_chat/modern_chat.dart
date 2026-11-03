import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../friends_page.dart' show FriendAvatar;
import 'chat_model.dart';
import 'chat_theme.dart';

/// Chat de Modern: tarjetas Tracky, burbujas de mensajería y compositor
/// flotante.
const ChatTheme modernChat = ChatTheme(
  row: _row,
  bubble: _bubble,
  composer: _composer,
  header: _header,
);

const _touch = BoxConstraints(minWidth: 44, minHeight: 44);

Widget _header(BuildContext context, FriendUser peer, VoidCallback onBack) {
  final text = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('chat-back'),
          tooltip: 'Volver a los chats',
          constraints: _touch,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        FriendAvatar(user: peer, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            peer.username,
            style: text.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        const ModernBadge('Chat', tone: ModernTone.mint),
      ],
    ),
  );
}

Widget _row(
  BuildContext context,
  FriendChat chat,
  String preview,
  VoidCallback onOpen,
) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: ModernCard(
      onTap: onOpen,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          children: [
            FriendAvatar(user: chat.peer, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.peer.username,
                    style: text.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    preview,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (chat.unseen > 0) ...[
              const SizedBox(width: 8),
              ModernBadge('${chat.unseen}', tone: ModernTone.mint),
            ],
          ],
        ),
      ),
    ),
  );
}

ModernTone _tone(ChatEntry e) => switch (e.kindLabel) {
  'Lista' => ModernTone.butter,
  'Jam' => ModernTone.coral,
  _ => ModernTone.neutral,
};

Widget _cover(ChatEntry e, Color fg) {
  final fallback = ColoredBox(
    color: fg.withValues(alpha: .12),
    child: Icon(e.icon, color: fg),
  );
  final url = e.artworkUrl;
  return ClipRRect(
    borderRadius: BorderRadius.circular(11),
    child: SizedBox(
      width: 48,
      height: 48,
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 144,
              errorBuilder: (_, _, _) => fallback,
            ),
    ),
  );
}

Widget _bubble(BuildContext context, ChatEntry entry) {
  final scheme = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final mine = entry.mine;
  final fg = mine ? Tracky.navy : scheme.onSurface;
  final soft = mine
      ? Tracky.navy.withValues(alpha: .75)
      : scheme.onSurfaceVariant;
  const big = Radius.circular(18), small = Radius.circular(6);
  final radius = BorderRadius.only(
    topLeft: big,
    topRight: big,
    bottomLeft: mine ? big : small,
    bottomRight: mine ? small : big,
  );
  final note = entry.note;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: mine ? Tracky.mint : scheme.surfaceContainerLow,
      borderRadius: radius,
      boxShadow: mine ? null : Tracky.warmShadow,
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: fg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ModernBadge(entry.kindLabel, tone: _tone(entry)),
                Text(entry.time, style: text.labelSmall?.copyWith(color: soft)),
                if (entry.unseen)
                  Semantics(
                    label: 'Nueva',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Tracky.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(entry, fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: text.titleMedium?.copyWith(color: fg),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        entry.subtitle,
                        style: text.bodySmall?.copyWith(color: soft),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                '«$note»',
                style: text.bodyMedium?.copyWith(
                  color: fg,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            if (entry.actions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                children: [
                  for (final a in entry.actions)
                    a.primary
                        ? IconButton.filled(
                            key: a.key,
                            tooltip: a.label,
                            constraints: _touch,
                            style: IconButton.styleFrom(
                              backgroundColor: Tracky.navy,
                              foregroundColor: Tracky.canvas,
                            ),
                            icon: Icon(a.icon),
                            onPressed: a.onTap,
                          )
                        : IconButton(
                            key: a.key,
                            tooltip: a.label,
                            constraints: _touch,
                            color: fg,
                            icon: Icon(a.icon),
                            onPressed: a.onTap,
                          ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _composer(BuildContext context, ChatComposerData data) {
  final scheme = Theme.of(context).colorScheme;
  final dark = isDarkTheme(context);
  const radius = BorderRadius.all(Radius.circular(18));
  const size = Size(0, 44);
  return Container(
    margin: const EdgeInsets.all(12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: coverTint(scheme.surfaceContainerLow, scheme.tertiary, .07),
      borderRadius: radius,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .38 : .10),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('chat-note'),
          controller: data.note,
          maxLength: 200,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Nota (opcional)',
            counterText: '',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in data.actions)
              a.primary
                  ? FilledButton.icon(
                      key: a.key,
                      style: FilledButton.styleFrom(minimumSize: size),
                      onPressed: data.busy ? null : a.onTap,
                      icon: Icon(a.icon),
                      label: Text(a.label),
                    )
                  : OutlinedButton.icon(
                      key: a.key,
                      style: OutlinedButton.styleFrom(minimumSize: size),
                      onPressed: data.busy ? null : a.onTap,
                      icon: Icon(a.icon),
                      label: Text(a.label),
                    ),
          ],
        ),
      ],
    ),
  );
}
