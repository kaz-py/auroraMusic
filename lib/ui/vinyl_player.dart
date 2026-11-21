import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models.dart';

import '../app_controller.dart';
import '../jam/jam_controller.dart';
import '../follow/follow_service.dart';
import 'slush/slush_player.dart';
import 'artwork.dart';
import 'cassette_player.dart';
import 'player/player_theme.dart';

class VinylPlayer extends StatefulWidget {
  const VinylPlayer({
    super.key,
    required this.controller,
    this.follow,
    this.onSection,
    this.onBack,
    this.jam,
  });

  /// Jam activa: limita saltos y anterior en los controles de Slush.
  final JamController? jam;

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

  /// Modern: portada sola por defecto; también puede ver vinilo o casete.
  late bool _modernPhoto =
      widget.controller.preferences.getBool('modernPhoto') ?? true;

  /// 0 portada, 1 vinilo, 2 casete.
  void _setModernView(int view) {
    setState(() {
      _modernPhoto = view == 0;
      if (view != 0) _cassette = view == 2;
    });
    widget.controller.preferences.setBool('modernPhoto', view == 0);
    if (view != 0) {
      widget.controller.preferences.setBool('cassetteMode', view == 2);
    }
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
    builder: (context, _) => playerThemeOf(context).rebuildsOnAudio
        ? ListenableBuilder(
            listenable: widget.controller.audio,
            builder: (context, _) => _content(context),
          )
        : _content(context),
  );

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

  /// Reparte el estado compartido al tema vigente, que dibuja el reproductor.
  Widget _content(BuildContext context) {
    final c = widget.controller;
    final theme = playerThemeOf(context);
    final scope = PlayerScope(
      controller: c,
      follow: widget.follow,
      jam: widget.jam,
      onSection: widget.onSection,
      onBack: widget.onBack,
      cassette: _cassette,
      modernPhoto: _modernPhoto,
      setCassette: _setCassette,
      setModernView: _setModernView,
      record: _record,
      seekable: _seekable,
      liveDuration: _liveDuration,
    );
    return LayoutBuilder(
      builder: (context, constraints) => theme.buildLayout(
        context,
        scope,
        c.currentTrack,
        constraints.maxWidth < theme.compactBreakpoint,
        constraints,
      ),
    );
  }
}

extension on _VinylPlayerState {
  /// Disco giratorio con etiqueta de portada, seek por toque/arrastre y
  /// brazo. El giro vive en su propio RepaintBoundary.
  Widget _record(
    BuildContext context,
    AppController c,
    Track? track,
    double artSize,
    PlayerDiscStyle s,
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
