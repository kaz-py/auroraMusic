import 'package:flutter/material.dart';

/// Escala de espaciado (px). Margen de pantalla y hueco entre secciones por
/// ancho: `SlushSpacing.margin(width)` / `SlushSpacing.sectionGap(width)`.
abstract final class SlushSpacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
  static const double s64 = 64;

  /// Margen lateral de pantalla: 16 (<600), 24 (600-899), 32 (>=900).
  static double margin(double width) => width < Breakpoints.medium
      ? (width < Breakpoints.compact ? s16 : s24)
      : s32;

  /// Hueco entre secciones: 24 (<600), 32 (600-899), 48 (>=900).
  static double sectionGap(double width) => width < Breakpoints.medium
      ? (width < Breakpoints.compact ? s24 : s32)
      : s48;
}

/// Radios únicos. Concéntrico: radio interno = externo - padding.
abstract final class SlushRadius {
  /// Miniaturas y chips de fila.
  static const double r8 = 8;

  /// Portadas pequeñas.
  static const double r12 = 12;

  /// Campos, menús, tiles internos.
  static const double r16 = 16;

  /// Tarjetas.
  static const double r24 = 24;

  /// Bandas, diálogos y hojas.
  static const double r32 = 32;
  static const double pill = 999;
}

/// Anchos de borde y alturas de control.
abstract final class SlushStroke {
  /// Contenedor y control.
  static const double base = 2;

  /// Foco y selección fuerte.
  static const double strong = 3;

  /// Divisor interno.
  static const double divider = 1.5;
}

abstract final class SlushControl {
  /// Objetivo táctil mínimo.
  static const double touch = 44;

  /// Barra inferior.
  static const double bar = 48;

  /// Mínimo con puntero fino (>= 900).
  static const double dense = 32;

  /// Altura de la píldora de estado informativa.
  static const double pill = 24;
}

/// Puntos de corte únicos de la interfaz.
abstract final class Breakpoints {
  static const double phone = 360;
  static const double phoneLarge = 412;

  /// Desde aquí: 3 columnas, margen 24.
  static const double compact = 600;

  /// Desde aquí: escritorio (barra superior, hover, margen 32).
  static const double medium = 900;
  static const double large = 1440;
  static const double huge = 1920;

  static bool isCompact(double width) => width < compact;
  static bool isWide(double width) => width >= medium;
}

/// Elevación = sombra dura de pegatina: (3,4) tarjeta, (2,3) control, 0.
enum SlushElevation {
  card(Offset(3, 4)),
  control(Offset(2, 3)),
  none(Offset.zero);

  const SlushElevation(this.offset);
  final Offset offset;
}

/// Curvas y duraciones de movimiento. Nada de `Curves.ease`/`linear`/
/// `easeIn` en UI (salvo progreso).
abstract final class SlushMotion {
  static const easeOut = Cubic(.23, 1, .32, 1);
  static const easeInOut = Cubic(.77, 0, .175, 1);
  static const drawer = Cubic(.32, .72, 0, 1);

  /// Pulsar: hundido al bajar, vuelve más lento al soltar.
  static const pressDown = Duration(milliseconds: 90);
  static const pressUp = Duration(milliseconds: 160);
  static const hover = Duration(milliseconds: 120);
  static const select = Duration(milliseconds: 140);
  static const sectionIn = Duration(milliseconds: 220);
  static const sectionOut = Duration(milliseconds: 140);
  static const sheetIn = Duration(milliseconds: 280);
  static const sheetOut = Duration(milliseconds: 200);
  static const dialogIn = Duration(milliseconds: 180);
  static const dialogOut = Duration(milliseconds: 120);
  static const listItem = Duration(milliseconds: 240);
  static const listStagger = Duration(milliseconds: 40);
  static const miniPlayerIn = Duration(milliseconds: 240);

  /// Con movimiento reducido solo hay opacidad, y breve.
  static const reduced = Duration(milliseconds: 120);

  /// Máximo de ítems de lista con entrada escalonada.
  static const listStaggerMax = 8;

  /// Movimiento reducido (ajuste del sistema o del usuario, ya cableado a
  /// `MediaQuery.disableAnimations` en main.dart).
  static bool reduce(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Entrada de sección: opacidad 0→1 + desplazamiento vertical 8→0.
  /// Con [reduced] solo opacidad.
  static Widget fadeSlide(
    Animation<double> animation,
    Widget child, {
    bool reduced = false,
  }) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: easeOut,
      reverseCurve: easeOut,
    );
    final faded = FadeTransition(opacity: curved, child: child);
    if (reduced) return faded;
    return AnimatedBuilder(
      animation: curved,
      child: faded,
      builder: (_, c) => Transform.translate(
        offset: Offset(0, 8 * (1 - curved.value)),
        child: c,
      ),
    );
  }
}

/// Transición de rutas: la de sección de [SlushMotion.fadeSlide].
class SlushPageTransitionsBuilder extends PageTransitionsBuilder {
  const SlushPageTransitionsBuilder();

  @override
  Duration get transitionDuration => SlushMotion.sectionIn;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlushMotion.fadeSlide(
    animation,
    child,
    reduced: SlushMotion.reduce(context),
  );
}
