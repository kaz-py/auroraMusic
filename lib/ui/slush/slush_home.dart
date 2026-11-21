import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import 'slush_decor.dart';

/// Blanco cálido sobre tinta (texto de la píldora negra; no depende del modo).
const _cream = Color(0xfffffdf8);

/// «2 h 04» / «45 min» a partir de la suma de duraciones; null si no hay datos.
String? slushTotalTime(Iterable<Track> tracks) {
  final min = tracks.fold<Duration>(Duration.zero, (a, t) => a + t.duration);
  if (min == Duration.zero) return null;
  final m = min.inMinutes;
  return m >= 60
      ? '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}'
      : '$m min';
}

/// «Buenas noches, Pablo» (sin nombre: solo el saludo).
String slushGreeting(AppController c, [DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  final base = h < 6
      ? 'Buenas noches'
      : h < 12
      ? 'Buenos días'
      : h < 20
      ? 'Buenas tardes'
      : 'Buenas noches';
  final name = c.profileName.trim();
  return name.isEmpty ? base : '$base, $name';
}

String _subtitle([DateTime? now]) {
  final n = now ?? DateTime.now();
  const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  final when = n.hour < 6
      ? 'de madrugada'
      : n.hour < 12
      ? 'por la mañana'
      : n.hour < 20
      ? 'por la tarde'
      : 'por la noche';
  return '${days[n.weekday - 1]} $when. Retoma donde lo dejaste o deja que el DJ decida.';
}

String _mmss(Duration d) =>
    '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

/// Ánimos del Inicio: etiqueta, color y palabras clave (género, título o
/// artista). `null` = papel.
const _moods = <(String, Color?, List<String>)>[
  ('Todo', null, []),
  (
    'Enfoque',
    Slush.pink,
    [
      'focus',
      'study',
      'ambient',
      'instrumental',
      'chill',
      'lofi',
      'lo-fi',
      'classical',
      'clásica',
      'piano',
      'jazz',
    ],
  ),
  (
    'Energía',
    Slush.yellow,
    [
      'rock',
      'pop',
      'dance',
      'electro',
      'edm',
      'house',
      'techno',
      'punk',
      'metal',
    ],
  ),
  (
    'Lluvia',
    Slush.mint,
    ['rain', 'lluvia', 'acoustic', 'acústic', 'folk', 'blues', 'indie', 'soul'],
  ),
  (
    'Nostalgia',
    Slush.lilac,
    ['70s', '80s', '90s', 'retro', 'oldies', 'vintage', 'disco', 'clásic'],
  ),
  (
    'Gimnasio',
    null,
    ['workout', 'gym', 'fitness', 'trap', 'hip hop', 'rap', 'bass', 'metal'],
  ),
  (
    'Viaje',
    null,
    ['road', 'trip', 'travel', 'latin', 'reggae', 'world', 'country', 'folk'],
  ),
];

/// Pistas de [tracks] que encajan con el ánimo [mood] (0 = todas).
List<Track> slushMoodTracks(List<Track> tracks, int mood) {
  if (mood <= 0 || mood >= _moods.length) return tracks;
  final keys = _moods[mood].$3;
  return [
    for (final t in tracks)
      if (keys.any(
        '${t.genres.join(' ')} ${t.title} ${t.artist}'.toLowerCase().contains,
      ))
        t,
  ];
}

/// Fila de chips de ánimo, cada uno con su color; el activo es tinta.
class SlushMoodChips extends StatelessWidget {
  const SlushMoodChips({
    super.key,
    required this.selected,
    required this.onSelected,
    this.scroll = false,
  });
  final int selected;
  final ValueChanged<int> onSelected;

  /// true: una sola fila con desplazamiento horizontal (móvil).
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final chips = [
      for (final (i, m) in _moods.indexed)
        SlushChip(
          m.$1,
          color: m.$2 ?? p.paper,
          selected: selected == i,
          elevation: SlushElevation.control,
          onTap: () => onSelected(i),
        ),
    ];
    if (scroll) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(right: 6, bottom: 4),
        child: Row(
          children: [
            for (final (i, c) in chips.indexed) ...[
              if (i > 0) const SizedBox(width: 10),
              c,
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 3, bottom: 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chips,
      ),
    );
  }
}

/// Portada cuadrada con borde de tinta de 2 px, esquinas [radius] y, si
/// [shadow], sombra dura de tarjeta.
class SlushCover extends StatelessWidget {
  const SlushCover({
    super.key,
    required this.track,
    required this.side,
    this.radius = SlushRadius.r24,
    this.shadow = false,
  });
  final Track? track;
  final double side;
  final double radius;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final t = track;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.fromBorderSide(p.border),
        color: p.inset,
        boxShadow: shadow ? p.shadowsFor(SlushElevation.card) : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(math.max(0, radius - 2)),
        child: SizedBox.square(
          dimension: side,
          child: t == null
              ? Icon(Icons.music_note_rounded, size: side * .4, color: p.ink2)
              : Artwork(track: t, size: side, radius: 0),
        ),
      ),
    );
  }
}

