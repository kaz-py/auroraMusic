/// Dueño: tema Brasa.
///
/// Posee la pintura de los paneles de la derecha: cola completa (QueuePanel)
/// y aside de sesión (StudioSessionAside).
library;

import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import 'right_panel_theme.dart';

/// Brasa: implementación de [RightPanelTheme].
const RightPanelTheme brasaRightPanel = BrasaRightPanelTheme();

class BrasaRightPanelTheme extends RightPanelTheme {
  const BrasaRightPanelTheme();

  /// Tarjeta Brasa: #17110e, radio 6 y la sombra de tarjeta del tema.
  @override
  Widget queueCard(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.obsidian,
      borderRadius: BorderRadius.circular(6),
      boxShadow: Brasa.cardShadow,
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  String get nowPlayingLabel => 'Sonando ahora';

  @override
  TextStyle? nowPlayingStyle(BuildContext context) => const TextStyle(
    fontFamily: 'Inter',
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: Brasa.cream,
  );

  @override
  double get currentArtRadius => 6;

  @override
  TextStyle artistStyle(BuildContext context) =>
      const TextStyle(color: Brasa.steel);

  @override
  ButtonStyle? get playButtonStyle => IconButton.styleFrom(
    backgroundColor: Brasa.cream,
    foregroundColor: Colors.black,
  );

  @override
  ShapeBorder? get tileShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(4));

  @override
  double get tileArtRadius => 4;

  @override
  TextStyle? get tileTitleStyle => const TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Brasa.cream,
  );

  @override
  TextStyle? get tileSubtitleStyle =>
      const TextStyle(fontSize: 12, color: Brasa.steel);

  @override
  Widget asidePanel(Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.obsidian,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );

  @override
  String get asideTitleFont => 'Inter';

  @override
  FontWeight get asideTitleWeight => FontWeight.w700;

  @override
  FontWeight? get asideQueueTitleWeight => FontWeight.w600;

  @override
  double get asideSectionGap => 20;
}
