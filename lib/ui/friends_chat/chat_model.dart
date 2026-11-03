import 'package:flutter/material.dart';

import '../../friends/friends_service.dart';

/// Acción de un mensaje o del compositor. La lógica es de `FriendChatThread`;
/// cada tema solo la pinta.
class ChatAction {
  const ChatAction({
    required this.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  /// Va en el widget que se pulsa.
  final Key key;
  final IconData icon;

  /// Tooltip, semántica y texto visible cuando el tema lo muestra.
  final String label;

  /// `null`: desactivada.
  final VoidCallback? onTap;
  final bool primary;
}

/// Un envío listo para pintar.
class ChatEntry {
  const ChatEntry({
    required this.item,
    required this.title,
    required this.subtitle,
    required this.kindLabel,
    required this.icon,
    required this.time,
    this.artworkUrl,
    this.actions = const [],
  });

  final SharedItem item;
  final String title, subtitle, kindLabel, time;
  final IconData icon;
  final String? artworkUrl;
  final List<ChatAction> actions;

  bool get mine => item.mine;

  /// Recibido y aún sin ver.
  bool get unseen => !item.mine && !item.seen;
  String? get note => item.note;
}

/// Pie del hilo: nota opcional y acciones de envío.
class ChatComposerData {
  const ChatComposerData({
    required this.note,
    required this.actions,
    required this.busy,
  });

  /// El tema dibuja el `TextField` con `ValueKey('chat-note')`, `maxLength` 200
  /// y la pista «Nota (opcional)».
  final TextEditingController note;
  final List<ChatAction> actions;

  /// Enviando: el tema desactiva las acciones.
  final bool busy;
}

/// Una línea de vista previa para la lista de chats.
String chatPreview(FriendChat chat) {
  final last = chat.last;
  if (last == null) return 'Aún no os habéis enviado nada';
  final p = last.mine ? 'Tú: ' : '';
  return switch (last.kind) {
    SharedKind.track => '$p${last.track.title} · ${last.track.artist}',
    SharedKind.playlist => '${p}Lista «${last.playlist?.name ?? ''}»',
    SharedKind.jam =>
      last.mine ? 'Tú: invitación a tu Jam' : 'Te invita a su Jam',
  };
}