/// Portada tocable con título y artista debajo (cuadrícula de «Para ti»).
class SlushCoverTile extends StatelessWidget {
  const SlushCoverTile({
    super.key,
    required this.track,
    required this.width,
    required this.onTap,
    this.radius = SlushRadius.r24,
    this.angle = 0,
  });
  final Track track;
  final double width;
  final VoidCallback onTap;
  final double radius;
  final double angle;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: angle,
            child: SlushPressable(
              onTap: onTap,
              radius: radius,
              elevation: SlushElevation.card,
              semanticLabel: 'Reproducir ${track.title}',
              child: SlushCover(track: track, side: width, radius: radius),
            ),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: slushHeadline(16, height: 1.2, color: p.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: p.ink2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Círculo pulsable con borde de tinta y sombra de control.
class _Circle extends StatelessWidget {
  const _Circle({
    required this.size,
    required this.fill,
    required this.icon,
    required this.label,
    required this.onTap,
    this.fg = Slush.ink,
  });
  final double size;
  final Color fill;
  final Color fg;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SlushPressable(
    onTap: onTap,
    semanticLabel: label,
    child: Tooltip(
      message: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          shape: BoxShape.circle,
          border: Border.fromBorderSide(context.slush.border),
        ),
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, size: size * .5, color: fg),
        ),
      ),
    ),
  );
}

/// Píldora de papel (o [fill]) con texto en negrita y borde de tinta.
class _Pill extends StatelessWidget {
  const _Pill(this.label, this.onTap, {this.icon});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return SlushPressable(
      onTap: onTap,
      semanticLabel: label,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: p.paper,
          shape: StadiumBorder(side: p.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: p.ink),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    color: p.ink,
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

/// Píldora informativa: tinta con texto crema (o [fill]/[fg]).
class _Tag extends StatelessWidget {
  const _Tag(
    this.label, {
    this.fill = Slush.ink,
    this.fg = _cream,
    this.mono = false,
  });
  final String label;
  final Color fill, fg;
  final bool mono;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: Text(
        label,
        style: mono
            ? slushMono(13, color: fg)
            : TextStyle(
                fontSize: 13,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
      ),
    ),
  );
}

BoxDecoration _cardDecoration(BuildContext context, Color fill) {
  final p = context.slush;
  return BoxDecoration(
    color: fill,
    borderRadius: BorderRadius.circular(SlushRadius.r32),
    border: Border.fromBorderSide(p.borderSoft),
    boxShadow: p.shadowsFor(SlushElevation.card),
  );
}

/// Inicio de escritorio de Slush: saludo, tarjeta lila «Seguir escuchando»,
/// tarjeta amarilla «DJ personal» y «Para ti esta noche» con chips de ánimo.
class SlushHome extends StatefulWidget {
  const SlushHome({
    super.key,
    required this.controller,
    required this.onSearch,
    this.onSearchQuery,
  });
  final AppController controller;
  final VoidCallback onSearch;

  /// Abre la búsqueda con un texto (Ver álbum); sin él se abre vacía.
  final ValueChanged<String>? onSearchQuery;

