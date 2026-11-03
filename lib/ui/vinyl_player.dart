import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

import '../app_controller.dart';
import '../follow/follow_service.dart';
import '../theme/accent_transition.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import '../theme/slush_theme.dart';
import 'slush/slush_player.dart';
import 'mini_player/blurred_cover_backdrop.dart';
import 'artwork.dart';
import 'cassette_player.dart';
import 'follow_widgets.dart';

class VinylPlayer extends StatefulWidget {
  const VinylPlayer({
    super.key,
    required this.controller,
    this.follow,
    this.onSection,
    this.onBack,
  });

  /// Slush: cambia de sección del shell (0 inicio, 4 vinilo, 5 cola, 6 letras, 13 EQ).
  final ValueChanged<int>? onSection;

  /// Atrás del reproductor (móvil); lo resuelve el shell.
  final VoidCallback? onBack;
  final AppController controller;

  /// Si se pasa, junto al artista aparece «Seguir / Siguiendo».
  final FollowService? follow;

  @override
  State<VinylPlayer> createState() => _VinylPlayerState();
}

class _VinylPlayerState extends State<VinylPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  );
  bool _foreground = true;
  Duration? _dragStartPosition;
  Duration? _dragTarget;
  double? _dragStartX;
  double? _pointerX;
  late bool _cassette =
      widget.controller.preferences.getBool('cassetteMode') ?? false;

  void _setCassette(bool value) {
    setState(() => _cassette = value);
    widget.controller.preferences.setBool('cassetteMode', value);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.audio.addListener(_syncRotation);
    widget.controller.addListener(_syncRotation);
  }

  @override
  void didUpdateWidget(covariant VinylPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.audio.removeListener(_syncRotation);
      oldWidget.controller.removeListener(_syncRotation);
      widget.controller.audio.addListener(_syncRotation);
      widget.controller.addListener(_syncRotation);
      _syncRotation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = _visible(state);
    _syncRotation();
  }

  // Perder el foco (p. ej. otro monitor) no oculta la ventana.
  static bool _visible(AppLifecycleState? s) =>
      s == null ||
      (s != AppLifecycleState.hidden &&
          s != AppLifecycleState.paused &&
          s != AppLifecycleState.detached);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _foreground = _visible(WidgetsBinding.instance.lifecycleState);
    _syncRotation();
  }

  void _syncRotation() {
    if (!mounted) return;
    final motion =
        !widget.controller.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (widget.controller.audio.isPlaying && _foreground && motion) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
    }
  }

  void _updateDragTarget(double artSize, Duration duration) {
    final start = _dragStartPosition;
    final startX = _dragStartX;
    final pointerX = _pointerX;
    if (start == null || startX == null || pointerX == null || artSize <= 0) {
      return;
    }
    _dragTarget = Duration(
      milliseconds:
          (start.inMilliseconds +
                  (pointerX - startX) * duration.inMilliseconds / artSize)
              .round()
              .clamp(0, duration.inMilliseconds),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.audio.removeListener(_syncRotation);
    widget.controller.removeListener(_syncRotation);
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => _withCoverBackdrop(
      isModern(context) || isBrasa(context)
          ? _content(context)
          : ListenableBuilder(
              listenable: widget.controller.audio,
              builder: (context, _) => _content(context),
            ),
    ),
  );

  /// «Fondo difuminado de la portada»: la portada difuminada sube tras la
  /// cabecera y se funde con el fondo del tema (el texto de la pantalla
  /// conserva sus colores; ver `BlurredCoverBackdrop.matchTheme`).
  Widget _withCoverBackdrop(Widget page) {
    final track = widget.controller.currentTrack;
    if (!widget.controller.blurredCoverMode || track == null) return page;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 240,
          child: BlurredCoverBackdrop(
            track: track,
            matchTheme: true,
            fadeBottom: true,
            child: const SizedBox.expand(),
          ),
        ),
        page,
      ],
    );
  }

  Duration _liveDuration() {
    final a = widget.controller.audio.duration;
    return a > Duration.zero
        ? a
        : widget.controller.currentTrack?.duration ?? Duration.zero;
  }

  /// Toque y arrastre horizontal sobre la portada/disco para buscar en la pista.
  Widget _seekable(AppController c, double artSize, Widget child) =>
      GestureDetector(
        onTapUp: (details) {
          final d = _liveDuration();
          if (d <= Duration.zero) return;
          c.seek(
            Duration(
              milliseconds:
                  (d.inMilliseconds *
                          (details.localPosition.dx / artSize).clamp(0.0, 1.0))
                      .round(),
            ),
          );
        },
        onHorizontalDragStart: (_) {
          if (_liveDuration() <= Duration.zero) return;
          _dragStartPosition = c.audio.position;
          _dragTarget = _dragStartPosition;
        },
        onHorizontalDragUpdate: (_) {
          final d = _liveDuration();
          if (d > Duration.zero) _updateDragTarget(artSize, d);
        },
        onHorizontalDragEnd: (_) {
          final target = _dragTarget;
          _dragStartPosition = null;
          _dragTarget = null;
          _dragStartX = null;
          _pointerX = null;
          if (target != null) c.seek(target);
        },
        child: Listener(
          onPointerDown: (event) {
            _dragStartX = event.position.dx;
            _pointerX = event.position.dx;
          },
          onPointerMove: (event) => _pointerX = event.position.dx,
          child: child,
        ),
      );

  Widget _content(BuildContext context) {
    final c = widget.controller;
    final track = c.currentTrack;
    final duration = c.audio.duration > Duration.zero
        ? c.audio.duration
        : track?.duration ?? Duration.zero;
    final pos = c.audio.position.inMilliseconds.clamp(
      0,
      math.max(0, duration.inMilliseconds),
    );
    final color = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Slush: el reproductor de escritorio (rejilla de 3 zonas) necesita >= 900.
        final compact =
            constraints.maxWidth <
            (isSlush(context) ? Breakpoints.medium : 760);
        final artSize = compact
            ? ArtworkContext.vinylCompact.constrain(
                BoxConstraints(
                  maxWidth: math.max(0.0, constraints.maxWidth - 36),
                ),
              )
            : math
                  .min(
                    (constraints.maxWidth - 300) * .58,
                    constraints.maxHeight - 48,
                  )
                  .clamp(0.0, ArtworkContext.vinyl.size);
        final record = _record(
          context,
          c,
          track,
          artSize,
          _VinylStyle(
            disc: const Color(0xff171514),
            label: color.surfaceContainerHighest,
            ring: Colors.white24,
            ringWidth: 1,
            shadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 26,
                offset: Offset(0, 12),
              ),
            ],
            groove: Colors.white,
            grooveHi: .065,
            grooveLo: .025,
            pivot: color.outline,
            arm: color.outlineVariant,
            needle: color.primary,
          ),
        );
        final metadata = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track?.title ?? 'Nada sonando',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                MouseRegion(
                  cursor: track == null
                      ? MouseCursor.defer
                      : SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: track == null
                        ? null
                        : () => widget.controller.openArtist(track.artist),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 44),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        widthFactor: 1,
                        child: Text(
                          track?.artist ??
                              'Elige una canci\u00f3n de tu biblioteca',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: color.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.follow != null &&
                    track != null &&
                    _primaryArtist(track.artist).isNotEmpty)
                  FollowButton(
                    service: widget.follow!,
                    name: _primaryArtist(track.artist),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  _time(c.audio.position),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Expanded(
                  child: Slider(
                    semanticFormatterCallback: (value) =>
                        'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                    min: 0,
                    max: math.max(1, duration.inMilliseconds).toDouble(),
                    value: pos.toDouble().clamp(
                      0,
                      math.max(1, duration.inMilliseconds).toDouble(),
                    ),
                    onChanged: duration > Duration.zero
                        ? (value) =>
                              c.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
                Text(
                  _time(duration),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Anterior',
                  onPressed: track == null ? null : c.previous,
                  icon: const Icon(Icons.skip_previous_rounded, size: 32),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: track == null ? null : c.togglePlayback,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(18),
                  ),
                  child: Icon(
                    c.audio.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Siguiente',
                  onPressed: track == null ? null : c.next,
                  icon: const Icon(Icons.skip_next_rounded, size: 32),
                ),
              ],
            ),
          ],
        );
        final nextTracks = c.queue.skip(c.queueIndex + 1).take(3).toList();
        final nextUp = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A CONTINUACIÓN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            if (nextTracks.isEmpty)
              Text(
                'La cola está vacía',
                style: TextStyle(color: color.onSurfaceVariant),
              )
            else
              for (var i = 0; i < nextTracks.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Artwork(
                    track: nextTracks[i],
                    artworkContext: ArtworkContext.thumbnailCompact,
                    radius: 5,
                  ),
                  title: Text(
                    nextTracks[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    nextTracks[i].artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => c.playQueueAt(c.queueIndex + i + 1),
                ),
          ],
        );
        if (isSlush(context)) {
          return _slushLayout(context, c, track, compact, constraints);
        }
        if (isModern(context) || isBrasa(context)) {
          return _dashLayout(
            context,
            c,
            track,
            compact,
            constraints,
            nextUp,
            brasa: isBrasa(context),
          );
        }
        if (compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: record),
                const SizedBox(height: 20),
                metadata,
                const SizedBox(height: 24),
                nextUp,
              ],
            ),
          );
        }
        final compositionWidth = math.min(constraints.maxWidth - 48, 1100.0);
        final contextWidth = math.min(300.0, compositionWidth - 460);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: SizedBox(
              width: compositionWidth,
              child: Row(
                children: [
                  SizedBox(
                    width: contextWidth,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EDICIÓN DE LA BIBLIOTECA',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: color.primary,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 12),
                          metadata,
                          const SizedBox(height: 20),
                          nextUp,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Expanded(child: Center(child: record)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Colores y radios del disco: Atelier, Modern y Brasa comparten la misma
/// lógica de giro y seek y solo cambian la pintura.
class _VinylStyle {
  const _VinylStyle({
    required this.disc,
    required this.label,
    required this.ring,
    required this.ringWidth,
    required this.shadow,
    required this.groove,
    required this.grooveHi,
    required this.grooveLo,
    required this.pivot,
    required this.arm,
    required this.needle,
    this.slush = false,
  });
  final bool slush;
  final Color disc, label, ring, groove, pivot, arm, needle;
  final double ringWidth, grooveHi, grooveLo;
  final List<BoxShadow> shadow;

  static const modern = _VinylStyle(
    disc: Color(0xff151b31),
    label: Color(0xff0b1020),
    ring: Tracky.coral,
    ringWidth: 2,
    shadow: [],
    groove: Colors.white,
    grooveHi: .05,
    grooveLo: .02,
    pivot: Tracky.mint,
    arm: Tracky.mint,
    needle: Tracky.mint,
  );
  static _VinylStyle get brasa => _VinylStyle(
    disc: Brasa.void_,
    label: Brasa.graphite,
    ring: Brasa.accent,
    ringWidth: 2,
    shadow: [],
    groove: Brasa.graphite,
    grooveHi: 1,
    grooveLo: .55,
    pivot: Brasa.cream,
    arm: Brasa.cream,
    needle: Brasa.cream,
  );
}

extension on _VinylPlayerState {
  /// Disco giratorio con etiqueta de portada, seek por toque/arrastre y
  /// brazo. El giro vive en su propio RepaintBoundary.
  Widget _record(
    BuildContext context,
    AppController c,
    Track? track,
    double artSize,
    _VinylStyle s,
  ) => SizedBox.square(
    dimension: artSize,
    child: Stack(
      children: [
        if (_cassette)
          Center(
            child: CassettePlayer(
              controller: c,
              track: track,
              rotation: _rotation,
              size: artSize,
            ),
          )
        else
          _seekable(
            c,
            artSize,
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _rotation,
                builder: (context, child) => Transform.rotate(
                  angle: _rotation.value * math.pi * 2,
                  child: child,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        key: const ValueKey('vinyl-disc'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.disc,
                          boxShadow: s.shadow,
                        ),
                        child: CustomPaint(
                          painter: _GroovesPainter(
                            s.groove,
                            s.grooveHi,
                            s.grooveLo,
                            dense: s.slush,
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        key: const ValueKey('vinyl-label'),
                        width: artSize * (s.slush ? .4 : .38),
                        height: artSize * (s.slush ? .4 : .38),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.label,
                          border: Border.all(color: s.ring, width: s.ringWidth),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: s.slush
                            ? SlushLabelArt(color: s.label)
                            : track == null
                            ? const Icon(Icons.music_note, size: 46)
                            : Artwork.fill(
                                track: track,
                                artworkContext: ArtworkContext.vinyl,
                              ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.center,
                      child: Container(
                        key: const ValueKey('vinyl-hole'),
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (!_cassette && !s.slush)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TonearmPainter(
                  pivot: s.pivot,
                  arm: s.arm,
                  needle: s.needle,
                ),
              ),
            ),
          ),
        if (!s.slush)
          Positioned(
            left: 0,
            top: 0,
            child: IconButton(
              key: const ValueKey('cassette-toggle'),
              tooltip: _cassette ? 'Ver vinilo' : 'Ver casete',
              onPressed: () => _setCassette(!_cassette),
              icon: Icon(
                _cassette ? Icons.album_outlined : Icons.sd_card_outlined,
                color: s.ring,
              ),
            ),
          ),
      ],
    ),
  );

  /// «A continuación» de Brasa: lista compacta con la pista actual en ámbar.
  Widget _brasaNext(BuildContext context, AppController c, Track? current) {
    final upcoming = c.queue.skip(c.queueIndex + 1).take(5).toList();
    Widget row(Track t, bool now, VoidCallback? onTap) => InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Artwork(
              track: t,
              artworkContext: ArtworkContext.thumbnailCompact,
              radius: 4,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: now ? Brasa.accent : Brasa.cream,
                    ),
                  ),
                  Text(
                    t.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 12,
                      color: Brasa.steel,
                    ),
                  ),
                ],
              ),
            ),
            if (now) Icon(Icons.graphic_eq, size: 16, color: Brasa.accent),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Brasa.obsidian,
        borderRadius: BorderRadius.circular(6),
        boxShadow: Brasa.cardShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A continuación',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Brasa.cream,
              ),
            ),
            const SizedBox(height: 8),
            if (current != null) row(current, true, null),
            if (upcoming.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'La cola está vacía',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    color: Brasa.steel,
                  ),
                ),
              )
            else
              for (var i = 0; i < upcoming.length; i++)
                row(
                  upcoming[i],
                  false,
                  () => c.playQueueAt(c.queueIndex + i + 1),
                ),
          ],
        ),
      ),
    );
  }

  /// Modo Vinilo de Slush: ver lib/ui/slush/slush_player.dart.
  Widget _slushLayout(
    BuildContext context,
    AppController c,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) => SlushPlayerScreen(
    controller: c,
    track: track,
    compact: compact,
    cassette: _cassette,
    onToggleCassette: () => _setCassette(!_cassette),
    onSection: widget.onSection,
    onBack: widget.onBack,
    recordBuilder: (size) {
      final p = context.slush;
      final dark = Theme.of(context).brightness == Brightness.dark;
      return _record(
        context,
        c,
        track,
        math.max(0.0, size),
        _VinylStyle(
          // Oscuro: el disco es el pozo `inset`; claro: vinilo negro.
          disc: dark ? p.inset : const Color(0xff111111),
          label: slushScreenColor(AccentScope.of(context, c.accentColor)),
          ring: p.line,
          ringWidth: SlushStroke.base,
          shadow: const [],
          groove: SlushPalette.dark.ink,
          grooveHi: .07,
          grooveLo: .03,
          pivot: p.line,
          arm: p.line,
          needle: p.line,
          slush: true,
        ),
      );
    },
  );

  /// Modo Vinilo de Modern y Brasa: mismo disco que Atelier dentro de una
  /// tarjeta de cada tema.
  Widget _dashLayout(
    BuildContext context,
    AppController c,
    Track? track,
    bool compact,
    BoxConstraints constraints,
    Widget nextUp, {
    required bool brasa,
  }) {
    final fg = brasa ? Brasa.cream : Colors.white;
    final recordSide = compact
        ? math.min(constraints.maxWidth - 36 - 48, 300.0)
        : math.min(constraints.maxWidth * .32, 340.0);
    final title = (track?.title ?? 'Nada sonando').trim();
    final words = title.split(RegExp(r'\s+'));
    final multi = words.length >= 2;
    final Widget headline = brasa
        ? Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: Brasa.cream,
            ),
          )
        : ClipRect(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 36 * 1.1 * 3),
              child: ModernHeadline(
                before: multi
                    ? '${words.sublist(0, words.length - 1).join(' ')} '
                    : words.first,
                emphasis: multi ? words.last : '',
                size: 36,
                onDark: true,
              ),
            ),
          );
    final artist = Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        MouseRegion(
          cursor: track == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: track == null
                ? null
                : () => widget.controller.openArtist(track.artist),
            child: Text(
              track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: brasa
                  ? const TextStyle(
                      fontFamily: 'Inter',
                      color: Brasa.cloud,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    )
                  : const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.16,
                    ),
            ),
          ),
        ),
        if (widget.follow != null &&
            track != null &&
            _primaryArtist(track.artist).isNotEmpty)
          FollowButton(
            service: widget.follow!,
            name: _primaryArtist(track.artist),
          ),
      ],
    );
    final controls = ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Anterior',
            color: fg,
            onPressed: track == null ? null : c.previous,
            icon: const Icon(Icons.skip_previous_rounded, size: 32),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: track == null ? null : c.togglePlayback,
            style: FilledButton.styleFrom(
              backgroundColor: brasa ? Brasa.cream : Tracky.mint,
              foregroundColor: brasa ? Colors.black : Tracky.navy,
              shape: brasa
                  ? const CircleBorder()
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
              padding: EdgeInsets.all(brasa ? 12 : 18),
            ),
            child: Icon(
              c.audio.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: brasa ? 30 : 32,
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            tooltip: 'Siguiente',
            color: fg,
            onPressed: track == null ? null : c.next,
            icon: const Icon(Icons.skip_next_rounded, size: 32),
          ),
        ],
      ),
    );
    final timeStyle = brasa
        ? const TextStyle(
            fontFamily: 'Inter',
            color: Brasa.steel,
            fontSize: 11,
            fontFeatures: [FontFeature.tabularFigures()],
          )
        : const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          );
    final progress = RepaintBoundary(
      child: ListenableBuilder(
        listenable: c.audio,
        builder: (context, _) {
          final duration = _liveDuration();
          final max = math.max(1, duration.inMilliseconds).toDouble();
          final pos = c.audio.position.inMilliseconds.toDouble().clamp(
            0.0,
            max,
          );
          return Row(
            children: [
              Text(_time(c.audio.position), style: timeStyle),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: brasa ? 4 : 3,
                    activeTrackColor: brasa ? Brasa.cream : Tracky.mint,
                    inactiveTrackColor: brasa ? Brasa.ash : Colors.white24,
                    thumbColor: brasa ? Brasa.cream : Tracky.coral,
                    overlayColor: (brasa ? Brasa.cream : Tracky.mint)
                        .withValues(alpha: .16),
                  ),
                  child: Slider(
                    semanticFormatterCallback: (value) =>
                        'Ir a ${Duration(milliseconds: value.round()).inSeconds} segundos',
                    min: 0,
                    max: max,
                    value: pos,
                    onChanged: duration > Duration.zero
                        ? (value) =>
                              c.seek(Duration(milliseconds: value.round()))
                        : null,
                  ),
                ),
              ),
              Text(_time(duration), style: timeStyle),
            ],
          );
        },
      ),
    );
    final info = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headline,
        SizedBox(height: brasa ? 6 : 10),
        artist,
        SizedBox(height: brasa ? 20 : 28),
        progress,
        controls,
      ],
    );
    final record = _record(
      context,
      c,
      track,
      math.max(0.0, recordSide),
      brasa ? _VinylStyle.brasa : _VinylStyle.modern,
    );
    final inner = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: record),
              const SizedBox(height: 24),
              info,
            ],
          )
        : Row(
            children: [
              if (brasa) record,
              if (brasa) const SizedBox(width: 32),
              Expanded(child: info),
              if (!brasa) const SizedBox(width: 32),
              if (!brasa) record,
            ],
          );
    final Widget feature = brasa
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: Brasa.obsidian,
              borderRadius: BorderRadius.circular(6),
              boxShadow: Brasa.cardShadow,
            ),
            child: Padding(padding: const EdgeInsets.all(24), child: inner),
          )
        : ModernCard(
            dark: true,
            feature: true,
            padding: EdgeInsets.all(compact ? 24 : 40),
            child: inner,
          );
    final next = brasa
        ? _brasaNext(context, c, track)
        : ModernCard(child: nextUp);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 24,
        vertical: 24,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [feature, const SizedBox(height: 20), next],
          ),
        ),
      ),
    );
  }
}

