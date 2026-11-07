import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/slush_theme.dart';
import 'playlist_cover.dart';
import 'playlist_photo_menu.dart';
import 'playlist_view_mode.dart';

/// Grid responsivo de playlists como casetes con carcasa, etiqueta y bobinas.
class PlaylistCassettes extends StatelessWidget {
  const PlaylistCassettes({
    super.key,
    required this.controller,
    required this.playlists,
    required this.onOpen,
  });
  final AppController controller;
  final List<MusicPlaylist> playlists;
  final ValueChanged<MusicPlaylist> onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 18.0;
      final total = box.maxWidth.isFinite ? box.maxWidth : 640.0;
      final cols = math.max(1, ((total + gap) / (240 + gap)).floor());
      final w = ((total - gap * (cols - 1)) / cols).clamp(180.0, 320.0);
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final p in playlists)
            PlaylistPhotoMenu(
              controller: controller,
              playlist: p,
              child: _Cassette(
                width: w,
                playlist: p,
                tracks: playlistCoverTracks(controller, p),
                onTap: () => onOpen(p),
              ),
            ),
        ],
      );
    },
  );
}

class _Cassette extends StatefulWidget {
  const _Cassette({
    required this.width,
    required this.playlist,
    required this.tracks,
    required this.onTap,
  });
  final double width;
  final MusicPlaylist playlist;
  final List<Track> tracks;
  final VoidCallback onTap;

  @override
  State<_Cassette> createState() => _CassetteState();
}

class _CassetteState extends State<_Cassette> {
  Offset _tilt = Offset.zero; // -1..1 según el puntero.
  bool _hover = false;

