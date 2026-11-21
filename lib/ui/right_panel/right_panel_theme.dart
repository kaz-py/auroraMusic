import 'package:flutter/material.dart';

import '../../theme/aurora_tokens.dart';
import 'right_panel_atelier.dart';
import 'right_panel_brasa.dart';
import 'right_panel_modern.dart';
import 'right_panel_slush.dart';

/// Pintura por tema de los paneles de la derecha: [QueuePanel] (cola completa)
/// y [StudioSessionAside] (Jam, cola y ecualizador).
///
/// Ambos widgets conservan estructura y lógica; cada tema solo aporta
/// tarjetas, tipografías, radios y colores. Un tema vive en su
/// `right_panel_<tema>.dart`.
abstract class RightPanelTheme {
  const RightPanelTheme();

  // ---- QueuePanel ----

  /// Envuelve la página de la cola (Slush añade su pantalla con título).
  Widget wrapQueue(BuildContext context, Widget body) => body;

  /// Tarjeta que contiene la pista actual y la lista de la cola.
  Widget queueCard(Widget child);

  /// Rótulo «Sonando ahora» y su estilo.
  String get nowPlayingLabel;
  TextStyle? nowPlayingStyle(BuildContext context);

  /// Radio de la portada grande de la pista actual.
  double get currentArtRadius;

  /// Estilo del artista de la pista actual.
  TextStyle artistStyle(BuildContext context);

  /// Estilo del botón reproducir/pausar (null = el del tema).
  ButtonStyle? get playButtonStyle;

  /// Forma, radio de portada y estilos de cada fila de la cola.
  ShapeBorder? get tileShape;
  double get tileArtRadius;
  TextStyle? get tileTitleStyle;
  TextStyle? get tileSubtitleStyle;

  // ---- StudioSessionAside ----

  /// Tarjeta de cada bloque del aside.
  Widget asidePanel(Widget child);

  /// Tipografía y peso de los títulos del aside.
  String get asideTitleFont;
  FontWeight get asideTitleWeight;

  /// Peso del título «En Cola» (null = el de la fuente).
  FontWeight? get asideQueueTitleWeight;

  /// Separación vertical entre bloques del aside.
  double get asideSectionGap;
}

/// Registro de temas de los paneles de la derecha.
const Map<AuroraThemeKind, RightPanelTheme> rightPanelThemes = {
  AuroraThemeKind.atelier: atelierRightPanel,
  AuroraThemeKind.modern: modernRightPanel,
  AuroraThemeKind.brasa: brasaRightPanel,
  AuroraThemeKind.slush: slushRightPanel,
};

RightPanelTheme rightPanelThemeFor(AuroraThemeKind kind) =>
    rightPanelThemes[kind]!;

/// Tema de paneles de la derecha vigente en [context].
RightPanelTheme rightPanelThemeOf(BuildContext context) =>
    rightPanelThemeFor(themeKindOf(context));
