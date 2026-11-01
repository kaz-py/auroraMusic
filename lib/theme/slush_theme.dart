import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';
import 'modern_theme.dart' show ModernMarker;

/// Paleta Slush: neo-brutalismo de pegatinas, tinta negra y colores planos.
/// Los colores vivos son iguales en claro y oscuro; el texto sobre ellos es
/// siempre [ink]. Lo neutro (papel, tinta, bordes) vive en [SlushPalette].
abstract final class Slush {
  /// Negro para texto e iconos sobre colores vivos (en ambos modos).
  static const ink = Color(0xff0a0a0a);
  static const mint = Color(0xff5fe0a0);
  static const yellow = Color(0xffffd62e);
  static const lilac = Color(0xffe3cdfb);
  static const orange = Color(0xffff4d0a);
  static const blue = Color(0xff3b8bf2);
  static const violet = Color(0xff5b3fe0);

  /// Fondo plano de pantalla teñido por la portada. Claro: pastel (texto
  /// negro legible); oscuro: tono muy profundo (texto crema legible).
  static Color background(Color accent, {bool dark = false}) {
    final h = HSLColor.fromColor(accent);
    return dark
        ? HSLColor.fromAHSL(
            1,
            h.hue,
            h.saturation.clamp(.30, .60),
            .12,
          ).toColor()
        : HSLColor.fromAHSL(
            1,
            h.hue,
            h.saturation.clamp(.45, .85),
            .86,
          ).toColor();
  }
}

/// Colores neutros de Slush que cambian entre claro y oscuro.
class SlushPalette extends ThemeExtension<SlushPalette> {
  const SlushPalette({
    required this.ink,
    required this.paper,
    required this.line,
    required this.shadow,
    required this.screen,
  });

  /// Texto e iconos sobre [paper] o el fondo; también relleno «tinta».
  final Color ink;

  /// Relleno de tarjetas, píldoras, barras y botones.
  final Color paper;

  /// Contorno de las piezas.
  final Color line;

  /// Sombra dura de pegatina.
  final Color shadow;

  /// Pantalla neutra (fondo gris de reproductores y paneles).
  final Color screen;

  static const light = SlushPalette(
    ink: Color(0xff0a0a0a),
    paper: Colors.white,
    line: Color(0xff0a0a0a),
    shadow: Color(0xff0a0a0a),
    screen: Color(0xffd9dbe0),
  );

  static const dark = SlushPalette(
    ink: Color(0xfff4efe6),
    paper: Color(0xff17171b),
    line: Color(0xfff4efe6),
    shadow: Color(0xfff4efe6),
    screen: Color(0xff1e2026),
  );

  /// Borde grueso de todas las piezas.
  BorderSide get border => BorderSide(color: line, width: 2);

  /// Sombra dura sin desenfoque, típica de pegatina.
  List<BoxShadow> get shadows => [
    BoxShadow(color: shadow, offset: const Offset(3, 4)),
  ];

  @override
  SlushPalette copyWith({
    Color? ink,
    Color? paper,
    Color? line,
    Color? shadow,
    Color? screen,
  }) => SlushPalette(
    ink: ink ?? this.ink,
    paper: paper ?? this.paper,
    line: line ?? this.line,
    shadow: shadow ?? this.shadow,
    screen: screen ?? this.screen,
  );

