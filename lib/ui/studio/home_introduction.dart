import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../slush/slush_home.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

/// Reloj de la portada; los tests lo fijan para no depender de la hora real.
@visibleForTesting
DateTime Function() studioClock = DateTime.now;

/// Título editorial de la portada según la hora local.
String studioGreeting(DateTime t) => switch (t.hour) {
  < 5 => 'Madrugada acústica',
  < 8 => 'Amanecer sonoro',
  < 12 => 'Mañana en calma',
  < 15 => 'Mediodía de vinilo',
  < 19 => 'Tarde en cinta',
  < 22 => 'Anochecer cálido',
  _ => 'Noche de válvulas',
};

/// Native translation of the reference's editorial header and master sleeve.
class StudioHomeIntroduction extends StatelessWidget {
  const StudioHomeIntroduction({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onVinyl,
    this.onSearchQuery,
  });
  final AppController controller;
  final VoidCallback onSearch, onVinyl;
  final ValueChanged<String>? onSearchQuery;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final track =
        c.currentTrack ??
        c.recentTracks.firstOrNull ??
        c.tracks.where((t) => !t.isPendingSpotifyMatch).firstOrNull;
    if (isBrasa(context)) return _brasa(context);
    if (isSlush(context)) return _slush(context, track);
    if (isModern(context)) return _modern(context, track);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          children: [
            StudioStamp(
              '● CALIBRACIÓN DE SEÑAL · VÁLVULAS CALIENTES',
              color: colors.primary,
            ),
            const StudioStamp('LATENCIA DAC: NO MEDIDA // MOTOR AURORA'),
          ],
        ),
        const SizedBox(height: 16),
        const StudioGreetingRow(),
        const SizedBox(height: 8),
        Text(
          'La resonancia del recinto está optimizada a 432Hz. El flujo analógico simula la atenuación natural de cinta magnética Studer A800.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: colors.tertiary),
        ),
        const SizedBox(height: 4),
        const StudioStamp(
          'TEXTO DE REFERENCIA · SIMULACIÓN ANALÓGICA PENDIENTE',
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _mood(
                context,
                StudioSymbols.waterDrop,
                'Tarde Lluviosa',
                () => showStudioPending(context, 'Ánimos de escucha'),
              ),
              _mood(
                context,
                StudioSymbols.graphicEq,
                'Cinta Magnética',
                () => showStudioPending(context, 'Simulación de cinta'),
              ),
              _mood(context, StudioSymbols.nightlife, 'Improvisación Jazz', () {
                _searchMood('jazz');
              }),
              _mood(
                context,
                StudioSymbols.psychology,
                'Enfoque Profundo',
                () => showStudioPending(context, 'Perfil de enfoque'),
              ),
              _mood(context, StudioSymbols.acUnit, 'Acústica Nórdica', () {
                _searchMood('acústica nórdica');
              }),
            ],
          ),
        ),
        const SizedBox(height: 36),
        if (track != null)
          _master(context, track)
        else
          StudioPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
                const SizedBox(height: 20),
                Text(
                  'Tu historia empieza aquí',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Busca una canción o abre tus archivos para comenzar.',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(StudioSymbols.search),
                  label: const Text('ENCONTRAR MÚSICA'),
                ),
              ],
            ),
          ),
        const SizedBox(height: 40),
        const StudioStamp('CAJA DE DISCOS // ROTACIÓN RECIENTE'),
        const SizedBox(height: 4),
        Text(
          'Crate Digger: Archivos en Rotación',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }

  /// Brasa: saludo breve y accesos rápidos 2×3 estilo Spotify.
  Widget _brasa(BuildContext context) {
    final c = controller;
    final hour = studioClock().hour;
    final greeting = hour < 6
        ? 'Buenas noches'
        : hour < 13
        ? 'Buenos días'
        : hour < 20
        ? 'Buenas tardes'
        : 'Buenas noches';
    final quick = (c.recentTracks.isNotEmpty ? c.recentTracks : c.tracks)
        .where((t) => !t.isPendingSpotifyMatch)
        .take(6)
        .toList();
    final playingId = c.currentTrack?.id;
    Widget tile(Track t) => _BrasaQuickTile(
      track: t,
      playing: t.id == playingId,
      onTap: () => c.playTrack(t, context: quick),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(greeting, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 16),
        if (quick.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tu historia empieza aquí',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Busca una canción o abre tus archivos para comenzar.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onSearch,
                icon: const Icon(StudioSymbols.search),
                label: const Text('Encontrar música'),
              ),
            ],
          )
        else
          LayoutBuilder(
            builder: (context, bounds) {
              final cols = bounds.maxWidth >= 480 ? 2 : 1;
              return Column(
                children: [
                  for (var i = 0; i < quick.length; i += cols)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          for (var j = i; j < i + cols; j++) ...[
                            if (j > i) const SizedBox(width: 8),
                            Expanded(
                              child: j < quick.length
                                  ? tile(quick[j])
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  /// Slush: inicio fiel al diseño (ver slush_home.dart).
  Widget _slush(BuildContext context, Track? track) =>
      SlushHome(controller: controller, onSearch: onSearch);

  Widget _modern(BuildContext context, Track? track) {
    final width = MediaQuery.sizeOf(context).width;
    final moods = <(IconData, String, VoidCallback)>[
      (
        StudioSymbols.waterDrop,
        'Tarde Lluviosa',
        () => showStudioPending(context, 'Ánimos de escucha'),
      ),
      (
        StudioSymbols.graphicEq,
        'Cinta Magnética',
        () => showStudioPending(context, 'Simulación de cinta'),
      ),
      (
        StudioSymbols.nightlife,
        'Improvisación Jazz',
        () => _searchMood('jazz'),
      ),
      (
        StudioSymbols.psychology,
        'Enfoque Profundo',
        () => showStudioPending(context, 'Perfil de enfoque'),
      ),
      (
        StudioSymbols.acUnit,
        'Acústica Nórdica',
        () => _searchMood('acústica nórdica'),
      ),
    ];
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isSlush(context))
          Row(
            children: [
              SlushPill(studioGreeting(studioClock())),
              const SizedBox(width: 12),
              const SlushSticker('NUEVO', size: 64),
            ],
          )
        else
          ModernBadge(studioGreeting(studioClock()), tone: ModernTone.mint),
        const SizedBox(height: 20),
        ModernHeadline(
          before: 'Tu ',
          emphasis: 'música',
          after: ', siempre',
          size: width < 600 ? 40 : 60,
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Text(
            'Escucha lo que amas, descubre lo que viene y deja que el DJ siga por ti.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(StudioSymbols.search),
          label: const Text('Encontrar música'),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in moods)
              ActionChip(
                avatar: Icon(m.$1, size: 16),
                label: Text(m.$2),
                onPressed: m.$3,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerLow,
              ),
          ],
        ),
      ],
    );
    if (track == null) return left;
    // Ancho: hero en dos columnas; estrecho: una columna.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= 1100
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 5, child: left),
                const SizedBox(width: 40),
                Expanded(
                  flex: 6,
                  child: _modernFeature(context, track, controller),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                left,
                const SizedBox(height: 48),
                _modernFeature(context, track, controller),
              ],
            ),
    );
  }

  Widget _modernFeature(BuildContext context, Track track, AppController c) {
    final albumTracks = track.album?.trim().isNotEmpty == true
        ? c.tracks
              .where(
                (t) =>
                    t.album == track.album &&
                    t.artist == track.artist &&
                    !t.isPendingSpotifyMatch,
              )
              .toList()
        : [track];
    final title = track.album?.trim().isNotEmpty == true
        ? track.album!
        : track.title;
    final still = MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: ModernCard(
        dark: true,
        feature: true,
        padding: const EdgeInsets.all(28),
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 560;
            final cover = Transform.rotate(
              angle: still ? 0 : -5 * math.pi / 180,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Artwork(
                  track: track,
                  artworkContext: ArtworkContext.card,
                  radius: 12,
                ),
              ),
            );
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ModernBadge('Seguir escuchando', tone: ModernTone.butter),
                const SizedBox(height: 16),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Bagel Fat One',
                    fontSize: 32,
                    height: 1.15,
                    letterSpacing: .96,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${track.artist} · ${albumTracks.length} pistas',
                  style: const TextStyle(color: Color(0xffb4b7c4)),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Tracky.navy,
                      ),
                      onPressed: c.jamPlaybackActive
                          ? null
                          : () => c.playTrack(track, context: albumTracks),
                      icon: const Icon(StudioSymbols.playArrow, size: 18),
                      label: Text(
                        track.album == null
                            ? 'Reproducir selección'
                            : 'Reproducir pistas disponibles',
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x66ffffff)),
                      ),
                      onPressed: c.jamPlaybackActive
                          ? null
                          : () async {
                              if (c.currentTrack?.id != track.id) {
                                await c.playTrack(track, context: albumTracks);
                              }
                              if (context.mounted) onVinyl();
                            },
                      icon: const Icon(StudioSymbols.album, size: 18),
                      label: const Text('Girar en Modo Vinilo'),
                    ),
                    IconButton(
                      tooltip: 'Guardar en favoritos',
                      color: Colors.white,
                      onPressed: () => c.toggleFavorite(track),
                      icon: Icon(
                        c.favoriteIds.contains(track.id)
                            ? StudioSymbols.favorite
                            : StudioSymbols.bookmarkAdd,
                      ),
                    ),
                  ],
                ),
              ],
            );
            return wide
                ? Row(
                    children: [
                      Expanded(child: info),
                      const SizedBox(width: 32),
                      cover,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(child: cover),
                      const SizedBox(height: 24),
                      info,
                    ],
                  );
          },
        ),
      ),
    );
  }

  void _searchMood(String query) {
    if (onSearchQuery != null) {
      onSearchQuery!(query);
    } else {
      onSearch();
      controller.search(query);
    }
  }

  Widget _mood(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback action,
  ) => Padding(
    padding: const EdgeInsets.only(right: 4, bottom: 4),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
      ),
      onPressed: action,
      icon: Icon(icon, size: 16),
      label: Text(label),
    ),
  );

  Widget _master(BuildContext context, Track track) {
    final c = controller;
    final colors = Theme.of(context).colorScheme;
    final albumTracks = track.album?.trim().isNotEmpty == true
        ? c.tracks
              .where(
                (t) =>
                    t.album == track.album &&
                    t.artist == track.artist &&
                    !t.isPendingSpotifyMatch,
              )
              .toList()
        : [track];
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StudioStamp(track.artist.toUpperCase(), color: colors.primary),
        const SizedBox(height: 8),
        Text(
          track.album?.trim().isNotEmpty == true ? track.album! : track.title,
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 16),
        StudioPanel(
          recessed: true,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Notas de producción y edición',
                style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontStyle: FontStyle.italic,
                  fontSize: 18,
                  color: colors.tertiary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Aurora todavía no dispone de notas de estudio para esta selección.',
              ),
              const SizedBox(height: 16),
              StudioStamp(
                '${albumTracks.length} PISTAS // ${track.isLocal ? 'ARCHIVO LOCAL' : 'FUENTE DE AUDIO EXISTENTE'}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: c.jamPlaybackActive
              ? null
              : () => c.playTrack(track, context: albumTracks),
          icon: const Icon(StudioSymbols.playArrow, size: 18),
          label: Text(
            track.album == null
                ? 'REPRODUCIR SELECCIÓN'
                : 'REPRODUCIR PISTAS DISPONIBLES',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: c.jamPlaybackActive
                  ? null
                  : () async {
                      if (c.currentTrack?.id != track.id) {
                        await c.playTrack(track, context: albumTracks);
                      }
                      if (context.mounted) onVinyl();
                    },
              icon: const Icon(StudioSymbols.album, size: 18),
              label: const Text('Girar en Modo Vinilo'),
            ),
            IconButton.filledTonal(
              tooltip: 'Guardar en favoritos',
              onPressed: () => c.toggleFavorite(track),
              icon: Icon(
                c.favoriteIds.contains(track.id)
                    ? StudioSymbols.favorite
                    : StudioSymbols.bookmarkAdd,
              ),
            ),
          ],
        ),
      ],
    );
    return StudioPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                StudioSymbols.verified,
                color: colors.primary,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: StudioStamp('EDICIÓN MÁSTER · AUDIÓFILO DE LA SEMANA'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 560;
              final sleeve = Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: StudioPalette.of(context),
                      boxShadow: const [
                        BoxShadow(color: Colors.black, offset: Offset(4, 6)),
                      ],
                    ),
                    child: Artwork.fill(
                      track: track,
                      artworkContext: ArtworkContext.sleeve,
                      radius: 8,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: StudioStamp(
                      track.isLocal
                          ? 'ARCHIVO LOCAL'
                          : 'METADATOS · AUDIO EXTERNO',
                      filled: true,
                    ),
                  ),
                ],
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth * .4,
                          child: sleeve,
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: info),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: SizedBox(
                            width: ArtworkContext.sleeve.constrain(constraints),
                            child: sleeve,
                          ),
                        ),
                        const SizedBox(height: 28),
                        info,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

/// Título y hora de la portada; se actualiza solo cuando cambia el minuto.
class StudioGreetingRow extends StatefulWidget {
  const StudioGreetingRow({super.key});

  @override
  State<StudioGreetingRow> createState() => _StudioGreetingRowState();
}

class _StudioGreetingRowState extends State<StudioGreetingRow> {
  late DateTime _now = studioClock();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = studioClock();
      if (now.hour != _now.hour || now.minute != _now.minute) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: [
        Text(
          studioGreeting(_now),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontStyle: FontStyle.italic,
            fontSize: width <= 400
                ? 28
                : width < 600
                ? 38
                : 56,
          ),
        ),
        StudioStamp(
          TimeOfDay.fromDateTime(_now).format(context),
          filled: true,
          color: colors.primary,
        ),
      ],
    );
  }
}

class _BrasaQuickTile extends StatelessWidget {
  const _BrasaQuickTile({
    required this.track,
    required this.playing,
    required this.onTap,
  });
  final Track track;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Material(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        hoverColor: Brasa.ash,
        onTap: onTap,
        child: Row(
          children: [
            Artwork(track: track, size: 56, radius: 0),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                track.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: playing ? Brasa.accent : Brasa.cream,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    ),
  );
}
