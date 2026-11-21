/// Dueño: tema Brasa.
///
/// Posee la pintura de los paneles de la derecha: cola completa (QueuePanel)
/// y aside de sesión (StudioSessionAside). El aside con pestañas y Jam al pie
/// vive en `brasa_aside.dart` (BrasaAside).
library;

import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import 'right_panel_theme.dart';

/// Brasa: implementación de [RightPanelTheme].
const RightPanelTheme brasaRightPanel = BrasaRightPanelTheme();

class BrasaRightPanelTheme extends RightPanelTheme {
  const BrasaRightPanelTheme();

  /// Tarjeta tonal (graphite), radio 24, sin borde ni sombra.
  @override
  Widget queueCard(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  String get nowPlayingLabel => 'SONANDO AHORA';

  @override
  TextStyle? nowPlayingStyle(BuildContext context) => Brasa.mono(11);

  @override
  double get currentArtRadius => 12;

  @override
  TextStyle artistStyle(BuildContext context) =>
      Brasa.sans(14, color: Brasa.cloud);

  @override
  ButtonStyle? get playButtonStyle => IconButton.styleFrom(
    backgroundColor: Brasa.ember,
    foregroundColor: Brasa.onEmber,
  );

  @override
  ShapeBorder? get tileShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  @override
  double get tileArtRadius => 8;

  @override
  TextStyle? get tileTitleStyle => Brasa.sans(14, weight: FontWeight.w500);

  @override
  TextStyle? get tileSubtitleStyle => Brasa.sans(12, color: Brasa.cloud);

  @override
  Widget asidePanel(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  String get asideTitleFont => 'Fraunces';

  @override
  FontWeight get asideTitleWeight => FontWeight.w600;

  @override
  FontWeight? get asideQueueTitleWeight => FontWeight.w600;

  @override
  double get asideSectionGap => 16;
}
