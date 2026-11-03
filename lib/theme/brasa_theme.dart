import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';
import 'modern_theme.dart' show coverTint;

/// Paleta Brasa: negro cálido de vinilería, un solo acento ámbar.
abstract final class Brasa {
  static const void_ = Color(0xff0d0907);
  static const obsidian = Color(0xff17110e);
  static const graphite = Color(0xff231b16);
  static const ash = Color(0xff3a2e26);
  static const steel = Color(0xff8a7b6e);
  static const cloud = Color(0xffc8b8aa);
  static const cream = Color(0xfffff4e8);
  static const amber = Color(0xffffb04a);

  /// Acento activo (el de Ajustes, aclarado para fondo oscuro).
  static Color accent = amber;

  /// Única sombra de elevación: solo para tarjetas de contenido.
  static const cardShadow = [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// Banner promocional (DJ, novedades): el único degradado del sistema.
  static const banner = LinearGradient(
    colors: [Color(0xffb3401f), Color(0xffffb04a)],
  );
}

/// Tema «Brasa»: interfaz compacta tipo carriles, botones píldora (9999),
/// tarjetas de 6 px, texto de 11–16 px y títulos de 24. Misma firma que
/// `auroraTheme`; tiñe fondos con el acento de portada (5 %).
ThemeData brasaTheme(Brightness brightness, Color accent) {
  final tone = HSLColor.fromColor(accent);
  Brasa.accent = tone.lightness < .6
      ? tone.withLightness(.62).toColor()
      : accent;
  final dark = brightness == Brightness.dark;
  Color tint(Color c) => coverTint(c, Brasa.accent);
  final canvas = tint(dark ? Brasa.void_ : const Color(0xfffbf5ee));
  final ink = dark ? Brasa.cream : const Color(0xff1c1410);
  final muted = dark ? Brasa.cloud : const Color(0xff6b5b4e);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brasa.accent,
        brightness: brightness,
      ).copyWith(
        primary: ink,
        onPrimary: dark ? Colors.black : Colors.white,
        primaryContainer: dark ? Brasa.graphite : const Color(0xffefe4d7),
        onPrimaryContainer: ink,
        secondary: Brasa.accent,
        onSecondary: Colors.black,
        secondaryContainer: dark ? Brasa.ash : const Color(0xffffe2b8),
        onSecondaryContainer: ink,
        tertiary: Brasa.accent,
        onTertiary: Colors.black,
        error: dark ? const Color(0xffff8a7a) : const Color(0xffb3261e),
        surface: canvas,
        surfaceDim: canvas,
        surfaceBright: dark ? Brasa.ash : Colors.white,
        surfaceContainerLowest: dark ? Colors.black : Colors.white,
        surfaceContainerLow: tint(
          dark ? Brasa.obsidian : const Color(0xfffff9f2),
        ),
        surfaceContainer: tint(dark ? Brasa.obsidian : const Color(0xfff6ede2)),
        surfaceContainerHigh: tint(
          dark ? Brasa.graphite : const Color(0xffefe4d7),
        ),
        surfaceContainerHighest: tint(
          dark ? Brasa.ash : const Color(0xffe6d9ca),
        ),
        onSurface: ink,
        onSurfaceVariant: muted,
        outline: dark ? Brasa.steel : const Color(0xff8a7b6e),
        outlineVariant: dark ? Brasa.ash : const Color(0xffe0d3c4),
      );

  const font = 'Inter';
  TextStyle t(double size, double h, FontWeight w, [Color? c]) => TextStyle(
    fontFamily: font,
    fontSize: size,
    height: h,
    fontWeight: w,
    color: c ?? scheme.onSurface,
  );
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(
        fontFamily: font,
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: t(24, 1.2, FontWeight.w700),
        headlineLarge: t(24, 1.2, FontWeight.w700),
        headlineMedium: t(24, 1.2, FontWeight.w700),
        headlineSmall: t(24, 1.2, FontWeight.w700),
        titleLarge: t(24, 1.2, FontWeight.w700),
        titleMedium: t(16, 1.3, FontWeight.w600),
        titleSmall: t(14, 1.4, FontWeight.w600),
        bodyLarge: t(16, 1.5, FontWeight.w400),
        bodyMedium: t(14, 1.5, FontWeight.w400),
        bodySmall: t(12, 1.33, FontWeight.w400, muted),
        labelLarge: t(14, 1.4, FontWeight.w700),
        labelMedium: t(12, 1.33, FontWeight.w600),
        labelSmall: t(11, 1.33, FontWeight.w400, muted),
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
  const pill = StadiumBorder();
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: c, width: w),
  );

  return ThemeData(
    useMaterial3: true,
    extensions: [states, const BrasaMarker()],
    visualDensity: VisualDensity.compact,
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: const DividerThemeData(color: Colors.transparent, space: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: t(14, 1.2, FontWeight.w700),
        shape: pill,
      ).copyWith(overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: t(14, 1.2, FontWeight.w700),
        shape: pill,
        side: BorderSide(color: scheme.onSurface.withValues(alpha: .35)),
      ).copyWith(overlayColor: overlay),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        textStyle: t(14, 1.2, FontWeight.w700),
        shape: pill,
      ).copyWith(overlayColor: overlay),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    // El tema usa densidad compacta: sin este padding los chips quedan en 32 px
    // y en móvil se exige >= 40.
    chipTheme: const ChipThemeData(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      fillColor: scheme.surfaceContainerHigh,
      border: field(Colors.transparent),
      enabledBorder: field(Colors.transparent),
      focusedBorder: field(scheme.onSurface, 1),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: states.onSelected,
      selectedTileColor: states.selected,
      iconColor: scheme.onSurfaceVariant,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: t(14, 1.4, FontWeight.w400),
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
      trackHeight: 4,
      activeTrackColor: scheme.onSurface,
      thumbColor: scheme.onSurface,
      inactiveTrackColor: scheme.outlineVariant,
      overlayColor: scheme.onSurface.withValues(alpha: .12),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

/// Marca del tema Brasa: la UI cambia composición con `isBrasa(context)`.
class BrasaMarker extends ThemeExtension<BrasaMarker> {
  const BrasaMarker();
  @override
  BrasaMarker copyWith() => this;
  @override
  BrasaMarker lerp(BrasaMarker? other, double t) => this;
}

bool isBrasa(BuildContext context) =>
    Theme.of(context).extension<BrasaMarker>() != null;
