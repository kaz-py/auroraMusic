import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../dj/ai_dj.dart' show djMaxDiversity;

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/discovery_controller.dart';
import '../../dj/recommendations.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../dj_filters_panel.dart';
import '../dj_panel.dart';
import 'slush_decor.dart';

/// Verde saturado con el tono del fondo pastel (que deriva de la portada).
Color _screenGreen(BuildContext context) {
  final h = HSLColor.fromColor(Theme.of(context).scaffoldBackgroundColor);
  return HSLColor.fromAHSL(1, h.hue, .68, .66).toColor();
}

/// Pantalla «DJ AUROR» del tema Slush. La lógica vive en [discovery]; [wrap]
/// añade el gesto de deslizar a la tarjeta principal.
class SlushDj extends StatelessWidget {
  const SlushDj({
    super.key,
    required this.controller,
    required this.discovery,
    required this.onSearch,
    required this.wrap,
    this.affinityOf,
  });
  final AppController controller;
  final DjDiscoveryController discovery;
  final VoidCallback onSearch;
  final Widget Function(Track track, Widget child) wrap;

  /// Afinidad 0-1 de una pista sin puntuación propia (memoizada por la página).
  final double? Function(Track track)? affinityOf;

  @override
  Widget build(BuildContext context) {
    final rec = discovery.current;
    final affinity = rec == null
        ? null
        : rec.affinity ?? affinityOf?.call(rec.track);
    final errors = [?discovery.error, ?controller.recommendationDiscoveryError];
    return ColoredBox(
      color: _screenGreen(context),
      child: slushOnVivid(
        context,
        LayoutBuilder(
          builder: (context, box) {
            final wide = Breakpoints.isWide(box.maxWidth);
            final stack = rec == null
                ? _empty(context)
                : wrap(
                    rec.track,
                    _Stack(
                      track: rec.track,
                      reason: rec.reason,
                      affinity: affinity,
                    ),
                  );
            final skip = _RoundAction(
              key: const ValueKey('dj-discovery-skip'),
              color: Slush.orange,
              icon: Icons.close,
              label: '← OMITIR',
              onTap: rec == null || discovery.busy
                  ? null
                  : () => discovery.skip(rec.track),
            );
            final save = _RoundAction(
              key: const ValueKey('dj-discovery-add'),
              color: Slush.mint,
              icon: Icons.favorite,
              label: discovery.busy ? 'GUARDANDO…' : 'GUARDAR →',
              onTap: rec == null || discovery.busy
                  ? null
                  : () => discovery.accept(rec.track),
            );
            final counters = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ESTA SESIÓN',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: SlushSpacing.s8),
                Wrap(
                  spacing: SlushSpacing.s8,
                  runSpacing: SlushSpacing.s8,
                  children: [
                    _Counter(discovery.added, 'guardadas'),
                    _Counter(discovery.skipped, 'omitidas'),
                  ],
                ),
              ],
            );
            final filters = KeyedSubtree(
              key: const ValueKey('dj-filters'),
              child: _SlushFilters(controller: controller, onSearch: onSearch),
            );
            // Detalle: tarjeta del tema y sus dos acciones. Con ancho
            // suficiente van a los lados; si no, debajo de la tarjeta.
            final detail = LayoutBuilder(
              builder: (context, d) {
                final inline = d.maxWidth >= 620;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (inline)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          skip,
                          const SizedBox(width: SlushSpacing.s24),
                          Expanded(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 460,
                                ),
                                child: stack,
                              ),
                            ),
                          ),
                          const SizedBox(width: SlushSpacing.s24),
                          save,
                        ],
                      )
                    else ...[
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: stack,
                        ),
                      ),
                      const SizedBox(height: SlushSpacing.s24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(child: skip),
                          const SizedBox(width: SlushSpacing.s24),
                          Flexible(child: save),
                        ],
                      ),
                    ],
                    const SizedBox(height: SlushSpacing.s24),
                    counters,
                  ],
                );
              },
            );
            final body = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: detail),
                      const SizedBox(width: SlushSpacing.s24),
                      SizedBox(width: 380, child: filters),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      detail,
                      const SizedBox(height: SlushSpacing.s24),
                      filters,
                    ],
                  );
            final side = math.max(
              SlushSpacing.margin(box.maxWidth),
              (box.maxWidth - 1280) / 2,
            );
            return ListView(
              padding: EdgeInsets.fromLTRB(side, 8, side, 32),
              children: [
                FittedBox(
                  fit: BoxFit.fitWidth,
                  child: Text(
                    'AUROR',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontSize: 260,
                      height: .95,
                      letterSpacing: -6,
                    ),
                  ),
                ),
                const SizedBox(height: SlushSpacing.s8),
                DjSessionCard(controller: controller),
                for (final e in errors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: SlushSpacing.s8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline),
                        const SizedBox(width: SlushSpacing.s8),
                        Expanded(child: Text(e)),
                      ],
                    ),
                  ),
                const SizedBox(height: SlushSpacing.s12),
                body,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => Container(
    padding: const EdgeInsets.all(SlushSpacing.s24),
    decoration: _cardDeco(context, context.slush.paper, SlushRadius.r24),
    child: Column(
      children: [
        Text(
          'No quedan canciones para esta selección',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: SlushSpacing.s8),
        Text(
          'Prueba otros filtros, busca novedades o añade canciones a tu biblioteca.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.slush.ink2),
        ),
      ],
    ),
  );
}