  @override
  State<SlushHome> createState() => _SlushHomeState();
}

class _SlushHomeState extends State<SlushHome> {
  int _mood = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final p = context.slush;
    final mix = c.recommendations.map((r) => r.track).toList();
    final pool = mix.isNotEmpty
        ? mix
        : c.tracks.where((t) => !t.isPendingSpotifyMatch).toList();
    final shown = slushMoodTracks(pool, _mood).take(12).toList();
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final side = w >= 860;
        final base = ((w - 80) / 5.1).clamp(140.0, 240.0);
        final now = _NowCard(
          controller: c,
          pool: pool,
          onSearch: widget.onSearch,
          onSearchQuery: widget.onSearchQuery,
          innerWidth: (side ? (w - SlushSpacing.s24) * 3 / 5 : w) - 48,
        );
        final dj = SlushDjCard(controller: c, count: pool.length);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                slushGreeting(c),
                style: slushHeadline(w >= 900 ? 50 : 40, color: p.ink),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle(),
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: p.ink2,
              ),
            ),
            const SizedBox(height: SlushSpacing.s24),
            if (side)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: now),
                    const SizedBox(width: SlushSpacing.s24),
                    Expanded(flex: 2, child: dj),
                  ],
                ),
              )
            else ...[
              now,
              const SizedBox(height: SlushSpacing.s24),
              dj,
            ],
            const SizedBox(height: SlushSpacing.s32),
            Wrap(
              spacing: SlushSpacing.s24,
              runSpacing: SlushSpacing.s12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Para ti esta noche',
                  style: slushHeadline(28, color: p.ink),
                ),
                SlushMoodChips(
                  selected: _mood,
                  onSelected: (i) => setState(() => _mood = i),
                ),
              ],
            ),
            const SizedBox(height: SlushSpacing.s16),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  c.tracks.isEmpty
                      ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                      : 'Ninguna pista encaja con este ánimo todavía.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: p.ink,
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.only(top: 10, right: 12, bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, t) in shown.indexed) ...[
                      if (i > 0) const SizedBox(width: 20),
                      SlushCoverTile(
                        track: t,
                        width: i == 0 ? base * 1.12 : base,
                        angle: i == 0 ? 0 : (i.isOdd ? -.035 : .035),
                        onTap: () => c.playTrack(t, context: shown),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tarjeta lila «Seguir escuchando»: pista actual (o la última reciente),
/// progreso, Play lima, «Ver álbum» y chip FLAC si el archivo es FLAC.
class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.controller,
    required this.pool,
    required this.onSearch,
    required this.innerWidth,
    this.onSearchQuery,
  });
  final AppController controller;
  final List<Track> pool;

  /// Ancho útil de la tarjeta (sin padding): decide el tamaño de portada sin
  /// LayoutBuilder, para poder vivir dentro de un IntrinsicHeight.
  final double innerWidth;
  final VoidCallback onSearch;
  final ValueChanged<String>? onSearchQuery;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final p = context.slush;
      final cur = c.currentTrack;
      final track = cur ?? c.recentTracks.firstOrNull ?? pool.firstOrNull;
      final isCur = cur != null && track?.id == cur.id;
      final dur = isCur ? c.audio.duration : Duration.zero;
      final pos = isCur ? c.audio.position : Duration.zero;
      final frac = dur > Duration.zero
          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
          : 0.0;
      final playing = isCur && c.audio.isPlaying;
      final meta = [
        if (track != null) track.artist,
        if (isCur && c.queue.length > 1)
          'pista ${c.queueIndex + 1} de ${c.queue.length}',
        if (dur > pos) 'quedan ${_mmss(dur - pos)}',
      ].join(' · ');
      final flac = track?.localPath?.toLowerCase().endsWith('.flac') ?? false;
      void play() {
        if (track == null) return onSearch();
        if (isCur) {
          c.togglePlayback();
        } else {
          c.playTrack(track, context: pool.isEmpty ? [track] : pool);
        }
      }

      return DecoratedBox(
        decoration: _cardDecoration(context, Slush.lilacHero),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Builder(
            builder: (context) {
              final narrow = innerWidth < 520;
              final cover = narrow ? 120.0 : 172.0;
              final info = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _Tag('Seguir escuchando'),
                  const SizedBox(height: 12),
                  Text(
                    track?.title ?? 'Tu música aparece aquí',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: slushHeadline(
                      narrow ? 26 : 34,
                      height: 1.05,
                      color: Slush.ink,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Slush.ink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Progreso',
                    value: '${(frac * 100).round()} %',
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: p.paper,
                        shape: StadiumBorder(side: p.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                          height: 14,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: frac,
                              heightFactor: 1,
                              child: ColoredBox(color: p.violetAccent),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _Circle(
                        size: 60,
                        fill: Slush.lime,
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        label: playing ? 'Pausar' : 'Reproducir',
                        onTap: play,
                      ),
                      if (track != null)
                        _Pill(
                          'Ver álbum',
                          () => onSearchQuery != null
                              ? onSearchQuery!(track.album ?? track.title)
                              : onSearch(),
                        ),
                      if (flac)
                        const _Tag(
                          'FLAC',
                          fill: Slush.ink,
                          fg: Slush.lime,
                          mono: true,
                        ),
                    ],
                  ),
                ],
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SlushCover(track: track, side: cover, shadow: true),
                  SizedBox(width: cover > 130 ? 28 : 16),
                  Expanded(child: info),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// Tarjeta amarilla «DJ personal». [compact] (móvil): título y botón Play en
/// una fila, sin onda. Reutiliza [AppController.startDjSession] y
/// [AppController.refreshRecommendations].
class SlushDjCard extends StatelessWidget {
  const SlushDjCard({
    super.key,
    required this.controller,
    required this.count,
    this.compact = false,
  });
  final AppController controller;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = context.slush;
    final detail = count == 0
        ? 'Tus favoritas y escuchas recientes, mezcladas por el DJ'
        : '$count pistas · tus favoritas y escuchas recientes';
    final play = _Circle(
      size: compact ? 64 : 52,
      fill: Slush.ink,
      fg: Slush.lime,
      icon: Icons.play_arrow_rounded,
      label: 'Iniciar DJ personal',
      onTap: () => c.startDjSession(),
    );
    final title = Text(
      'Mix de medianoche',
      style: slushHeadline(compact ? 26 : 32, height: 1.05, color: Slush.ink),
    );
    final body = Text(
      detail,
      maxLines: compact ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        height: 1.35,
        fontWeight: FontWeight.w500,
        color: Slush.ink,
      ),
    );
    return DecoratedBox(
      decoration: _cardDecoration(context, Slush.yellow),
      child: Padding(
        padding: EdgeInsets.all(compact ? 20 : 24),
        child: compact
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Tag('DJ personal'),
                        const SizedBox(height: 10),
                        title,
                        const SizedBox(height: 4),
                        body,
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  play,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const _Tag('DJ personal'),
                  const SizedBox(height: 14),
                  title,
                  const SizedBox(height: 8),
                  body,
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _WavePainter(Slush.ink, p.ink2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      play,
                      _Pill(
                        'Otro mix',
                        c.refreshRecommendations,
                        icon: Icons.auto_awesome,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// Onda de barras redondeadas: el primer 45 % en tinta, el resto atenuado.
/// Decorativa y estática.
class _WavePainter extends CustomPainter {
  const _WavePainter(this.on, this.off);
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 7.0;
    final n = (size.width / step).floor();
    final paint = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final v =
          (math.sin(i * .55) + math.sin(i * 1.7 + 1) * .6 + math.cos(i * .23))
              .abs() /
          2.2;
      final h = (size.height * (.18 + v * .82)).clamp(4.0, size.height);
      final x = i * step + 1.5;
      paint.color = i < n * .45 ? on : off.withValues(alpha: .45);
      canvas.drawLine(
        Offset(x, (size.height - h) / 2),
        Offset(x, (size.height + h) / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.on != on || old.off != off;
}
