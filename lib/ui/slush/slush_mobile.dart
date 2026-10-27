import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import 'slush_decor.dart';

const _bagel = 'Bagel Fat One';

Widget _circle(BuildContext context, Widget child) => DecoratedBox(
  decoration: BoxDecoration(
    color: context.slush.paper,
    shape: BoxShape.circle,
    border: Border.fromBorderSide(context.slush.border),
  ),
  child: Center(child: child),
);

/// Barra superior del Inicio móvil: logo «A» y botones circulares.
class SlushMobileTopBar extends StatelessWidget {
  const SlushMobileTopBar({
    super.key,
    required this.onSettings,
    required this.onMore,
  });
  final VoidCallback onSettings;
  final ValueChanged<int> onMore;

  static const _more = <(int, IconData, String)>[
    (3, Icons.download_outlined, 'Descargas'),
    (12, Icons.mic_none_rounded, 'Artistas'),
    (11, Icons.video_file_outlined, 'Descargar vídeos'),
    (14, Icons.people_outline, 'Amigos'),
    (4, Icons.album_outlined, 'Modo Vinilo'),
    (5, Icons.queue_music, 'Cola de reproducción'),
    (6, Icons.lyrics_outlined, 'Letras'),
    (13, Icons.equalizer, 'Ecualizador'),
  ];

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: Row(
      children: [
        SizedBox.square(
          dimension: 40,
          child: _circle(
            context,
            const Text('A', style: TextStyle(fontFamily: _bagel, fontSize: 20)),
          ),
        ),
        const Spacer(),
        PopupMenuButton<int>(
          tooltip: 'Más vistas',
          onSelected: onMore,
          child: SizedBox.square(
            dimension: 40,
            child: _circle(context, const Icon(Icons.more_horiz, size: 20)),
          ),
          itemBuilder: (_) => [
            for (final m in _more)
              PopupMenuItem(
                value: m.$1,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(m.$2),
                  title: Text(m.$3),
                ),
              ),
          ],
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Ajustes',
          child: GestureDetector(
            onTap: onSettings,
            child: SizedBox.square(
              dimension: 40,
              child: _circle(
                context,
                const Icon(Icons.dark_mode_outlined, size: 20),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Inicio móvil de Slush: «PARA TI.», tarjeta «Mix del día», chips y «Hace poco».
class SlushMobileHome extends StatefulWidget {
  const SlushMobileHome({
    super.key,
    required this.controller,
    required this.onSearch,
  });
  final AppController controller;
  final VoidCallback onSearch;

  @override
  State<SlushMobileHome> createState() => _SlushMobileHomeState();
}

class _SlushMobileHomeState extends State<SlushMobileHome> {
  int _filter = 0; // 0 todo, 1 favoritos, 2 descargas

  List<Track> _recent(AppController c) {
    final all = {
      for (final t in [...c.recentTracks, ...c.tracks]) t.id: t,
    }.values;
    final list = switch (_filter) {
      1 => all.where((t) => c.favoriteIds.contains(t.id)),
      2 => all.where((t) => t.isLocal),
      _ => c.recentTracks.isNotEmpty ? c.recentTracks : c.tracks,
    };
    return list.where((t) => !t.isPendingSpotifyMatch).take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final mix = c.recommendations.map((r) => r.track).toList();
    final pool = mix.isNotEmpty
        ? mix
        : c.tracks.where((t) => !t.isPendingSpotifyMatch).toList();
    final cover = pool.firstOrNull ?? c.recentTracks.firstOrNull;
    final recent = _recent(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 190,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              const Positioned(
                left: -24,
                right: -24,
                top: 50,
                child: SlushWave(height: 120),
              ),
              Text(
                'PARA\nTI.',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                  fontSize: 92,
                  height: .85,
                  letterSpacing: -3,
                ),
              ),
              const Positioned(
                right: 0,
                top: 20,
                child: SlushSticker('NUEVO', size: 72),
              ),
              const Positioned(
                right: 70,
                top: 100,
                child: SlushDecor(SlushShape.bolt, size: 34),
              ),
              const Positioned(
                left: 150,
                bottom: 4,
                child: SlushDecor(SlushShape.star, size: 26, color: Slush.mint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Transform.rotate(
          angle: -.02,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Slush.lilac,
              borderRadius: BorderRadius.circular(22),
              border: Border.fromBorderSide(context.slush.border),
              boxShadow: context.slush.shadows,
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: cover == null
                        ? _circle(context, const Icon(Icons.music_note))
                        : Artwork(track: cover, size: 64, radius: 14),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'MIX DEL DÍA',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Slush.ink,
                          ),
                        ),
                        Text(
                          '${pool.length} canciones',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Slush.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Reproducir mix',
                    style: IconButton.styleFrom(
                      backgroundColor: context.slush.ink,
                      foregroundColor: context.slush.paper,
                    ),
                    onPressed: pool.isEmpty
                        ? widget.onSearch
                        : () => c.playTrack(pool.first, context: pool),
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (i, label, color) in const [
              (0, 'TODO', Slush.lilac),
              (1, 'FAVORITOS', Slush.mint),
              (2, 'DESCARGAS', Slush.yellow),
            ])
              SlushChip(
                label,
                color: color,
                selected: _filter == i,
                onTap: () => setState(() => _filter = i),
              ),
          ],
        ),
        const SizedBox(height: 20),
        SlushBand(
          tone: Slush.mint,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HACE POCO',
                style: TextStyle(fontFamily: _bagel, fontSize: 34),
              ),
              const SizedBox(height: 10),
              if (recent.isEmpty)
                const Text('Aquí aparecerá lo que escuches.')
              else
                SizedBox(
                  height: 128,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: recent.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => c.playTrack(recent[i], context: recent),
                      child: SizedBox(
                        width: 92,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.fromBorderSide(
                                  context.slush.border,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Artwork(
                                  track: recent[i],
                                  size: 88,
                                  radius: 0,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              recent[i].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Mini reproductor en píldora de tinta (crema en oscuro).
class SlushMiniPlayer extends StatelessWidget {
  const SlushMiniPlayer({
    super.key,
    required this.controller,
    required this.onOpen,
    required this.onToggle,
    required this.onNext,
  });
  final AppController controller;
  final VoidCallback onOpen, onToggle, onNext;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final t = controller.currentTrack;
      if (t == null) return const SizedBox.shrink();
      final playing = controller.audio.isPlaying;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: context.slush.ink,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  ClipOval(child: Artwork(track: t, size: 40, radius: 0)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.slush.paper,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.slush.paper.withValues(alpha: .7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filled(
                    tooltip: playing ? 'Pausar' : 'Reproducir',
                    style: IconButton.styleFrom(
                      backgroundColor: context.slush.paper,
                      foregroundColor: context.slush.ink,
                    ),
                    onPressed: onToggle,
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Siguiente',
                    onPressed: onNext,
                    icon: Icon(
                      Icons.skip_next_rounded,
                      color: context.slush.paper,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Zona inferior de Slush en móvil: mini reproductor (opcional) y barra de
/// iconos en píldora de papel; el destino activo va en círculo de tinta.
class SlushBottomBar extends StatelessWidget {
  const SlushBottomBar({
    super.key,
    required this.icons,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.mini,
  });
  final List<IconData> icons;
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget? mini;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?mini,
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.slush.paper,
              borderRadius: BorderRadius.circular(999),
              border: Border.fromBorderSide(context.slush.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (var i = 0; i < icons.length; i++)
                    Semantics(
                      button: true,
                      selected: i == selected,
                      label: labels[i],
                      child: Tooltip(
                        message: labels[i],
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(i),
                          child: Container(
                            width: 48,
                            height: 40,
                            decoration: BoxDecoration(
                              color: i == selected ? context.slush.ink : null,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Icon(
                              icons[i],
                              size: 22,
                              color: i == selected
                                  ? context.slush.paper
                                  : context.slush.ink,
                            ),
                          ),
                        ),
                      ),
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
