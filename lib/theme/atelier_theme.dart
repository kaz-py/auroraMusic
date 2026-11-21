/// Atelier «Papel y tinta»: papel cálido, tinta casi negra, un acento terracota
/// y filetes finos en vez de cajas. Es el tema sin marca (`ThemeExtension`):
/// `themeKindOf` lo resuelve por descarte. Ver docs/temas.md.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';

/// Acento por omisión de la app; con él se usa la terracota exacta del diseño.
const _kDefaultAccent = 0xffe86927;

/// Paleta y utilidades tipográficas del Atelier. Las pantallas del tema leen
/// de aquí; el resto de la app sigue usando el `ColorScheme`.
@immutable
class AtelierTokens extends ThemeExtension<AtelierTokens> {
  const AtelierTokens({
    required this.dark,
    required this.paper,
    required this.panel,
    required this.panel2,
    required this.rule,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.accent,
    required this.accentText,
    required this.onAccent,
    required this.ok,
  });

  final bool dark;

  /// Fondo, panel (sidebar, aside, mini), panel hundido y filete decorativo.
  final Color paper, panel, panel2, rule;

  /// Tinta principal, secundaria y apagada (metadatos).
  final Color ink, ink2, muted;

  /// Acento para botones/progreso (≥ 3:1), el mismo para texto (≥ 4.5:1) y el
  /// color de lo que va encima del botón.
  final Color accent, accentText, onAccent;
  final Color ok;

  static const light = AtelierTokens(
    dark: false,
    paper: Color(0xfff4eee3),
    panel: Color(0xffebe3d3),
    panel2: Color(0xffe2d8c4),
    rule: Color(0xffcfc3ac),
    ink: Color(0xff1e1a16),
    ink2: Color(0xff4d453b),
    muted: Color(0xff625848),
    accent: Color(0xffb4532a),
    accentText: Color(0xff9c4222),
    onAccent: Color(0xfffbf6ec),
    ok: Color(0xff3f6b4f),
  );

  static const night = AtelierTokens(
    dark: true,
    paper: Color(0xff17130f),
    panel: Color(0xff1f1a15),
    panel2: Color(0xff28221b),
    rule: Color(0xff3d352b),
    ink: Color(0xffede4d3),
    ink2: Color(0xffcfc4b0),
    muted: Color(0xffa99d89),
    accent: Color(0xffe07a4a),
    accentText: Color(0xffe8885a),
    onAccent: Color(0xff17130f),
    ok: Color(0xff7fb08f),
  );

  static AtelierTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AtelierTokens>() ??
        (theme.brightness == Brightness.dark ? night : light);
  }

  // ---- Tipografía ----

  /// Newsreader (títulos, pistas, letras, saludo).
  TextStyle serif(
    double size, {
    bool italic = false,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.15,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: 'Newsreader',
    fontSize: size,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: weight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? ink,
  );

  /// IBM Plex Mono en versalitas: metadatos, atajos, números de sección.
  TextStyle mono({
    double size = 11,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) {
    // Móvil: mono mínimo 12 px (DISENO.md).
    if (defaultTargetPlatform == TargetPlatform.android && size < 12) size = 12;
    return TextStyle(
      fontFamily: 'IBM Plex Mono',
      fontSize: size,
      fontWeight: weight,
      letterSpacing: size * .09,
      height: 1.3,
      color: color ?? muted,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// Inter (interfaz y cuerpo).
  TextStyle ui(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
    double height = 1.3,
  }) => TextStyle(
    fontFamily: 'Inter',
    fontSize: size,
    fontWeight: weight,
    height: height,
    color: color ?? ink,
  );

  @override
  AtelierTokens copyWith() => this;

  @override
  AtelierTokens lerp(AtelierTokens? other, double t) =>
      t < .5 || other == null ? this : other;
}

double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

/// Oscurece (claro) o aclara (noche) [c] hasta que [ok] se cumpla.
Color _fit(Color c, bool dark, bool Function(Color) ok) {
  var out = c;
  for (var i = 0; i < 100 && !ok(out); i++) {
    final hsl = HSLColor.fromColor(out);
    out = hsl
        .withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0.0, 1.0))
        .toColor();
  }
  return out;
}

