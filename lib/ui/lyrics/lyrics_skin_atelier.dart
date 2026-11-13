import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/window_controls.dart';
import '../../theme/atelier_theme.dart';
import '../mini_player/blurred_cover_backdrop.dart';
import '../mini_player/mini_player_model.dart' show miniClock;
import '../shell/atelier_widgets.dart';
import 'lyrics_skin.dart';

/// Piel del modo letra de Atelier («Papel y tinta», ver docs/temas.md): papel
/// con las manchas de la portada ya desenfocada bajo un velo de papel, letra en
/// Newsreader (activa en cursiva con marcador terracota), botones rectos de 3
/// px con filete de tinta, progreso de 1 px con rombo y play terracota. En el
/// tema noche usa la variante oscura del Atelier.
const LyricsSkin atelierLyricsSkin = LyricsSkin(
  backdrop: _backdrop,
  exitButton: _exit,
  iconButtonStyle: _transportStyle,
  topButtonStyle: _topStyle,
  cover: _cover,
  compactCoverRadius: 2,
  title: _title,
  subtitle: _subtitle,
  progress: _progress,
  lineStyle: _lineStyle,
  lineBuilder: _line,
  playButton: _play,
  controlIconColor: _controlColor,
);

bool _compact(BuildContext context) => MediaQuery.sizeOf(context).width < 760;

// --- Fondo ------------------------------------------------------------------

Widget _backdrop(BuildContext context, Track? track, Widget child) =>
    _AtelierBackdrop(track: track, child: child);

/// Papel + portada ya desenfocada de la caché (una textura, sin desenfoque por
/// fotograma) + velo de papel cuyo alfa mínimo sale de [CoverTone.themed]: la
/// tinta cumple 4,5:1 sobre cualquier portada. Con animaciones reducidas no hay
/// fundido.
class _AtelierBackdrop extends StatefulWidget {
  const _AtelierBackdrop({required this.track, required this.child});

  final Track? track;
  final Widget child;

  @override
  State<_AtelierBackdrop> createState() => _AtelierBackdropState();
}

class _AtelierBackdropState extends State<_AtelierBackdrop> {
  CoverBackdropData? _data;
  String? _key;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_AtelierBackdrop old) {
    super.didUpdateWidget(old);
    if (old.track?.id != widget.track?.id ||
        old.track?.artworkUrl != widget.track?.artworkUrl) {
      _resolve();
    }
  }

  void _resolve() {
    final track = widget.track;
    final cache = CoverBackdropCache.shared;
    final key = track == null ? null : cache.keyOf(track);
    _key = key;
    if (track == null || key == null) {
      _data = null;
      return;
    }
    final hit = cache.peek(track);
    if (hit != null) {
      _data = hit;
      return;
    }
    cache.load(track).then((data) {
      if (!mounted || _key != key) return;
      setState(() => _data = data);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final data = _data;
    final tone = CoverTone.themed(
      data?.samples ?? const [],
      surface: t.paper,
      onSurface: t.ink,
      onSurfaceVariant: t.ink2,
    );
    final veil = tone.scrim;
    final base = veil.withAlpha(255);
    final top = veil.a < .5 ? base.withValues(alpha: .5) : veil;
    final bottom = veil.a < .8 ? base.withValues(alpha: .8) : veil;
    final instant = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: t.paper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (data != null)
            IgnorePointer(
              child: ExcludeSemantics(
                child: RepaintBoundary(
                  child: AnimatedOpacity(
                    opacity: t.dark ? .5 : .85,
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
              foreground: t.ink,
              secondary: t.ink2,
              scrim: tone.scrim,
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

/// «← Salir del modo letra»: rectángulo de 3 px con filete de tinta (48 px).
Widget _exit(BuildContext context, LyricsExitArgs a) {
  final t = AtelierTokens.of(context);
  // Poco ancho con controles de ventana o texto grande: etiqueta corta.
  final short =
      MediaQuery.sizeOf(context).width < 520 &&
      (WindowControls.supported ||
          MediaQuery.textScalerOf(context).scale(14) > 17);
  return Material(
    color: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(3),
      side: BorderSide(color: t.ink),
    ),
    child: InkWell(
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
      ),
      onTap: a.onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: Padding(
          // Etiqueta corta: menos relleno para que la barra superior (salir,
          // copiar y controles de ventana) quepa en 320 dp a 200 % de texto.
          padding: EdgeInsets.symmetric(
            horizontal: short ? 10 : 14,
            vertical: 6,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_back, size: 18, color: t.ink),
              SizedBox(width: short ? 8 : 10),
              Flexible(
                child: Text(
                  short ? 'Salir' : 'Salir del modo letra',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.ui(14, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Color _ink(Set<WidgetState> s, Color enabled) =>
    s.contains(WidgetState.disabled) ? enabled.withValues(alpha: .38) : enabled;

ButtonStyle _transportStyle(CoverTone tone) => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size.square(48)),
  minimumSize: const WidgetStatePropertyAll(Size.square(48)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
  ),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: WidgetStateProperty.resolveWith(
    (s) => _ink(s, tone.foreground),
  ),
  iconColor: WidgetStateProperty.resolveWith((s) => _ink(s, tone.foreground)),
  overlayColor: WidgetStatePropertyAll(tone.foreground.withValues(alpha: .08)),
);

/// Copiar y controles de ventana: 44 px, radio 3, trazo fino.
ButtonStyle _topStyle(CoverTone tone, {required bool copy}) => ButtonStyle(
  fixedSize: const WidgetStatePropertyAll(Size.square(44)),
  minimumSize: const WidgetStatePropertyAll(Size.square(44)),
  padding: const WidgetStatePropertyAll(EdgeInsets.zero),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
  ),
  backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: WidgetStateProperty.resolveWith(
    (s) => _ink(s, tone.foreground),
  ),
  iconColor: WidgetStateProperty.resolveWith((s) => _ink(s, tone.foreground)),
  overlayColor: WidgetStatePropertyAll(tone.foreground.withValues(alpha: .08)),
);

Color _controlColor(CoverTone tone, {required bool active}) =>
    active ? tone.foreground : tone.secondary;

/// Play terracota (`onAccent` sobre acento, 4,63:1): círculo de 60 px en
/// escritorio, «squircle» de 64 px (radio 22) en móvil.
Widget _play(BuildContext context, LyricsPlayArgs a) {
  final t = AtelierTokens.of(context);
  final squircle = _compact(context);
  final size = squircle ? 64.0 : 60.0;
  final shape = squircle
      ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))
      : const CircleBorder();
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: IconButton(
      tooltip: a.tooltip,
      onPressed: a.onPressed,
      style: IconButton.styleFrom(
        backgroundColor: t.accent,
        foregroundColor: t.onAccent,
        disabledBackgroundColor: t.accent.withValues(alpha: .38),
        disabledForegroundColor: t.onAccent,
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
                color: t.onAccent,
              ),
            )
          : Icon(
              a.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 32,
            ),
    ),
  );
}

// --- Portada y textos -------------------------------------------------------

Widget _cover(BuildContext context, Widget artwork, double size) {
  final t = AtelierTokens.of(context);
  return DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: t.dark ? .5 : .30),
          blurRadius: 18,
          spreadRadius: -12,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: t.ink.withValues(alpha: .14)),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(2), child: artwork),
    ),
  );
}

