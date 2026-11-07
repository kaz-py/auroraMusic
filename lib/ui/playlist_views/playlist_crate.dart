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

/// Playlists como discos de pie en una caja de madera. Se hojean deslizando;
/// la funda enfocada se eleva dejando asomar el vinilo y tocarla la abre.
class PlaylistCrate extends StatefulWidget {
  const PlaylistCrate({
    super.key,
    required this.controller,
    required this.playlists,
    required this.onOpen,
  });
  final AppController controller;
  final List<MusicPlaylist> playlists;
  final ValueChanged<MusicPlaylist> onOpen;

  @override
  State<PlaylistCrate> createState() => _PlaylistCrateState();
}

class _PlaylistCrateState extends State<PlaylistCrate> {
  static const _sleeve = 150.0;
  static const _peek = 28.0;
  static const _slat = 76.0;
  PageController _pages = PageController(viewportFraction: .4);
  double _fraction = .4;
  int _current = 0;
  int? _lifted;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  // Cada funda ocupa su ancho: en pantallas anchas se acercan, en estrechas no se cortan.
  void _fit(double width) {
    final f = ((_sleeve + 8) / width).clamp(.2, .62);
    if ((f - _fraction).abs() < .005) return;
    final old = _pages;
    _fraction = f;
    _pages = PageController(initialPage: _current, viewportFraction: f);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  Future<void> _tap(int i) async {
    if (i != _current) {
      await _pages.animateToPage(
        i,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => _lifted = i);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() => _lifted = null);
    widget.onOpen(widget.playlists[i]);
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.playlists;
    if (list.isEmpty) return const SizedBox.shrink();
    final index = _current.clamp(0, list.length - 1);
    final look = _CrateLook.of(context, playlistColor(list[index]));
    return LayoutBuilder(
      builder: (context, box) {
        _fit(box.maxWidth.isFinite ? box.maxWidth : 600);
        return SizedBox(
          height: 270,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // Interior con sombra en bordes y arriba.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 245,
                child: DecoratedBox(
                  decoration: look.interior,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: look.topRadius,
                      gradient: LinearGradient(
                        colors: [
                          look.shade,
                          Colors.transparent,
                          Colors.transparent,
                          look.shade,
                        ],
                        stops: const [0, .08, .92, 1],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: _slat - 36,
                height: _sleeve + _peek + 14,
                child: PageView.builder(
                  controller: _pages,
                  clipBehavior: Clip.none,
                  itemCount: list.length,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemBuilder: (context, i) => AnimatedBuilder(
                    animation: _pages,
                    builder: (context, _) {
                      final page =
                          _pages.hasClients && _pages.position.haveDimensions
                          ? (_pages.page ?? _current.toDouble())
                          : _current.toDouble();
                      final d = (i - page).clamp(-2.0, 2.0);
                      final near = 1 - math.min(d.abs(), 1);
                      return Transform(
                        alignment: Alignment.bottomCenter,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0011)
                          ..rotateY(-d * .45)
                          ..scaleByDouble(.9 + .1 * near, .9 + .1 * near, 1, 1),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedSlide(
                            duration: const Duration(milliseconds: 220),
                            offset: _lifted == i
                                ? const Offset(0, -.22)
                                : Offset.zero,
                            child: PlaylistPhotoMenu(
                              controller: widget.controller,
                              playlist: list[i],
                              child: _Sleeve(
                                playlist: list[i],
                                tracks: playlistCoverTracks(
                                  widget.controller,
                                  list[i],
                                ),
                                look: look,
                                peek: _peek * near,
                                dim: .45 * (1 - near),
                                onTap: () => _tap(i),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              // Listón frontal con clavos y placa con el nombre.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: _slat,
                child: CustomPaint(
                  painter: _SlatPainter(look),
                  child: Center(
                    child: _Plate(
                      look: look,
                      name: list[index].name,
                      count: list[index].trackIds.length,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Plate extends StatelessWidget {
  const _Plate({required this.look, required this.name, required this.count});
  final _CrateLook look;
  final String name;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(maxWidth: 260),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: look.plate,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: look.plateInk,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        Text(
          '$count canciones',
          style: TextStyle(color: look.plateSub, fontSize: 11),
        ),
      ],
    ),
  );
}

class _Sleeve extends StatelessWidget {
  const _Sleeve({
    required this.playlist,
    required this.tracks,
    required this.look,
    required this.peek,
    required this.dim,
    required this.onTap,
  });
  final MusicPlaylist playlist;
  final List<Track> tracks;
  final _CrateLook look;
  final double peek;
  final double dim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const s = _PlaylistCrateState._sleeve;
    return Semantics(
      button: true,
      label: 'Abrir ${playlist.name}',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 8,
                top: -peek,
                width: s - 16,
                height: s - 16,
                child: CustomPaint(
                  painter: _VinylPainter(
                    playlistColor(playlist),
                    look.vinylRim,
                  ),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(look.sleeveRadius),
                    border: look.sleeveBorder,
                    boxShadow: look.sleeveShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(look.sleeveRadius),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        PlaylistCover(
                          playlist: playlist,
                          tracks: tracks,
                          size: s,
                        ),
                        // Brillo diagonal, lomo con grosor y sombra de profundidad.
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withValues(alpha: .22),
                                Colors.transparent,
                                Colors.black.withValues(alpha: .12),
                              ],
                              stops: const [0, .4, 1],
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 7,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: .5),
                                  Colors.white.withValues(alpha: .14),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (dim > 0)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: dim),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VinylPainter extends CustomPainter {
  _VinylPainter(this.label, this.rim);
  final Color label;
  final Color? rim;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2A2A2E), Color(0xFF0B0B0D)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    if (rim != null) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = rim!,
      );
    }
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .6
      ..color = Colors.white.withValues(alpha: .07);
    for (var k = .4; k < .97; k += .07) {
      canvas.drawCircle(c, r * k, groove);
    }
    canvas.drawCircle(c, r * .3, Paint()..color = label);
    canvas.drawCircle(c, r * .04, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(_VinylPainter o) => o.label != label || o.rim != rim;
}

class _SlatPainter extends CustomPainter {
  _SlatPainter(this.look);
  final _CrateLook look;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(look.slatRadius),
      topRight: Radius.circular(look.slatRadius),
    );
    if (look.hardSlat) {
      canvas.drawRRect(
        rr.shift(const Offset(0, -3)),
        Paint()..color = Slush.ink,
      );
    } else {
      canvas.drawShadow(Path()..addRRect(rr), look.slatShadow, 8, true);
    }
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: look.slat,
        ).createShader(rect),
    );
    canvas.save();
    canvas.clipRRect(rr);
    if (look.grain) _grain(canvas, size);
    // Biseles: luz arriba, sombra abajo.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2),
      Paint()..color = look.edgeLight,
    );
    if (look.grain) {
      canvas.drawRect(
        Rect.fromLTWH(0, size.height - 3, size.width, 3),
        Paint()..color = Colors.black.withValues(alpha: .35),
      );
      for (final x in [14.0, size.width - 14]) {
        for (final y in [14.0, size.height - 16]) {
          _nail(canvas, Offset(x, y));
        }
      }
    }
    canvas.restore();
    if (look.slatOutline != null) {
      canvas.drawRRect(
        rr.deflate(look.slatOutlineWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = look.slatOutlineWidth
          ..color = look.slatOutline!,
      );
    }
  }

  void _grain(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    final grain = Paint()
      ..strokeWidth = .8
      ..style = PaintingStyle.stroke;
    for (var y = 3.0; y < size.height; y += 2 + rnd.nextDouble() * 4) {
      grain.color = (rnd.nextBool() ? Colors.black : Colors.white).withValues(
        alpha: .03 + rnd.nextDouble() * .06,
      );
      final w = y + rnd.nextDouble() * 3;
      canvas.drawPath(
        Path()
          ..moveTo(0, y)
          ..cubicTo(size.width * .3, w, size.width * .6, y - 2, size.width, w),
        grain,
      );
    }
  }

  void _nail(Canvas canvas, Offset o) {
    canvas.drawCircle(
      o + const Offset(0, 1.2),
      4,
      Paint()..color = Colors.black.withValues(alpha: .45),
    );
    canvas.drawCircle(
      o,
      3.6,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-.4, -.4),
          colors: [Color(0xFFE6E0D4), Color(0xFF6E6A62)],
        ).createShader(Rect.fromCircle(center: o, radius: 3.6)),
    );
    canvas.drawLine(
      o + const Offset(-2, 0),
      o + const Offset(2, .6),
      Paint()
        ..color = Colors.black54
        ..strokeWidth = .9,
    );
  }

  @override
  bool shouldRepaint(_SlatPainter o) => o.look != look;
}

/// Aspecto del cajón por tema. Atelier: madera cálida y placa de papel marfil;
/// Modern: cajón liso de superficies suaves con el acento de la portada;
/// Brasa: madera oscura sobria con líneas ámbar; Slush: pegatina con contornos negros.
class _CrateLook {
  _CrateLook({
    required this.interior,
    required this.shade,
    required this.topRadius,
    required this.slat,
    required this.slatShadow,
    required this.edgeLight,
    required this.plate,
    required this.plateInk,
    required this.plateSub,
    required this.sleeveRadius,
    required this.sleeveShadow,
    this.sleeveBorder,
    this.vinylRim,
    this.grain = false,
    this.hardSlat = false,
    this.slatRadius = 8,
    this.slatOutline,
    this.slatOutlineWidth = 1,
  });
  final BoxDecoration interior, plate;
  final Color shade, slatShadow, edgeLight, plateInk, plateSub;
  final BorderRadius topRadius;
  final List<Color> slat;
  final bool grain, hardSlat;
  final double sleeveRadius, slatRadius, slatOutlineWidth;
  final List<BoxShadow> sleeveShadow;
  final Border? sleeveBorder;
  final Color? vinylRim, slatOutline;

  factory _CrateLook.of(BuildContext context, Color accent) {
    final cs = Theme.of(context).colorScheme;
    final dark = cs.brightness == Brightness.dark;
    BorderRadius top(double r) =>
        BorderRadius.vertical(top: Radius.circular(r));
    if (isSlush(context)) {
      return _CrateLook(
        interior: BoxDecoration(
          borderRadius: top(SlushRadius.r16),
          color: Slush.lilac,
          border: Border.fromBorderSide(context.slush.border),
        ),
        shade: Slush.ink.withValues(alpha: .12),
        topRadius: top(SlushRadius.r16),
        slat: [Slush.yellow, Slush.yellow],
        slatShadow: Slush.ink,
        edgeLight: Colors.white.withValues(alpha: .6),
        hardSlat: true,
        slatRadius: SlushRadius.r16,
        slatOutline: Slush.ink,
        slatOutlineWidth: SlushStroke.base,
        plate: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: context.slush.paper,
          border: Border.fromBorderSide(context.slush.border),
          boxShadow: [
            BoxShadow(color: context.slush.shadow, offset: const Offset(2, 3)),
          ],
        ),
        plateInk: context.slush.ink,
        plateSub: context.slush.ink2,
        sleeveRadius: 6,
        sleeveBorder: const Border.fromBorderSide(
          BorderSide(color: Slush.ink, width: 2),
        ),
        sleeveShadow: const [BoxShadow(color: Slush.ink, offset: Offset(3, 4))],
        vinylRim: Slush.ink,
      );
    }
    if (isBrasa(context)) {
      return _CrateLook(
        interior: BoxDecoration(
          borderRadius: top(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Brasa.void_, Brasa.obsidian],
          ),
        ),
        shade: Colors.black.withValues(alpha: .55),
        topRadius: top(8),
        slat: const [Color(0xFF4A3727), Color(0xFF362719), Color(0xFF241A12)],
        slatShadow: Colors.black,
        edgeLight: Brasa.amber.withValues(alpha: .55),
        grain: false,
        slatRadius: 8,
        plate: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: Brasa.graphite,
          border: Border.all(
            color: Brasa.amber.withValues(alpha: .75),
            width: .8,
          ),
        ),
        plateInk: Brasa.cream,
        plateSub: Brasa.cloud,
        sleeveRadius: 3,
        sleeveShadow: const [
          BoxShadow(
            blurRadius: 10,
            offset: Offset(4, 2),
            color: Colors.black87,
          ),
        ],
      );
    }
    if (isModern(context)) {
      final tint = Color.lerp(cs.surfaceContainer, accent, dark ? .12 : .16)!;
      return _CrateLook(
        interior: BoxDecoration(
          borderRadius: top(22),
          border: Border.all(color: cs.onSurface.withValues(alpha: .08)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.surfaceContainerLow, tint],
          ),
        ),
        shade: cs.shadow.withValues(alpha: dark ? .3 : .08),
        topRadius: top(22),
        slat: [
          Color.lerp(
            cs.surfaceContainerHighest,
            Colors.white,
            dark ? .06 : .4,
          )!,
          cs.surfaceContainerHigh,
          Color.lerp(cs.surfaceContainerHigh, accent, .14)!,
        ],
        slatShadow: Color.lerp(cs.shadow, accent, .4)!,
        edgeLight: Colors.white.withValues(alpha: dark ? .18 : .7),
        slatRadius: 22,
        slatOutline: cs.onSurface.withValues(alpha: .1),
        plate: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: cs.surface.withValues(alpha: .82),
          border: Border.all(color: cs.onSurface.withValues(alpha: .12)),
          boxShadow: [
            BoxShadow(
              blurRadius: 10,
              offset: const Offset(0, 3),
              color: cs.shadow.withValues(alpha: .18),
            ),
          ],
        ),
        plateInk: cs.onSurface,
        plateSub: cs.onSurfaceVariant,
        sleeveRadius: 10,
        sleeveShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(3, 4),
            color: Color.lerp(cs.shadow, accent, .4)!.withValues(alpha: .35),
          ),
        ],
      );
    }
    // Atelier: madera cálida clara (nogal en modo oscuro) y placa de papel marfil.
    final wood = Color.lerp(
      const Color(0xFFC08A55),
      const Color(0xFF4A301B),
      dark ? .5 : 0,
    )!;
    return _CrateLook(
      interior: BoxDecoration(
        borderRadius: top(10),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(wood, Colors.black, dark ? .6 : .32)!,
            Color.lerp(wood, Colors.black, dark ? .4 : .16)!,
          ],
        ),
      ),
      shade: Colors.black.withValues(alpha: dark ? .4 : .22),
      topRadius: top(10),
      slat: [
        Color.lerp(wood, Colors.white, .16)!,
        wood,
        Color.lerp(wood, Colors.black, .28)!,
      ],
      slatShadow: Colors.black,
      edgeLight: Colors.white.withValues(alpha: .3),
      grain: true,
      plate: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: const Color(0xFFF6EFDD),
        border: Border.all(color: const Color(0xFFB59E70), width: .8),
        boxShadow: const [
          BoxShadow(blurRadius: 3, offset: Offset(0, 2), color: Colors.black45),
        ],
      ),
      plateInk: const Color(0xFF2B1D08),
      plateSub: const Color(0xFF5A4A28),
      sleeveRadius: 2,
      sleeveShadow: const [
        BoxShadow(blurRadius: 10, offset: Offset(4, 2), color: Colors.black87),
      ],
    );
  }
}
