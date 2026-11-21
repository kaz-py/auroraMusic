import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import 'cover_backdrop_source.dart';
import 'cover_tone.dart' show coverContrast;
import 'mini_player_model.dart';

/// Piezas compartidas del mini reproductor de Modern (barra flotante de
/// escritorio y tarjeta móvil). Dueño: tema Modern.

/// Acerca [c] a claro (tema oscuro) u oscuro hasta llegar a 3:1 con [bg].
Color modernMiniLegible(Color c, Color bg, bool dark) {
  var hsl = HSLColor.fromColor(c);
  for (var i = 0; i < 100 && coverContrast(c, bg) < 3; i++) {
    hsl = hsl.withLightness((hsl.lightness + (dark ? .01 : -.01)).clamp(0, 1));
    c = hsl.toColor();
  }
  return c;
}

/// Cambio de icono: escala 0,8 → 1 con fundido; con movimiento reducido solo
/// fundido.
class ModernMiniSwitch extends StatelessWidget {
  const ModernMiniSwitch({super.key, required this.value, required this.child});
  final Object value;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: Duration(milliseconds: still ? 120 : 180),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => still
          ? FadeTransition(opacity: animation, child: child)
          : FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween(begin: .8, end: 1.0).animate(animation),
                child: child,
              ),
            ),
      child: KeyedSubtree(key: ValueKey(value), child: child),
    );
  }
}

/// Escala 0,96 mientras se pulsa. Sin movimiento reducido no hay escala.
class ModernMiniPress extends StatefulWidget {
  const ModernMiniPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  State<ModernMiniPress> createState() => _ModernMiniPressState();
}

class _ModernMiniPressState extends State<ModernMiniPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && widget.enabled && !still ? .96 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Título + línea secundaria (artista, aviso de Jam o fallo del motor). La
/// semántica y los textos son los de siempre; solo cambia la piel.
class ModernMiniText extends StatelessWidget {
  const ModernMiniText({
    super.key,
    required this.state,
    this.titleSize = 14.5,
    this.titleLines = 1,
  });

  final MiniPlayerState state;
  final double titleSize;
  final int titleLines;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final error = Theme.of(context).colorScheme.error;
    final isError = miniSubtitleIsError(state);
    final secondary = Cristal.ui(
      12.5,
      weight: 500,
      color: c.text2,
      height: 1.25,
    );
    final String? note = isError
        ? miniErrorNotice
        : state.jamHostName != null
        ? 'Lo controla ${state.jamHostName}'
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.track!.title,
          maxLines: titleLines,
          overflow: TextOverflow.ellipsis,
          style: Cristal.ui(
            titleSize,
            weight: 700,
            color: c.text,
            height: 1.2,
            tracking: -.01,
          ),
        ),
        if (note != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isError) ...[
                Icon(Icons.error_outline_rounded, size: 14, color: error),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  note,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary.copyWith(color: isError ? error : c.text2),
                ),
              ),
            ],
          )
        else
          Text(
            miniSubtitle(state),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary,
          ),
      ],
    );
  }
}

/// Color de aura de la portada (el más vivo) para teñir el cristal. Usa la
/// caché compartida (sin decodificar de nuevo); `null` mientras no hay datos.
class ModernMiniTint extends StatefulWidget {
  const ModernMiniTint({super.key, required this.track, required this.builder});

  final Track? track;
  final Widget Function(BuildContext context, Color? tint) builder;

  @override
  State<ModernMiniTint> createState() => _ModernMiniTintState();
}

class _ModernMiniTintState extends State<ModernMiniTint> {
  Color? _tint;
  String? _key;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ModernMiniTint old) {
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
      _tint = null;
      return;
    }
    final hit = cache.peek(track);
    if (hit != null) {
      _tint = modernAuraColors(hit.samples).$1;
      return;
    }
    cache.load(track).then((data) {
      if (!mounted || _key != key) return;
      setState(
        () => _tint = data == null ? null : modernAuraColors(data.samples).$1,
      );
    });
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
    tween: ColorTween(end: _tint ?? const Color(0x00000000)),
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400),
    builder: (context, tint, _) => widget.builder(
      context,
      _tint == null && (tint == null || tint.a == 0) ? null : tint,
    ),
  );
}

/// Botón de utilidad de 44 px con tesela de radio 12: tooltip, semántica y
/// objetivo propios. [active] = tesela de cristal con icono en el acento.
class ModernMiniTile extends StatelessWidget {
  const ModernMiniTile({
    super.key,
    required this.tip,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.iconSize = 20,
  });

  final String tip;
  final IconData icon;
  final VoidCallback? onTap;
  final bool active;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final color = onTap == null
        ? c.text3.withValues(alpha: .5)
        : active
        ? c.accent
        : c.text2;
    return Tooltip(
      message: tip,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        selected: active,
        label: tip,
        excludeSemantics: true,
        onTap: onTap,
        child: ModernMiniPress(
          enabled: onTap != null,
          child: SizedBox.square(
            dimension: 44,
            child: Material(
              color: active ? c.glassHover : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Center(
                  child: Icon(icon, size: iconSize, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