  void _move(PointerEvent e) {
    final h = widget.width / 1.6;
    setState(() {
      _hover = true;
      _tilt = Offset(
        (e.localPosition.dx / widget.width * 2 - 1).clamp(-1, 1),
        (e.localPosition.dy / h * 2 - 1).clamp(-1, 1),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w / 1.6;
    final stripe = playlistColor(widget.playlist, lightness: .5);
    final look = _CassetteLook.of(context, stripe);
    return Semantics(
      button: true,
      label: 'Abrir ${widget.playlist.name}',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: _move,
        onExit: (_) => setState(() {
          _hover = false;
          _tilt = Offset.zero;
        }),
        child: GestureDetector(
          onTap: widget.onTap,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: _tilt),
            duration: const Duration(milliseconds: 140),
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, .0012)
                ..rotateX(-t.dy * .09)
                ..rotateY(t.dx * .12)
                ..translateByDouble(0, _hover ? -3 : 0, 0, 1),
              child: child,
            ),
            child: Container(
              width: w,
              height: h,
              decoration: look.decoration(_hover),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _ShellPainter(look)),
                  ),
                  // Etiqueta de papel con portada y nombre rotulado.
                  Positioned(
                    left: w * .07,
                    right: w * .07,
                    top: h * .1,
                    height: h * .42,
                    child: _Label(
                      playlist: widget.playlist,
                      tracks: widget.tracks,
                      stripe: stripe,
                      look: look,
                      height: h * .42,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.playlist,
    required this.tracks,
    required this.stripe,
    required this.look,
    required this.height,
  });
  final MusicPlaylist playlist;
  final List<Track> tracks;
  final Color stripe;
  final _CassetteLook look;
  final double height;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: look.labelBg,
      borderRadius: BorderRadius.circular(look.labelRadius),
      border: look.labelBorder,
      boxShadow: look.labelShadow,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(look.labelRadius),
      child: Row(
        children: [
          Container(width: 5, color: stripe),
          Padding(
            padding: const EdgeInsets.all(3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: PlaylistCover(
                playlist: playlist,
                tracks: tracks,
                size: height - 6,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Text(
                      playlist.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Bagel Fat One',
                        color: look.labelInk,
                        fontSize: 14,
                        height: 1.05,
                      ),
                    ),
                  ),
                  Text(
                    '${playlist.trackIds.length} canciones',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: look.labelSub, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Textura, tornillos, ventana con bobinas y zócalo del casete.
class _ShellPainter extends CustomPainter {
  _ShellPainter(this.look);
  final _CassetteLook look;
  Color get body => look.body;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    if (look.hardware) _texture(canvas, w, h);
    _window(canvas, w, h);
    if (look.hardware) _hardware(canvas, w, h);
  }

  void _texture(Canvas canvas, double w, double h) {
    // Textura sutil de líneas diagonales.
    final tex = Paint()
      ..color = Colors.white.withValues(alpha: .025)
      ..strokeWidth = .8;
    for (var x = -h; x < w; x += 5) {
      canvas.drawLine(Offset(x, h), Offset(x + h, 0), tex);
    }
    // Brillo superior.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 2, w - 6, h * .16),
        const Radius.circular(7),
      ),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: .16),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h * .18)),
    );
  }

  void _window(Canvas canvas, double w, double h) {
    // Ventana con cinta.
    final win = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * .2, h * .56, w * .6, h * .2),
      Radius.circular(h * .1),
    );
    canvas.drawRRect(win, Paint()..color = look.window);
    canvas.drawRRect(
      win,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = look.windowEdge,
    );
    final cy = win.top + win.height / 2;
    final rl = Offset(w * .32, cy), rr = Offset(w * .68, cy);
    final tape = Paint()..color = look.tape;
    canvas.save();
    canvas.clipRRect(win);
    canvas.drawCircle(rl, win.height * .62, tape);
    canvas.drawCircle(rr, win.height * .42, tape);
    canvas.restore();
    for (final c in [rl, rr]) {
      _reel(canvas, c, win.height * .34);
    }
  }

  void _hardware(Canvas canvas, double w, double h) {
    // Zócalo trapezoidal con orificios.
    final base = Path()
      ..moveTo(w * .16, h)
      ..lineTo(w * .23, h * .8)
      ..lineTo(w * .77, h * .8)
      ..lineTo(w * .84, h)
      ..close();
    canvas.drawPath(
      base,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(body, Colors.white, .16)!,
            Color.lerp(body, Colors.black, .2)!,
          ],
        ).createShader(Rect.fromLTWH(0, h * .8, w, h * .2)),
    );
    canvas.drawPath(
      base,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: .5),
    );
    final hole = Paint()..color = Colors.black.withValues(alpha: .85);
    for (final fx in [.3, .7]) {
      canvas.drawCircle(Offset(w * fx, h * .9), h * .045, hole);
    }
    for (final fx in [.42, .58]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(w * fx, h * .9),
            width: w * .03,
            height: h * .07,
          ),
          const Radius.circular(2),
        ),
        hole,
      );
    }

    // Cinco tornillos: cuatro esquinas y centro superior.
    for (final o in [
      Offset(w * .04, h * .08),
      Offset(w * .96, h * .08),
      Offset(w * .04, h * .92),
      Offset(w * .96, h * .92),
      Offset(w * .5, h * .045),
    ]) {
      _screw(canvas, o);
    }
  }

  void _reel(Canvas canvas, Offset c, double r) {
    canvas.drawCircle(c, r, Paint()..color = look.reel);
    canvas.drawCircle(c, r * .6, Paint()..color = look.window);
    final tooth = Paint()..color = look.reel;
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3;
      canvas.drawCircle(c + Offset.fromDirection(a, r * .55), r * .13, tooth);
    }
  }

  void _screw(Canvas canvas, Offset o) {
    canvas.drawCircle(
      o,
      3.2,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.4),
          colors: [Color(0xFFD8D4CA), Color(0xFF55524B)],
        ).createShader(Rect.fromCircle(center: o, radius: 3.2)),
    );
    canvas.drawLine(
      o + const Offset(-1.8, 1.2),
      o + const Offset(1.8, -1.2),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_ShellPainter o) => o.look != look;
}

/// Aspecto del casete por tema: Atelier plástico cálido con papel marfil,
/// Modern pastel translúcido y liso, Brasa grafito con franja ámbar, Slush pegatina.
class _CassetteLook {
  _CassetteLook({
    required this.body,
    required this.radius,
    required this.shadow,
    required this.labelBg,
    required this.labelInk,
    required this.labelSub,
    required this.window,
    required this.windowEdge,
    required this.reel,
    required this.tape,
    this.flat = false,
    this.border,
    this.hardware = true,
    this.labelBorder,
    this.labelRadius = 4,
    this.labelShadow = const [],
  });
  final Color body, labelBg, labelInk, labelSub, window, windowEdge, reel, tape;
  final double radius, labelRadius;
  final bool flat, hardware;
  final Border? border;
  final Border? labelBorder;
  final List<BoxShadow> labelShadow;
  final List<BoxShadow> Function(bool hover) shadow;

