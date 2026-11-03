import 'package:flutter/widgets.dart';

import 'mini_player_legacy.dart';
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Brasa. Fase 2: sustituir el cuerpo de [_build] por el mini nuevo y quitar
/// `legacy: true`. Hoy delega en la barra de siempre.
const MiniPlayerTheme brasaMiniPlayer = MiniPlayerTheme(
  build: _build,
  legacy: true,
);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool blurred,
  required bool wide,
}) => legacyMiniPlayerBar(context);
