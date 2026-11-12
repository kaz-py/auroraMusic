import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/window_controls.dart';
import '../mini_player/mini_player_host.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../slush/slush_bars.dart';
import '../slush/slush_eq_queue.dart';
import '../slush/slush_mobile.dart';
import '../slush/slush_pages.dart';
import '../jam/jam_widgets.dart';
import '../studio/studio_navigation.dart';
import 'shell_chrome.dart';
import 'shell_header.dart';
import 'shell_nav.dart';
import 'shell_sections.dart';

/// Dueño: tema Slush. Chrome del shell: barra superior/inferior, cabeceras
/// móviles, marco de página (SlushPage), cola/EQ y transición de sección.
const slushChrome = SlushChrome();

/// Secciones cuyo titular gigante pinta [SlushPage] en vez del shell.
const _slushOwnedSections = [1, 2, 3, 7, 11, 12, 14];

class SlushChrome extends ShellChrome {
  const SlushChrome();

  @override
  Widget? topBar(BuildContext context, ShellScope scope) {
    if (scope.rail) {
      return SlushTopBar(
        selected: scope.section,
        onNavigate: scope.onNavigate,
        onProfile: scope.onProfile,
        avatar: scope.avatar,
        sessionText: scope.jamOn ? 'JAM ACTIVA' : 'INICIAR JAM',
        onSession: scope.jamOn ? scope.onOpenJamPanel : scope.onStartJam,
        onAdd: scope.onCreatePlaylist,
      );
    }
    if (!WindowControls.supported) return null;
    return MouseOnlyRegion(
      child: StudioTitleBar(
        onNavigate: scope.onNavigate,
        onProfile: scope.onProfile,
        avatar: scope.avatar,
        searchController: null,
        searchFocus: scope.searchFocus,
        onSearch: scope.onSearch,
        onSearchChanged: scope.onSearchChanged,
        sessionText: scope.jamOn
            ? 'JAM · ${scope.jam!.peopleCount} ${scope.jam!.peopleCount == 1 ? 'PERSONA' : 'PERSONAS'} · ${scope.jam!.roleLabel.toUpperCase()}'
            : 'INICIAR UNA JAM',
        activeSession: scope.jamOn,
        onSession: scope.jamOn ? scope.onOpenJamPanel : scope.onStartJam,
      ),
    );
  }

  /// Sin sidebar: la navegación va en [SlushTopBar].
  @override
  Widget? sidebar(BuildContext context, ShellScope scope) => null;

  /// Sin panel lateral derecho (el panel ≥ 1200 implica carril: barra Slush).
  @override
  Widget? aside(BuildContext context, ShellScope scope) => null;

  @override
  Widget? header(BuildContext context, ShellScope scope) {
    if (scope.rail && scope.section == 0) return null;
    if (scope.wide && [0, 3].contains(scope.section)) return null;
    if (scope.rail && ownsPageFrame(scope)) return const SizedBox.shrink();
    return !scope.rail &&
            ((scope.section == 0 && scope.playlist == null) ||
                ownsPageFrame(scope))
        ? SlushMobileTopBar(
            onSettings: () => scope.onNavigate(7),
            onProfile: scope.onProfile,
            avatar: scope.avatar,
            onMore: scope.onNavigate,
            friendsBadge: scope.friendsBadge,
          )
        : ShellHeaderBar(scope: scope, modern: true, playerMoreActions: false);
  }

  /// Slush lleva `ModernMarker`: mismo aviso que Modern.
  @override
  Widget errorBanner(BuildContext context, ShellScope scope) => ModernBanner(
    message: scope.controller.error!,
    onClose: scope.controller.clearError,
  );

