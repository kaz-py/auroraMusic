import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../core/window_controls.dart';
import '../jam/jam_controller.dart';
import '../lyrics/lyrics_service.dart';
import 'artwork.dart';
import 'mini_player/blurred_cover_backdrop.dart';
import 'mini_player/mini_player_model.dart';

/// Alto mínimo de la página: por debajo, todo se desplaza.
const _minPageHeight = 480.0;

/// «Modo artista»: página inmersiva (portada difuminada a pantalla completa,
/// portada grande con progreso y título a la izquierda, letra sincronizada a la
/// derecha y los controles abajo). Mientras está abierta se oculta la barra de
/// reproducción de abajo (`MiniPlayerHost.isVisible`): los controles viven aquí.
///
/// Los textos usan el tono de `BlurredCoverTheme`, que garantiza el contraste
/// sobre cualquier portada; sin portada se ven con los colores del tema.
/// Los permisos de la Jam y los errores salen de [MiniPlayerState] y
/// [MiniPlayerActions], igual que la barra.
class ArtistModePage extends StatefulWidget {
  const ArtistModePage({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onTogglePlay,
    this.jam,
    this.service,
  });

  final AppController controller;
  final JamController? jam;

  /// Sale del modo (vuelve a Inicio).
  final VoidCallback onClose;
  final VoidCallback onTogglePlay;

  /// Servicio de letras (pruebas); por defecto el de la app.
  final LyricsService? service;

  @override
  State<ArtistModePage> createState() => _ArtistModePageState();
}

