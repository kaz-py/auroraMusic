import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';

/// Tiñe una superficie con el color de portada (sin cambiar su luminosidad base).
Color coverTint(Color base, Color accent, [double amount = .05]) =>
    Color.lerp(base, accent, amount)!;

/// Tema «Modern»: lienzo cálido, tinta azul marino, acentos coral y menta,
/// radios 8/16/24 y sombras cálidas. Misma firma que `auroraTheme`.
ThemeData modernTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  const navy = Color(0xff151b31);
  const canvas = Color(0xfff2f2f2);
  const mint = Color(0xff86e0c1);

  Color t(Color c) => coverTint(c, accent);
  final surface = t(dark ? const Color(0xff0e1222) : canvas);

  double contrast(Color a, Color b) {
    final x = a.computeLuminance(), y = b.computeLuminance();
    return (math.max(x, y) + .05) / (math.min(x, y) + .05);
  }

  // El acento de Ajustes/portada (sliders, progreso) conserva contraste >= 3.
  var tint = accent;
  for (var i = 0; i < 100 && contrast(tint, surface) < 3; i++) {
    final hsl = HSLColor.fromColor(tint);
    tint = hsl
        .withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0.0, 1.0))
        .toColor();
  }

  final primary = dark ? canvas : navy;
  final onPrimary = dark ? navy : Colors.white;
  final scheme = ColorScheme.fromSeed(seedColor: navy, brightness: brightness)
      .copyWith(
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: dark ? const Color(0xff262e4f) : navy,
        onPrimaryContainer: dark ? canvas : Colors.white,
        secondary: mint,
        onSecondary: navy,
        secondaryContainer: dark ? const Color(0xff1f3a37) : mint,
        onSecondaryContainer: dark ? mint : navy,
        tertiary: tint,
        onTertiary: contrast(tint, Colors.white) > contrast(tint, navy)
            ? Colors.white
            : navy,
        error: dark ? const Color(0xffff8a8a) : const Color(0xffc62828),
        surface: surface,
        surfaceDim: dark ? const Color(0xff0a0d19) : const Color(0xffe3e3e3),
        surfaceBright: dark ? const Color(0xff2a3254) : Colors.white,
        surfaceContainerLowest: dark ? const Color(0xff0a0d19) : Colors.white,
        surfaceContainerLow: t(dark ? const Color(0xff151b31) : Colors.white),
        surfaceContainer: t(
          dark ? const Color(0xff1a213b) : const Color(0xfff7f7f7),
        ),
        surfaceContainerHigh: t(
          dark ? const Color(0xff222a48) : const Color(0xffeeeeee),
        ),
        surfaceContainerHighest: t(
          dark ? const Color(0xff2b3456) : const Color(0xffe8e7e5),
        ),
        onSurface: dark ? canvas : navy,
        onSurfaceVariant: dark
            ? const Color(0xffb4b7c4)
            : const Color(0xff4d5160),
        outline: dark ? const Color(0xff8a91b3) : const Color(0xff6d6f75),
        outlineVariant: dark
            ? const Color(0xff6a739b)
            : const Color(0xff8c8a85),
      );

  // Guía Tracky: GRIFTER (sustituta libre: Bagel Fat One) solo en títulos
  // grandes; Inter con tracking -0.01em en toda la interfaz.
  const font = 'Inter';
  const display = 'Bagel Fat One';
  TextStyle head(double size, double height, {bool brand = true}) => TextStyle(
    fontFamily: brand ? display : font,
    fontSize: size,
    height: height,
    fontWeight: brand ? FontWeight.w400 : FontWeight.w700,
    letterSpacing: brand ? size * .03 : -size * .01,
    color: scheme.onSurface,
  );
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(
        fontFamily: font,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: head(56, 1.1),
        headlineLarge: head(36, 1.2),
        headlineMedium: head(28, 1.2),
        headlineSmall: head(24, 1.3),
        titleLarge: head(22, 1.3, brand: false),
        titleMedium: const TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w600,
          letterSpacing: -.16,
        ),
        bodyLarge: const TextStyle(fontFamily: font, letterSpacing: -.18),
        bodyMedium: const TextStyle(fontFamily: font, letterSpacing: -.14),
        bodySmall: const TextStyle(fontFamily: font, letterSpacing: -.12),
      );

  final states = AuroraStates.from(scheme);
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? states.pressed
        : s.contains(WidgetState.focused)
        ? states.focusRing.withValues(alpha: .28)
        : s.contains(WidgetState.hovered)
        ? states.hover
        : null,
  );
  RoundedRectangleBorder shape(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    extensions: [states, const ModernMarker()],
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    // Las líneas finas siguen suaves; los bordes de controles usan outline.
    dividerTheme: DividerThemeData(
      color: dark ? const Color(0xff4a5275) : const Color(0xffc4c2be),
      thickness: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: shape(8),
      ).copyWith(overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: scheme.surfaceContainerLow,
            shape: shape(8),
          ).copyWith(
            overlayColor: overlay,
            side: WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? states.disabledText
                    : s.contains(WidgetState.focused)
                    ? states.focusRing
                    : scheme.outline,
                width: s.contains(WidgetState.focused) ? 2 : 1.5,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        shape: shape(8),
      ).copyWith(overlayColor: overlay),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primary,
      checkmarkColor: scheme.onPrimary,
      // Seleccionado el fondo es primary: el texto pasa a onPrimary (también
      // en FilterChip, que no usa secondaryLabelStyle).
      labelStyle: TextStyle(
        color: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface,
        ),
        fontWeight: FontWeight.w500,
      ),
      secondaryLabelStyle: TextStyle(
        color: scheme.onPrimary,
        fontWeight: FontWeight.w500,
      ),
      // Alto >= 40 para el toque en móvil (el texto mide 14: 14 + 2 * 13 = 40).
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
      side: BorderSide(color: scheme.outline, width: 1.5),
      shape: shape(8),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.all(
          BorderSide(color: scheme.outline, width: 1.5),
        ),
        overlayColor: overlay,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurface,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.surfaceContainerHighest,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.onPrimary
            : scheme.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
      ),
      trackOutlineWidth: WidgetStateProperty.all(1.5),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shadowColor: const Color(0xff8a857d),
      shape: shape(16),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: border(scheme.outline),
      enabledBorder: border(scheme.outline),
      focusedBorder: border(scheme.primary, 2),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: shape(24),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: scheme.onSecondaryContainer,
      selectedTileColor: scheme.secondaryContainer,
      iconColor: scheme.onSurfaceVariant,
      shape: shape(8),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: shape(16),
      textStyle: TextStyle(color: scheme.onSurface),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? states.disabledText
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
        overlayColor: overlay,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.tertiary,
      thumbColor: scheme.tertiary,
      inactiveTrackColor: scheme.outline.withValues(alpha: .5),
      overlayColor: scheme.tertiary.withValues(alpha: .14),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

/// Marca del tema Modern: los paneles Studio cambian radio y sombra con ella.
class ModernMarker extends ThemeExtension<ModernMarker> {
  const ModernMarker();
  @override
  ModernMarker copyWith() => this;
  @override
  ModernMarker lerp(ModernMarker? other, double t) => this;
}

bool isModern(BuildContext context) =>
    Theme.of(context).extension<ModernMarker>() != null;
