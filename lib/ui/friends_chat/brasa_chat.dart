import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';
import '../../theme/brasa_theme.dart';
import '../friends_page.dart' show FriendAvatar;
import 'chat_model.dart';
import 'chat_theme.dart';

/// Chat de Brasa: consola oscura con la brasa como único acento.
const ChatTheme brasaChat = ChatTheme(
  row: _row,
  bubble: _bubble,
  composer: _composer,
  header: _header,
);

const _mono = TextStyle(
  fontFamily: 'monospace',
  fontSize: 11.5,
  color: Brasa.cloud,
  fontFeatures: [FontFeature.tabularFigures()],
);

TextStyle get _kind => TextStyle(
  color: Brasa.accent,
  fontSize: 11.5,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.4,
);

LinearGradient _ember(Axis axis) => LinearGradient(
  begin: axis == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
  end: axis == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
  colors: [Brasa.accent.withValues(alpha: .4), Brasa.accent],
);

Widget _hairline() => DecoratedBox(
  decoration: BoxDecoration(gradient: _ember(Axis.horizontal)),
  child: const SizedBox(height: 2, width: double.infinity),
);

Widget _header(BuildContext context, FriendUser peer, VoidCallback onBack) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('chat-back'),
              tooltip: 'Volver a los chats',
              onPressed: onBack,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              icon: const Icon(Icons.arrow_back, color: Brasa.cream),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CHAT', style: _kind),
                  Text(
                    peer.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Brasa.cream,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      _hairline(),
    ],
  );
}

Widget _row(
  BuildContext context,
  FriendChat chat,
  String preview,
  VoidCallback onOpen,
) {
  final n = chat.unseen;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Material(
      color: Brasa.obsidian,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FriendAvatar(user: chat.peer, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chat.peer.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Brasa.cream,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Brasa.cloud,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (n > 0) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    label: '$n sin ver',
                    excludeSemantics: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, color: Brasa.accent),
                        const SizedBox(width: 6),
                        Text('$n', style: _mono.copyWith(color: Brasa.cream)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _cover(ChatEntry e) {
  final fallback = Icon(e.icon, color: Brasa.steel, size: 22);
  final url = e.artworkUrl;
  return Container(
    width: 44,
    height: 44,
    decoration: BoxDecoration(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Colors.white.withValues(alpha: .14)),
    ),
    clipBehavior: Clip.antiAlias,
    child: url == null || url.isEmpty
        ? Center(child: fallback)
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (c, err, st) => Center(child: fallback),
          ),
  );
}

Widget _square(ChatAction a) {
  final enabled = a.onTap != null;
  final primary = a.primary;
  return Tooltip(
    message: a.label,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: a.label,
      onTap: a.onTap,
      excludeSemantics: true,
      child: Material(
        color: primary ? Brasa.amber : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: primary ? Brasa.amber : Colors.white.withValues(alpha: .14),
          ),
        ),
        child: InkWell(
          key: a.key,
          borderRadius: BorderRadius.circular(4),
          onTap: a.onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              a.icon,
              size: 20,
              color: primary
                  ? Brasa.void_
                  : (enabled ? Brasa.cream : Brasa.steel),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _bubble(BuildContext context, ChatEntry e) {
  final note = e.note;
  final line = Positioned(
    top: 0,
    bottom: 0,
    left: e.mine ? null : 0,
    right: e.mine ? 0 : null,
    width: 2,
    child: DecoratedBox(
      decoration: BoxDecoration(gradient: _ember(Axis.vertical)),
    ),
  );
  return ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: ColoredBox(
      color: e.mine ? Brasa.graphite : Brasa.obsidian,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(e.kindLabel.toUpperCase(), style: _kind),
                    Text(e.time, style: _mono),
                    if (e.unseen)
                      Semantics(
                        label: 'Nueva',
                        child: Container(
                          width: 8,
                          height: 8,
                          color: Brasa.accent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _cover(e),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Brasa.cream,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            e.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Brasa.cloud,
                              fontSize: 12,
                            ),
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
                    style: const TextStyle(
                      color: Brasa.cloud,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
                if (e.actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final a in e.actions) _square(a)],
                  ),
                ],
              ],
            ),
          ),
          line,
        ],
      ),
    ),
  );
}

Widget _composer(BuildContext context, ChatComposerData data) {
  final size = WidgetStateProperty.all(const Size(0, 44));
  return ColoredBox(
    color: Brasa.obsidian,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _hairline(),
        Padding(
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
                style: const TextStyle(color: Brasa.cream, fontSize: 13),
                cursorColor: Brasa.accent,
                decoration: InputDecoration(
                  hintText: 'Nota (opcional)',
                  hintStyle: const TextStyle(color: Brasa.steel, fontSize: 13),
                  counterText: '',
                  filled: true,
                  fillColor: Brasa.graphite,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in data.actions)
                    if (a.primary)
                      FilledButton.icon(
                        key: a.key,
                        style: ButtonStyle(minimumSize: size),
                        onPressed: data.busy ? null : a.onTap,
                        icon: Icon(a.icon, size: 18),
                        label: Text(a.label),
                      )
                    else
                      OutlinedButton.icon(
                        key: a.key,
                        style: ButtonStyle(minimumSize: size),
                        onPressed: data.busy ? null : a.onTap,
                        icon: Icon(a.icon, size: 18),
                        label: Text(a.label),
                      ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