class _ArtistModePageState extends State<ArtistModePage> {
  late final LyricsService _service = widget.service ?? LyricsService();
  LyricsResult? _result;
  bool _loading = false;
  String? _trackId;
  int _request = 0;
  int _lastActive = -1;
  double? _drag;
  final Map<int, GlobalKey> _lineKeys = {};
  final _plainScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _plainScroll.dispose();
    super.dispose();
  }

  void _changed() {
    final track = widget.controller.nowTrack;
    if (track?.id == _trackId) return;
    _trackId = track?.id;
    _request++;
    _lastActive = -1;
    _lineKeys.clear();
    _result = null;
    _loading = false;
    if (track != null) unawaited(_load(track));
  }

  Future<void> _load(Track track) async {
    final request = _request;
    setState(() => _loading = true);
    try {
      final result = await _service.load(
        track,
        widget.controller.supportDirectory,
      );
      if (!mounted || request != _request) return;
      setState(() => _result = result);
    } catch (_) {
      // Sin letra: se muestra el aviso de siempre.
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, c.audio, ?widget.jam]),
      builder: (context, _) {
        final state = MiniPlayerState.fromController(c, jam: widget.jam);
        final actions = MiniPlayerActions.forController(
          c,
          jam: widget.jam,
          openPlayer: widget.onClose,
          togglePlay: widget.onTogglePlay,
        );
        return BlurredCoverBackdrop(
          track: state.track,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Builder(
              builder: (context) => _content(context, state, actions),
            ),
          ),
        );
      },
    );
  }

  Widget _content(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
  ) {
    final tone = BlurredCoverTheme.of(context);
    final track = state.track;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: Focus(
        autofocus: true,
        child: _frame(context, state, actions, tone, track),
      ),
    );
  }

  /// Barra superior: zona de arrastre (la ventana no tiene marco), salir del
  /// modo y, en Windows, minimizar / maximizar / cerrar la ventana.
  Widget _topBar() {
    ButtonStyle style() => IconButton.styleFrom(
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
    );
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (_) => WindowControls.invoke('drag'),
            onDoubleTap: () => WindowControls.invoke('maximize'),
            child: const SizedBox(height: 44),
          ),
        ),
        IconButton(
          tooltip: 'Salir del modo artista',
          onPressed: widget.onClose,
          icon: const Icon(Icons.fullscreen_exit_rounded),
          style: style(),
        ),
        if (WindowControls.supported) ...[
          IconButton(
            tooltip: 'Minimizar',
            onPressed: () => WindowControls.invoke('minimize'),
            icon: const Icon(Icons.remove_rounded),
            style: style(),
          ),
          IconButton(
            tooltip: 'Maximizar o restaurar',
            onPressed: () => WindowControls.invoke('maximize'),
            icon: const Icon(Icons.crop_square_rounded, size: 20),
            style: style(),
          ),
          IconButton(
            tooltip: 'Cerrar la ventana',
            onPressed: () => WindowControls.invoke('close'),
            icon: const Icon(Icons.close_rounded),
            style: style(),
          ),
        ],
      ],
    );
  }

  Widget _frame(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    CoverTone tone,
    Track? track,
  ) {
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: tone.foreground),
        child: IconTheme.merge(
          data: IconThemeData(color: tone.foreground),
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < 760;
              final page = Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 40,
                  8,
                  compact ? 16 : 40,
                  12,
                ),
                child: Column(
                  children: [
                    _topBar(),
                    Expanded(
                      child: track == null
                          ? Center(
                              child: Text(
                                'No suena nada',
                                style: TextStyle(color: tone.secondary),
                              ),
                            )
                          : compact
                          ? _compactBody(context, state, actions, track, tone)
                          : _wideBody(context, state, actions, track, tone),
                    ),
                    _controls(context, state, actions, tone),
                  ],
                ),
              );
              // Con la página muy baja (barras, texto grande) todo se
              // desplaza en lugar de desbordar.
              final h = box.hasBoundedHeight
                  ? math.max(box.maxHeight, _minPageHeight)
                  : _minPageHeight;
              return h > box.maxHeight
                  ? SingleChildScrollView(
                      child: SizedBox(height: h, child: page),
                    )
                  : page;
            },
          ),
        ),
      ),
    );
  }

  Widget _wideBody(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    Track track,
    CoverTone tone,
  ) => LayoutBuilder(
    builder: (context, box) {
      final left = math.min(box.maxWidth * .38, 440.0);
      // La portada deja sitio al progreso y al título bajo ella.
      final cover = math.max(96.0, math.min(left, box.maxHeight - 150));
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: left,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: cover,
                child: _identity(context, state, actions, track, tone, cover),
              ),
            ),
          ),
          const SizedBox(width: 48),
          Expanded(child: _lyrics(context, state, actions, tone, large: true)),
        ],
      );
    },
  );

  Widget _compactBody(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    Track track,
    CoverTone tone,
  ) => Column(
    children: [
      Row(
        children: [
          Artwork(
            track: track,
            size: 72,
            artworkContext: ArtworkContext.thumbnailDetail,
            radius: 8,
          ),
          const SizedBox(width: 12),
          Expanded(child: _titles(context, state, track, tone)),
        ],
      ),
      const SizedBox(height: 4),
      _progress(context, state, actions, tone),
      const SizedBox(height: 8),
      Expanded(child: _lyrics(context, state, actions, tone, large: false)),
    ],
  );

  /// Portada, progreso, título y artista (columna izquierda).
  Widget _identity(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    Track track,
    CoverTone tone,
    double cover,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        label: 'Portada de ${track.title}',
        child: Artwork(
          track: track,
          size: cover,
          artworkContext: ArtworkContext.playerDetail,
          radius: 6,
        ),
      ),
      const SizedBox(height: 4),
      _progress(context, state, actions, tone),
      _titles(context, state, track, tone, center: true),
    ],
  );

  Widget _titles(
    BuildContext context,
    MiniPlayerState state,
    Track track,
    CoverTone tone, {
    bool center = false,
  }) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: text.titleMedium?.copyWith(
            color: tone.foreground,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          miniSubtitle(state),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: text.bodyMedium?.copyWith(color: tone.secondary),
        ),
      ],
    );
  }

  Widget _progress(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    CoverTone tone,
  ) {
    final value = (_drag ?? state.progress).clamp(0.0, 1.0);
    final shown = state.duration * value;
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: tone.secondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Text(miniClock(shown), style: small),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: tone.foreground,
                inactiveTrackColor: tone.foreground.withValues(alpha: .3),
                thumbColor: tone.foreground,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                semanticFormatterCallback: (_) =>
                    'Posición ${miniClock(shown)}',
                value: value,
                onChanged: state.canSeek
                    ? (v) => setState(() => _drag = v)
                    : null,
                onChangeEnd: state.canSeek
                    ? (v) {
                        setState(() => _drag = null);
                        actions.seek(v);
                      }
                    : null,
              ),
            ),
          ),
          Text(
            state.duration > Duration.zero
                ? miniClock(state.duration)
                : '--:--',
            style: small,
          ),
        ],
      ),
    );
  }

  Widget _lyrics(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    CoverTone tone, {
    required bool large,
  }) {
    final result = _result;
    final message = TextStyle(color: tone.secondary);
    if (_loading && result == null) {
      return Center(child: Text('Buscando letra…', style: message));
    }
    if (result == null || result.kind == LyricsKind.notFound) {
      return Center(child: Text('Sin letra para esta pista', style: message));
    }
    if (result.kind == LyricsKind.instrumental) {
      return Center(child: Text('Instrumental', style: message));
    }
    final size = large ? 30.0 : 22.0;
    if (result.kind == LyricsKind.plain || result.lines.isEmpty) {
      return Scrollbar(
        controller: _plainScroll,
        child: SingleChildScrollView(
          controller: _plainScroll,
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            result.text,
            style: TextStyle(
              color: tone.foreground,
              fontSize: size * .7,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final lines = result.lines;
    final position = widget.controller.audio.position;
    final active = lines.lastIndexWhere(
      (line) => line.at.inMilliseconds <= position.inMilliseconds,
    );
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _lineKeys[active]?.currentContext;
        if (key != null && mounted) {
          Scrollable.ensureVisible(
            key,
            alignment: .35,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    return ShaderMask(
      // Las líneas se funden arriba y abajo, como en el reproductor de Apple.
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0x00FFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: [0, .12, .88, 1],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(vertical: large ? 120 : 60),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final line = lines[i];
          final on = i == active;
          return Padding(
            key: _lineKeys.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: state.canSeek && state.duration > Duration.zero
                  ? () => actions.seek(
                      line.at.inMilliseconds / state.duration.inMilliseconds,
                    )
                  : null,
              child: Text(
                line.text.isEmpty ? '♪' : line.text,
                style: TextStyle(
                  color: on ? tone.foreground : tone.secondary,
                  fontSize: size,
                  height: 1.25,
                  fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controls(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    CoverTone tone,
  ) {
    final c = widget.controller;
    ButtonStyle style() => IconButton.styleFrom(
      fixedSize: const Size.square(48),
      minimumSize: const Size.square(48),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final ink = tone.foreground.computeLuminance() > .5
        ? const Color(0xff151312)
        : const Color(0xfffffaf5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Aleatorio',
          isSelected: c.shuffle,
          onPressed: () => c.setShuffle(!c.shuffle),
          style: style(),
          icon: Icon(
            Icons.shuffle_rounded,
            color: c.shuffle ? tone.foreground : tone.secondary,
          ),
        ),
        IconButton(
          tooltip: state.previousLabel(),
          onPressed: state.hasPrevious ? actions.previous : null,
          style: style(),
          icon: const Icon(Icons.skip_previous_rounded, size: 28),
        ),
        IconButton.filled(
          tooltip: state.buffering
              ? 'Cargando'
              : state.isPlaying
              ? 'Pausar'
              : 'Reproducir',
          onPressed: state.canTogglePlay ? actions.togglePlay : null,
          style: IconButton.styleFrom(
            backgroundColor: tone.foreground,
            foregroundColor: ink,
            disabledBackgroundColor: tone.foreground.withValues(alpha: .38),
            fixedSize: const Size.square(52),
            minimumSize: const Size.square(52),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: state.buffering
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: ink,
                  ),
                )
              : Icon(
                  state.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 30,
                ),
        ),
        IconButton(
          tooltip: state.nextLabel(),
          onPressed: state.hasNext ? actions.next : null,
          style: style(),
          icon: Icon(
            state.jamVoteSkip
                ? Icons.how_to_vote_outlined
                : Icons.skip_next_rounded,
            size: 28,
          ),
        ),
        IconButton(
          tooltip: 'Repetir',
          isSelected: c.repeat != RepeatMode.off,
          onPressed: c.cycleRepeat,
          style: style(),
          icon: Icon(
            c.repeat == RepeatMode.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            color: c.repeat == RepeatMode.off
                ? tone.secondary
                : tone.foreground,
          ),
        ),
      ],
    );
  }
}
