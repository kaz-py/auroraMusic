import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/aurora_tokens.dart';
import '../mini_player/blurred_cover_backdrop.dart';
import 'lyrics_skin_atelier.dart';
import 'lyrics_skin_brasa.dart';
import 'lyrics_skin_modern.dart';
import 'lyrics_skin_slush.dart';

/// Piel del modo letra: la composición (portada y progreso a la izquierda,
/// letra a la derecha, transporte abajo; compacta en móvil) es la misma en
/// todos los temas; cada tema solo cambia tipografía, colores, forma de los
/// botones, fondo y estilo del progreso. Todos los ganchos son opcionales: sin
/// ellos, el aspecto es el de siempre.
///
/// Cada tema define su piel en `lyrics_skin_<tema>.dart` y la registra en
/// [lyricsSkinFor].
class LyricsSkin {
  const LyricsSkin({
    this.backdrop,
    this.exitButton,
    this.iconButtonStyle,
    this.cover,
    this.title,
    this.subtitle,
    this.meta,
    this.progress,
    this.lineStyle,
    this.lineBuilder,
    this.playButton,
    this.controlIconColor,
  });

  /// Fondo de toda la página (por defecto, la portada desenfocada). Debe
  /// colocar un [BlurredCoverTheme] con los colores de texto que correspondan
  /// (p. ej. tinta oscura sobre papel).
  final Widget Function(BuildContext context, Track? track, Widget child)?
  backdrop;

  /// Botón «Salir del modo letra».
  final Widget Function(BuildContext context, LyricsExitArgs args)? exitButton;

  /// Estilo de los botones de icono sueltos (copiar, ventana, anterior…).
  final ButtonStyle Function(CoverTone tone)? iconButtonStyle;

  /// Marco de la portada (esquinas, sombra, sello…). Recibe la portada ya construida.
  final Widget Function(BuildContext context, Widget artwork, double size)?
  cover;

  /// Estilo del título y del subtítulo (sobre el del tema).
  final TextStyle Function(BuildContext context, CoverTone tone)? title;
  final TextStyle Function(BuildContext context, CoverTone tone)? subtitle;

  /// Fila extra bajo el título (p. ej. chip «FLAC 24/96»).
  final Widget Function(BuildContext context, CoverTone tone)? meta;

  /// Barra de progreso con tiempos (línea, onda…).
  final Widget Function(BuildContext context, LyricsProgressArgs args)?
  progress;

  /// Estilo de una línea de letra; [size] ya distingue escritorio y móvil.
  final TextStyle Function(
    BuildContext context,
    CoverTone tone, {
    required bool active,
    required double size,
  })?
  lineStyle;

  /// Línea de letra completa (para resaltar una palabra, subrayar…). Si falta,
  /// se usa un texto con [lineStyle].
  final Widget Function(BuildContext context, LyricsLineArgs args)? lineBuilder;

  /// Botón de reproducir/pausar.
  final Widget Function(BuildContext context, LyricsPlayArgs args)? playButton;

  /// Color de los iconos de transporte (por defecto, el de la portada).
  final Color Function(CoverTone tone, {required bool active})?
  controlIconColor;
}

class LyricsExitArgs {
  const LyricsExitArgs({
    required this.tone,
    required this.compact,
    required this.onPressed,
  });
  final CoverTone tone;
  final bool compact;
  final VoidCallback onPressed;
}

class LyricsProgressArgs {
  const LyricsProgressArgs({
    required this.tone,
    required this.value,
    required this.position,
    required this.duration,
    required this.canSeek,
    required this.onChanged,
    required this.onChangeEnd,
  });
  final CoverTone tone;

  /// 0–1.
  final double value;
  final Duration position, duration;
  final bool canSeek;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
}

class LyricsLineArgs {
  const LyricsLineArgs({
    required this.text,
    required this.active,
    required this.size,
    required this.tone,
    required this.style,
  });
  final String text;
  final bool active;
  final double size;
  final CoverTone tone;

  /// Estilo por defecto (el de [LyricsSkin.lineStyle] o el clásico).
  final TextStyle style;
}

class LyricsPlayArgs {
  const LyricsPlayArgs({
    required this.tone,
    required this.playing,
    required this.buffering,
    required this.onPressed,
    required this.tooltip,
  });
  final CoverTone tone;
  final bool playing, buffering;
  final VoidCallback? onPressed;
  final String tooltip;
}

/// Piel de cada tema: cada uno edita SOLO su `lyrics_skin_<tema>.dart`.
LyricsSkin lyricsSkinFor(AuroraThemeKind kind) => switch (kind) {
  AuroraThemeKind.atelier => atelierLyricsSkin,
  AuroraThemeKind.modern => modernLyricsSkin,
  AuroraThemeKind.brasa => brasaLyricsSkin,
  AuroraThemeKind.slush => slushLyricsSkin,
};
