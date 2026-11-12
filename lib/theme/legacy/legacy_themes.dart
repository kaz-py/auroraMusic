import 'package:flutter/material.dart';

import '../aurora_tokens.dart';
import 'legacy_atelier_theme.dart';
import 'legacy_brasa_theme.dart';
import 'legacy_modern_theme.dart';
import 'legacy_slush_theme.dart';

/// `ThemeData` congelado del tema [kind] (ver los `legacy_*_theme.dart`). Solo
/// lo usa el shell para el modo letra (sección 6).
ThemeData legacyThemeFor(
  AuroraThemeKind kind,
  Brightness brightness,
  Color accent,
) => switch (kind) {
  AuroraThemeKind.atelier => legacyAtelierTheme(brightness, accent),
  AuroraThemeKind.modern => legacyModernTheme(brightness, accent),
  AuroraThemeKind.brasa => legacyBrasaTheme(brightness, accent),
  AuroraThemeKind.slush => legacySlushTheme(brightness, accent),
};