BoxDecoration _cardDeco(
  BuildContext context,
  Color color, [
  double r = SlushRadius.r32,
]) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(r),
  border: Border.fromBorderSide(context.slush.borderSoft),
);

class _Stack extends StatelessWidget {
  const _Stack({required this.track, required this.reason, this.affinity});
  final Track track;
  final String reason;
  final double? affinity;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (track.album?.trim().isNotEmpty ?? false) track.album!,
      ...track.genres,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 28, 28, 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(14, 4),
              child: Transform.rotate(
                angle: .1,
                child: DecoratedBox(
                  decoration: _cardDeco(context, Slush.violet),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Transform.translate(
              offset: const Offset(-10, 8),
              child: Transform.rotate(
                angle: -.07,
                child: DecoratedBox(
                  decoration: _cardDeco(context, Slush.yellow),
                ),
              ),
            ),
          ),
          Container(
            key: const ValueKey('dj-discovery-card'),
            padding: const EdgeInsets.all(SlushSpacing.s16),
            decoration: _cardDeco(context, context.slush.paper),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: _cardDeco(context, Slush.lilac, SlushRadius.r16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(SlushRadius.r12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: (track.artworkUrl?.trim().isEmpty ?? true)
                          ? const _StarPlaceholder()
                          : Artwork.fill(
                              track: track,
                              artworkContext: ArtworkContext.playerCompact,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.slush.ink2,
                  ),
                ),
                if (track.duration > Duration.zero || meta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: SlushSpacing.s4),
                    child: Text(
                      [
                        if (meta.isNotEmpty) meta,
                        if (track.duration > Duration.zero)
                          '${track.duration.inMinutes}:${(track.duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: context.slush.ink3),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: SlushSpacing.s8,
                  runSpacing: SlushSpacing.s8,
                  children: [
                    if (affinity != null)
                      SlushPill(
                        '${(affinity! * 100).round()}% afinidad',
                        color: Slush.mint,
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 260),
                      child: SlushPill(reason, color: Slush.lilac),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            top: -26,
            left: 36,
            child: Transform.rotate(
              angle: -.1,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: context.slush.paper,
                  borderRadius: BorderRadius.circular(SlushRadius.r16),
                  border: Border.fromBorderSide(context.slush.border),
                  boxShadow: context.slush.shadowsFor(SlushElevation.control),
                ),
                child: Text(
                  'DJ AUROR',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontSize: 20),
                ),
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 700)
            Positioned(
              top: -34,
              right: -10,
              child: Transform.rotate(
                angle: .25,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.bolt, size: 64, color: context.slush.line),
                    const Icon(Icons.bolt, size: 52, color: Slush.violet),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Portada de reemplazo: estrella amarilla con centro naranja sobre lila.
class _StarPlaceholder extends StatelessWidget {
  const _StarPlaceholder();

  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: Slush.lilac,
    child: CustomPaint(painter: _StarPainter(), size: Size.infinite),
  );
}

class _StarPainter extends CustomPainter {
  const _StarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * .38;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + math.pi * i / 4;
      final rr = i.isEven ? r : r * .42;
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = Slush.yellow);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..color = Slush.ink;
    canvas.drawPath(path, line);
    final dot = Rect.fromCircle(center: c, radius: r * .26);
    canvas.drawOval(dot, Paint()..color = Slush.orange);
    canvas.drawOval(dot, line);
  }

  @override
  bool shouldRepaint(_StarPainter old) => false;
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    super.key,
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .5 : 1,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SlushPressable(
          onTap: onTap,
          elevation: SlushElevation.card,
          semanticLabel: label.replaceAll('←', '').replaceAll('→', '').trim(),
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.fromBorderSide(context.slush.border),
            ),
            child: Icon(icon, size: 42, color: slushOnColor(context, color)),
          ),
        ),
        const SizedBox(height: SlushSpacing.s12),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: SlushPill(label, color: context.slush.paper),
        ),
      ],
    ),
  );
}

