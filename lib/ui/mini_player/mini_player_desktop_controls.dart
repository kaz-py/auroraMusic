import 'package:flutter/material.dart';

import '../studio/studio_symbols.dart';
import 'mini_player_model.dart';

/// Lado del objetivo táctil de cada botón.
const double kMiniControlTarget = 44;

/// Ancho del slider de volumen.
const double kMiniVolumeSlider = 96;

/// Botones de los controles de escritorio: silencio, cola, ecualizador, letras
/// y modo difuminado (más «Mini reproductor» si hay ventana que reducir).
const int kMiniDesktopButtons = 5;

/// Ancho completo (botones + slider) y sin slider de los controles de
/// escritorio: los temas reservan este ancho en su fila ancha.
double miniDesktopNoSlider(MiniPlayerActions actions) =>
    kMiniControlTarget *
    (kMiniDesktopButtons + (actions.openMini != null ? 1 : 0));
double miniDesktopFull(MiniPlayerActions actions) =>
    miniDesktopNoSlider(actions) + kMiniVolumeSlider;

/// Portada y título del mini en escritorio: el clic abre el menú de la canción
/// ([MiniPlayerActions.openMenu]) anclado en la esquina de esta zona. Sin
/// `openMenu` (móvil) no envuelve nada y el toque lo recoge la barra entera.
class MiniPlayerInfoTap extends StatelessWidget {
  const MiniPlayerInfoTap({
    super.key,
    required this.actions,
    required this.child,
  });

  final MiniPlayerActions actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = actions.openMenu;
    if (open == null) return child;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final box = context.findRenderObject() as RenderBox;
          open(box.localToGlobal(Offset.zero));
        },
        child: Semantics(
          button: true,
          label: 'Opciones de la canción',
          excludeSemantics: false,
          child: child,
        ),
      ),
    );
  }
}

