import 'package:flutter/material.dart';

import '../../theme/brasa_theme.dart';
import '../studio/studio_symbols.dart';
import 'mini_player_desktop_controls.dart'
    show
        kMiniControlTarget,
        kMiniVolumeSlider,
        miniDesktopFull,
        miniDesktopNoSlider;
import 'mini_player_model.dart';

/// Zona derecha de la barra de Brasa: silencio, cola, ecualizador, letras (y
/// «Mini reproductor» si hay ventana que reducir) con iconos en tono nube y
/// volumen con relleno de brasa. Se adapta al ancho recibido: completo →
/// sin volumen → menú «⋯». Nunca desborda. Mismos tooltips y semántica que
/// `MiniPlayerDesktopControls`.
class BrasaMiniControls extends StatelessWidget {
  const BrasaMiniControls({
    super.key,
    required this.state,
    required this.actions,
    this.compact = false,
  });

  final MiniPlayerState state;
  final MiniPlayerActions actions;

  /// Fuerza la variante sin slider de volumen.
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
                  size: 20,
                  color: onTap == null
                      ? Brasa.cloud.withValues(alpha: .38)
                      : Brasa.cloud,
                ),
                if (marked)
                  const Positioned(
                    right: -3,
                    top: -3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Brasa.ember,
                        shape: BoxShape.circle,
                      ),
                      child: SizedBox.square(dimension: 6),
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
        activeTrackColor: Brasa.ember,
        inactiveTrackColor: Brasa.surface3,
        disabledActiveTrackColor: Brasa.ember.withValues(alpha: .4),
        disabledInactiveTrackColor: Brasa.surface3,
        thumbColor: Brasa.ember,
        overlayColor: Brasa.ember.withValues(alpha: .14),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        semanticFormatterCallback: (value) =>
            'Volumen ${(value * 100).round()} por ciento',
        value: state.volume.clamp(0.0, 1.0),
        onChanged: state.canSetVolume ? actions.setVolume : null,
      ),
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

  Widget _menu() => SizedBox.square(
    dimension: kMiniControlTarget,
    child: PopupMenuButton<void>(
      tooltip: 'Más acciones',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz_rounded, size: 20, color: Brasa.cloud),
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
              'Letras',
              StudioSymbols.lyrics,
              state.lyricsAvailable ? actions.openLyrics : null,
            ),
            _button(_queueTip, StudioSymbols.queueMusic, actions.openQueue),
            _button(
              _eqTip,
              StudioSymbols.equalizer,
              state.equalizerAvailable ? actions.openEqualizer : null,
              marked: state.equalizerAvailable && state.equalizerActive,
            ),
            _button(
              _muteTip,
              _volumeIcon,
              state.canSetVolume ? actions.toggleMute : null,
            ),
            if (slider) _slider(context),
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
        child: Align(alignment: Alignment.centerRight, child: content),
      );
    },
  );
}