  @override
  Widget bottomNavigation(BuildContext context, ShellScope scope) {
    final primary = primarySections(AuroraThemeKind.slush, mobile: true);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: SlushBottomBar(
        icons: [
          for (final s in primary)
            switch (s) {
              2 => Icons.queue_music,
              8 => Icons.auto_awesome,
              9 => Icons.groups_outlined,
              _ => shellSectionIcons[s]!,
            },
        ],
        labels: [for (final s in primary) shellSectionTitles[s]!],
        selected: primary.indexOf(scope.section),
        onSelect: (i) => scope.onNavigate(primary[i]),
        mini: scope.miniPlayer(MiniPlayerPlacement.bottomBar),
      ),
    );
  }

  @override
  Widget pageTransition(BuildContext context, ShellScope scope, Widget child) =>
      _SlushSectionFade(section: scope.section, child: child);

  /// Estas secciones llevan su propio titular gigante (SlushPage).
  @override
  bool ownsPageFrame(ShellScope scope) =>
      _slushOwnedSections.contains(scope.section);

  /// Cabecera gigante + píldoras + contenido en tarjeta blanca.
  @override
  Widget pageFrame(BuildContext context, ShellScope scope, Widget child) {
    final c = scope.controller;
    final s = scope.section;
    final libRoot = s == 2 && scope.playlist == null && !scope.likesSelected;
    final songs = '${c.tracks.length} canciones';
    final list = c.playlists
        .where((p) => p.id == scope.playlist?.id)
        .firstOrNull;
    final found = c.searchEntries.isNotEmpty && c.searchResults.isEmpty
        ? c.searchEntries.length
        : c.searchResults.length;
    final (base, title, sticker, pills) = switch (s) {
      1 => (
        Slush.lilac,
        'BÚSQUEDA',
        '¡HEY!',
        [
          scope.spotifySearch ? 'Spotify' : 'YouTube',
          if (c.searching)
            'Buscando…'
          else if (found > 0)
            '$found resultados'
          else
            '${c.recentSearches.length} recientes',
        ],
      ),
      2 => (
        Slush.mint,
        scope.likesSelected
            ? 'ME GUSTA'
            : scope.playlist == null
            ? 'BIBLIOTECA'
            : (list?.name ?? 'LISTA').toUpperCase(),
        scope.likesSelected ? 'AMOR' : 'TUYA',
        libRoot
            ? [
                songs,
                '${c.playlists.length} listas',
                '${c.favoriteIds.length} me gusta',
              ]
            : [
                '${scope.likesSelected ? c.favoriteIds.length : (list?.trackIds.length ?? 0)} canciones',
              ],
      ),
      3 => (
        const Color(0xffa9d0ff),
        'DESCARGAS',
        'BAJA',
        [
          '${c.downloads.where((j) => j.status == DownloadStatus.completed).length} listas',
          '${c.downloads.where((j) => j.status == DownloadStatus.queued || j.status == DownloadStatus.downloading).length} en curso',
        ],
      ),
      11 => (const Color(0xffa9d0ff), 'VÍDEOS', 'MP4', ['yt-dlp']),
      14 => (Slush.mint, 'AMIGOS', 'HOLA', const <String>[]),
      12 => (
        Slush.yellow,
        'ARTISTAS',
        'FANS',
        ['${c.tracks.map((t) => t.artist).toSet().length} artistas', songs],
      ),
      _ => (
        const Color(0xffffb48a),
        'AJUSTES',
        'TUYO',
        ['Slush', scope.settingsTabLabel],
      ),
    };
    return SlushPage(
      color: slushTone(context, base),
      title: title,
      sticker: sticker,
      pills: pills,
      card: !libRoot && s != 7,
      child: child,
    );
  }

  @override
  Widget? sectionOverride(
    BuildContext context,
    ShellScope scope,
    int section,
  ) => switch (section) {
    5 => SlushEqQueue(
      controller: scope.controller,
      onNavigate: scope.onNavigate,
      queueFirst: true,
    ),
    13 => SlushEqQueue(
      controller: scope.controller,
      onNavigate: scope.onNavigate,
    ),
    _ => null,
  };
}

/// Slush: entrada de sección (opacidad + 8 px, 220 ms `easeOut`) al cambiar de
/// pestaña. El hijo conserva su estado; con movimiento reducido es un corte.
class _SlushSectionFade extends StatefulWidget {
  const _SlushSectionFade({required this.section, required this.child});
  final int section;
  final Widget child;

  @override
  State<_SlushSectionFade> createState() => _SlushSectionFadeState();
}

class _SlushSectionFadeState extends State<_SlushSectionFade>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: SlushMotion.sectionIn,
    value: 1,
  );

  @override
  void didUpdateWidget(_SlushSectionFade old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section && !SlushMotion.reduce(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlushMotion.fadeSlide(_c, widget.child);
}
