import 'package:flutter/widgets.dart';

import 'brasa_theme.dart';
import 'modern_theme.dart';
import 'slush_theme.dart';

/// Los cuatro temas de Aurora (`AppController.themeKind`).
enum AuroraThemeKind { atelier, modern, brasa, slush }

/// Único resolvedor del tema vigente según el `ThemeData` activo.
///
/// Slush también lleva `ModernMarker`: se comprueba antes que Modern. Atelier
/// es el tema sin marca.
AuroraThemeKind themeKindOf(BuildContext context) => isSlush(context)
    ? AuroraThemeKind.slush
    : isBrasa(context)
    ? AuroraThemeKind.brasa
    : isModern(context)
    ? AuroraThemeKind.modern
    : AuroraThemeKind.atelier;