class _Counter extends StatelessWidget {
  const _Counter(this.n, this.label);
  final int n;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: context.slush.paper,
      shape: StadiumBorder(side: context.slush.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$n', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );
}

/// Tarjeta «Filtros»: solo controles que existen en el DJ.
class _SlushFilters extends StatelessWidget {
  const _SlushFilters({required this.controller, required this.onSearch});
  final AppController controller;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final f = c.djFilters;
    Future<void> set(DjFilters n) => c.setDjFilters(n);
    DjFilters copy({
      List<String>? excludedArtists,
      List<String>? excludedGenres,
      List<String>? excludedTrackIds,
    }) => DjFilters(
      artists: f.artists,
      trackIds: f.trackIds,
      genres: f.genres,
      excludedArtists: excludedArtists ?? f.excludedArtists,
      excludedTrackIds: excludedTrackIds ?? f.excludedTrackIds,
      excludedGenres: excludedGenres ?? f.excludedGenres,
    );
    final titles = {for (final t in c.tracks) t.id: t.title};
    final blocked = <(String, VoidCallback)>[
      for (final a in f.excludedArtists)
        (
          a,
          () => set(copy(excludedArtists: [...f.excludedArtists]..remove(a))),
        ),
      for (final g in f.excludedGenres)
        (g, () => set(copy(excludedGenres: [...f.excludedGenres]..remove(g)))),
      for (final id in f.excludedTrackIds)
        (
          titles[id] ?? id,
          () =>
              set(copy(excludedTrackIds: [...f.excludedTrackIds]..remove(id))),
        ),
    ];
    final artists =
        c.tracks
            .map((t) => t.artist)
            .where((a) => a.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final yt = c.personalDjIncludeDiscovery;
    final busy = c.discoveringRecommendations;
    return Container(
      padding: const EdgeInsets.all(SlushSpacing.s16),
      decoration: _cardDeco(
        context,
        context.slush.paper,
        SlushRadius.r24,
      ).copyWith(boxShadow: context.slush.shadows),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtros', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: SlushSpacing.s8),
          _SwitchRow(
            'Novedades de YouTube',
            yt,
            c.setPersonalDjIncludeDiscovery,
          ),
          _SwitchRow(
            'Enfriar artistas',
            c.djArtistCooldown,
            c.setDjArtistCooldown,
          ),
          const SizedBox(height: SlushSpacing.s8),
          const Text(
            'Diversidad',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const _DotThumb(),
              trackHeight: 8,
              activeTrackColor: context.slush.ink,
              inactiveTrackColor: context.slush.ink,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: SizedBox(
              height: SlushControl.touch,
              child: Slider(
                value: c.djDiversity.clamp(0.0, djMaxDiversity),
                max: djMaxDiversity,
                onChanged: c.setDjDiversity,
              ),
            ),
          ),
          const SizedBox(height: SlushSpacing.s12),
          const Text(
            'Bloqueados',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: SlushSpacing.s8),
          Wrap(
            spacing: SlushSpacing.s8,
            runSpacing: SlushSpacing.s8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (blocked.isEmpty)
                Text(
                  'Nada bloqueado.',
                  style: TextStyle(fontSize: 12, color: context.slush.ink2),
                ),
              for (final b in blocked)
                SlushChip(
                  b.$1,
                  icon: Icons.close,
                  color: Slush.lilac,
                  onTap: b.$2,
                ),
              SlushChip(
                'Bloquear artista',
                icon: Icons.add,
                color: context.slush.paper,
                onTap: () async {
                  final sel = await DjFiltersPanel.choose(
                    context,
                    'Artistas bloqueados',
                    {for (final a in artists) a: a},
                    f.excludedArtists,
                  );
                  if (sel != null) await set(copy(excludedArtists: sel));
                },
              ),
              if (f.artists.length + f.trackIds.length + f.genres.length > 0 ||
                  blocked.isNotEmpty)
                SlushChip(
                  'Quitar filtros',
                  color: context.slush.paper,
                  onTap: () => set(const DjFilters()),
                ),
            ],
          ),
          const SizedBox(height: SlushSpacing.s12),
          Text(
            'Perfil local: ${c.tracks.length} canciones en tu biblioteca. '
            '${yt ? 'Con' : 'Sin'} recomendaciones de YouTube.',
            style: TextStyle(fontSize: 12, color: context.slush.ink2),
          ),
          const SizedBox(height: SlushSpacing.s12),
          Wrap(
            spacing: SlushSpacing.s8,
            runSpacing: SlushSpacing.s8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, SlushControl.bar),
                ),
                onPressed: busy || !c.canDiscoverRecommendations
                    ? null
                    : c.refreshRecommendations,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
                label: Text(busy ? 'BUSCANDO…' : 'ACTUALIZAR'),
              ),
              TextButton.icon(
                onPressed: onSearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Buscar música'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Switch(
        value: value,
        onChanged: onChanged,
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Slush.yellow : Slush.lilac,
        ),
      ),
      const SizedBox(width: SlushSpacing.s8),
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

/// Punto amarillo con borde negro para el slider.
class _DotThumb extends SliderComponentShape {
  const _DotThumb();
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(10);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 9, Paint()..color = Slush.yellow);
    canvas.drawCircle(
      center,
      9,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = SlushStroke.base
        ..color = sliderTheme.activeTrackColor ?? Slush.ink,
    );
  }
}
