// CONGELADO: solo para el modo letra; no editar al rediseñar.
//
// Copia literal (sin cambios) de `slushTheme (lib/theme/slush_theme.dart)` tal como era antes del rediseño de
// temas. El shell envuelve `ArtistModePage` (sección 6) con este `ThemeData`
// para que el modo letra herede siempre el mismo textTheme, fontFamily y temas
// de IconButton/Slider/Tooltip, pase lo que pase con el tema vivo.
//
// Sigue dependiendo de los tokens públicos compartidos (Slush, SlushPalette, SlushRadius, SlushMarker, AuroraStates):
// no cambies sus valores; si hay que hacerlo, duplica aquí el valor antiguo.

import 'package:flutter/material.dart';

import '../../ui/aurora_states.dart';
import '../modern_theme.dart' show ModernMarker;
import '../slush_theme.dart';

/// Tema «Slush»: claro u oscuro según [brightness]; fondo plano teñido por la
/// portada, contornos de 2 px, titulares Bagel Fat One, píldoras y tarjetas
/// de papel. Misma firma que `auroraTheme`. Lleva también [ModernMarker] para
/// reutilizar las composiciones de Modern (tarjetas, paneles, barras).
ThemeData legacySlushTheme(
  Brightness brightness,
  Color accent, {
  bool onVivid = false,
}) {
  final dark = brightness == Brightness.dark;
  final base = dark ? SlushPalette.dark : SlushPalette.light;
  // Sobre colores vivos no hay gris: secundario y terciario = tinta plena.
  final p = onVivid ? base.copyWith(ink2: Slush.ink, ink3: Slush.ink) : base;
  final ink = p.ink;
  final paper = p.paper;
  final bg = Slush.background(accent, dark: dark);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Slush.blue,
        brightness: brightness,
      ).copyWith(
        primary: ink,
        onPrimary: paper,
        primaryContainer: ink,
        onPrimaryContainer: paper,
        secondary: Slush.mint,
        onSecondary: Slush.ink,
        secondaryContainer: Slush.mint,
        onSecondaryContainer: Slush.ink,
        tertiary: Slush.orange,
        onTertiary: Slush.ink,
        error: p.error,
        onError: dark ? Slush.ink : Colors.white,
        surface: bg,
        surfaceDim: bg,
        surfaceBright: p.raised,
        surfaceContainerLowest: paper,
        surfaceContainerLow: paper,
        surfaceContainer: paper,
        surfaceContainerHigh: dark ? p.raised : Slush.lilac,
        surfaceContainerHighest: dark ? const Color(0xff3a3945) : Slush.yellow,
        onSurface: ink,
        onSurfaceVariant: p.ink2,
        outline: p.line,
        outlineVariant: p.lineSoft,
      );

  const font = 'Inter';
  const display = 'Bagel Fat One';
  TextStyle head(double size, double h) => TextStyle(
    fontFamily: display,
    fontSize: size,
    height: h,
    letterSpacing: -size * .01,
    color: ink,
  );
  TextStyle inter(
    double size,
    FontWeight w,
    double h, {
    double tracking = 0,
    Color? color,
  }) => TextStyle(
    fontFamily: font,
    fontSize: size,
    fontWeight: w,
    height: h,
    letterSpacing: size * tracking,
    color: color ?? ink,
  );
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(fontFamily: font, bodyColor: ink, displayColor: ink)
      .copyWith(
        displayLarge: head(72, 1),
        headlineLarge: head(44, 1.05),
        headlineMedium: head(32, 1.1),
        headlineSmall: head(26, 1.15),
        titleLarge: head(22, 1.2),
        titleMedium: inter(16, FontWeight.w800, 1.25),
        titleSmall: inter(14, FontWeight.w800, 1.25),
        bodyLarge: inter(15, FontWeight.w500, 1.55),
        bodyMedium: inter(14, FontWeight.w500, 1.45),
        bodySmall: inter(12, FontWeight.w500, 1.4, color: p.ink2),
        labelLarge: inter(14, FontWeight.w800, 1.2, tracking: .002),
        labelMedium: inter(12, FontWeight.w800, 1.2, tracking: .002),
        labelSmall: inter(
          11,
          FontWeight.w700,
          1.2,
          tracking: .02,
          color: p.ink2,
        ),
      );

  final states = AuroraStates.from(scheme);
  final pill = StadiumBorder(side: p.border);
  RoundedRectangleBorder card(double r, {bool soft = true}) =>
      RoundedRectangleBorder(
        side: soft ? p.borderSoft : p.border,
        borderRadius: BorderRadius.circular(r),
      );
  OutlineInputBorder field(BorderSide side) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(SlushRadius.r16),
    borderSide: side,
  );
  final heavy = inter(14, FontWeight.w800, 1.2, tracking: .002);
  // Hover (solo puntero fino) y pulsado: capas propias de cada modo.
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? p.pressed
        : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
        ? p.hover
        : null,
  );
  // Reposo: contorno de control; foco: anillo de 3 px (nunca solo color de
  // relleno); deshabilitado: borde apagado.
  final ringSide = WidgetStateProperty.resolveWith<BorderSide>(
    (s) => s.contains(WidgetState.disabled)
        ? BorderSide(color: p.disabledBorder, width: SlushStroke.base)
        : s.contains(WidgetState.focused)
        ? p.focusRing
        : p.border,
  );
  final iconRing = WidgetStateProperty.resolveWith<BorderSide?>(
    (s) => s.contains(WidgetState.focused) ? p.focusRing : null,
  );
  final hoverFill = p.hoverFill, pressedFill = p.pressedFill;
  Color chipFill(Set<WidgetState> s) => s.contains(WidgetState.disabled)
      ? p.disabledFill
      : s.contains(WidgetState.selected)
      ? Slush.mint
      : s.contains(WidgetState.pressed)
      ? pressedFill
      : s.contains(WidgetState.hovered)
      ? hoverFill
      : paper;
  // Solo el relleno seleccionado (mint) lleva tinta fija; el resto la del modo.
  Color onFill(Set<WidgetState> s) => s.contains(WidgetState.disabled)
      ? p.disabledText
      : s.contains(WidgetState.selected)
      ? Slush.ink
      : ink;
  final focusFill = p.focus.withValues(alpha: .3);
  final sheetShape = RoundedRectangleBorder(
    side: p.borderSoft,
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(SlushRadius.r32),
    ),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [states, const ModernMarker(), const SlushMarker(), p],
    // Objetivos táctiles >= 44 en todas las plataformas (el valor adaptativo
    // compacta en escritorio).
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        for (final t in TargetPlatform.values)
          t: const SlushPageTransitionsBuilder(),
      },
    ),
    hoverColor: p.hover,
    focusColor: focusFill,
    highlightColor: p.pressed,
    splashColor: p.pressed,
    disabledColor: p.disabledText,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: textTheme,
    scaffoldBackgroundColor: bg,
    dividerTheme: DividerThemeData(
      color: p.divider,
      thickness: SlushStroke.divider,
      space: SlushStroke.divider,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, SlushControl.touch),
        backgroundColor: Slush.mint,
        foregroundColor: Slush.ink,
        disabledBackgroundColor: p.disabledFill,
        disabledForegroundColor: p.disabledText,
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, SlushControl.touch),
        backgroundColor: paper,
        foregroundColor: ink,
        disabledBackgroundColor: p.disabledFill,
        disabledForegroundColor: p.disabledText,
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(0, SlushControl.touch)),
        side: ringSide,
        foregroundColor: WidgetStateProperty.resolveWith(onFill),
        iconColor: WidgetStateProperty.resolveWith(onFill),
        textStyle: WidgetStateProperty.all(heavy),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        backgroundColor: WidgetStateProperty.resolveWith(chipFill),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style:
          TextButton.styleFrom(
            minimumSize: const Size(0, SlushControl.touch),
            foregroundColor: ink,
            disabledForegroundColor: p.disabledText,
            textStyle: heavy,
            // Sin contorno propio: dentro de listas el borde se recortaba.
            shape: const StadiumBorder(),
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.focused) ? p.focusRing : null,
            ),
            overlayColor: overlay,
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: iconRing, overlayColor: overlay),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: paper,
      shape: card(SlushRadius.r24),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: paper,
      selectedColor: Slush.mint,
      elevation: 0,
      pressElevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      iconTheme: const IconThemeData(size: 18),
      color: WidgetStateProperty.resolveWith(chipFill),
      disabledColor: p.disabledFill,
      // RawChip solo resuelve el color: el estilo debe llevar WidgetStateColor.
      labelStyle: inter(
        12,
        FontWeight.w800,
        1.2,
        tracking: .002,
      ).copyWith(color: WidgetStateColor.resolveWith(onFill)),
      secondaryLabelStyle: inter(
        12,
        FontWeight.w800,
        1.2,
        tracking: .002,
        color: Slush.ink,
      ),
      checkmarkColor: Slush.ink,
      shape: const StadiumBorder(),
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? BorderSide(color: p.disabledBorder, width: SlushStroke.base)
            : s.contains(WidgetState.focused)
            ? p.focusRing
            : p.border,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.inset,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: TextStyle(color: p.ink3),
      labelStyle: TextStyle(color: p.ink2, fontWeight: FontWeight.w700),
      floatingLabelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
      helperStyle: TextStyle(color: p.ink2),
      counterStyle: TextStyle(color: p.ink3),
      errorStyle: TextStyle(color: p.error, fontWeight: FontWeight.w700),
      prefixIconColor: p.ink2,
      suffixIconColor: p.ink2,
      // Reposo: contorno de contenedor; foco: anillo 3 px; error: 2 px error.
      border: field(p.borderSoft),
      enabledBorder: field(p.borderSoft),
      focusedBorder: field(p.focusRing),
      disabledBorder: field(
        BorderSide(color: p.disabledBorder, width: SlushStroke.base),
      ),
      errorBorder: field(BorderSide(color: p.error, width: SlushStroke.base)),
      focusedErrorBorder: field(
        BorderSide(color: p.error, width: SlushStroke.strong),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: card(SlushRadius.r32, soft: dark),
      constraints: const BoxConstraints(minWidth: 280, maxWidth: 560),
      titleTextStyle: head(26, 1.15),
      contentTextStyle: inter(14, FontWeight.w500, 1.45, color: p.ink2),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.raised,
      modalBackgroundColor: p.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: sheetShape,
      clipBehavior: Clip.antiAlias,
      dragHandleColor: p.lineSoft,
      dragHandleSize: const Size(40, 4),
      constraints: const BoxConstraints(maxWidth: 640),
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: Slush.ink,
      selectedTileColor: Slush.mint,
      textColor: ink,
      iconColor: ink,
      shape: card(SlushRadius.r16, soft: false),
      minTileHeight: 48,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: card(SlushRadius.r16),
      textStyle: TextStyle(
        fontFamily: font,
        color: ink,
        fontWeight: FontWeight.w700,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? p.raised : Slush.ink,
      contentTextStyle: inter(
        14,
        FontWeight.w600,
        1.4,
        color: dark ? ink : SlushPalette.dark.ink,
      ),
      actionTextColor: Slush.mint,
      disabledActionTextColor: dark ? p.disabledText : p.disabledBorder,
      closeIconColor: dark ? ink : SlushPalette.dark.ink,
      shape: card(SlushRadius.r16, soft: dark),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      margin: const EdgeInsets.all(8),
      textStyle: inter(
        12,
        FontWeight.w700,
        1.3,
        color: dark ? ink : SlushPalette.dark.ink,
      ),
      decoration: BoxDecoration(
        color: dark ? p.raised : Slush.ink,
        borderRadius: BorderRadius.circular(SlushRadius.r8),
        border: dark ? Border.fromBorderSide(p.borderSoft) : null,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: ink,
      unselectedLabelColor: p.ink2,
      labelStyle: inter(12, FontWeight.w800, 1.2, tracking: .002),
      unselectedLabelStyle: inter(12, FontWeight.w800, 1.2, tracking: .002),
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(
          color: p.violetAccent,
          width: SlushStroke.strong,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
      ),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: p.divider,
      dividerHeight: SlushStroke.divider,
      overlayColor: overlay,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? paper : Slush.ink,
      indicatorColor: Slush.yellow,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Slush.ink
              : dark
              ? ink
              : SlushPalette.dark.ink,
        ),
      ),
      labelTextStyle: WidgetStateProperty.all(
        inter(
          12,
          FontWeight.w800,
          1.2,
          color: dark ? ink : SlushPalette.dark.ink,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? p.disabledText : Slush.ink,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? p.disabledFill
            : s.contains(WidgetState.selected)
            ? Slush.mint
            : Slush.lilac,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? p.disabledBorder
            : s.contains(WidgetState.focused)
            ? p.focus
            : p.line,
      ),
      trackOutlineWidth: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.focused)
            ? SlushStroke.strong
            : SlushStroke.base,
      ),
      overlayColor: overlay,
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: ink,
      thumbColor: p.violetAccent,
      inactiveTrackColor: dark ? p.lineSoft : const Color(0xff5c5c5c),
      disabledActiveTrackColor: p.disabledText,
      disabledInactiveTrackColor: p.disabledBorder,
      disabledThumbColor: p.disabledText,
      overlayColor: p.violetAccent.withValues(alpha: .2),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: p.inset,
    ),
  );
}
