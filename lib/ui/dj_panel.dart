import 'package:flutter/material.dart';
import '../app_controller.dart';
import '../dj/dj_modes.dart';
import '../theme/brasa_theme.dart';
import '../theme/modern_theme.dart';
import '../theme/slush_theme.dart';
import '../theme/modern_widgets.dart';
import 'artwork.dart';
import 'track_actions.dart';
import 'slush/slush_decor.dart';
import 'dj_filters_panel.dart';

class DjPanel extends StatelessWidget {
  const DjPanel({
    super.key,
    required this.controller,
    this.showRecommendations = true,
  });
  final bool showRecommendations;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final recommendations = c.recommendations;
    final filters = c.djFilters;
    final filtered =
        filters.artists.isNotEmpty ||
        filters.trackIds.isNotEmpty ||
        filters.genres.isNotEmpty ||
        filters.excludedArtists.isNotEmpty ||
        filters.excludedTrackIds.isNotEmpty ||
        filters.excludedGenres.isNotEmpty;
    final libraryIds = c.tracks.map((track) => track.id).toSet();
    final personalized =
        c.favoriteIds.any(libraryIds.contains) ||
        c.playlists.any(
          (playlist) => playlist.trackIds.any(libraryIds.contains),
        ) ||
        c.recentTracks.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showRecommendations)
          _sectionTitle(
            context,
            'Para ti',
            personalized
                ? 'Basado en tus favoritos, listas y escucha reciente'
                : 'Aún no hay señales personales; elegimos de tu biblioteca',
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: c.refreshRecommendations,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar recomendaciones'),
            ),
          ],
        ),
        DjSessionCard(controller: c),
        DjFiltersPanel(controller: c),

        if (showRecommendations && recommendations.isEmpty)
          _empty(
            context,
            Icons.auto_awesome_outlined,
            filtered
                ? 'No hay canciones para estos filtros'
                : 'Tu biblioteca está lista para crecer',
            filtered
                ? 'Amplía tu selección o quita los filtros del DJ para encontrar más canciones.'
                : 'Añade canciones reproducibles y aparecerán recomendaciones aquí.',
          )
        else if (showRecommendations)
          ...recommendations.map(
            (recommendation) => TrackActionsRegion(
              controller: c,
              track: recommendation.track,
              builder: (context, hot) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Artwork(
                  track: recommendation.track,
                  artworkContext: ArtworkContext.thumbnail,
                  radius: 8,
                ),
                title: Text(
                  recommendation.track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${recommendation.track.artist} · ${recommendation.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () =>
                    c.playTrack(recommendation.track, replaceQueue: false),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reproducir ${recommendation.track.title}',
                      onPressed: () => c.playTrack(
                        recommendation.track,
                        replaceQueue: false,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    TrackMenuButton(
                      controller: c,
                      track: recommendation.track,
                      quickAdd: true,
                      quickAddVisible: hot,
                    ),
                  ],
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed:
                c.discoveringRecommendations || !c.canDiscoverRecommendations
                ? null
                : c.discoverRecommendations,
            icon: c.discoveringRecommendations
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore),
            label: Text(
              c.discoveringRecommendations
                  ? 'Buscando en YouTube…'
                  : c.discoveredRecommendations.isEmpty
                  ? 'Descubrir en YouTube'
                  : 'Actualizar descubrimiento',
            ),
          ),
        ),
        if (c.recommendationDiscoveryError != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'No se pudo buscar: ${c.recommendationDiscoveryError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (showRecommendations && c.discoveredRecommendations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionTitle(
            context,
            'Encontradas en YouTube',
            'Búsqueda solicitada por ti',
          ),
          ...c.discoveredRecommendations.map(
            (track) => TrackActionsRegion(
              controller: c,
              track: track,
              builder: (context, hot) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: Artwork(
                  track: track,
                  artworkContext: ArtworkContext.thumbnail,
                  radius: 8,
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${track.artist} · Resultado de YouTube',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => c.playTrack(track, replaceQueue: false),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Reproducir ${track.title}',
                      onPressed: () => c.playTrack(track, replaceQueue: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                    TrackMenuButton(
                      controller: c,
                      track: track,
                      quickAdd: true,
                      quickAddVisible: hot,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );

  Widget _empty(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Entrada única del DJ: estado «DJ activo», modo, iniciar y detener. Todo el
/// trabajo (cola infinita, perfil, coherencia, YouTube) es del controlador.
class DjSessionCard extends StatefulWidget {
  const DjSessionCard({super.key, required this.controller});
  final AppController controller;

  @override
  State<DjSessionCard> createState() => _DjSessionCardState();
}

class _DjSessionCardState extends State<DjSessionCard> {
  bool _starting = false;
  bool _failed = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    final c = widget.controller;
    final ok = await c.startDjSession(
      includeDiscovery: c.personalDjIncludeDiscovery,
    );
    if (mounted) {
      setState(() {
        _starting = false;
        _failed = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final theme = Theme.of(context);
      final active = c.personalDjActive;
      final jam = c.jamPlaybackActive;
      final brasa = isBrasa(context);
      final next = c.personalDjNextReason;
      final note = jam
          ? 'Hay una Jam en curso: el DJ queda en pausa hasta que termine.'
          : _failed && !active
          ? 'No hay con qué empezar: añade música a tu biblioteca, busca una canción o revisa tu conexión.'
          : null;
      final slush = isSlush(context);
      final card = Card(
        key: const ValueKey('dj-session-card'),
        margin: slush
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(
                vertical: brasa
                    ? 0
                    : isModern(context)
                    ? 24
                    : 12,
              ),
        color: brasa
            ? Colors.transparent
            : slush
            ? context.slush.paper
            : theme.colorScheme.surfaceContainerLow,
        clipBehavior: brasa ? Clip.antiAlias : Clip.none,
        child: Container(
          decoration: brasa
              ? const BoxDecoration(gradient: Brasa.banner)
              : null,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      active ? Icons.graphic_eq : Icons.auto_awesome_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        active
                            ? 'DJ activo · ${c.djMode.label}'
                            : 'DJ detenido',
                        key: const ValueKey('dj-status'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (isModern(context))
                      ModernBadge(
                        active ? 'ACTIVO' : 'DETENIDO',
                        tone: active ? ModernTone.mint : ModernTone.butter,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                active
                    ? (next == null
                          ? 'La cola no termina: el DJ sigue sumando canciones.'
                          : 'A continuación: $next')
                    : 'Empieza una sesión sin fin con tu perfil, tus favoritos y recomendaciones de YouTube.',
                style: TextStyle(
                  color: brasa
                      ? Brasa.cream
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in DjMode.values)
                    if (slush)
                      SlushChip(
                        mode.label,
                        selected: c.djMode == mode,
                        color: Slush.mint,
                        onTap: () => c.setDjMode(mode),
                      )
                    else
                      ChoiceChip(
                        label: Text(mode.label),
                        selected: c.djMode == mode,
                        onSelected: (_) => c.setDjMode(mode),
                        showCheckmark: !isModern(context) && !brasa,
                        side: isModern(context) || brasa
                            ? BorderSide.none
                            : null,
                        shape: brasa ? const StadiumBorder() : null,
                        backgroundColor: brasa ? Brasa.graphite : null,
                        selectedColor: brasa
                            ? Brasa.cream
                            : isModern(context)
                            ? Tracky.navy
                            : null,
                        labelStyle: brasa
                            ? TextStyle(
                                color: c.djMode == mode
                                    ? Colors.black
                                    : Brasa.cream,
                                fontWeight: FontWeight.w600,
                              )
                            : isModern(context) && c.djMode == mode
                            ? const TextStyle(color: Colors.white)
                            : null,
                      ),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Incluir novedades de YouTube'),
                subtitle: Text(
                  'Hasta 2 búsquedas por recarga, guiadas por tu perfil.',
                  style: brasa ? const TextStyle(color: Brasa.cream) : null,
                ),
                value: c.personalDjIncludeDiscovery,
                onChanged: c.setPersonalDjIncludeDiscovery,
              ),
              FilledButton.icon(
                key: const ValueKey('dj-toggle'),
                style: slush
                    ? FilledButton.styleFrom(
                        minimumSize: const Size(0, SlushControl.bar),
                      )
                    : null,
                onPressed: _starting || jam
                    ? null
                    : active
                    ? c.stopPersonalDj
                    : _start,
                icon: _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        active ? Icons.stop_circle_outlined : Icons.play_circle,
                      ),
                label: Text(
                  _starting
                      ? 'Preparando el DJ…'
                      : active
                      ? 'Detener DJ'
                      : 'Iniciar DJ',
                ),
              ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    note,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (active && c.personalDjError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'El DJ seguirá con tu biblioteca: ${c.personalDjError}',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      );
      if (!slush) return card;
      final p = context.slush;
      final hot = active && theme.brightness == Brightness.dark;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: SlushSpacing.s12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SlushRadius.r24),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: hot ? Slush.mint : p.shadow,
                      offset: SlushElevation.card.offset,
                    ),
                  ]
                : const [],
          ),
          child: card,
        ),
      );
    },
  );
}
