/// Dueño: tema Brasa. Página de Inicio («Salón con estufa»): fecha mono,
/// saludo serif, filtros, «Seguir escuchando», banda DJ y recomendaciones.
library;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../playlist_shelf.dart';
import '../studio/home_introduction.dart';
import '../track_actions.dart';
import 'brasa_home_dj.dart';
import 'brasa_home_widgets.dart';
import 'home_theme.dart';

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// «JUEVES 12 DE NOVIEMBRE · 21:40».
String brasaDateLine(DateTime t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${_weekdays[t.weekday - 1]} ${t.day} de ${_months[t.month - 1]} · $hh:$mm'
      .toUpperCase();
}

/// Saludo según la hora local.
String brasaGreeting(DateTime t) => t.hour < 6 || t.hour >= 20
    ? 'Buenas noches'
    : t.hour < 13
    ? 'Buenos días'
    : 'Buenas tardes';

/// Fecha, saludo y lema. En móvil, lema discreto y sin fecha.
class BrasaGreeting extends StatelessWidget {
  const BrasaGreeting({super.key, required this.name, this.mobile = false});
  final String name;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final now = studioClock();
    final greet = brasaGreeting(now);
    final hello = name.trim().isEmpty ? '$greet.' : '$greet, ${name.trim()}.';
    final size = mobile ? 30.0 : 32.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!mobile) ...[
          Text(
            brasaDateLine(now),
            style: Brasa.mono(11, weight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
        ],
        Semantics(
          header: true,
          child: Text(hello, style: Brasa.serif(size, height: 1.08)),
        ),
        if (mobile)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Hay brasas en la estufa.',
              style: Brasa.sans(14, color: Brasa.cloud),
            ),
          )
        else
          Text(
            'Hay brasas en la estufa.',
            style: Brasa.serif(size, color: Brasa.amber, height: 1.08),
          ),
      ],
    );
  }
}

class BrasaHomePage extends StatefulWidget {
  const BrasaHomePage({super.key, required this.data});
  final HomePageData data;

  @override
  State<BrasaHomePage> createState() => _BrasaHomePageState();
}

class _BrasaHomePageState extends State<BrasaHomePage> {
  BrasaHomeFilter _filter = BrasaHomeFilter.all;

  HomePageData get d => widget.data;

  String _tooltip(Track t, String verb) => t.isPendingSpotifyMatch
      ? 'Elegir audio para ${t.title}'
      : '$verb ${t.title}';

  /// Tarjeta de carril de una pista con sus menús (clic derecho / pulsación larga).
  Widget _card(
    BuildContext context,
    Track t,
    List<Track> list, {
    required double aspect,
    bool replaceQueue = true,
  }) => TrackActionsRegion(
    controller: d.controller,
    track: t,
    builder: (context, _) => BrasaCoverCard(
      cover: t,
      title: t.title,
      subtitle: t.artist,
      aspect: aspect,
      playing: d.controller.currentTrack?.id == t.id,
      tooltip: _tooltip(t, 'Reproducir'),
      onTap: () => d.play(context, t, list, replaceQueue: replaceQueue),
    ),
  );

