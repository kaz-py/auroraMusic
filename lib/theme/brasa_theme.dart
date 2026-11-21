import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';

/// Paleta Brasa («Salón con estufa»): superficies ahumadas, tipografía serif
/// de revista y una sola brasa que marca lo vivo (activo, suena, progreso).
abstract final class Brasa {
  /// Sidebar / base profunda.
  static const void_ = Color(0xff0f0a08);

  /// Lienzo.
  static const obsidian = Color(0xff17110d);

  /// Superficie 1 (tarjetas, ítem activo).
  static const graphite = Color(0xff211914);

  /// Superficie 2 (chips, hover).
  static const ash = Color(0xff2c2219);

  /// Superficie 3 (pista de seek, pestaña activa).
  static const surface3 = Color(0xff382c20);

  /// Barra de reproducción flotante.
  static const bar = Color(0xff251b15);

  /// Texto terciario / metadatos (5,3:1 sobre el lienzo).
  static const steel = Color(0xff968675);

  /// Texto secundario.
  static const cloud = Color(0xffbba997);

  /// Texto principal.
  static const cream = Color(0xfff2e6d8);

  /// Ámbar: datos técnicos (FLAC, DAC), enlaces.
  static const amber = Color(0xffe8a24a);

  /// La brasa: acento único (play, activo, progreso).
  static const ember = Color(0xffff7a3d);

  /// Texto sobre brasa (7,4:1).
  static const onEmber = Color(0xff1a0c05);

  /// Extremos del filamento: `#B3401F → #FF7A3D → #E8A24A`.
  static const filament = LinearGradient(
    colors: [Color(0xffb3401f), ember, amber],
  );

  /// Acento activo: siempre la brasa (el tema ya no se tiñe con la portada).
  static const accent = ember;

  /// Sombra de elevación (tarjetas de contenido, filas con portada).
  static const cardShadow = [
    BoxShadow(color: Color(0x80000000), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// Sombra de lo flotante (barra, mini reproductor, portada grande).
  static const floatShadow = [
    BoxShadow(color: Color(0xb3000000), offset: Offset(0, 16), blurRadius: 40),
  ];

  /// Banner promocional (DJ, novedades).
  static const banner = LinearGradient(
    colors: [Color(0xffb3401f), Color(0xffe8a24a)],
  );

  /// Titulares / letras: Fraunces 600, tracking −0,02 em.
  static TextStyle serif(
    double size, {
    Color color = cream,
    double height = 1.15,
    double wght = 600,
    double tracking = -.02,
    FontStyle? style,
  }) => TextStyle(
    fontFamily: 'Fraunces',
    fontSize: size,
    height: height,
    fontWeight: FontWeight.w600,
    fontStyle: style,
    letterSpacing: size * tracking,
    color: color,
    fontVariations: [
      FontVariation('wght', wght),
      const FontVariation('opsz', 72),
    ],
  );

  /// Metadatos, tiempos, etiquetas de sección: DM Mono en versalitas.
  static TextStyle mono(
    double size, {
    Color color = steel,
    double tracking = .14,
    FontWeight weight = FontWeight.w400,
    double height = 1.3,
  }) => TextStyle(
    fontFamily: 'DM Mono',
    fontSize: size,
    height: height,
    fontWeight: weight,
    letterSpacing: size * tracking,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// UI / cuerpo: DM Sans.
  static TextStyle sans(
    double size, {
    Color color = cream,
    FontWeight weight = FontWeight.w400,
    double height = 1.4,
  }) => TextStyle(
    fontFamily: 'DM Sans',
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: color,
    fontVariations: [FontVariation('wght', weight.value.toDouble())],
  );
}

/// Tema «Brasa»: solo oscuro (humo cálido), un acento (la brasa), titulares
/// en Fraunces, cuerpo en DM Sans y metadatos en DM Mono. Misma firma que
/// `auroraTheme`; el brillo y el acento de portada se ignoran a propósito
/// (la identidad es una sola brasa), pero se mantienen por compatibilidad.
ThemeData brasaTheme(Brightness brightness, Color accent) {
  const ink = Brasa.cream;
  const muted = Brasa.cloud;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Brasa.ember,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Brasa.ember,
        onPrimary: Brasa.onEmber,
        primaryContainer: Brasa.graphite,
        onPrimaryContainer: ink,
        secondary: Brasa.ember,
        onSecondary: Brasa.onEmber,
        secondaryContainer: Brasa.ash,
        onSecondaryContainer: ink,
        tertiary: Brasa.amber,
        onTertiary: Brasa.onEmber,
        error: const Color(0xffff8a7a),
        surface: Brasa.obsidian,
        surfaceDim: Brasa.void_,
        surfaceBright: Brasa.surface3,
        surfaceContainerLowest: Brasa.void_,
        surfaceContainerLow: Brasa.graphite,
        surfaceContainer: Brasa.graphite,
        surfaceContainerHigh: Brasa.ash,
        surfaceContainerHighest: Brasa.surface3,
        onSurface: ink,
        onSurfaceVariant: muted,
        outline: Brasa.steel,
        outlineVariant: Brasa.surface3,
      );

  TextStyle t(double size, double h, FontWeight w, [Color? c]) =>
      Brasa.sans(size, color: c ?? ink, weight: w, height: h);
  TextStyle head(double size) => Brasa.serif(size, height: 1.2);
  final textTheme = ThemeData.dark().textTheme
      .apply(
        fontFamily: 'DM Sans',
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      )
      .copyWith(
        displayLarge: head(40),
        headlineLarge: head(32),
        headlineMedium: head(28),
        headlineSmall: head(24),
        titleLarge: head(22),
        titleMedium: t(16, 1.3, FontWeight.w600),
        titleSmall: t(14, 1.4, FontWeight.w500),
        bodyLarge: t(16, 1.5, FontWeight.w400),
        bodyMedium: t(14, 1.5, FontWeight.w400),
        bodySmall: t(12, 1.33, FontWeight.w400, muted),
        labelLarge: t(14, 1.4, FontWeight.w700),
        labelMedium: t(12, 1.33, FontWeight.w500),
        labelSmall: Brasa.mono(11, color: muted),
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
  const squircle = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(14)),
  );
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
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
    fontFamily: 'DM Sans',
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: const DividerThemeData(color: Colors.transparent, space: 0),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        textStyle: t(14, 1.2, FontWeight.w700),
        shape: squircle,
      ).copyWith(overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: t(14, 1.2, FontWeight.w700),
        shape: pill,
        side: BorderSide(color: scheme.onSurface.withValues(alpha: .35)),
      ).copyWith(overlayColor: overlay),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        visualDensity: VisualDensity.standard,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    // El tema usa densidad compacta: sin este padding los chips quedan en 32 px
    // y en móvil se exige >= 40.
    chipTheme: const ChipThemeData(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      isDense: true,
      fillColor: scheme.surfaceContainerHigh,
      border: field(Colors.transparent),
      enabledBorder: field(Colors.transparent),
      focusedBorder: field(Brasa.ember, 1),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
      activeTrackColor: Brasa.ember,
      thumbColor: Brasa.cream,
      inactiveTrackColor: Brasa.surface3,
      overlayColor: Brasa.ember.withValues(alpha: .16),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Brasa.graphite,
      contentTextStyle: const TextStyle(
        color: Brasa.cream,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: Brasa.cream,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.white.withValues(alpha: .08)),
      ),
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
