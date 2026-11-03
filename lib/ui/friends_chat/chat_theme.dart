import 'package:flutter/widgets.dart';

import '../../friends/friends_service.dart';
import 'chat_model.dart';

typedef ChatRowBuilder =
    Widget Function(
      BuildContext context,
      FriendChat chat,
      String preview,
      VoidCallback onOpen,
    );
typedef ChatBubbleBuilder =
    Widget Function(BuildContext context, ChatEntry entry);
typedef ChatComposerBuilder =
    Widget Function(BuildContext context, ChatComposerData data);
typedef ChatHeaderBuilder =
    Widget Function(BuildContext context, FriendUser peer, VoidCallback onBack);

/// Diseño de chat de un tema (contrato como el del mini reproductor): la lógica
/// vive en `FriendChatList` y `FriendChatThread`; el tema solo pinta.
///
/// Obligaciones de todo tema:
/// - [header]: el botón atrás lleva `ValueKey('chat-back')` y el tooltip
///   «Volver a los chats».
/// - [row]: toda la fila se pulsa (`onOpen`); muestra `FriendAvatar`, el nombre,
///   la vista previa y `chat.unseen` si es mayor que 0.
/// - [bubble]: pinta título, subtítulo, tipo, hora, portada (o el icono), la
///   nota entre «» y cada acción con su `key`.
/// - Con menos de 600 px de ancho, destinos táctiles de 44 px como mínimo y sin
///   desbordes a 360 px con texto ×2.
class ChatTheme {
  const ChatTheme({
    required this.row,
    required this.bubble,
    required this.composer,
    required this.header,
  });

  final ChatRowBuilder row;
  final ChatBubbleBuilder bubble;
  final ChatComposerBuilder composer;
  final ChatHeaderBuilder header;
}
