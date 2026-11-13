import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import '../../theme/brasa_widgets.dart';
import '../artwork.dart';
import 'brasa_mini_controls.dart';
import 'mini_player_desktop_controls.dart'
    show MiniPlayerInfoTap, miniDesktopFull, miniDesktopNoSlider;
import 'mini_player_model.dart';
import 'mini_player_theme.dart';

/// Mini reproductor de Brasa: barra FLOTANTE de tono `bar` (sin bordes entre
/// zonas), con sombra ancha y un filo de luz del 7 %. Escritorio: tres zonas
/// (portada + título + corazón, transporte con el filamento de brasa debajo,
/// letras/cola/volumen). Móvil: tarjeta compacta sobre la navegación, con el
/// filamento de 3 px en el borde inferior. La brasa solo marca lo vivo: el
/// botón de reproducir, el progreso y el volumen.
const MiniPlayerTheme brasaMiniPlayer = MiniPlayerTheme(build: _build);

Widget _build(
  BuildContext context,
  MiniPlayerState state,
  MiniPlayerActions actions, {
  required bool wide,
}) => BrasaMiniPlayer(state: state, actions: actions, wide: wide);

/// Ancho de la tarjeta móvil desde el que se añade «siguiente»; por debajo
/// basta con deslizar.
const _kNextMinInner = 340.0;
const _error = Color(0xffff8a7a);

/// Hora `m:ss` (`h:mm:ss` desde la hora).
@visibleForTesting
String brasaClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = s % 3600 ~/ 60, sec = s % 60;
  final tail = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$tail' : '$m:$tail';
}

class BrasaMiniPlayer extends StatelessWidget {
  const BrasaMiniPlayer({
    super.key,
    required this.state,
    required this.actions,
    required this.wide,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (state.track == null) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
    return wide
        ? Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: _Floating(
              radius: 20,
              minHeight: 88 * scale,
              child: _Desktop(state: state, actions: actions, scale: scale),
            ),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _Floating(
              radius: 18,
              minHeight: 64 * scale,
              child: _Mobile(state: state, actions: actions),
            ),
          );
  }
}

/// Tarjeta flotante: sombra ancha en su propia capa cacheada (no se repinta con
/// el progreso) y filo de luz del 7 % por dentro.
class _Floating extends StatelessWidget {
  const _Floating({
    required this.radius,
    required this.minHeight,
    required this.child,
  });

