import 'package:flutter/material.dart';

import '../ui/aurora_states.dart';
import 'modern_theme.dart' show ModernMarker;
import 'slush_tokens.dart';

export 'slush_tokens.dart';

/// Paleta Slush: neo-brutalismo de pegatinas, tinta negra y colores planos.
/// Los colores vivos son iguales en claro y oscuro; el texto sobre ellos es
/// siempre [ink] (salvo [violet]: blanco). Lo neutro (papel, tinta, bordes)
/// vive en [SlushPalette].
abstract final class Slush {
  /// Negro para texto e iconos sobre colores vivos (en ambos modos).
  static const ink = Color(0xff14101f);
  static const mint = Color(0xff5fe0a0);
  static const yellow = Color(0xffffd62e);
  static const lilac = Color(0xffe3d8ff);
  static const orange = Color(0xffff4d0a);
  static const blue = Color(0xff3b8bf2);
  static const violet = Color(0xff5b3fe0);
  static const pink = Color(0xffff8fc7);

  /// Slush 2.0: lima = «lo que suena» (Play, progreso, pista actual).
  static const lime = Color(0xffd8ff5c);

  /// Slush 2.0: lila saturado del hero («Ahora suena», mini reproductor).
  static const lilacHero = Color(0xffc4b0ff);

  /// Velo violeta oscuro del fondo del modo letra.
  static const violetDeep = Color(0xff2b1a86);

  /// Texto e iconos sobre relleno [violet] (6.50:1; la tinta da 3.05).
  static const onViolet = Color(0xffffffff);

  /// Violeta como acento sobre superficie oscura (6.41:1 contra el fondo).
  static const violetOnDark = Color(0xff9a85ff);

  /// Fondo oscuro sin portada.
  static const darkBackground = Color(0xff121117);

  /// Fondo plano de pantalla teñido por la portada. Claro: pastel (texto
  /// negro legible); oscuro: tono casi neutro y muy profundo (texto crema
  /// legible, sin competir con los vivos).
  static Color background(Color accent, {bool dark = false}) {
    final h = HSLColor.fromColor(accent);
    return dark
        ? HSLColor.fromAHSL(
            1,
            h.hue,
            h.saturation.clamp(.18, .34),
            .07,
          ).toColor()
        : const Color(0xffe9e0ff);
  }
}

/// Colores neutros de Slush que cambian entre claro y oscuro.
///
/// Capas en oscuro (de atrás hacia delante): [inset] < fondo < [screen] <
/// [paper] < [raised]. Un elemento nunca se pinta más oscuro que su padre
/// (salvo [inset], hueco por diseño).
class SlushPalette extends ThemeExtension<SlushPalette> {
  const SlushPalette({
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.paper,
    required this.raised,
    required this.inset,
    required this.screen,
    required this.line,
    required this.lineSoft,
    required this.divider,
    required this.shadow,
    required this.focus,
    required this.violetAccent,
    required this.hover,
    required this.pressed,
    required this.error,
    required this.disabledFill,
    required this.disabledText,
    required this.disabledBorder,
  });

  /// Texto e iconos sobre [paper] o el fondo; también relleno «tinta».
  final Color ink;

  /// Texto secundario (subtítulos, artista, metadatos).
  final Color ink2;

  /// Texto terciario (hint, tiempos, leyendas).
  final Color ink3;

  /// Relleno de tarjetas, píldoras, barras y botones.
  final Color paper;

  /// Diálogos, hojas, menús, mini reproductor, fila seleccionada.
  final Color raised;

  /// Pozos: campo de texto, pista de slider, visualizador EQ.
  final Color inset;

  /// Pantalla neutra (fondo gris de reproductores y paneles).
  final Color screen;

  /// Contorno de controles (botón, chip, píldora, campo enfocado).
  final Color line;

  /// Contorno de contenedores (tarjeta, banda, diálogo, hoja). En claro
  /// igual que [line].
  final Color lineSoft;

  /// Separador interno de 1,5 px (decorativo).
  final Color divider;

  /// Sombra dura de pegatina.
  final Color shadow;

  /// Anillo de foco de teclado/mando.
  final Color focus;

  /// Violeta usable como acento sobre la superficie de este modo.
  final Color violetAccent;

  /// Capa (con alfa) de hover con puntero fino.
  final Color hover;

  /// Capa (con alfa) de pulsado.
  final Color pressed;

  /// Error de formulario (texto y borde).
  final Color error;

  /// Deshabilitado: relleno, texto y borde.
  final Color disabledFill;
  final Color disabledText;
  final Color disabledBorder;

  static const light = SlushPalette(
    ink: Color(0xff14101f),
    ink2: Color(0xff4a4358),
    ink3: Color(0xff4f4b59),
    paper: Color(0xfffffdf8),
    raised: Color(0xffffffff),
    inset: Color(0xfff3efe6),
    screen: Color(0xffe9e0ff),
    line: Color(0xff14101f),
    lineSoft: Color(0xff14101f),
    divider: Color(0xffd8d2c6),
    shadow: Color(0xff14101f),
    focus: Color(0xff5b3fe0),
    violetAccent: Color(0xff5b3fe0),
    hover: Color(0x8cffd62e),
    pressed: Color(0xd9e3cdfb),
    error: Color(0xffa8221b),
    disabledFill: Color(0xffebe8ef),
    disabledText: Color(0xff6f6b78),
    disabledBorder: Color(0xff9a96a3),
  );

