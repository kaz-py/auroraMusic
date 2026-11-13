import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';
import 'modern_cristal.dart';

/// Tiñe una superficie con el color de portada (sin cambiar su luminosidad base).
Color coverTint(Color base, Color accent, [double amount = .05]) =>
    Color.lerp(base, accent, amount)!;

/// Tema «Modern · Cristal y aura»: lienzo casi negro, cristal fino, un solo
/// acento azul, menta solo para la señal y coral para «me gusta». Manrope +
/// Geist Mono. Misma firma que `auroraTheme`; [accent] ya no tiñe el tema (el
/// color viene de la portada vía `ModernAura`).
ThemeData modernTheme(Brightness brightness, Color accent) {
  final c = brightness == Brightness.dark
      ? Cristal.darkPalette
      : Cristal.lightPalette;
  final dark = c.dark;
  Color over(Color glass) => Color.alphaBlend(glass, c.canvas);
  final low = over(c.glass);
  final mid = over(c.glass.withValues(alpha: dark ? .09 : .07));
  final high = over(c.glassHover.withValues(alpha: dark ? .13 : .1));
  final highest = over(c.glassHover.withValues(alpha: dark ? .18 : .14));

  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        primaryContainer: over(c.accentSoft),
        onPrimaryContainer: c.text,
        secondary: c.signal,
        onSecondary: dark ? const Color(0xff06130f) : Colors.white,
        secondaryContainer: over(c.signalFill),
        onSecondaryContainer: c.signal,
        tertiary: c.accent,
        onTertiary: c.onAccent,
        error: c.like,
        onError: c.onAccent,
        surface: c.canvas,
        surfaceDim: dark ? const Color(0xff07080c) : const Color(0xffe6e9f2),
        surfaceBright: highest,
        surfaceContainerLowest: dark
            ? const Color(0xff07080c)
            : const Color(0xffffffff),
        surfaceContainerLow: low,
        surfaceContainer: mid,
        surfaceContainerHigh: high,
        surfaceContainerHighest: highest,
        onSurface: c.text,
        onSurfaceVariant: c.text2,
        outline: c.text3,
        outlineVariant: c.border,
      );

  TextStyle ui(double size, int w, {double tracking = 0, double? height}) =>
      Cristal.ui(
        size,
        weight: w,
        color: c.text,
        tracking: tracking,
        height: height,
      );
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(fontFamily: 'Manrope', bodyColor: c.text, displayColor: c.text)
      .copyWith(
        displayLarge: ui(56, 800, tracking: -.03, height: 1.1),
        displayMedium: ui(44, 800, tracking: -.03, height: 1.1),
        displaySmall: ui(34, 800, tracking: -.03, height: 1.15),
        headlineLarge: ui(34, 800, tracking: -.03, height: 1.15),
        headlineMedium: ui(28, 800, tracking: -.03, height: 1.2),
        headlineSmall: ui(22, 800, tracking: -.03, height: 1.25),
        titleLarge: ui(18, 700, tracking: -.02, height: 1.3),
        titleMedium: ui(15, 700, tracking: -.01),
        titleSmall: ui(13.5, 700),
        bodyLarge: ui(15, 500),
        bodyMedium: ui(13.5, 500),
        bodySmall: ui(12, 500),
        labelLarge: ui(13.5, 700),
        labelMedium: Cristal.mono(12, color: c.text2),
        labelSmall: Cristal.mono(10.5, color: c.text3),
      );

  final states = AuroraStates.from(scheme);
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? c.glassHover
        : s.contains(WidgetState.focused)
        ? c.accent.withValues(alpha: .22)
        : s.contains(WidgetState.hovered)
        ? c.glass
        : null,
  );
  RoundedRectangleBorder shape(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  const pill = StadiumBorder();
  OutlineInputBorder border(Color color, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: w),
  );
  final label = Cristal.ui(13.5, weight: 700);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [states, const ModernMarker()],
    hoverColor: c.glass,
    focusColor: c.accent.withValues(alpha: .22),
    highlightColor: c.glass,
    splashColor: c.glassHover,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: 'Manrope',
    textTheme: textTheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        shape: pill,
        textStyle: label,
      ).copyWith(overlayColor: overlay),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 44),
        elevation: 0,
        backgroundColor: c.glassHover,
        foregroundColor: c.text,
        shape: pill,
        textStyle: label,
      ).copyWith(overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            backgroundColor: c.glass,
            foregroundColor: c.text,
            shape: pill,
            textStyle: label,
          ).copyWith(
            overlayColor: overlay,
            side: WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? c.border
                    : s.contains(WidgetState.focused)
                    ? c.accent
                    : c.border,
                width: s.contains(WidgetState.focused) ? 2 : 1,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: c.accent,
        shape: pill,
        textStyle: label,
      ).copyWith(overlayColor: overlay),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.glass,
      selectedColor: c.chip,
      checkmarkColor: c.onChip,
      labelStyle: Cristal.ui(
        13.5,
        weight: 600,
        color: c.text2,
      ).copyWith(color: _selectedAware(c.onChip, c.text2)),
      secondaryLabelStyle: Cristal.ui(13.5, weight: 600, color: c.onChip),
      // Alto >= 40 para el toque en móvil (texto 13,5 * 1,4 + 2 * 11).
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
      side: BorderSide(color: c.border),
      shape: pill,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStateProperty.all(BorderSide(color: c.border)),
        overlayColor: overlay,
        textStyle: WidgetStateProperty.all(label),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onChip : c.text,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.chip : c.glass,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.text2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.glassHover,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.text3,
      ),
      trackOutlineWidth: WidgetStateProperty.all(1),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: ui(18, 800, tracking: -.02),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: low,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.glass,
      hintStyle: Cristal.ui(13.5, weight: 500, color: c.text3),
      border: border(c.border),
      enabledBorder: border(c.border),
      focusedBorder: border(c.accent, 1.5),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: highest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: c.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: over(c.glass.withValues(alpha: dark ? .09 : .07)),
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: highest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: mid,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: c.text,
      selectedTileColor: over(c.accentSoft),
      iconColor: c.text2,
      textColor: c.text,
      shape: shape(16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: highest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
      textStyle: Cristal.ui(13.5, weight: 600, color: c.text),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? states.disabledText
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)
              ? c.text
              : c.text2,
        ),
        overlayColor: overlay,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      thumbColor: c.accent,
      inactiveTrackColor: c.text.withValues(alpha: .24),
      overlayColor: c.accent.withValues(alpha: .14),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.text.withValues(alpha: .12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: highest,
      contentTextStyle: Cristal.ui(14, weight: 600, color: c.text),
      actionTextColor: c.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: highest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      textStyle: Cristal.ui(12, weight: 600, color: c.text),
    ),
  );
}

/// Color de etiqueta que pasa a [selected] cuando el chip está seleccionado.
WidgetStateColor _selectedAware(Color selected, Color normal) =>
    WidgetStateColor.resolveWith(
      (s) => s.contains(WidgetState.selected) ? selected : normal,
    );

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