  final double radius, minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            child: RepaintBoundary(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: shape,
                  boxShadow: Brasa.floatShadow,
                ),
              ),
            ),
          ),
        ),
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: Colors.white.withValues(alpha: .07)),
          ),
          child: Material(
            color: Brasa.bar,
            borderRadius: shape,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

class _Desktop extends StatelessWidget {
  const _Desktop({
    required this.state,
    required this.actions,
    required this.scale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        // Zona derecha: completa con volumen desde 1000 px, sin volumen desde
        // 760 y, por debajo, solo el menú «⋯».
        final controls = w >= 1000
            ? miniDesktopFull(actions)
            : w >= 760
            ? miniDesktopNoSlider(actions)
            : 44.0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Row(
                  children: [
                    Expanded(
                      child: MiniPlayerInfoTap(
                        actions: actions,
                        child: _Info(state: state, cover: 56, titleSize: 14),
                      ),
                    ),
                    _Heart(state: state, actions: actions, target: 44),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                flex: 6,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: _Center(
                      state: state,
                      actions: actions,
                      scale: scale,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: controls,
                child: BrasaMiniControls(
                  state: state,
                  actions: actions,
                  compact: w < 1000,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Transporte y, debajo, tiempos mono con el filamento de seek.
class _Center extends StatefulWidget {
  const _Center({
    required this.state,
    required this.actions,
    required this.scale,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final double scale;

  @override
  State<_Center> createState() => _CenterState();
}

class _CenterState extends State<_Center> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final s = widget.state, actions = widget.actions;
    final value = (_drag ?? s.progress).clamp(0.0, 1.0);
    final length = s.duration > Duration.zero ? s.duration : s.track!.duration;
    final timeStyle = Brasa.mono(11, color: Brasa.cloud, tracking: .04);
    final filament = BrasaFilament(
      value: value,
      height: 4,
      hitHeight: 20,
      onChanged: s.canSeek ? (v) => setState(() => _drag = v) : null,
      onChangeEnd: s.canSeek
          ? (v) {
              setState(() => _drag = null);
              actions.seek(v);
            }
          : null,
      semanticLabel: 'Posición',
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Key(
              label: s.shuffle ? 'Aleatorio (activado)' : 'Aleatorio',
              onTap: s.canShuffle ? actions.toggleShuffle : null,
              fill: s.shuffle ? Brasa.ember.withValues(alpha: .16) : null,
              icon: Icon(
                Icons.shuffle_rounded,
                size: 20,
                color: s.shuffle ? Brasa.ember : Brasa.cloud,
              ),
            ),
            const SizedBox(width: 4),
            _Key(
              label: s.previousLabel('Pista anterior'),
              onTap: s.hasPrevious ? actions.previous : null,
              icon: const Icon(
                Icons.skip_previous_rounded,
                size: 24,
                color: Brasa.cream,
              ),
            ),
            const SizedBox(width: 4),
            _PlayKey(
              state: s,
              onTap: s.canTogglePlay ? actions.togglePlay : null,
              target: 44,
            ),
            const SizedBox(width: 4),
            _NextKey(state: s, actions: actions, target: 44),
          ],
        ),
        const SizedBox(height: 2),
        LayoutBuilder(
          builder: (context, box) {
            final text = MediaQuery.textScalerOf(context).scale(1);
            final times = box.maxWidth >= 190 + 70 * (text - 1);
            if (!times) return filament;
            return Row(
              children: [
                s.hasError
                    ? Text(
                        'ERR',
                        maxLines: 1,
                        style: Brasa.mono(
                          11,
                          color: _error,
                          weight: FontWeight.w700,
                        ),
                      )
                    : Text(
                        brasaClock(length * value),
                        maxLines: 1,
                        style: timeStyle,
                      ),
                const SizedBox(width: 10),
                Expanded(child: filament),
                const SizedBox(width: 10),
                Text(
                  length > Duration.zero ? brasaClock(length) : '--:--',
                  maxLines: 1,
                  style: timeStyle,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Mobile extends StatelessWidget {
  const _Mobile({required this.state, required this.actions});

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final showNext = box.maxWidth >= _kNextMinInner;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _Info(state: state, cover: 52, titleSize: 14),
                  ),
                  _Heart(state: state, actions: actions, target: 48),
                  _PlayKey(
                    state: state,
                    onTap: state.canTogglePlay ? actions.togglePlay : null,
                    target: 48,
                  ),
                  if (showNext)
                    _NextKey(state: state, actions: actions, target: 48),
                ],
              ),
            ),
            // Solo indicador: tocar la tarjeta abre el reproductor.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
              child: BrasaFilament(
                value: state.progress,
                height: 3,
                hitHeight: 5,
                head: false,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Portada (radio 12 en escritorio, 10 en móvil) y, a su lado, título y artista.
class _Info extends StatelessWidget {
  const _Info({
    required this.state,
    required this.cover,
    required this.titleSize,
  });

  final MiniPlayerState state;
  final double cover, titleSize;

  @override
  Widget build(BuildContext context) {
    final track = state.track!;
    final artist = track.artist.trim().isEmpty ? '—' : track.artist;
    final subtitle = state.jamAudio || state.hasError
        ? miniSubtitle(state)
        : artist;
    return Row(
      children: [
        Artwork(
          track: track,
          size: cover,
          radius: cover >= 56 ? 12 : 10,
          artworkContext: ArtworkContext.thumbnail,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Brasa.sans(
                  titleSize,
                  weight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Brasa.sans(
                  12,
                  color: miniSubtitleIsError(state) ? _error : Brasa.cloud,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Heart extends StatelessWidget {
  const _Heart({
    required this.state,
    required this.actions,
    required this.target,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final double target;

  @override
  Widget build(BuildContext context) => _Key(
    label: state.liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
    onTap: actions.toggleLike,
    target: target,
    icon: Icon(
      state.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: 19,
      color: state.liked ? Brasa.ember : Brasa.cloud,
    ),
  );
}

class _NextKey extends StatelessWidget {
  const _NextKey({
    required this.state,
    required this.actions,
    required this.target,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final double target;

  @override
  Widget build(BuildContext context) => _Key(
    label: state.nextLabel('Pista siguiente'),
    onTap: state.hasNext ? actions.next : null,
    target: target,
    icon: Icon(
      state.jamVoteSkip ? Icons.how_to_vote_outlined : Icons.skip_next_rounded,
      size: 24,
      color: Brasa.cream,
    ),
  );
}

/// Tecla con zona táctil de [target] px y un cuadrado visible de 36 (squircle
/// de 10). Sin movimiento reducido encoge al pulsar; con él solo baja la
/// opacidad.
class _Key extends StatefulWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.icon,
    this.target = 44,
    this.chip = 36,
    this.radius = 10,
    this.fill,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget icon;
  final double target, chip, radius;
  final Color? fill;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final enabled = widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Tooltip(
        message: widget.label,
        excludeFromSemantics: true,
        child: SizedBox.square(
          dimension: widget.target,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => setState(() => _down = true),
            onPointerUp: (_) => setState(() => _down = false),
            onPointerCancel: (_) => setState(() => _down = false),
            child: Opacity(
              opacity: enabled ? 1 : .4,
              child: AnimatedScale(
                scale: _down && !reduce ? .92 : 1,
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 100),
                curve: Curves.easeOut,
                child: AnimatedOpacity(
                  opacity: _down && reduce ? .7 : 1,
                  duration: const Duration(milliseconds: 100),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: widget.onTap,
                      customBorder: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(widget.radius + 2),
                      ),
                      child: Center(
                        child: Container(
                          width: widget.chip,
                          height: widget.chip,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: widget.fill,
                            borderRadius: BorderRadius.circular(widget.radius),
                          ),
                          child: widget.icon,
                        ),
                      ),
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
}

/// Reproducir/pausar: squircle de brasa (radio 14) con icono `onEmber`; con
/// búfer, un anillo; con fallo, reintento en rojo.
class _PlayKey extends StatelessWidget {
  const _PlayKey({
    required this.state,
    required this.onTap,
    required this.target,
  });

  final MiniPlayerState state;
  final VoidCallback? onTap;
  final double target;

  @override
  Widget build(BuildContext context) {
    final error = state.hasError;
    final playing = state.isPlaying && !error;
    final label = error
        ? 'Error de reproducción, reintentar'
        : state.jamHostName != null
        ? 'Lo controla ${state.jamHostName}'
        : playing
        ? 'Pausar'
        : 'Reproducir';
    final Widget icon = state.buffering && !error
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Brasa.onEmber,
            ),
          )
        : Icon(
            error
                ? Icons.replay_rounded
                : playing
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            size: 26,
            color: Brasa.onEmber,
          );
    return _Key(
      label: label,
      onTap: onTap,
      target: target,
      chip: target,
      radius: 14,
      fill: error ? _error : Brasa.ember,
      icon: icon,
    );
  }
}