  Widget _trackShelf(
    BuildContext context, {
    required Key key,
    required String title,
    String? subtitle,
    required List<Track> tracks,
    required List<Track> playList,
    required bool replaceQueue,
    required double pad,
    required double inner,
    required bool mobile,
  }) {
    final itemW = mobile
        ? 132.0
        : ((inner + 16) / 6 - 16).clamp(160.0, 240.0).toDouble();
    final aspect = mobile ? 1.0 : 2.0;
    return BrasaShelf(
      key: key,
      title: title,
      subtitle: subtitle,
      count: tracks.length,
      pad: pad,
      gap: mobile ? 12 : 16,
      itemWidth: itemW,
      itemHeight: BrasaCoverCard.heightFor(context, itemW / aspect),
      itemBuilder: (context, i) => _card(
        context,
        tracks[i],
        playList,
        aspect: aspect,
        replaceQueue: replaceQueue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final c = d.controller;
      final w = box.maxWidth;
      final mobile = MediaQuery.sizeOf(context).width < 600;
      final pad = w >= 600 ? 40.0 : 20.0;
      final inner = w - pad * 2;
      const gap = SizedBox(height: 28);
      Widget padded(Widget child) => Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: child,
      );

      final chips = BrasaFilterChips(
        selected: _filter,
        mobile: mobile,
        alignment: inner >= 760 ? WrapAlignment.end : WrapAlignment.start,
        onChanged: (f) => setState(() => _filter = f),
      );
      final greeting = BrasaGreeting(name: c.profileName, mobile: mobile);

      final recent = (c.recentTracks.isNotEmpty ? c.recentTracks : c.tracks)
          .where((t) => !t.isPendingSpotifyMatch && _filter.accepts(t))
          .toList();
      final recs = [
        for (final r in d.recommendations)
          if (_filter.accepts(r.track)) r.track,
      ];
      final library = c.tracks.where(_filter.accepts).toList();
      final discovered = c.discoveredRecommendations
          .where(_filter.accepts)
          .toList();
      final djCovers = [
        for (final t in [...recs, ...c.tracks])
          if (t.artworkUrl?.isNotEmpty == true) t,
      ];
      final seen = <String>{};
      final covers = [
        for (final t in djCovers)
          if (seen.add(t.artworkUrl!)) t,
      ];

      return ListView(
        padding: EdgeInsets.only(top: mobile ? 0 : 24, bottom: 32),
        children: [
          if (mobile) _MobileHeader(pad: pad, onSettings: d.onSettings),
          padded(
            inner >= 760
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: greeting),
                      const SizedBox(width: 24),
                      Flexible(child: chips),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      greeting,
                      SizedBox(height: mobile ? 12 : 16),
                      chips,
                    ],
                  ),
          ),
          SizedBox(height: mobile ? 16 : 20),
          padded(
            c.tracks.isEmpty
                ? _Welcome(d: d)
                : _Continue(
                    key: const ValueKey('home-recent'),
                    d: d,
                    tracks: recent,
                    inner: inner,
                    mobile: mobile,
                    filtered: _filter != BrasaHomeFilter.all,
                  ),
          ),
          gap,
          padded(
            BrasaDjBand(controller: c, covers: covers, wide: inner >= 520),
          ),
          gap,
          if (recs.isNotEmpty)
            _trackShelf(
              context,
              key: const ValueKey('home-recommendations'),
              title: 'Recomendaciones para ti',
              subtitle: d.personalized
                  ? null
                  : 'Aún no hay señales personales; elegimos de tu biblioteca',
              tracks: recs,
              playList: d.recommendedTracks,
              replaceQueue: false,
              pad: pad,
              inner: inner,
              mobile: mobile,
            )
          else
            padded(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BrasaSectionHeader('Recomendaciones para ti', mobile: mobile),
                  Text(
                    c.tracks.isEmpty
                        ? 'Añade canciones reproducibles y aparecerán recomendaciones aquí.'
                        : 'No hay recomendaciones disponibles con tus filtros y escucha actual.',
                    style: Brasa.sans(14, color: Brasa.cloud),
                  ),
                ],
              ),
            ),
          if (discovered.isNotEmpty) ...[
            gap,
            _trackShelf(
              context,
              key: const ValueKey('home-discovered'),
              title: 'Encontradas en YouTube',
              subtitle: 'Búsqueda solicitada por ti',
              tracks: discovered,
              playList: c.discoveredRecommendations,
              replaceQueue: false,
              pad: pad,
              inner: inner,
              mobile: mobile,
            ),
          ],
          if (c.playlists.isNotEmpty) ...[
            gap,
            padded(
              PlaylistShelf(
                controller: c,
                horizontal: true,
                onOpen: d.onOpenPlaylist,
              ),
            ),
          ],
          if (d.followed.isNotEmpty) ...[
            gap,
            BrasaShelf(
              key: const ValueKey('home-artists'),
              title: 'Tus artistas',
              count: d.followed.length,
              pad: pad,
              gap: 16,
              itemWidth: 132,
              itemHeight: BrasaCoverCard.heightFor(context, 132),
              itemBuilder: (context, i) => d.followedCard(d.followed[i]),
            ),
          ],
          if (library.isNotEmpty) ...[
            gap,
            _trackShelf(
              context,
              key: const ValueKey('home-library'),
              title: 'Tu colección',
              subtitle:
                  '${c.tracks.length} canciones · ${c.playlists.length} listas',
              tracks: library,
              playList: c.tracks,
              replaceQueue: true,
              pad: pad,
              inner: inner,
              mobile: mobile,
            ),
          ],
        ],
      );
    },
  );
}

