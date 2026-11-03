import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';
import '../friends_page.dart' show FriendAvatar;
import '../studio/studio_components.dart';
import 'chat_model.dart';
import 'chat_theme.dart';

/// Atelier: funda de disco y notas de carátula. Sin tarjetas: filas planas con
/// regla fina, mensajes como fundas (`StudioPanel`) con un filo del color de
/// acento hacia el centro.
const atelierChat = ChatTheme(
  row: _row,
  bubble: _bubble,
  composer: _composer,
  header: _header,
);

const _serif = 'Newsreader';

ButtonStyle _icon44(ColorScheme colors, {bool primary = false}) =>
    IconButton.styleFrom(
      minimumSize: const Size(44, 44),
      tapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: primary ? colors.primary : null,
      foregroundColor: primary ? colors.onPrimary : null,
    );

Widget _header(BuildContext context, FriendUser peer, VoidCallback onBack) {
  final colors = Theme.of(context).colorScheme;
  return DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: colors.outlineVariant)),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('chat-back'),
            tooltip: 'Volver a los chats',
            style: _icon44(colors),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const StudioStamp('CONVERSACIÓN'),
                Text(
                  peer.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _row(
  BuildContext context,
  FriendChat chat,
  String preview,
  VoidCallback onOpen,
) {
  final colors = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final n = chat.unseen;
  return Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onOpen,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontFamily: _serif,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (n > 0) ...[
                  const SizedBox(width: 8),
                  StudioStamp('$n NUEVO${n == 1 ? '' : 'S'}', filled: true),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _cover(BuildContext context, ChatEntry e) {
  final colors = Theme.of(context).colorScheme;
  final fallback = ColoredBox(
    color: colors.surfaceContainerHigh,
    child: Center(child: Icon(e.icon, color: colors.onSurfaceVariant)),
  );
  final url = e.artworkUrl;
  return ClipRRect(
    borderRadius: StudioPalette.sleeve,
    child: SizedBox(
      width: 56,
      height: 56,
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 168,
              errorBuilder: (_, _, _) => fallback,
            ),
    ),
  );
}

Widget _bubble(BuildContext context, ChatEntry e) {
  final colors = Theme.of(context).colorScheme;
  final text = Theme.of(context).textTheme;
  final who = e.mine ? 'TÚ' : e.item.peer.username.toUpperCase();
  final edge = BorderSide(color: colors.primary, width: 3);
  return StudioPanel(
    recessed: !e.mine,
    padding: EdgeInsets.zero,
    child: DecoratedBox(
      // El filo mira hacia el centro: a la derecha en lo mío, a la izquierda
      // en lo del amigo.
      decoration: BoxDecoration(
        border: Border(
          left: e.mine ? BorderSide.none : edge,
          right: e.mine ? edge : BorderSide.none,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      StudioStamp('$who · ${e.time}'),
                      StudioStamp(e.kindLabel.toUpperCase()),
                    ],
                  ),
                ),
                if (e.unseen)
                  Semantics(
                    label: 'Nueva',
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(left: 8, top: 2),
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _cover(context, e),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleLarge?.copyWith(
                          fontFamily: _serif,
                          fontSize: 20,
                        ),
                      ),
                      Text(
                        e.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (e.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '«${e.note}»',
                  style: TextStyle(
                    fontFamily: _serif,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                    color: colors.onSurface,
                  ),
                ),
              ),
            if (e.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final a in e.actions)
                      a.primary
                          ? IconButton.filled(
                              key: a.key,
                              tooltip: a.label,
                              style: _icon44(colors, primary: true),
                              icon: Icon(a.icon),
                              onPressed: a.onTap,
                            )
                          : IconButton(
                              key: a.key,
                              tooltip: a.label,
                              style: _icon44(colors),
                              icon: Icon(a.icon),
                              onPressed: a.onTap,
                            ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _composer(BuildContext context, ChatComposerData d) {
  final colors = Theme.of(context).colorScheme;
  const size = Size(0, 44);
  return DecoratedBox(
    decoration: BoxDecoration(
      color: colors.surfaceContainerLow,
      border: Border(top: BorderSide(color: colors.outlineVariant)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('chat-note'),
              controller: d.note,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Nota (opcional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in d.actions)
                  if (a.primary)
                    FilledButton.icon(
                      key: a.key,
                      style: FilledButton.styleFrom(minimumSize: size),
                      onPressed: d.busy ? null : a.onTap,
                      icon: Icon(a.icon, size: 18),
                      label: Text(a.label),
                    )
                  else
                    OutlinedButton.icon(
                      key: a.key,
                      style: OutlinedButton.styleFrom(minimumSize: size),
                      onPressed: d.busy ? null : a.onTap,
                      icon: Icon(a.icon, size: 18),
                      label: Text(a.label),
                    ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
