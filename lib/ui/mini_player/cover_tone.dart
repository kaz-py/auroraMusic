import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// Relación de contraste mínima que se exige al texto sobre el fondo con
/// portada. El requisito de la app es 4,5; el margen cubre la interpolación
/// bilineal y el difuminado (la media de píxeles no cae fuera del rango
/// muestreado, pero la luminancia no es lineal).
const double kCoverContrastTarget = 4.8;

/// Relación de contraste WCAG entre dos colores opacos.
double coverContrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + .05) / (lo + .05);
}

/// Colores de un fondo con portada difuminada: velo ([scrim], con su alfa) y
/// texto ([foreground] principal y [secondary] atenuado) que cumplen
/// [kCoverContrastTarget] sobre **todos** los píxeles muestreados de la
/// portada una vez cubiertos por el velo.
///
/// Cálculo puro, sin Flutter ni E/S: se prueba con portadas sintéticas.
@immutable
class CoverTone {
  const CoverTone({
    required this.foreground,
    required this.secondary,
    required this.scrim,
  });

  final Color foreground;
  final Color secondary;

  /// Velo; su alfa es la mínima que garantiza el contraste.
  final Color scrim;

  /// Velo oscuro con texto claro.
  bool get darkScrim => scrim.computeLuminance() < .5;

  static const _darkScrim = Color(0xff0e0e12);
  static const _lightScrim = Color(0xfff7f5f2);
  static const _onDark = Color(0xffffffff);
  static const _onLight = Color(0xff121212);

  // Alfa mínimo por dirección: con menos velo la portada manda demasiado y el
  // texto queda a merced de un único píxel claro.
  static const _minDark = 96, _minLight = 115, _maxAlpha = 235;

  /// Prefiere el velo oscuro salvo que el claro necesite bastante menos.
  static const _lightMargin = 12;

  /// Elige velo claro u oscuro según las [samples] (colores opacos de la
  /// portada ya difuminada) con el alfa mínimo que garantiza el contraste.
  factory CoverTone.adaptive(List<Color> samples) {
    final dark = _solve(samples, _darkScrim, _onDark, _minDark, _maxAlpha);
    final light = _solve(samples, _lightScrim, _onLight, _minLight, _maxAlpha);
    if (dark != null &&
        (light == null || dark.alpha <= light.alpha + _lightMargin)) {
      return dark.tone;
    }
    if (light != null) return light.tone;
    // Inalcanzable con 235/255 sobre cualquier color; velo casi opaco por si acaso.
    return CoverTone(
      foreground: _onDark,
      secondary: _secondaryOf(_onDark, _darkScrim),
      scrim: _darkScrim,
    );
  }

  /// Variante para la cabecera del reproductor: el velo es la superficie del
  /// tema y el texto el del tema, así el resto de la pantalla no cambia de
  /// color. Alfa mínimo que mantiene [onSurface] y [onSurfaceVariant] sobre el
  /// objetivo; si la superficie sola no llega, el velo es opaco (look del tema).
  factory CoverTone.themed(
    List<Color> samples, {
    required Color surface,
    required Color onSurface,
    required Color onSurfaceVariant,
  }) {
    final opaque = surface.withAlpha(255);
    final fg = onSurface.withAlpha(255), sec = onSurfaceVariant.withAlpha(255);
    for (var a = 110; a <= 255; a++) {
      if (_holds(samples, opaque, a, [fg, sec])) {
        return CoverTone(
          foreground: fg,
          secondary: sec,
          scrim: opaque.withAlpha(a),
        );
      }
    }
    return CoverTone(foreground: fg, secondary: sec, scrim: opaque);
  }

  static Color _secondaryOf(Color fg, Color scrim) =>
      Color.lerp(fg, scrim, .2)!.withAlpha(255);

  static ({int alpha, CoverTone tone})? _solve(
    List<Color> samples,
    Color scrim,
    Color fg,
    int from,
    int to,
  ) {
    final sec = _secondaryOf(fg, scrim);
    for (var a = from; a <= to; a++) {
      if (_holds(samples, scrim, a, [fg, sec])) {
        return (
          alpha: a,
          tone: CoverTone(
            foreground: fg,
            secondary: sec,
            scrim: scrim.withAlpha(a),
          ),
        );
      }
    }
    return null;
  }

  static bool _holds(
    List<Color> samples,
    Color scrim,
    int alpha,
    List<Color> foregrounds,
  ) {
    final veil = scrim.withAlpha(alpha);
    for (final pixel in samples) {
      final bg = Color.alphaBlend(veil, pixel.withAlpha(255));
      for (final fg in foregrounds) {
        if (coverContrast(fg, bg) < kCoverContrastTarget) return false;
      }
    }
    return true;
  }

  /// Peor contraste de [foreground] y [secondary] sobre [samples] cubiertas
  /// por el velo. Para pruebas y auditoría.
  double worstContrast(List<Color> samples) {
    var worst = double.infinity;
    for (final pixel in samples) {
      final bg = Color.alphaBlend(scrim, pixel.withAlpha(255));
      for (final fg in [foreground, secondary]) {
        final c = coverContrast(fg, bg);
        if (c < worst) worst = c;
      }
    }
    return worst;
  }

  @override
  bool operator ==(Object other) =>
      other is CoverTone &&
      other.foreground == foreground &&
      other.secondary == secondary &&
      other.scrim == scrim;

  @override
  int get hashCode => Object.hash(foreground, secondary, scrim);
}
