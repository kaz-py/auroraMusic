/// Dueño: tema Slush.
///
/// Posee la pintura de los paneles de la derecha: cola completa (QueuePanel)
/// y aside de sesión (StudioSessionAside).
library;

import 'package:flutter/material.dart';

import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import 'right_panel_theme.dart';

/// Slush: implementación de [RightPanelTheme].
const RightPanelTheme slushRightPanel = SlushRightPanelTheme();

class SlushRightPanelTheme extends RightPanelTheme {
  const SlushRightPanelTheme();

  @override
  Widget queueCard(Widget child) => ModernCard(child: child);

  @override
  Widget wrapQueue(BuildContext context, Widget body) =>
      SlushScreen(color: context.slush.screen, title: 'COLA', child: body);

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
  double get currentArtRadius => 16;

  @override
  ButtonStyle? get playButtonStyle => IconButton.styleFrom(
    backgroundColor: Tracky.mint,
    foregroundColor: Tracky.navy,
  );

  @override
  ShapeBorder? get tileShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));

  @override
  double get tileArtRadius => 8;

  @override
  Widget asidePanel(Widget child) => ModernCard(child: child);

  @override
  String get asideTitleFont => 'Inter';

  @override
  FontWeight get asideTitleWeight => FontWeight.w600;

  @override
  FontWeight? get asideQueueTitleWeight => FontWeight.w600;

  @override
  double get asideSectionGap => 20;
}
