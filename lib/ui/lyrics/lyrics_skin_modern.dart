import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import '../mini_player/blurred_cover_backdrop.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import 'lyrics_skin.dart';

/// Piel del modo letra de Modern «Cristal y aura» (ver docs/temas.md): lienzo
/// oscuro + portada desenfocada + aura de dos manchas + velo que mantiene el
/// contraste, botones de cristal, onda fina de búsqueda, letra activa blanca
/// con halo azul y play en el único acento. Sin menta ni coral. Esta pantalla
/// es siempre oscura (paleta oscura de [Cristal]), también con el tema claro.
const LyricsSkin modernLyricsSkin = LyricsSkin(
  backdrop: _backdrop,
  exitButton: _exit,
  iconButtonStyle: _transportStyle,
  topButtonStyle: _topStyle,
  cover: _cover,
  compactCoverRadius: 16,
  title: _title,
  subtitle: _subtitle,
  progress: _progress,
  lineStyle: _lineStyle,
  playButton: _play,
  controlIconColor: _controlColor,
);

const Cristal _c = Cristal.darkPalette;

/// Mismas dimensiones con las que la página pasa a composición compacta.
bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

// --- Fondo ------------------------------------------------------------------

Widget _backdrop(BuildContext context, Track? track, Widget child) =>
    _ModernLyricsBackdrop(track: track, child: child);

/// Lienzo + aura ([ModernAura]) + portada ya desenfocada de la caché (una sola
/// textura, sin desenfoque por fotograma) + velo degradado 45 % → 88 % cuyo
/// alfa mínimo sale de [CoverTone.themed], de modo que el texto fijo de esta
/// piel cumple 4,5:1 sobre cualquier portada.
class _ModernLyricsBackdrop extends StatefulWidget {
  const _ModernLyricsBackdrop({required this.track, required this.child});

  final Track? track;
  final Widget child;

  @override
  State<_ModernLyricsBackdrop> createState() => _ModernLyricsBackdropState();
}

class _ModernLyricsBackdropState extends State<_ModernLyricsBackdrop> {
  CoverBackdropData? _data;
  String? _key;
  CoverTone _tone = _toneFor(const []);

  static CoverTone _toneFor(List<Color> samples) => CoverTone.themed(
    samples,
    surface: _c.canvas,
    onSurface: _c.text,
    onSurfaceVariant: _c.text2,
  );

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_ModernLyricsBackdrop old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.track?.artworkUrl != widget.track?.artworkUrl) {
      _resolve();
    }
  }

  void _apply(CoverBackdropData? data) {
    _data = data;
    _tone = _toneFor(data?.samples ?? const []);
  }

  void _resolve() {
    final track = widget.track;
    final cache = CoverBackdropCache.shared;
    final key = track == null ? null : cache.keyOf(track);
    _key = key;
    if (track == null || key == null) return _apply(null);
    final hit = cache.peek(track);
    if (hit != null) return _apply(hit);
    cache.load(track).then((data) {
      if (!mounted || _key != key) return;
      setState(() => _apply(data));
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final veil = _tone.scrim;
    final base = veil.withAlpha(255);
    final top = veil.a < .45 ? base.withValues(alpha: .45) : veil;
    final bottom = veil.a < .88 ? base.withValues(alpha: .88) : veil;
    final instant = MediaQuery.disableAnimationsOf(context);
    return ModernAura(
      track: widget.track,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (data != null)
            IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedOpacity(
                    opacity: .55,
                    duration: instant ? Duration.zero : kCoverCrossfade,
                    child: RawImage(
                      image: data.image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, bottom],
                ),
              ),
            ),
          ),
          BlurredCoverTheme(
            tone: CoverTone(
              foreground: _c.text,
              secondary: _c.text2,
              scrim: _tone.scrim,
            ),
            active: true,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

// --- Botones ----------------------------------------------------------------

/// «← Salir del modo letra»: píldora de cristal de 40 px.
Widget _exit(BuildContext context, LyricsExitArgs a) {
  final narrow = a.compact;
  return ModernGlass(
    radius: 999,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: a.onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.only(
              left: 10,
              right: narrow ? 14 : 18,
              top: 6,
              bottom: 6,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left_rounded, size: 22, color: _c.text),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    narrow ? 'Salir' : 'Salir del modo letra',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Cristal.ui(14, weight: 700, color: _c.text),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Color _ink(Set<WidgetState> s, Color enabled) =>
    s.contains(WidgetState.disabled) ? enabled.withValues(alpha: .38) : enabled;

/// Transporte: 48 px, radio 12, sin relleno; activo = tesela de cristal.
ButtonStyle _transportStyle(CoverTone tone) => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size.square(48)),
  minimumSize: const WidgetStatePropertyAll(Size.square(48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) =>
        s.contains(WidgetState.selected) ? _c.glassHover : Colors.transparent,
  ),
  foregroundColor: WidgetStateProperty.resolveWith((s) => _ink(s, _c.text)),
  iconColor: WidgetStateProperty.resolveWith((s) => _ink(s, _c.text)),
  overlayColor: WidgetStatePropertyAll(_c.glass),
);

/// Botones de la barra superior: copiar = círculo de cristal de 40 px;
/// controles de ventana = 40 px radio 12 sin relleno.
ButtonStyle _topStyle(CoverTone tone, {required bool copy}) => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size.square(44)),
  minimumSize: const WidgetStatePropertyAll(Size.square(44)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStatePropertyAll(
    copy
        ? CircleBorder(side: BorderSide(color: _c.border))
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  backgroundColor: WidgetStatePropertyAll(copy ? _c.glass : Colors.transparent),
  foregroundColor: WidgetStateProperty.resolveWith((s) => _ink(s, _c.text)),
  iconColor: WidgetStateProperty.resolveWith((s) => _ink(s, _c.text)),
  overlayColor: WidgetStatePropertyAll(_c.glassHover),
);

Color _controlColor(CoverTone tone, {required bool active}) =>
    active ? _c.accent : _c.text2;

Widget _play(BuildContext context, LyricsPlayArgs a) {
  final squircle = _compact(context);
  final size = squircle ? 72.0 : 60.0;
  final shape = squircle
      ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(26))
      : const CircleBorder();
  final enabled = a.onPressed != null;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: enabled
            ? [
                BoxShadow(
                  color: _c.accent.withValues(alpha: .40),
                  blurRadius: 28,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: IconButton(
        tooltip: a.tooltip,
        onPressed: a.onPressed,
        style: IconButton.styleFrom(
          backgroundColor: _c.accent,
          foregroundColor: _c.onAccent,
          disabledBackgroundColor: _c.accent.withValues(alpha: .38),
          disabledForegroundColor: _c.onAccent,
          fixedSize: Size.square(size),
          minimumSize: Size.square(size),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: shape,
        ),
        icon: a.buffering
            ? SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: _c.onAccent,
                ),
              )
            : Icon(
                a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: squircle ? 38 : 32,
              ),
      ),
    ),
  );
}