/// Tokens del Atelier para [brightness] y [accent]. El acento por omisión da
/// la terracota del diseño; otro acento (portada) conserva su tono ajustado
/// para contraste.
AtelierTokens atelierTokens(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  final base = dark ? AtelierTokens.night : AtelierTokens.light;
  if (accent.toARGB32() == _kDefaultAccent) return base;
  final onFill = base.onAccent;
  final fill = _fit(
    accent,
    dark,
    (c) =>
        _contrast(c, onFill) >= 4.5 &&
        _contrast(c, base.paper) >= 3 &&
        (dark || _contrast(c, base.panel2) >= 3),
  );
  final text = _fit(
    fill,
    dark,
    (c) => _contrast(c, base.paper) >= 4.7 && _contrast(c, base.panel) >= 4.7,
  );
  return AtelierTokens(
    dark: dark,
    paper: base.paper,
    panel: base.panel,
    panel2: base.panel2,
    rule: base.rule,
    ink: base.ink,
    ink2: base.ink2,
    muted: base.muted,
    accent: fill,
    accentText: text,
    onAccent: onFill,
    ok: base.ok,
  );
}

/// Rombo de 8 px del seek (tirador del Atelier).
class AtelierDiamondThumb extends SliderComponentShape {
  const AtelierDiamondThumb([this.size = 8]);
  final double size;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size.square(size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final r = size / 2 * (1 + .25 * activationAnimation.value);
    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r, center.dy)
      ..close();
    context.canvas.drawPath(
      path,
      Paint()..color = sliderTheme.thumbColor ?? Colors.black,
    );
  }
}