  factory _CassetteLook.of(BuildContext context, Color stripe) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    if (isSlush(context)) {
      return _CassetteLook(
        body: Color.lerp(stripe, Colors.white, .25)!,
        flat: true,
        radius: 12,
        border: Border.fromBorderSide(context.slush.border),
        shadow: (h) => [
          BoxShadow(
            color: context.slush.shadow,
            offset: h ? const Offset(5, 6) : const Offset(3, 4),
          ),
        ],
        hardware: false,
        labelBg: context.slush.paper,
        labelInk: context.slush.ink,
        labelSub: context.slush.ink2,
        labelRadius: 6,
        labelBorder: Border.fromBorderSide(context.slush.border),
        window: Slush.ink,
        windowEdge: Slush.ink,
        reel: Colors.white,
        tape: Slush.yellow,
      );
    }
    if (isBrasa(context)) {
      return _CassetteLook(
        body: Color.lerp(Brasa.graphite, stripe, .06)!,
        radius: 8,
        border: Border.all(color: Brasa.amber.withValues(alpha: .28)),
        shadow: (h) => [
          BoxShadow(
            blurRadius: h ? 22 : 12,
            offset: Offset(0, h ? 12 : 6),
            color: Colors.black.withValues(alpha: .6),
          ),
        ],
        hardware: false,
        labelBg: Brasa.ash,
        labelInk: Brasa.cream,
        labelSub: Brasa.cloud,
        labelRadius: 3,
        labelBorder: Border.all(color: Brasa.amber.withValues(alpha: .7)),
        window: Brasa.void_,
        windowEdge: Brasa.amber.withValues(alpha: .5),
        reel: Brasa.amber,
        tape: Brasa.steel,
      );
    }
    if (isModern(context)) {
      return _CassetteLook(
        body: Color.lerp(
          cs.surfaceContainerHigh,
          stripe,
          dark ? .3 : .38,
        )!.withValues(alpha: .9),
        flat: true,
        radius: 20,
        border: Border.all(color: cs.onSurface.withValues(alpha: .12)),
        shadow: (h) => [
          BoxShadow(
            blurRadius: h ? 26 : 16,
            offset: Offset(0, h ? 12 : 7),
            color: Color.lerp(
              cs.shadow,
              stripe,
              .5,
            )!.withValues(alpha: dark ? .35 : .2),
          ),
        ],
        hardware: false,
        labelBg: cs.surface.withValues(alpha: .92),
        labelInk: cs.onSurface,
        labelSub: cs.onSurfaceVariant,
        labelRadius: 12,
        window: cs.surfaceContainerLowest.withValues(alpha: dark ? .5 : .75),
        windowEdge: cs.onSurface.withValues(alpha: .1),
        reel: cs.onSurface.withValues(alpha: .75),
        tape: Color.lerp(cs.primary, stripe, .5)!.withValues(alpha: .6),
      );
    }
    // Atelier: plástico cálido (marfil de día, nogal de noche), etiqueta de papel.
    return _CassetteLook(
      body: Color.lerp(
        dark ? const Color(0xFF3B3128) : const Color(0xFFDCCDB0),
        stripe,
        .16,
      )!,
      radius: 9,
      border: Border.all(color: Colors.white.withValues(alpha: .22)),
      shadow: (h) => [
        BoxShadow(
          blurRadius: h ? 22 : 12,
          offset: Offset(0, h ? 12 : 6),
          color: Colors.black.withValues(alpha: dark ? .6 : .28),
        ),
      ],
      labelBg: const Color(0xFFF6EFDD),
      labelInk: const Color(0xFF231F18),
      labelSub: const Color(0xFF5A5448),
      labelShadow: const [
        BoxShadow(blurRadius: 2, offset: Offset(0, 1), color: Colors.black38),
      ],
      window: const Color(0xFF1B1713),
      windowEdge: Colors.white.withValues(alpha: .22),
      reel: const Color(0xFFE9E4D6),
      tape: const Color(0xFF5A3A24),
    );
  }

  BoxDecoration decoration(bool hover) => BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    color: flat ? body : null,
    gradient: flat
        ? null
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(body, Colors.white, .12)!,
              body,
              Color.lerp(body, Colors.black, .25)!,
            ],
          ),
    border: border,
    boxShadow: shadow(hover),
  );
}
