import 'package:flutter/widgets.dart';

import 'mini_player_model.dart';

/// Constructor del mini reproductor de un tema.
///
/// - [wide]: diseño con carril lateral (≥ 600 px, sin barra de navegación
///   inferior); la barra va al final del contenido. Falso en móvil: encima de
///   la navegación inferior.
///
/// El host ya envuelve el resultado en [MiniPlayerGestures] (toque o arrastre
/// arriba = abrir; deslizar a los lados = anterior/siguiente) y le exige una
/// altura mínima de [MiniPlayerHost.heightFor]: el tema solo dibuja y cablea
/// sus botones. Nunca se construye sin pista ni en la sección 4.
typedef MiniPlayerBuilder =
    Widget Function(
      BuildContext context,
      MiniPlayerState state,
      MiniPlayerActions actions, {
      required bool wide,
    });

/// Un tema del mini reproductor.
class MiniPlayerTheme {
  const MiniPlayerTheme({required this.build});
  final MiniPlayerBuilder build;
}
