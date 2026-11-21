import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';
import '../../theme/modern_cristal.dart';
import '../friends_page.dart' show FriendAvatar;
import 'chat_model.dart';
import 'chat_theme.dart';

/// Chat de Modern «Cristal y aura»: burbujas de cristal, las propias en
/// acento con tinta oscura, y compositor de cristal.
const ChatTheme modernChat = ChatTheme(
  row: _row,
  bubble: _bubble,
  composer: _composer,
  header: _header,
);

const _touch = BoxConstraints(minWidth: 44, minHeight: 44);

/// Etiqueta mono pequeña (tipo de mensaje, «Chat»).
Widget _tag(String label, Color color, {bool filled = false}) => DecoratedBox(
  decoration: BoxDecoration(
    color: filled ? color.withValues(alpha: .14) : null,
    border: Border.all(color: color.withValues(alpha: .45)),
    borderRadius: BorderRadius.circular(8),
  ),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: Text(
      label.toUpperCase(),
      style: Cristal.mono(10.5, weight: 600, color: color, tracking: .08),
    ),
  ),
);

Widget _header(BuildContext context, FriendUser peer, VoidCallback onBack) {
  final c = Cristal.of(context);
  return Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('chat-back'),
          tooltip: 'Volver a los chats',
          constraints: _touch,
          color: c.text,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        FriendAvatar(user: peer, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            peer.username,
            style: Cristal.ui(20, weight: 800, color: c.text, tracking: -.02),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _tag('Chat', c.signal, filled: true),
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
  final c = Cristal.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Semantics(
      button: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: ModernGlass(
          radius: 16,
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
                        style: Cristal.ui(15, weight: 700, color: c.text),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        preview,
                        style: Cristal.ui(13, weight: 500, color: c.text2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (chat.unseen > 0) ...[
                  const SizedBox(width: 8),
                  _tag('${chat.unseen}', c.accent, filled: true),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Color _toneColor(Cristal c, ChatEntry e) => switch (e.kindLabel) {
  'Lista' => c.vu,
  'Jam' => c.like,
  _ => c.text3,
};

Widget _cover(ChatEntry e, Color fg) {
  final fallback = ColoredBox(
    color: fg.withValues(alpha: .12),
    child: Icon(e.icon, color: fg),
  );
  final url = e.artworkUrl;
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
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
  final c = Cristal.of(context);
  final mine = entry.mine;
  final fg = mine ? c.onAccent : c.text;
  final soft = mine ? c.onAccent.withValues(alpha: .78) : c.text2;
  const big = Radius.circular(20), small = Radius.circular(6);
  final radius = BorderRadius.only(
    topLeft: big,
    topRight: big,
    bottomLeft: mine ? big : small,
    bottomRight: mine ? small : big,
  );
  final note = entry.note;
  final body = Padding(
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
              _tag(entry.kindLabel, mine ? c.onAccent : _toneColor(c, entry)),
              Text(entry.time, style: Cristal.mono(10.5, color: soft)),
              if (entry.unseen)
                Semantics(
                  label: 'Nueva',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.like,
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
                      style: Cristal.ui(15, weight: 700, color: fg),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      entry.subtitle,
                      style: Cristal.ui(13, weight: 500, color: soft),
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
              style: Cristal.ui(
                14,
                weight: 500,
                color: fg,
              ).copyWith(fontStyle: FontStyle.italic),
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
                            backgroundColor: mine ? c.onAccent : c.accent,
                            foregroundColor: mine ? c.accent : c.onAccent,
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
  );
  if (mine) {
    return DecoratedBox(
      decoration: BoxDecoration(color: c.accent, borderRadius: radius),
      child: body,
    );
  }
  return DecoratedBox(
    decoration: BoxDecoration(
      color: c.glass,
      borderRadius: radius,
      border: Border.all(color: c.border),
    ),
    child: body,
  );
}

Widget _composer(BuildContext context, ChatComposerData data) {
  const size = Size(0, 44);
  return Padding(
    padding: const EdgeInsets.all(12),
    child: ModernGlass(
      radius: 24,
      padding: const EdgeInsets.all(12),
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
    ),
  );
}