class _TonearmPainter extends CustomPainter {
  const _TonearmPainter({
    required this.pivot,
    required this.arm,
    required this.needle,
  });
  final Color pivot;
  final Color arm;
  final Color needle;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * .82, size.height * .12);
    final bend = Offset(size.width * .75, size.height * .20);
    final end = Offset(size.width * .58, size.height * .50);
    canvas.drawCircle(start, size.width * .045, Paint()..color = pivot);
    canvas.drawLine(
      start,
      bend,
      Paint()
        ..color = arm
        ..strokeWidth = size.width * .018
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      bend,
      end,
      Paint()
        ..color = arm
        ..strokeWidth = size.width * .014
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(end, size.width * .018, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(covariant _TonearmPainter oldDelegate) =>
      pivot != oldDelegate.pivot ||
      arm != oldDelegate.arm ||
      needle != oldDelegate.needle;
}

class _GroovesPainter extends CustomPainter {
  const _GroovesPainter(this.color, this.hi, this.lo, {this.dense = false});
  final bool dense;
  final Color color;
  final double hi, lo;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final paint = Paint()..style = PaintingStyle.stroke;
    final n = dense ? 70 : 34;
    for (var i = 0; i < n; i++) {
      final r = radius * (dense ? .42 + i * .0079 : .43 + i * .0088);
      paint.color = color.withValues(alpha: i.isEven ? hi : lo);
      paint.strokeWidth = i % 5 == 0 ? 1.2 : .7;
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GroovesPainter old) =>
      color != old.color || hi != old.hi || lo != old.lo || dense != old.dense;
}

/// Primer artista de «A, B feat. C» (YouTube Music los lista juntos).
String _primaryArtist(String artist) =>
    artist.split(RegExp(r'\s*(?:,|&|;|\sfeat\.?\s|\sft\.?\s)\s*')).first.trim();

String _time(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
