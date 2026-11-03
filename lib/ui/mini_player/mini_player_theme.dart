import 'package:flutter/widgets.dart';

import 'mini_player_model.dart';

/// Constructor del mini reproductor de un tema.
///
/// - [wide]: diseño con carril lateral (≥ 600 px, sin barra de navegación
///   inferior); la barra va al final del contenido. Falso en móvil: encima de
///   la navegación inferior.
/// - [blurred]: el ajuste «Fondo difuminado de la portada» está activo y la
///   pista tiene portada; el tema pinta `BlurredCoverBackdrop` con su forma y
///   usa `BlurredCoverTheme.of(context)` para el texto (artista en grande).
///   Sin portada llega `false` y se pinta el aspecto normal.
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
      required bool blurred,
      required bool wide,
    });

/// Un tema del mini reproductor.
///
/// [legacy]: sigue siendo la barra anterior a 1.5.0. El host conserva
/// entonces su visibilidad y su manejo de Jam de siempre y **no** lo envuelve
/// en gestos ni altura mínima. Al sustituir el cuerpo por el mini nuevo,
/// quitar `legacy: true`.
class MiniPlayerTheme {
  const MiniPlayerTheme({required this.build, this.legacy = false});
  final MiniPlayerBuilder build;
  final bool legacy;
}
