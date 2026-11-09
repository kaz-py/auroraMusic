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
import 'lyrics_offset_controls.dart';
import 'mini_player/blurred_cover_backdrop.dart';
import 'mini_player/mini_player_model.dart';
import 'undo_snackbar.dart';

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
  // La lista de líneas ya está colocada en la línea activa. Mientras no lo
  // esté se oculta (sin parpadeo de las primeras líneas) y el primer
  // posicionamiento es un salto, no un desplazamiento animado.
  bool _placed = false;
  bool _revealing = false;
  int _revealGen = 0;
  int _lineCount = 0;
  double? _drag;
  bool _fullscreen = false;
  int _offsetMs = 0;
  final Map<int, GlobalKey> _lineKeys = {};
  final _lineScroll = ScrollController();
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
    if (_fullscreen) unawaited(WindowControls.setFullscreen(false));
    _plainScroll.dispose();
    _lineScroll.dispose();
    super.dispose();
  }

  void _changed() {
    final track = widget.controller.nowTrack;
    if (track?.id == _trackId) return;
    _trackId = track?.id;
    _request++;
    _lastActive = -1;
    _placed = false;
    _revealing = false;
    _revealGen++;
    _lineKeys.clear();
    _offsetMs = 0;
    _result = null;
    _loading = false;
    if (track != null) {
      unawaited(_load(track));
      unawaited(
        _service.readOffset(track, widget.controller.supportDirectory).then((
          v,
        ) {
          if (mounted && _trackId == track.id) setState(() => _offsetMs = v);
        }),
      );
    }
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
      if (result.kind == LyricsKind.plain) {
        unawaited(_upgrade(track, request));
      }
    } catch (_) {
      // Sin letra: se muestra el aviso de siempre.
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _setOffset(int ms) {
    final track = widget.controller.nowTrack;
    if (track == null) return;
    final value = ms.clamp(
      -LyricsService.maxOffsetMs,
      LyricsService.maxOffsetMs,
    );
    setState(() => _offsetMs = value);
    unawaited(
      _service.writeOffset(track, widget.controller.supportDirectory, value),
    );
  }

  /// La letra llegó sin sincronizar: se busca una versión sincronizada que
  /// case (ver [LyricsService.upgradeToSynced]) y, si hay, se usa.
  Future<void> _upgrade(Track track, int request) async {
    try {
      final result = await _service.upgradeToSynced(
        track,
        widget.controller.supportDirectory,
      );
      if (result == null || !mounted || request != _request) return;
      // `upgradeToSynced` puede haber fijado un desfase inicial.
      final offset = await _service.readOffset(
        track,
        widget.controller.supportDirectory,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _offsetMs = offset;
        _result = result;
        _lastActive = -1;
        _placed = false;
        _revealing = false;
        _revealGen++;
        _lineKeys.clear();
      });
    } catch (_) {
      // Se queda la letra aproximada.
    }
  }

  /// Aviso cuando la búsqueda terminó sin letra; `null` si hay letra o aún se
  /// busca. Sin letra la página muestra solo la portada, centrada.
  String? get _noLyricsLabel {
    final r = _result;
    if (r == null) return _loading ? null : 'Sin letra para esta pista';
    return switch (r.kind) {
      LyricsKind.notFound => 'Sin letra para esta pista',
      LyricsKind.instrumental => 'Instrumental',
      _ => null,
    };
  }

  /// Texto de la letra para copiar; `null` si no hay.
  String? _copyText() {
    final r = _result;
    if (r == null) return null;
    final text = switch (r.kind) {
      LyricsKind.synced => r.lines.map((l) => l.text).join('\n'),
      LyricsKind.plain => r.text,
      _ => '',
    };
    return text.trim().isEmpty ? null : text;
  }

  Future<void> _copy() async {
    final text = _copyText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showUndoSnackBar(
      ScaffoldMessenger.maybeOf(context),
      const Text('Letra copiada'),
    );
  }

  Future<void> _setFullscreen(bool on) async {
    if (!WindowControls.fullscreenSupported || on == _fullscreen) return;
    if (await WindowControls.setFullscreen(on) && mounted) {
      setState(() => _fullscreen = on);
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
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _fullscreen ? _setFullscreen(false) : widget.onClose(),
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            _setFullscreen(!_fullscreen),
      },
      child: Focus(
        autofocus: true,
        child: _frame(context, state, actions, tone, track),
      ),
    );
  }

  /// Barra superior: zona de arrastre (la ventana no tiene marco), salir del
  /// modo y, en Windows, minimizar / maximizar / cerrar la ventana.
  Widget _topBar(BuildContext context, CoverTone tone, bool compact) {
    ButtonStyle style() => IconButton.styleFrom(
      minimumSize: const Size.square(44),
      fixedSize: const Size.square(44),
      padding: EdgeInsets.zero,
    );
    return Row(
      children: [
        _exit(context, tone, compact),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Copiar letra',
          icon: const Icon(Icons.copy_rounded),
          onPressed: _copyText() == null ? null : _copy,
          style: style(),
        ),
        if (!compact && _result?.kind == LyricsKind.synced)
          LyricsOffsetControls(offsetMs: _offsetMs, onChanged: _setOffset),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: _fullscreen
                ? null
                : (_) => WindowControls.invoke('drag'),
            onDoubleTap: () => _fullscreen
                ? _setFullscreen(false)
                : WindowControls.invoke('maximize'),
            child: const SizedBox(height: 44),
          ),
        ),
        if (WindowControls.fullscreenSupported)
          IconButton(
            tooltip: _fullscreen
                ? 'Salir de pantalla completa'
                : 'Pantalla completa',
            onPressed: () => _setFullscreen(!_fullscreen),
            icon: Icon(
              _fullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
            ),
            style: style(),
          ),
        if (WindowControls.supported) ...[
          // En ventana estrecha no caben todos los botones: minimizar y
          // maximizar ceden sitio a copiar, pantalla completa y cerrar.
          if (!compact) ...[
            IconButton(
              tooltip: 'Minimizar',
              onPressed: () => WindowControls.invoke('minimize'),
              icon: const Icon(Icons.remove_rounded),
              style: style(),
            ),
            if (!_fullscreen)
              IconButton(
                tooltip: 'Maximizar o restaurar',
                onPressed: () => WindowControls.invoke('maximize'),
                icon: const Icon(Icons.crop_square_rounded, size: 20),
                style: style(),
              ),
          ],
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

  /// Botón de salir: con texto y flecha, arriba a la izquierda, donde se busca
  /// el «volver» (un icono suelto no se entiende). Esc hace lo mismo.
  Widget _exit(BuildContext context, CoverTone tone, bool compact) => Tooltip(
    message: 'Salir del modo letra',
    child: Semantics(
      button: true,
      label: 'Salir del modo letra',
      excludeSemantics: true,
      child: Material(
        color: tone.foreground.withValues(alpha: .16),
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: widget.onClose,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_rounded,
                    size: 20,
                    color: tone.foreground,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    compact ? 'Salir' : 'Salir del modo letra',
                    style: TextStyle(
                      color: tone.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

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
              // SafeArea: en Android la barra de estado y la de navegación
              // no deben tapar «Salir» ni los controles (en pantalla completa
              // inmersiva los márgenes valen 0).
              final page = SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 16 : 40,
                    8,
                    compact ? 16 : 40,
                    12,
                  ),
                  child: Column(
                    children: [
                      _topBar(context, tone, compact),
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
      final label = _noLyricsLabel;
      if (label != null) {
        return _noLyricsBody(context, state, actions, track, tone, label, box);
      }
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
  ) {
    final label = _noLyricsLabel;
    if (label != null) {
      return LayoutBuilder(
        builder: (context, box) =>
            _noLyricsBody(context, state, actions, track, tone, label, box),
      );
    }
    return Column(
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
  }

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

  /// Sin letra: una sola portada, centrada en la página, con el progreso y el
  /// título debajo. El aviso se oculta solo a los pocos segundos.
  Widget _noLyricsBody(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerActions actions,
    Track track,
    CoverTone tone,
    String label,
    BoxConstraints box,
  ) {
    // La portada deja sitio al progreso, al título y al aviso bajo ella.
    final cover = math.max(
      96.0,
      math.min(math.min(box.maxWidth, 440.0), box.maxHeight - 170),
    );
    return Center(
      child: SizedBox(
        width: cover,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _identity(context, state, actions, track, tone, cover),
            const SizedBox(height: 8),
            _FadingNotice(
              key: ValueKey(track.id),
              label: label,
              style: TextStyle(color: tone.secondary),
            ),
          ],
        ),
      ),
    );
  }

  /// Lleva la línea activa a su sitio. Con [jump] (primera colocación) salta sin
  /// animar: el ListView es perezoso y la línea puede no estar construida, así
  /// que se salta a una posición estimada y se reintenta hasta que exista.
  void _reveal({required int gen, required bool jump, int tries = 0}) {
    if (!mounted || gen != _revealGen) return;
    final ctx = _lineKeys[_lastActive]?.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(
        ctx,
        alignment: .35,
        duration: jump || MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      if (jump) {
        _revealing = false;
        setState(() => _placed = true);
      }
      return;
    }
    if (!jump) return;
    if (tries >= 8 || _lineCount == 0) {
      _revealing = false;
      setState(() => _placed = true);
      return;
    }
    if (_lineScroll.hasClients && _lineScroll.position.hasContentDimensions) {
      final p = _lineScroll.position;
      final total = p.maxScrollExtent + p.viewportDimension;
      p.jumpTo(
        (total * _lastActive / _lineCount).clamp(0.0, p.maxScrollExtent),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _reveal(gen: gen, jump: true, tries: tries + 1),
    );
    WidgetsBinding.instance.ensureVisualUpdate();
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
    if (result == null ||
        result.kind == LyricsKind.notFound ||
        result.kind == LyricsKind.instrumental) {
      // Sin letra no se llega aquí (ver [_noLyricsLabel]): solo «buscando».
      return Center(child: Text('Buscando letra…', style: message));
    }
    final size = large ? 30.0 : 22.0;
    if ((result.kind == LyricsKind.plain || result.lines.isEmpty) &&
        state.duration <= Duration.zero) {
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
    // Sin sincronizar (LRCLIB no tiene versión que case con esta duración): las
    // líneas se reparten a lo largo de la pista para que la letra avance igual.
    final approx = result.kind == LyricsKind.plain || result.lines.isEmpty
        ? LyricsService.spreadLines(result.text, state.duration)
        : const <LyricLine>[];
    final isApprox = approx.isNotEmpty;
    final lines = isApprox ? approx : result.lines;
    final position = widget.controller.audio.position;
    final active = lines.lastIndexWhere(
      (line) => line.at.inMilliseconds <= position.inMilliseconds + _offsetMs,
    );
    _lineCount = lines.length;
    // Antes de la primera línea no hay nada que centrar: el inicio es correcto.
    if (!_placed && active < 0) _placed = true;
    final changed = active != _lastActive;
    _lastActive = active;
    if (!_placed) {
      if (!_revealing) {
        _revealing = true;
        final gen = _revealGen;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _reveal(gen: gen, jump: true),
        );
      }
    } else if (changed) {
      final gen = _revealGen;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _reveal(gen: gen, jump: false),
      );
    }
    final list = Opacity(
      opacity: _placed ? 1 : 0,
      child: ShaderMask(
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
          controller: _lineScroll,
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
                // La línea activa va en blanco, grande y en negrita; el resto se
                // atenúa y se encoge, para que se vea de un vistazo por dónde va.
                child: AnimatedDefaultTextStyle(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  style: TextStyle(
                    color: on
                        ? tone.foreground
                        : tone.secondary.withValues(alpha: .55),
                    fontSize: on ? size * 1.12 : size * .88,
                    height: 1.25,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  ),
                  child: Text(line.text.isEmpty ? '♪' : line.text),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (!isApprox) return list;
    return Stack(
      children: [
        list,
        Positioned(
          top: 0,
          left: 0,
          child: Text(
            'Sincronización aproximada',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tone.secondary),
          ),
        ),
      ],
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

/// Aviso de «sin letra»: se muestra unos segundos y se desvanece solo.
class _FadingNotice extends StatefulWidget {
  const _FadingNotice({super.key, required this.label, required this.style});

  final String label;
  final TextStyle style;

  @override
  State<_FadingNotice> createState() => _FadingNoticeState();
}

class _FadingNoticeState extends State<_FadingNotice> {
  bool _visible = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: _visible ? 1 : 0,
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 400),
    child: Text(widget.label, textAlign: TextAlign.center, style: widget.style),
  );
}
