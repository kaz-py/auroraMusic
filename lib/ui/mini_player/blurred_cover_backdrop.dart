import 'package:flutter/material.dart';

import '../../core/models.dart';
import 'cover_backdrop_source.dart';
import 'cover_tone.dart';

export 'cover_backdrop_source.dart'
    show CoverBackdropCache, CoverBackdropData, CoverBackdropSource;
export 'cover_tone.dart' show CoverTone, coverContrast, kCoverContrastTarget;

/// Duración del cruce entre portadas al cambiar de pista (movimiento reducido:
/// instantáneo).
const Duration kCoverCrossfade = Duration(milliseconds: 350);

/// Colores del texto sobre un [BlurredCoverBackdrop] activo.
///
/// ```dart
/// final tone = BlurredCoverTheme.of(context);
/// Text(artist, style: TextStyle(color: tone.foreground));
/// Text(title, style: TextStyle(color: tone.secondary));
/// ```
///
/// [CoverTone.foreground] y [CoverTone.secondary] mantienen una relación de
/// contraste ≥ 4,8 (el requisito de la app es 4,5) sobre cualquier portada una
/// vez cubierta por [CoverTone.scrim]. Sin portada (sin pista, sin imagen o
/// fallo de carga) [of] devuelve los colores del tema y [isActive] es falso:
/// los widgets deben mantener su aspecto normal.
class BlurredCoverTheme extends InheritedWidget {
  const BlurredCoverTheme({
    super.key,
    required this.tone,
    required this.active,
    required super.child,
  });

  final CoverTone tone;

  /// Hay portada pintada detrás.
  final bool active;

  /// Colores vigentes; sin ancestro o sin portada, los del tema.
  static CoverTone of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlurredCoverTheme>()?.tone ??
      _themeTone(Theme.of(context).colorScheme);

  /// ¿Hay un fondo con portada activo sobre este contexto?
  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BlurredCoverTheme>()?.active ??
      false;

  static CoverTone _themeTone(ColorScheme scheme) => CoverTone(
    foreground: scheme.onSurface,
    secondary: scheme.onSurfaceVariant,
    scrim: Colors.transparent,
  );

  @override
  bool updateShouldNotify(BlurredCoverTheme old) =>
      old.tone != tone || old.active != active;
}

/// Fondo con la portada de [track] difuminada y un velo que garantiza el
/// contraste del texto de [child] (ver [BlurredCoverTheme]).
///
/// - La portada se decodifica pequeña, se difumina **una vez** y se guarda en
///   [CoverBackdropCache] por pista/URL: pintar es una textura, sin desenfoque
///   por fotograma.
/// - Al cambiar de pista cruza las dos portadas en [kCoverCrossfade]; la antigua
///   se queda hasta que la nueva carga (nunca un parpadeo). Con movimiento
///   reducido (`MediaQuery.disableAnimationsOf`) el cambio es instantáneo.
/// - Sin pista, sin portada o con fallo de carga se pinta solo [child] sobre lo
///   que haya detrás: la apariencia normal del tema.
/// - [matchTheme]: en vez de elegir velo claro/oscuro, el velo es el fondo del
///   tema y el texto el del tema (cabecera del reproductor, donde el resto de
///   la pantalla conserva sus colores). [fadeBottom] funde el borde inferior
///   con el fondo del tema.
/// - Al cruzar entre portadas de distinto tono (clara ↔ oscura) el color del
///   texto cambia a mitad del cruce; en ese instante el contraste baja a ~4
///   durante menos de [kCoverCrossfade]. En reposo siempre es ≥ 4,8.
class BlurredCoverBackdrop extends StatefulWidget {
  const BlurredCoverBackdrop({
    super.key,
    required this.track,
    required this.child,
    this.radius,
    this.source,
    this.matchTheme = false,
    this.fadeBottom = false,
  });

  final Track? track;
  final Widget child;
  final BorderRadius? radius;

  /// Origen de portadas; por defecto la caché compartida de la app.
  final CoverBackdropSource? source;
  final bool matchTheme;
  final bool fadeBottom;

  @override
  State<BlurredCoverBackdrop> createState() => _BlurredCoverBackdropState();
}