  static const dark = SlushPalette(
    ink: Color(0xfff4efe6),
    ink2: Color(0xffc9c3b8),
    ink3: Color(0xffa39d93),
    paper: Color(0xff1f1e28),
    raised: Color(0xff2a2937),
    inset: Color(0xff0c0b10),
    screen: Color(0xff17161e),
    line: Color(0xfff4efe6),
    lineSoft: Color(0xff7b778c),
    divider: Color(0xff34323f),
    shadow: Color(0xff5a5772),
    focus: Color(0xffffd62e),
    violetAccent: Color(0xff9a85ff),
    hover: Color(0x14f4efe6),
    pressed: Color(0x2ee3cdfb),
    error: Color(0xffff8a80),
    disabledFill: Color(0xff2a2937),
    disabledText: Color(0xff8f8aa0),
    disabledBorder: Color(0xff7b778c),
  );

  /// Borde de control (2 px, [line]).
  BorderSide get border => BorderSide(color: line, width: SlushStroke.base);

  /// Borde de contenedor (2 px, [lineSoft]).
  BorderSide get borderSoft =>
      BorderSide(color: lineSoft, width: SlushStroke.base);

  /// Anillo de foco (3 px, [focus]).
  BorderSide get focusRing =>
      BorderSide(color: focus, width: SlushStroke.strong);

  /// Relleno de hover sobre [paper].
  Color get hoverFill => Color.alphaBlend(hover, paper);

  /// Relleno de pulsado sobre [paper].
  Color get pressedFill => Color.alphaBlend(pressed, paper);

  /// Sombra dura de tarjeta (3,4); ver [shadowsFor].
  List<BoxShadow> get shadows => shadowsFor(SlushElevation.card);

  /// Sombra dura sin desenfoque: (3,4) tarjeta, (2,3) control, ninguna.
  List<BoxShadow> shadowsFor(SlushElevation e) => e == SlushElevation.none
      ? const []
      : [BoxShadow(color: shadow, offset: e.offset)];

  @override
  SlushPalette copyWith({
    Color? ink,
    Color? ink2,
    Color? ink3,
    Color? paper,
    Color? raised,
    Color? inset,
    Color? screen,
    Color? line,
    Color? lineSoft,
    Color? divider,
    Color? shadow,
    Color? focus,
    Color? violetAccent,
    Color? hover,
    Color? pressed,
    Color? error,
    Color? disabledFill,
    Color? disabledText,
    Color? disabledBorder,
  }) => SlushPalette(
    ink: ink ?? this.ink,
    ink2: ink2 ?? this.ink2,
    ink3: ink3 ?? this.ink3,
    paper: paper ?? this.paper,
    raised: raised ?? this.raised,
    inset: inset ?? this.inset,
    screen: screen ?? this.screen,
    line: line ?? this.line,
    lineSoft: lineSoft ?? this.lineSoft,
    divider: divider ?? this.divider,
    shadow: shadow ?? this.shadow,
    focus: focus ?? this.focus,
    violetAccent: violetAccent ?? this.violetAccent,
    hover: hover ?? this.hover,
    pressed: pressed ?? this.pressed,
    error: error ?? this.error,
    disabledFill: disabledFill ?? this.disabledFill,
    disabledText: disabledText ?? this.disabledText,
    disabledBorder: disabledBorder ?? this.disabledBorder,
  );

  @override
  SlushPalette lerp(SlushPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SlushPalette(
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      ink3: l(ink3, other.ink3),
      paper: l(paper, other.paper),
      raised: l(raised, other.raised),
      inset: l(inset, other.inset),
      screen: l(screen, other.screen),
      line: l(line, other.line),
      lineSoft: l(lineSoft, other.lineSoft),
      divider: l(divider, other.divider),
      shadow: l(shadow, other.shadow),
      focus: l(focus, other.focus),
      violetAccent: l(violetAccent, other.violetAccent),
      hover: l(hover, other.hover),
      pressed: l(pressed, other.pressed),
      error: l(error, other.error),
      disabledFill: l(disabledFill, other.disabledFill),
      disabledText: l(disabledText, other.disabledText),
      disabledBorder: l(disabledBorder, other.disabledBorder),
    );
  }
}

extension SlushContext on BuildContext {
  SlushPalette get slush =>
      Theme.of(this).extension<SlushPalette>() ?? SlushPalette.light;
}

/// Tema «Slush»: claro u oscuro según [brightness]; fondo plano teñido por la
/// portada, contornos de 2 px, titulares Bricolage Grotesque 800, píldoras y tarjetas
/// de papel. Misma firma que `auroraTheme`. Lleva también [ModernMarker] para
/// reutilizar las composiciones de Modern (tarjetas, paneles, barras).
ThemeData slushTheme(
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
  TextStyle head(double size, double h) =>
      slushHeadline(size, height: h, color: ink);
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
final slushVividTheme = slushTheme(
  Brightness.light,
  Slush.lilac,
  onVivid: true,
);

/// Envuelve [child] con [slushVividTheme] solo en modo oscuro. El estilo de
/// texto por defecto también pasa a tinta: `Text` sin estilo hereda el
/// `DefaultTextStyle` de fuera (crema en oscuro), no el del tema.
Widget slushOnVivid(BuildContext context, Widget child) =>
    Theme.of(context).brightness == Brightness.dark
    ? Theme(
        data: slushVividTheme,
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: Slush.ink),
          child: child,
        ),
      )
    : child;

/// Texto sobre un relleno cualquiera: tinta fija, tinta del modo o blanco
/// (violeta), el primero con contraste >= 7; si ninguno, el mejor.
Color slushOnColor(BuildContext context, Color fill) {
  double ratio(Color a) {
    final x = a.computeLuminance(), y = fill.computeLuminance();
    return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
  }

  final options = [Slush.ink, context.slush.ink, Slush.onViolet];
  for (final o in options) {
    if (ratio(o) >= 7) return o;
  }
  return options.reduce((a, b) => ratio(a) >= ratio(b) ? a : b);
}