// --- Portada y textos -------------------------------------------------------

/// Portada cuadrada: radio 28 (grande) o 16, sombra de portada.
Widget _cover(BuildContext context, Widget artwork, double size) {
  final radius = BorderRadius.circular(size >= 200 ? 28 : 16);
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: radius,
      boxShadow: const [
        BoxShadow(
          color: Color(0x99000000),
          blurRadius: 40,
          spreadRadius: -12,
          offset: Offset(0, 18),
        ),
      ],
    ),
    child: ClipRRect(borderRadius: radius, child: artwork),
  );
}

TextStyle _title(BuildContext context, CoverTone tone) => Cristal.ui(
  _compact(context) ? 22 : 30,
  weight: 800,
  color: _c.text,
  height: 1.15,
  tracking: -.03,
);

TextStyle _subtitle(BuildContext context, CoverTone tone) =>
    Cristal.ui(_compact(context) ? 14 : 15, weight: 500, color: _c.text2);

// --- Progreso ---------------------------------------------------------------

/// Onda fina de 22 px (barras de 2 px) con los tiempos en mono debajo.
Widget _progress(BuildContext context, LyricsProgressArgs a) {
  final style = Cristal.mono(
    11.5,
    color: _c.text3,
    tracking: .04,
  ).copyWith(height: 1.3);
  final known = a.duration > Duration.zero;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ModernWaveSeekBar(
          progress: a.value,
          seed: a.trackId,
          height: 22,
          barWidth: 2,
          gap: 2,
          onSeek: a.canSeek ? a.onChangeEnd : null,
        ),
        const SizedBox(height: 4),
        Semantics(
          label:
              'Tiempo: ${miniClock(a.position)} de '
              '${known ? miniClock(a.duration) : 'desconocido'}',
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(miniClock(a.position), style: style),
              Text(known ? miniClock(a.duration) : '--:--', style: style),
            ],
          ),
        ),
      ],
    ),
  );
}

// --- Letra ------------------------------------------------------------------

/// Activa: 44 px (móvil 32), blanca con halo azul. Resto: 28 px (móvil 24) al
/// 38 % (texto grande: 3:1 basta). [size] ya distingue escritorio (30) y móvil.
TextStyle _lineStyle(
  BuildContext context,
  CoverTone tone, {
  required bool active,
  required double size,
}) {
  final desktop = size > 25;
  final px = active ? (desktop ? 44.0 : 32.0) : (desktop ? 28.0 : 24.0);
  return Cristal.ui(
    px,
    weight: 800,
    height: 1.2,
    tracking: -.03,
    color: active ? Colors.white : _c.text.withValues(alpha: .38),
  ).copyWith(
    shadows: active
        ? [Shadow(color: _c.accent.withValues(alpha: .55), blurRadius: 24)]
        : const [],
  );
}