  @override
  SlushPalette lerp(SlushPalette? other, double t) {
    if (other == null) return this;
    return SlushPalette(
      ink: Color.lerp(ink, other.ink, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      line: Color.lerp(line, other.line, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      screen: Color.lerp(screen, other.screen, t)!,
    );
  }
}

extension SlushContext on BuildContext {
  SlushPalette get slush =>
      Theme.of(this).extension<SlushPalette>() ?? SlushPalette.light;
}

/// Tema «Slush»: claro u oscuro según [brightness]; fondo plano teñido por la
/// portada, contornos de 2 px, titulares Bagel Fat One, píldoras y tarjetas
/// de papel. Misma firma que `auroraTheme`. Lleva también [ModernMarker] para
/// reutilizar las composiciones de Modern (tarjetas, paneles, barras).
ThemeData slushTheme(Brightness brightness, Color accent) {
  final dark = brightness == Brightness.dark;
  final p = dark ? SlushPalette.dark : SlushPalette.light;
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
        error: dark ? const Color(0xffff8a80) : const Color(0xffc62828),
        surface: bg,
        surfaceDim: bg,
        surfaceBright: paper,
        surfaceContainerLowest: paper,
        surfaceContainerLow: paper,
        surfaceContainer: paper,
        surfaceContainerHigh: dark ? const Color(0xff2a2140) : Slush.lilac,
        surfaceContainerHighest: dark ? const Color(0xff3a3212) : Slush.yellow,
        onSurface: ink,
        onSurfaceVariant: dark
            ? const Color(0xffc9c3b8)
            : const Color(0xff2b2b2b),
        outline: p.line,
        outlineVariant: p.line,
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
  final textTheme = (dark ? ThemeData.dark() : ThemeData.light()).textTheme
      .apply(fontFamily: font, bodyColor: ink, displayColor: ink)
      .copyWith(
        displayLarge: head(72, 1),
        headlineLarge: head(44, 1.05),
        headlineMedium: head(32, 1.1),
        headlineSmall: head(26, 1.15),
        titleLarge: head(22, 1.2),
        titleMedium: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
        labelLarge: TextStyle(
          fontFamily: font,
          fontWeight: FontWeight.w800,
          color: ink,
        ),
      );

  final states = AuroraStates.from(scheme);
  final pill = StadiumBorder(side: p.border);
  RoundedRectangleBorder card(double r) => RoundedRectangleBorder(
    side: p.border,
    borderRadius: BorderRadius.circular(r),
  );
  OutlineInputBorder field([double w = 2]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: p.line, width: w),
  );
  const heavy = TextStyle(fontFamily: font, fontWeight: FontWeight.w800);
  // Hover amarillo, pulsado lila: se ve sobre papel, menta y el fondo. En
  // oscuro más tenue para que el texto crema siga legible.
  final overlay = WidgetStateProperty.resolveWith<Color?>(
    (s) => s.contains(WidgetState.pressed)
        ? Slush.lilac.withValues(alpha: dark ? .35 : .85)
        : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
        ? Slush.yellow.withValues(alpha: dark ? .22 : .55)
        : null,
  );
  final muted = dark ? const Color(0xff8f8a82) : const Color(0xff6b6b6b);
  final ringSide = WidgetStateProperty.resolveWith<BorderSide>(
    (s) => s.contains(WidgetState.disabled)
        ? BorderSide(color: muted, width: 2)
        : p.border,
  );
  final disabledFill = dark ? const Color(0xff2a2a30) : const Color(0xffe6e6e6);
  // Rellenos vivos llevan texto negro; el papel lleva la tinta del modo.
  bool vivid(Set<WidgetState> s) =>
      s.contains(WidgetState.selected) || s.contains(WidgetState.hovered);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [states, const ModernMarker(), const SlushMarker(), p],
    hoverColor: states.hover,
    focusColor: states.focusRing.withValues(alpha: .22),
    highlightColor: states.pressed,
    splashColor: states.pressed,
    disabledColor: states.disabledText,
    colorScheme: scheme,
    fontFamily: font,
    textTheme: textTheme,
    scaffoldBackgroundColor: bg,
    dividerTheme: DividerThemeData(color: p.line, thickness: 2, space: 2),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: Slush.mint,
        foregroundColor: Slush.ink,
        disabledBackgroundColor: paper,
        disabledForegroundColor: dark
            ? const Color(0xffa8a29a)
            : const Color(0xff595959),
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        backgroundColor: paper,
        foregroundColor: ink,
        textStyle: heavy,
        shape: pill,
      ).copyWith(side: ringSide, overlayColor: overlay),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: ringSide,
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => vivid(s) ? Slush.ink : ink,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => vivid(s) ? Slush.ink : ink,
        ),
        textStyle: WidgetStateProperty.all(heavy),
        overlayColor: overlay,
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Slush.mint
              : s.contains(WidgetState.hovered)
              ? Slush.yellow
              : paper,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: ink,
        textStyle: heavy,
        // Sin contorno propio: dentro de listas el borde se recortaba.
        shape: const StadiumBorder(),
      ).copyWith(overlayColor: overlay),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    cardTheme: CardThemeData(elevation: 0, color: paper, shape: card(24)),
    chipTheme: ChipThemeData(
      backgroundColor: paper,
      selectedColor: Slush.mint,
      elevation: 0,
      pressElevation: 0,
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? disabledFill
            : s.contains(WidgetState.selected)
            ? Slush.mint
            : s.contains(WidgetState.pressed)
            ? Slush.lilac
            : s.contains(WidgetState.hovered)
            ? Slush.yellow
            : paper,
      ),
      disabledColor: disabledFill,
      labelStyle: WidgetStateTextStyle.resolveWith(
        (s) => heavy.copyWith(
          color: vivid(s) || s.contains(WidgetState.pressed) ? Slush.ink : ink,
        ),
      ),
      secondaryLabelStyle: heavy.copyWith(color: Slush.ink),
      checkmarkColor: Slush.ink,
      shape: pill,
      side: p.border,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: paper,
      hintStyle: TextStyle(
        color: dark ? const Color(0xffa8a29a) : const Color(0xff4a4a4a),
      ),
      labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
      border: field(),
      enabledBorder: field(),
      focusedBorder: field(4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
      shape: card(28),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: paper,
      surfaceTintColor: Colors.transparent,
    ),
    listTileTheme: ListTileThemeData(
      selectedColor: Slush.ink,
      selectedTileColor: Slush.mint,
      textColor: ink,
      iconColor: ink,
      shape: card(16),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper,
      surfaceTintColor: Colors.transparent,
      shape: card(16),
      textStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: ink),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ink,
      indicatorColor: Slush.yellow,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? Slush.ink : paper,
        ),
      ),
      labelTextStyle: WidgetStateProperty.all(
        heavy.copyWith(fontSize: 12, color: paper),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Slush.ink),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Slush.mint : Slush.lilac,
      ),
      trackOutlineColor: WidgetStateProperty.all(p.line),
      trackOutlineWidth: WidgetStateProperty.all(2),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: ink,
      thumbColor: Slush.violet,
      inactiveTrackColor: dark
          ? const Color(0xff6a6660)
          : const Color(0xff5c5c5c),
      overlayColor: const Color(0x335b3fe0),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: paper,
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 500),
    ),
  );
}

/// Marca del tema Slush: la UI añade bordes/pegatinas con `isSlush(context)`.
class SlushMarker extends ThemeExtension<SlushMarker> {
  const SlushMarker();
  @override
  SlushMarker copyWith() => this;
  @override
  SlushMarker lerp(SlushMarker? other, double t) => this;
}

bool isSlush(BuildContext context) =>
    Theme.of(context).extension<SlushMarker>() != null;

/// Tema claro para el contenido dentro de superficies vivas: tinta sobre color
/// vivo también en modo oscuro.
final slushVividTheme = slushTheme(Brightness.light, Slush.lilac);

/// Envuelve [child] con [slushVividTheme] solo en modo oscuro.
Widget slushOnVivid(BuildContext context, Widget child) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme(data: slushVividTheme, child: child)
    : child;