class _BlurredCoverBackdropState extends State<BlurredCoverBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kCoverCrossfade,
    value: 1,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _fade,
    curve: Curves.easeInOut,
  );
  late final Animation<double> _reverse = ReverseAnimation(_curve);

  CoverBackdropData? _current, _previous;
  String? _key;
  bool _newTone = true;

  // Tono temático memorizado (el cálculo recorre las muestras).
  CoverBackdropData? _themedData;
  List<Color>? _themedColors;
  CoverTone? _themedTone;

  CoverBackdropSource get _source => widget.source ?? CoverBackdropCache.shared;

  @override
  void initState() {
    super.initState();
    _fade.addListener(_onTick);
    _fade.addStatusListener((status) {
      if (status == AnimationStatus.completed && _previous != null) {
        setState(() => _previous = null);
      }
    });
    final track = widget.track;
    if (track != null) {
      _key = _source.keyOf(track);
      _current = _source.peek(track);
      if (_current == null && _key != null) _request(track, _key!);
    }
  }

  @override
  void didUpdateWidget(BlurredCoverBackdrop old) {
    super.didUpdateWidget(old);
    final track = widget.track;
    final key = track == null ? null : _source.keyOf(track);
    if (key == _key && identical(old.source, widget.source)) return;
    _key = key;
    if (track == null || key == null) return _apply(null);
    final hit = _source.peek(track);
    if (hit != null) return _apply(hit);
    _request(track, key);
  }

  void _request(Track track, String key) {
    _source.load(track).then((data) {
      if (mounted && _key == key) setState(() => _apply(data));
    });
  }

  /// Cambia de portada; el llamador reconstruye (setState o didUpdateWidget).
  void _apply(CoverBackdropData? data) {
    if (identical(data, _current)) return;
    final instant = MediaQuery.disableAnimationsOf(context);
    _previous = _current;
    _current = data;
    if (instant || (_previous == null && data == null)) {
      _previous = null;
      _newTone = true;
      _fade.value = 1;
    } else {
      _newTone = _previous == null;
      _fade.forward(from: 0);
    }
  }

  void _onTick() {
    final flip = _previous == null || _fade.value >= .5;
    if (flip != _newTone) setState(() => _newTone = flip);
  }

  @override
  void dispose() {
    _curve.dispose();
    _fade.dispose();
    super.dispose();
  }

  CoverTone _toneOf(CoverBackdropData data, ThemeData theme) {
    if (!widget.matchTheme) return data.adaptiveTone;
    final colors = [
      theme.scaffoldBackgroundColor,
      theme.colorScheme.onSurface,
      theme.colorScheme.onSurfaceVariant,
    ];
    final cached = _themedColors;
    if (identical(_themedData, data) &&
        cached != null &&
        cached[0] == colors[0] &&
        cached[1] == colors[1] &&
        cached[2] == colors[2]) {
      return _themedTone!;
    }
    _themedData = data;
    _themedColors = colors;
    return _themedTone = CoverTone.themed(
      data.samples,
      surface: colors[0],
      onSurface: colors[1],
      onSurfaceVariant: colors[2],
    );
  }

  Widget _layer(CoverBackdropData data, ThemeData theme) => Stack(
    fit: StackFit.expand,
    children: [
      RawImage(
        image: data.image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
      ColoredBox(color: _toneOf(data, theme).scrim),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previous = _previous, current = _current;
    final shown = previous != null && !_newTone ? previous : current;
    final tone = shown == null
        ? BlurredCoverTheme._themeTone(theme.colorScheme)
        : _toneOf(shown, theme);
    final backdrop = IgnorePointer(
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: ClipRRect(
            borderRadius: widget.radius ?? BorderRadius.zero,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (previous != null)
                  FadeTransition(
                    opacity: current == null
                        ? _reverse
                        : const AlwaysStoppedAnimation(1),
                    child: _layer(previous, theme),
                  ),
                if (current != null)
                  FadeTransition(
                    opacity: _curve,
                    child: _layer(current, theme),
                  ),
                if (widget.fadeBottom && (previous != null || current != null))
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.scaffoldBackgroundColor.withAlpha(0),
                          theme.scaffoldBackgroundColor,
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: backdrop),
        BlurredCoverTheme(
          tone: tone,
          active: shown != null,
          child: DefaultTextStyle.merge(
            style: shown == null ? null : TextStyle(color: tone.foreground),
            child: IconTheme.merge(
              data: IconThemeData(
                color: shown == null ? null : tone.foreground,
              ),
              child: widget.child,
            ),
          ),
        ),
      ],
    );
  }
}
