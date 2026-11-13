import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../friends_page.dart' show FriendAvatar;
import 'chat_model.dart';
import 'chat_theme.dart';

/// Chat de Slush: pegatinas con borde y sombra dura.
const ChatTheme slushChat = ChatTheme(
  row: _row,
  bubble: _bubble,
  composer: _composer,
  header: _header,
);

TextStyle _inter(double size, FontWeight w, Color c, {bool italic = false}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: w,
      color: c,
      height: 1.25,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    );

Widget _header(BuildContext context, FriendUser peer, VoidCallback onBack) {
  final p = context.slush;
  return Padding(
    padding: const EdgeInsets.fromLTRB(
      SlushSpacing.s12,
      SlushSpacing.s8,
      SlushSpacing.s12,
      SlushSpacing.s8,
    ),
    child: Row(
      children: [
        Tooltip(
          message: 'Volver a los chats',
          child: SlushPressable(
            key: const ValueKey('chat-back'),
            semanticLabel: 'Volver a los chats',
            onTap: onBack,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: p.paper,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(p.border),
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_rounded, color: p.ink),
              ),
            ),
          ),
        ),
        const SizedBox(width: SlushSpacing.s12),
        Expanded(
          child: Text(
            peer.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: slushHeadline(22, height: 1.1, color: p.ink),
          ),
        ),
        const SizedBox(width: SlushSpacing.s8),
        const SlushPill('CHAT', color: Slush.mint),
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
  final p = context.slush;
  return Padding(
    padding: const EdgeInsets.only(bottom: SlushSpacing.s12, right: 3),
    child: SlushPressable(
      radius: SlushRadius.r24,
      elevation: SlushElevation.card,
      semanticLabel: chat.peer.username,
      onTap: onOpen,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(SlushRadius.r24),
          border: Border.fromBorderSide(p.border),
          boxShadow: p.shadows,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.all(SlushSpacing.s12),
            child: Row(
              children: [
                FriendAvatar(user: chat.peer, size: 44),
                const SizedBox(width: SlushSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        chat.peer.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(16, FontWeight.w800, p.ink),
                      ),
                      Text(
                        preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(12, FontWeight.w600, p.ink2),
                      ),
                    ],
                  ),
                ),
                if (chat.unseen > 0) ...[
                  const SizedBox(width: SlushSpacing.s8),
                  SlushPill('${chat.unseen}', color: Slush.mint),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Color _kindColor(String kind) => switch (kind) {
  'Lista' => Slush.lilac,
  'Jam' => Slush.mint,
  _ => Slush.yellow,
};

Widget _cover(BuildContext context, ChatEntry e, Color fill) {
  final p = context.slush;
  final icon = Icon(e.icon, color: p.ink2);
  final url = e.artworkUrl;
  return Container(
    width: 48,
    height: 48,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: p.inset,
      borderRadius: BorderRadius.circular(SlushRadius.r12),
      border: Border.all(color: p.line, width: SlushStroke.base),
    ),
    child: url == null
        ? Center(child: icon)
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => Center(child: icon),
          ),
  );
}

Widget _circleAction(BuildContext context, ChatAction a) {
  final p = context.slush;
  final fill = a.primary ? Slush.ink : p.paper;
  return Tooltip(
    message: a.label,
    child: SlushPressable(
      key: a.key,
      semanticLabel: a.label,
      elevation: SlushElevation.control,
      onTap: a.onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(p.border),
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            a.icon,
            size: 22,
            color: a.primary ? slushOnColor(context, fill) : p.ink,
          ),
        ),
      ),
    ),
  );
}

Widget _bubble(BuildContext context, ChatEntry entry) {
  final p = context.slush;
  final mine = entry.mine;
  final fill = mine ? Slush.lilacHero : p.paper;
  final on = slushOnColor(context, fill);
  final sub = mine ? on : p.ink2;
  final time = mine ? on : p.ink3;
  const r = Radius.circular(SlushRadius.r24);
  const small = Radius.circular(SlushRadius.r8);
  final note = entry.note;
  return Padding(
    // Hueco para la sombra dura (3,4).
    padding: const EdgeInsets.only(right: 3, bottom: 4),
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.only(
          topLeft: r,
          topRight: r,
          bottomLeft: mine ? r : small,
          bottomRight: mine ? small : r,
        ),
        border: Border.fromBorderSide(p.border),
        boxShadow: p.shadows,
      ),
      child: Padding(
        padding: const EdgeInsets.all(SlushSpacing.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: SlushSpacing.s8,
              runSpacing: SlushSpacing.s4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SlushPill(
                  entry.kindLabel.toUpperCase(),
                  color: _kindColor(entry.kindLabel),
                ),
                Text(entry.time, style: _inter(11, FontWeight.w700, time)),
                if (entry.unseen)
                  Semantics(
                    label: 'Nueva',
                    child: const SlushPill('Nueva', color: Slush.pink),
                  ),
              ],
            ),
            const SizedBox(height: SlushSpacing.s8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(context, entry, fill),
                const SizedBox(width: SlushSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(15, FontWeight.w800, on),
                      ),
                      Text(
                        entry.subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(12, FontWeight.w600, sub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (note != null && note.isNotEmpty) ...[
              const SizedBox(height: SlushSpacing.s8),
              Text(
                '«$note»',
                style: _inter(13, FontWeight.w600, on, italic: true),
              ),
            ],
            if (entry.actions.isNotEmpty) ...[
              const SizedBox(height: SlushSpacing.s8),
              Wrap(
                spacing: SlushSpacing.s8,
                runSpacing: SlushSpacing.s8,
                children: [
                  for (final a in entry.actions) _circleAction(context, a),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Widget _pillAction(BuildContext context, ChatAction a, bool busy) {
  final p = context.slush;
  final enabled = !busy && a.onTap != null;
  final fill = !enabled
      ? p.disabledFill
      : a.primary
      ? Slush.mint
      : Slush.yellow;
  final fg = enabled ? slushOnColor(context, fill) : p.disabledText;
  return SlushPressable(
    key: a.key,
    semanticLabel: a.label,
    elevation: SlushElevation.control,
    onTap: busy ? null : a.onTap,
    child: DecoratedBox(
      decoration: ShapeDecoration(
        color: fill,
        shape: StadiumBorder(side: p.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SlushSpacing.s16,
            vertical: SlushSpacing.s8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(a.icon, size: 20, color: fg),
              const SizedBox(width: SlushSpacing.s8),
              Flexible(
                child: Text(
                  a.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _inter(13, FontWeight.w800, fg),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _composer(BuildContext context, ChatComposerData data) {
  final p = context.slush;
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(SlushRadius.r16),
    borderSide: p.border,
  );
  return DecoratedBox(
    decoration: BoxDecoration(
      color: p.raised,
      border: Border(top: p.border),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(SlushSpacing.s12),
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
              style: _inter(14, FontWeight.w600, p.ink),
              decoration: InputDecoration(
                hintText: 'Nota (opcional)',
                hintStyle: _inter(14, FontWeight.w600, p.ink3),
                counterText: '',
                filled: true,
                fillColor: p.inset,
                border: field,
                enabledBorder: field,
                focusedBorder: field.copyWith(borderSide: p.focusRing),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: SlushSpacing.s16,
                  vertical: SlushSpacing.s12,
                ),
              ),
            ),
            const SizedBox(height: SlushSpacing.s12),
            Wrap(
              spacing: SlushSpacing.s8,
              runSpacing: SlushSpacing.s12,
              children: [
                for (final a in data.actions)
                  _pillAction(context, a, data.busy),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
