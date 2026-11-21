import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/brasa_widgets.dart';
import '../mini_player/blurred_cover_backdrop.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import 'lyrics_skin.dart';

/// Piel del modo letra del tema brasa (ver docs/temas.md): salón a oscuras con
/// la portada difuminada (textura cacheada, sin `BackdropFilter`) teñida de
/// brasa, letra en Fraunces con UNA palabra de la línea activa en brasa,
/// tiempos en DM Mono, botones como cuadrados redondeados y el play como
/// círculo de brasa con resplandor.
const LyricsSkin brasaLyricsSkin = LyricsSkin(
  backdrop: _backdrop,
  exitButton: _exit,
  iconButtonStyle: _iconStyle,
  cover: _cover,
  title: _title,
  subtitle: _subtitle,
  progress: _progress,
  lineStyle: _lineStyle,
  lineBuilder: _line,
  playButton: _play,
  controlIconColor: _controlColor,
);

/// Misma frontera que `artist_mode` (`compact = ancho < 760`).
bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

Widget _backdrop(BuildContext context, Track? track, Widget child) =>
    BlurredCoverBackdrop(
      track: track,
      // El velo y el texto son los del tema (oscuros): nunca el velo claro.
      matchTheme: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Calor de la estufa y velo de humo: degradados estáticos, una sola
          // capa cacheada.
          const Positioned.fill(
            child: IgnorePointer(
              child: ExcludeSemantics(child: RepaintBoundary(child: _Smoke())),
            ),
          ),
          child,
        ],
      ),
    );

class _Smoke extends StatelessWidget {
  const _Smoke();

  @override
  Widget build(BuildContext context) => const Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.7, -.8),
            radius: 1.1,
            colors: [Color(0x59B3401F), Color(0x00B3401F)],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(.8, .6),
            radius: 1,
            colors: [Color(0x26E8A24A), Color(0x00E8A24A)],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-.55, -.1),
            radius: .8,
            colors: [Color(0x1FFF7A3D), Color(0x00FF7A3D)],
          ),
        ),
      ),
      // Velo hacia #0F0A08 abajo: legibilidad de letra y transporte.
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x330F0A08), Color(0x990F0A08), Color(0xF20F0A08)],
            stops: [0, .6, 1],
          ),
        ),
      ),
    ],
  );
}

Widget _exit(BuildContext context, LyricsExitArgs a) => Material(
  color: Brasa.ash.withValues(alpha: .85),
  shape: const StadiumBorder(),
  child: InkWell(
    customBorder: const StadiumBorder(),
    onTap: a.onPressed,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back_rounded, size: 20, color: Brasa.ember),
            const SizedBox(width: 10),
            Text(
              // En ventana estrecha con botones de ventana no cabe el texto largo.
              a.compact && MediaQuery.sizeOf(context).width < 480
                  ? 'Salir'
                  : 'Salir del modo letra',
              maxLines: 1,
              style: Brasa.sans(14, weight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  ),
);

ButtonStyle _iconStyle(CoverTone tone) => IconButton.styleFrom(
  fixedSize: const Size.square(48),
  minimumSize: const Size.square(48),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  foregroundColor: Brasa.cream,
  disabledForegroundColor: Brasa.steel,
  overlayColor: Brasa.ember,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);

Color _controlColor(CoverTone tone, {required bool active}) =>
    active ? Brasa.ember : Brasa.cloud;

Widget _cover(BuildContext context, Widget artwork, double size) => BrasaGlow(
  spread: 1.9,
  intensity: .3,
  child: DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.white.withValues(alpha: .07)),
    ),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: Brasa.floatShadow,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: artwork),
    ),
  ),
);

TextStyle _title(BuildContext context, CoverTone tone) =>
    Brasa.serif(_compact(context) ? 20 : 30, height: 1.15);

TextStyle _subtitle(BuildContext context, CoverTone tone) =>
    Brasa.sans(14, color: Brasa.cloud);

Widget _progress(BuildContext context, LyricsProgressArgs a) {
  final style = Brasa.mono(11, color: Brasa.cloud, tracking: .06);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(miniClock(a.position), style: style),
        const SizedBox(width: 10),
        Expanded(
          child: BrasaFilament(
            value: a.value,
            height: _compact(context) ? 6 : 4,
            hitHeight: 32,
            onChanged: a.onChanged,
            onChangeEnd: a.onChangeEnd,
            semanticLabel: 'Posición',
          ),
        ),
        const SizedBox(width: 10),
        Text(
          a.duration > Duration.zero ? miniClock(a.duration) : '--:--',
          style: style,
        ),
      ],
    ),
  );
}

/// [size] llega como 30 (ancho) o 22 (compacto): la activa mide 44 / 32 y el
/// resto 34 / 26.
TextStyle _lineStyle(
  BuildContext context,
  CoverTone tone, {
  required bool active,
  required double size,
}) {
  final wide = size >= 28;
  return Brasa.serif(
    active ? (wide ? 44 : 32) : (wide ? 34 : 26),
    color: active ? Brasa.cream : Brasa.cream.withValues(alpha: .38),
    height: 1.22,
    tracking: -.005,
  ).copyWith(
    shadows: active
        ? [Shadow(color: Brasa.ember.withValues(alpha: .28), blurRadius: 28)]
        : null,
  );
}

final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

/// Palabra de brasa de una línea: la más larga de ≥ 4 letras (la primera en
/// empate). Determinista, sin estado.
@visibleForTesting
Match? brasaAccentWord(String text) {
  Match? best;
  for (final m in _word.allMatches(text)) {
    final len = m.end - m.start;
    if (len >= 4 && (best == null || len > best.end - best.start)) best = m;
  }
  return best;
}

Widget _line(BuildContext context, LyricsLineArgs a) {
  final accent = a.active ? brasaAccentWord(a.text) : null;
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 280);
  return AnimatedDefaultTextStyle(
    duration: duration,
    curve: Curves.easeOutCubic,
    style: a.style,
    child: accent == null
        ? Text(a.text)
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: a.text.substring(0, accent.start)),
                TextSpan(
                  text: a.text.substring(accent.start, accent.end),
                  style: const TextStyle(color: Brasa.ember),
                ),
                TextSpan(text: a.text.substring(accent.end)),
              ],
            ),
          ),
  );
}

Widget _play(BuildContext context, LyricsPlayArgs a) {
  final size = _compact(context) ? 76.0 : 68.0;
  final enabled = a.onPressed != null;
  return Tooltip(
    message: a.tooltip,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: a.tooltip,
      excludeSemantics: true,
      onTap: a.onPressed,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Brasa.ember.withValues(alpha: .42),
                blurRadius: 32,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Material(
            color: Brasa.ember,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: a.onPressed,
              child: SizedBox.square(
                dimension: size,
                child: Center(
                  child: a.buffering
                      ? const SizedBox.square(
                          dimension: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Brasa.onEmber,
                          ),
                        )
                      : Icon(
                          a.playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: size * .5,
                          color: Brasa.onEmber,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
