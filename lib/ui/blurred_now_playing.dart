import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'mini_player/blurred_cover_backdrop.dart';

/// «Modo difuminado»: apartado propio (se abre desde el botón de la barra de
/// abajo) con la portada de la pista difuminada de fondo y las letras encima.
///
/// El fondo se funde con el tema (`matchTheme`): el velo es el fondo del tema y
/// los textos de [child] (la página de letras) conservan sus colores, así que
/// el contraste lo sigue garantizando el tema. Sin portada se ve la página de
/// letras normal.
class BlurredNowPlaying extends StatelessWidget {
  const BlurredNowPlaying({
    super.key,
    required this.controller,
    required this.child,
  });

  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => BlurredCoverBackdrop(
      track: controller.nowTrack,
      matchTheme: true,
      child: child,
    ),
  );
}