TextStyle _title(BuildContext context, CoverTone tone) => AtelierTokens.of(
  context,
).serif(_compact(context) ? 20 : 24, color: tone.foreground);

TextStyle _subtitle(BuildContext context, CoverTone tone) => AtelierTokens.of(
  context,
).serif(_compact(context) ? 15 : 17, italic: true, color: tone.secondary);

// --- Progreso ---------------------------------------------------------------

/// Línea de 1 px con relleno terracota, rombo y tiempos mono a los lados.
Widget _progress(BuildContext context, LyricsProgressArgs a) {
  final t = AtelierTokens.of(context);
  final style = t.mono(size: 11.5, color: t.ink2);
  final known = a.duration > Duration.zero;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Semantics(
      label:
          'Tiempo: ${miniClock(a.position)} de '
          '${known ? miniClock(a.duration) : 'desconocido'}',
      container: true,
      child: Row(
        children: [
          ExcludeSemantics(child: Text(miniClock(a.position), style: style)),
          const SizedBox(width: 10),
          Expanded(
            child: AtelierLine(
              progress: a.value,
              onSeek: a.canSeek ? a.onChangeEnd : null,
            ),
          ),
          const SizedBox(width: 10),
          ExcludeSemantics(
            child: Text(known ? miniClock(a.duration) : '--:--', style: style),
          ),
        ],
      ),
    ),
  );
}

// --- Letra ------------------------------------------------------------------

/// Activa: Newsreader 48 (móvil 32) en cursiva, tinta. Resto: 38 (móvil 27) al
/// 42 % (texto grande: 3:1 basta; la línea activa tiene 14,97:1).
TextStyle _lineStyle(
  BuildContext context,
  CoverTone tone, {
  required bool active,
  required double size,
}) {
  final t = AtelierTokens.of(context);
  final desktop = size > 25;
  final px = active ? (desktop ? 48.0 : 32.0) : (desktop ? 38.0 : 27.0);
  return t.serif(
    px,
    italic: active,
    height: 1.25,
    color: active ? t.ink : t.ink.withValues(alpha: .42),
  );
}

/// Línea activa con marcador terracota al 26 % (fondo del texto, por línea).
Widget _line(BuildContext context, LyricsLineArgs a) {
  final t = AtelierTokens.of(context);
  final style = a.active
      ? a.style.copyWith(
          backgroundColor: t.accent.withValues(alpha: t.dark ? .32 : .26),
        )
      : a.style;
  return AnimatedDefaultTextStyle(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    style: style,
    child: Text(a.text),
  );
}