/// Cabecera móvil: logo con ascua, «Aurora» y ajustes (≥48). Sin botón de
/// cast: la app no tiene emisión a dispositivos.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.pad, required this.onSettings});
  final double pad;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(pad, 4, pad - 8, 4),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              gradient: const RadialGradient(
                center: Alignment(0, .4),
                colors: [Color(0xffffb04a), Brasa.ember, Color(0xffb3401f)],
                stops: [0, .45, 1],
              ),
              boxShadow: [
                BoxShadow(
                  color: Brasa.ember.withValues(alpha: .5),
                  blurRadius: 12,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Aurora',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Brasa.serif(20, wght: 700, tracking: -.01),
            ),
          ),
          if (onSettings != null)
            IconButton(
              tooltip: 'Ajustes',
              color: Brasa.cloud,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
        ],
      ),
    ),
  );
}

/// Biblioteca vacía: invitación a empezar.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.d});
  final HomePageData d;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tu historia empieza aquí', style: Brasa.serif(22)),
        const SizedBox(height: 8),
        Text(
          'Busca una canción o abre tus archivos para comenzar.',
          style: Brasa.sans(14, color: Brasa.cloud),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Brasa.ember,
                foregroundColor: Brasa.onEmber,
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: d.onSearch,
              icon: const Icon(Icons.search),
              label: const Text('Encontrar música'),
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Brasa.cream,
                minimumSize: const Size(0, 48),
                side: BorderSide.none,
                backgroundColor: Brasa.ash,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: d.controller.importFiles,
              icon: const Icon(Icons.add),
              label: const Text('Añadir música a tu biblioteca'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// «Seguir escuchando»: hero + filas compactas (escritorio) o teselas (móvil).
class _Continue extends StatelessWidget {
  const _Continue({
    super.key,
    required this.d,
    required this.tracks,
    required this.inner,
    required this.mobile,
    required this.filtered,
  });
  final HomePageData d;
  final List<Track> tracks;
  final double inner;
  final bool mobile, filtered;

  Widget _track(
    BuildContext context,
    Track t,
    Widget Function(BuildContext context, VoidCallback onPlay, bool playing) b,
  ) => TrackActionsRegion(
    controller: d.controller,
    track: t,
    builder: (context, _) => b(
      context,
      () => d.play(context, t, tracks),
      d.controller.currentTrack?.id == t.id,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final header = BrasaSectionHeader('Seguir escuchando', mobile: mobile);
    if (tracks.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          Text(
            filtered
                ? 'No hay pistas que cumplan este filtro.'
                : 'Aún no has escuchado nada.',
            style: Brasa.sans(14, color: Brasa.cloud),
          ),
        ],
      );
    }
    Widget hero(Track t) => _track(
      context,
      t,
      (context, onPlay, playing) =>
          _Hero(track: t, playing: playing, onPlay: onPlay),
    );
    Widget row(Track t) => _track(
      context,
      t,
      (context, onPlay, playing) =>
          _RowTile(track: t, playing: playing, onPlay: onPlay),
    );
    Widget tile(Track t) => _track(
      context,
      t,
      (context, onPlay, playing) =>
          _CompactTile(track: t, playing: playing, onPlay: onPlay),
    );
    Widget pairs(List<Widget> items, int cols) => Column(
      children: [
        for (var i = 0; i < items.length; i += cols) ...[
          if (i > 0) SizedBox(height: mobile ? 8 : 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var j = i; j < i + cols; j++) ...[
                if (j > i) SizedBox(width: mobile ? 8 : 12),
                Expanded(child: j < items.length ? items[j] : const SizedBox()),
              ],
            ],
          ),
        ],
      ],
    );

    final Widget body;
    if (mobile || inner < 520) {
      final cols = inner >= 340 && scale <= 1.3 ? 2 : 1;
      body = pairs([for (final t in tracks.take(4)) tile(t)], cols);
    } else {
      final rest = tracks.skip(1).take(4).toList();
      final rows = [for (final t in rest) row(t)];
      if (inner >= 700 && scale <= 1.4) {
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 135, child: hero(tracks.first)),
            const SizedBox(width: 12),
            Expanded(
              flex: 200,
              child: rows.isEmpty ? const SizedBox() : pairs(rows, 2),
            ),
          ],
        );
      } else {
        body = Column(
          children: [
            hero(tracks.first),
            if (rows.isNotEmpty) ...[
              const SizedBox(height: 12),
              pairs(rows, inner >= 560 && scale <= 1.4 ? 2 : 1),
            ],
          ],
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [header, body],
    );
  }
}

