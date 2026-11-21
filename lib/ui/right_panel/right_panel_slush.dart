/// Dueño: tema Slush.
///
/// Posee la pintura de los paneles de la derecha: cola completa (QueuePanel)
/// y aside de sesión (StudioSessionAside).
library;

import 'package:flutter/material.dart';

import '../../theme/slush_theme.dart';
import 'right_panel_theme.dart';

/// Slush: implementación de [RightPanelTheme].
const RightPanelTheme slushRightPanel = SlushRightPanelTheme();

/// Tarjeta de papel con borde de 2 px y sombra dura de tarjeta.
Widget _paperCard(BuildContext context, Widget child, {double radius = 24}) {
  final p = context.slush;
  return DecoratedBox(
    decoration: BoxDecoration(
      color: p.paper,
      borderRadius: BorderRadius.circular(radius),
      border: Border.fromBorderSide(p.borderSoft),
      boxShadow: p.shadowsFor(SlushElevation.card),
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class SlushRightPanelTheme extends RightPanelTheme {
  const SlushRightPanelTheme();

  @override
  Widget queueCard(Widget child) =>
      Builder(builder: (context) => _paperCard(context, child));

  @override
  Widget wrapQueue(BuildContext context, Widget body) => ColoredBox(
    color: context.slush.screen,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'Cola',
              style: slushHeadline(72, height: .95, color: context.slush.ink),
            ),
          ),
        ),
        Expanded(child: body),
      ],
    ),
  );

  @override
  String get nowPlayingLabel => 'SONANDO AHORA';

  @override
  TextStyle? nowPlayingStyle(BuildContext context) =>
      slushMono(11, color: context.slush.violetAccent, letterSpacing: 1.4);

  @override
  TextStyle artistStyle(BuildContext context) =>
      TextStyle(color: context.slush.ink2, fontWeight: FontWeight.w600);

  @override
  TextStyle? get tileTitleStyle => null;

  @override
  TextStyle? get tileSubtitleStyle => null;

  @override
  double get currentArtRadius => 16;

  /// Play lima con borde de tinta: lo que suena.
  @override
  ButtonStyle? get playButtonStyle => IconButton.styleFrom(
    backgroundColor: Slush.lime,
    foregroundColor: Slush.ink,
    side: const BorderSide(color: Slush.ink, width: SlushStroke.base),
  );

  @override
  ShapeBorder? get tileShape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  @override
  double get tileArtRadius => 12;

  @override
  Widget asidePanel(Widget child) =>
      Builder(builder: (context) => _paperCard(context, child));

  @override
  String get asideTitleFont => 'Bricolage Grotesque';

  @override
  FontWeight get asideTitleWeight => FontWeight.w800;

  @override
  FontWeight? get asideQueueTitleWeight => FontWeight.w800;

  @override
  double get asideSectionGap => 20;
}