/// Controles de escritorio del mini reproductor (carril ancho): volumen
/// (silencio + slider corto), cola, ecualizador y letras. Los 4 temas lo
/// colocan en su fila ancha y solo le pasan su color.
///
/// - Cada botón mide 44×44 y lleva tooltip y semántica propios; el slider
///   anuncia «Volumen N por ciento».
/// - Se adapta al ancho que recibe (póngalo en un `SizedBox`/`Flexible`; sin
///   límite usa el tamaño completo): completo (slider + 3 botones) →
///   [compact] sin slider (el volumen es solo el botón de silencio) → menú «⋯»
///   (silencio, cola, ecualizador, letras). Nunca desborda.
/// - [compact] fuerza directamente la variante sin slider.
/// - El EQ se desactiva si `state.equalizerAvailable` es falso; letras, si no
///   hay pista. El EQ activo se marca con un punto del color del tema.
/// - [color]: color de iconos y slider; el tema es responsable de que alcance
///   contraste ≥ 3 con su fondo (la pista inactiva del slider usa el mismo
///   color con menos opacidad). Los botones desactivados lo atenúan.
class MiniPlayerDesktopControls extends StatelessWidget {
  const MiniPlayerDesktopControls({
    super.key,
    required this.state,
    required this.actions,
    required this.color,
    this.iconSize = 20,
    this.compact = false,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;
  final Color color;
  final double iconSize;
  final bool compact;

  IconData get _volumeIcon => state.muted
      ? Icons.volume_off_rounded
      : state.volume < .5
      ? Icons.volume_down_rounded
      : StudioSymbols.volumeUp;

  String get _muteTip => state.muted ? 'Quitar silencio' : 'Silenciar';
  String get _queueTip =>
      state.hasQueue ? 'Abrir cola (${state.queueLength})' : 'Abrir cola';
  String get _eqTip => !state.equalizerAvailable
      ? state.equalizerUnavailableReason == null
            ? 'Ecualizador no disponible en este reproductor'
            : 'Ecualizador no disponible: ${state.equalizerUnavailableReason}'
      : 'Ecualizador${state.equalizerActive ? ' (activo)' : ''}';

  Widget _button(
    String tip,
    IconData icon,
    VoidCallback? onTap, {
    bool marked = false,
  }) => Tooltip(
    message: tip,
    child: Semantics(
      button: true,
      enabled: onTap != null,
      label: tip,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox.square(
        dimension: kMiniControlTarget,
        child: InkResponse(
          onTap: onTap,
          radius: kMiniControlTarget / 2,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: iconSize,
                  color: onTap == null ? color.withValues(alpha: .38) : color,
                ),
                if (marked)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox.square(dimension: 6),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _slider(BuildContext context) => SizedBox(
    width: kMiniVolumeSlider,
    height: kMiniControlTarget,
    child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        activeTrackColor: color,
        inactiveTrackColor: color.withValues(alpha: .35),
        thumbColor: color,
        overlayColor: color.withValues(alpha: .12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
      ),
      child: Slider(
        semanticFormatterCallback: (value) =>
            'Volumen ${(value * 100).round()} por ciento',
        value: state.volume.clamp(0.0, 1.0),
        onChanged: state.canSetVolume ? actions.setVolume : null,
      ),
    ),
  );

  Widget _menu() => SizedBox.square(
    dimension: kMiniControlTarget,
    child: PopupMenuButton<void>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz_rounded, size: iconSize, color: color),
      itemBuilder: (_) => [
        _item(_muteTip, _volumeIcon, actions.toggleMute, state.canSetVolume),
        _item(_queueTip, StudioSymbols.queueMusic, actions.openQueue, true),
        _item(
          _eqTip,
          StudioSymbols.equalizer,
          actions.openEqualizer,
          state.equalizerAvailable,
        ),
        _item(
          'Letras',
          StudioSymbols.lyrics,
          actions.openLyrics,
          state.lyricsAvailable,
        ),
        _item(
          'Modo difuminado',
          Icons.blur_on_rounded,
          actions.openBlurred,
          true,
        ),
        if (actions.openMini case final openMini?)
          _item(
            'Mini reproductor',
            Icons.picture_in_picture_alt_rounded,
            openMini,
            true,
          ),
      ],
    ),
  );

  PopupMenuItem<void> _item(
    String text,
    IconData icon,
    VoidCallback onTap,
    bool enabled,
  ) => PopupMenuItem<void>(
    enabled: enabled,
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final room = box.maxWidth;
      final Widget content;
      if (room < miniDesktopNoSlider(actions)) {
        content = _menu();
      } else {
        final slider = !compact && room >= miniDesktopFull(actions);
        content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              _muteTip,
              _volumeIcon,
              state.canSetVolume ? actions.toggleMute : null,
            ),
            if (slider) _slider(context),
            _button(_queueTip, StudioSymbols.queueMusic, actions.openQueue),
            _button(
              _eqTip,
              StudioSymbols.equalizer,
              state.equalizerAvailable ? actions.openEqualizer : null,
              marked: state.equalizerAvailable && state.equalizerActive,
            ),
            _button(
              'Letras',
              StudioSymbols.lyrics,
              state.lyricsAvailable ? actions.openLyrics : null,
            ),
            _button(
              'Modo difuminado',
              Icons.blur_on_rounded,
              actions.openBlurred,
            ),
            if (actions.openMini case final openMini?)
              _button(
                'Mini reproductor',
                Icons.picture_in_picture_alt_rounded,
                openMini,
              ),
          ],
        );
      }
      return Semantics(
        container: true,
        explicitChildNodes: true,
        label: 'Controles del reproductor',
        child: content,
      );
    },
  );
}

/// Ancho fijo que reserva [MiniPlayerTime] (el texto se encoge, no desborda).
const double kMiniTimeWidth = 104;

/// `1:23 / 3:45` en cifras tabulares, solo para filas anchas con holgura. Mide
/// siempre [kMiniTimeWidth]: con tamaños de texto grandes el texto se reduce
/// para caber. Un solo nodo semántico («Tiempo: 1:23 de 3:45»).
class MiniPlayerTime extends StatelessWidget {
  const MiniPlayerTime({super.key, required this.state, required this.color});

  final MiniPlayerState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final known = state.duration > Duration.zero;
    final elapsed = miniClock(known ? state.elapsed : Duration.zero);
    final total = known ? miniClock(state.duration) : '--:--';
    return Semantics(
      label: 'Tiempo: $elapsed de $total',
      excludeSemantics: true,
      child: SizedBox(
        width: kMiniTimeWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            '$elapsed / $total',
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