/// Tarjeta hero: portada atenuada de fondo, etiqueta, título y play squircle.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.track,
    required this.playing,
    required this.onPlay,
  });
  final Track track;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final detail = [
      track.artist,
      if (track.album?.trim().isNotEmpty == true) track.album!.trim(),
    ].where((s) => s.trim().isNotEmpty).join(' · ');
    return RepaintBoundary(
      child: Material(
        color: Brasa.graphite,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPlay,
          child: Stack(
            children: [
              Positioned.fill(child: BrasaFill(track: track, px: 360)),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Brasa.graphite.withValues(alpha: .65),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x8C0F0A08), Color(0xF00F0A08)],
                      stops: [.1, 1],
                    ),
                  ),
                ),
              ),
              Container(
                constraints: const BoxConstraints(minHeight: 168),
                alignment: Alignment.bottomLeft,
                padding: const EdgeInsets.fromLTRB(20, 20, 88, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BrasaCaption(
                      'Continúa donde lo dejaste',
                      dot: true,
                      color: Brasa.cloud,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      track.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Brasa.serif(
                        26,
                        color: playing ? Brasa.ember : Brasa.cream,
                      ),
                    ),
                    if (detail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        detail,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.sans(14, color: Brasa.cloud),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: BrasaPlayButton(
                  onPressed: onPlay,
                  tooltip: track.isPendingSpotifyMatch
                      ? 'Elegir audio para ${track.title}'
                      : 'Reproducir ${track.title}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila compacta de escritorio: portada 56, título, artista y tiempo mono.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.track,
    required this.playing,
    required this.onPlay,
  });
  final Track track;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final time = brasaClock(track.duration);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Semantics(
      button: true,
      label: 'Reproducir ${track.title}',
      excludeSemantics: true,
      onTap: onPlay,
      child: Material(
        color: Brasa.graphite,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          hoverColor: Brasa.ash,
          onTap: onPlay,
          child: LayoutBuilder(
            builder: (context, box) => ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 78),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: BrasaCover(track: track, radius: 10, px: 112),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Brasa.sans(
                              14,
                              color: playing ? Brasa.ember : Brasa.cream,
                              weight: FontWeight.w700,
                              height: 1.25,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Brasa.sans(
                              12,
                              color: Brasa.cloud,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (time.isNotEmpty && box.maxWidth >= 230 && scale <= 1.3)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 8),
                        child: Text(time, style: Brasa.mono(11, tracking: .04)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tesela compacta móvil: portada 56 a sangre + título (hasta 2 líneas).
class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.track,
    required this.playing,
    required this.onPlay,
  });
  final Track track;
  final bool playing;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Reproducir ${track.title}',
    excludeSemantics: true,
    onTap: onPlay,
    child: Material(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              SizedBox(
                width: 56,
                height: 56,
                child: BrasaFill(track: track, px: 112),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    track.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Brasa.sans(
                      13,
                      color: playing ? Brasa.ember : Brasa.cream,
                      weight: FontWeight.w500,
                      height: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    ),
  );
}