ThemeData auroraTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  final t = atelierTokens(brightness, accent);
  var scheme = ColorScheme.fromSeed(seedColor: t.accent, brightness: brightness)
      .copyWith(
        primary: t.accentText,
        onPrimary: t.onAccent,
        primaryContainer: t.accent,
        onPrimaryContainer: t.onAccent,
        secondary: t.ink2,
        onSecondary: t.paper,
        secondaryContainer: t.panel2,
        onSecondaryContainer: t.ink,
        tertiary: t.ink2,
        onTertiary: t.paper,
        tertiaryContainer: t.panel2,
        onTertiaryContainer: t.ink,
        surface: t.paper,
        surfaceDim: t.panel2,
        surfaceBright: dark ? t.panel2 : const Color(0xfffbf6ec),
        surfaceContainerLowest: dark
            ? const Color(0xff120f0b)
            : const Color(0xfffbf6ec),
        surfaceContainerLow: t.panel,
        surfaceContainer: t.panel2,
        surfaceContainerHigh: dark
            ? const Color(0xff302922)
            : const Color(0xffe1d7c3),
        surfaceContainerHighest: dark
            ? const Color(0xff39322a)
            : const Color(0xffd0c4ab),
        onSurface: t.ink,
        onSurfaceVariant: t.ink2,
        outline: t.muted,
        outlineVariant: t.rule,
        inverseSurface: dark ? t.ink : t.ink,
        onInverseSurface: t.paper,
        inversePrimary: dark
            ? const Color(0xffb4532a)
            : const Color(0xffe8885a),
      );
  if (dark) scheme = scheme.copyWith(error: const Color(0xffffb4a8));
  // Velos y barra de selección: la misma receta que el resto de la app, sobre
  // el esquema de Atelier (cumple los umbrales de contrast_test).
  // Con la terracota fija: un acento casi negro dejaría el texto sin contraste.
  final base = AuroraStates.from(
    scheme.copyWith(
      primary: (dark ? AtelierTokens.night : AtelierTokens.light).accentText,
    ),
  );
  final states = AuroraStates(
    hover: base.hover,
    selected: base.selected,
    pressed: base.pressed,
    focusRing: t.accentText,
    selectedBar: base.selectedBar,
    onSelected: t.ink,
    disabledText: Color.lerp(t.paper, t.muted, .85)!,
    tertiaryText: t.muted,
  );
  const bodyFont = 'Inter';
  const headlineFont = 'Newsreader';
  TextStyle head(double size, double h, {double? ls}) => TextStyle(
    fontFamily: headlineFont,
    fontSize: size,
    height: h,
    letterSpacing: ls,
    color: t.ink,
  );
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(fontFamily: bodyFont, bodyColor: t.ink, displayColor: t.ink)
      .copyWith(
        displayLarge: head(56, 1.05, ls: -1.1),
        displayMedium: head(44, 1.08, ls: -.8),
        displaySmall: head(36, 1.12),
        headlineLarge: head(32, 1.15),
        headlineMedium: head(28, 1.18),
        headlineSmall: head(22, 1.2),
        titleLarge: head(22, 1.2),
        labelSmall: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontSize: 11,
          letterSpacing: 1,
          color: t.muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
  const radius = BorderRadius.all(Radius.circular(3));
  final shape = const RoundedRectangleBorder(borderRadius: radius);
  final underline = UnderlineInputBorder(borderSide: BorderSide(color: t.ink));
  return ThemeData(
    useMaterial3: true,
    extensions: [t, states],
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    splashFactory: NoSplash.splashFactory,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: bodyFont,
    textTheme: textTheme,
    scaffoldBackgroundColor: t.paper,
    canvasColor: t.paper,
    dividerTheme: DividerThemeData(color: t.rule, thickness: 1, space: 1),
    visualDensity: VisualDensity.standard,
    chipTheme: ChipThemeData(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: t.rule),
      ),
      backgroundColor: Colors.transparent,
      selectedColor: t.ink,
      labelStyle: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 12,
        letterSpacing: 1,
        color: t.ink,
      ),
      secondaryLabelStyle: TextStyle(
        fontFamily: 'IBM Plex Mono',
        fontSize: 12,
        letterSpacing: 1,
        color: t.paper,
      ),
      checkmarkColor: t.paper,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        shape: shape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ).copyWith(overlayColor: _overlay(states)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        elevation: 0,
        shape: shape,
      ).copyWith(overlayColor: _overlay(states)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: t.ink,
            shape: shape,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ).copyWith(
            overlayColor: _overlay(states),
            side: WidgetStateProperty.resolveWith(
              (s) => BorderSide(
                color: s.contains(WidgetState.disabled)
                    ? states.disabledText
                    : s.contains(WidgetState.focused)
                    ? states.focusRing
                    : t.ink,
                width: s.contains(WidgetState.focused) ? 2 : 1,
              ),
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: t.accentText,
        shape: shape,
      ).copyWith(overlayColor: _overlay(states)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: t.ink,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(2),
        side: BorderSide(color: t.rule),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      border: underline,
      enabledBorder: underline,
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: t.accentText, width: 2),
      ),
      errorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      hintStyle: TextStyle(color: t.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: t.rule),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: t.panel,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: states.onSelected,
      selectedTileColor: states.selected,
      iconColor: t.ink2,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: t.ink),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: t.rule),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? states.disabledText
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.focused)
              ? t.ink
              : t.ink2,
        ),
        overlayColor: _overlay(states),
      ),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: t.accent,
      thumbColor: t.accent,
      inactiveTrackColor: t.rule,
      overlayColor: t.accent.withValues(alpha: .14),
      thumbShape: const AtelierDiamondThumb(),
      trackShape: const RectangularSliderTrackShape(),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: t.accent,
      linearTrackColor: t.rule,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: t.ink,
      unselectedLabelColor: t.ink2,
      indicatorColor: t.accent,
      dividerColor: t.rule,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.onAccent : t.ink2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.panel2,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? t.accent : t.muted,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? t.panel2 : t.ink,
      contentTextStyle: TextStyle(
        color: dark ? t.ink : t.paper,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      actionTextColor: dark ? t.accentText : scheme.inversePrimary,
      closeIconColor: dark ? t.ink : t.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

WidgetStateProperty<Color?> _overlay(AuroraStates st) =>
    WidgetStateProperty.resolveWith(
      (s) => s.contains(WidgetState.pressed)
          ? st.pressed
          : s.contains(WidgetState.focused)
          ? st.focusRing.withValues(alpha: .28)
          : s.contains(WidgetState.hovered)
          ? st.hover
          : null,
    );
