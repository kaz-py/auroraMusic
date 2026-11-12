/// Dueño: tema Atelier Sonoro (sin marca).
///
/// Posee la pintura de los paneles de la derecha: cola completa (QueuePanel)
/// y aside de sesión (StudioSessionAside).
library;

import 'package:flutter/material.dart';

import '../studio/studio_components.dart';
import 'right_panel_theme.dart';

/// Atelier Sonoro (sin marca): implementación de [RightPanelTheme].
const RightPanelTheme atelierRightPanel = AtelierRightPanelTheme();

class AtelierRightPanelTheme extends RightPanelTheme {
  const AtelierRightPanelTheme();

  @override
  Widget queueCard(Widget child) => child;

  @override
  String get nowPlayingLabel => 'SONANDO AHORA';

  @override
  TextStyle? nowPlayingStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelSmall?.copyWith(
        letterSpacing: 1.4,
        color: Theme.of(context).colorScheme.primary,
      );

  @override
  TextStyle artistStyle(BuildContext context) =>
      TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);

  @override
  TextStyle? get tileTitleStyle => null;

  @override
  TextStyle? get tileSubtitleStyle => null;

  @override
  double get currentArtRadius => 8;

  @override
  ButtonStyle? get playButtonStyle => null;

  @override
  ShapeBorder? get tileShape => null;

  @override
  double get tileArtRadius => 5;

  @override
  Widget asidePanel(Widget child) => StudioPanel(child: child);

  @override
  String get asideTitleFont => 'Newsreader';

  @override
  FontWeight get asideTitleWeight => FontWeight.w500;

  @override
  FontWeight? get asideQueueTitleWeight => null;

  @override
  double get asideSectionGap => 24;
}
