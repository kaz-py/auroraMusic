import 'dart:typed_data';

import '../../shortcuts/shortcut_service.dart';
import 'package:flutter/material.dart';
import '../aurora_states.dart';
import '../../app_controller.dart';
import '../../core/window_controls.dart';
import '../../core/models.dart';
import '../../theme/brasa_sidebar_playlists.dart';
import '../../theme/slush_theme.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../playlist_views/playlist_photo_menu.dart';
import 'studio_components.dart';
import 'studio_symbols.dart';

class StudioTitleBar extends StatelessWidget {
  const StudioTitleBar({
    super.key,
    required this.onNavigate,
    required this.sessionText,
    this.activeSession = false,
    this.onSession,
    this.searchController,
    this.searchFocus,
    this.onSearch,
    this.onSearchChanged,
    this.avatar,
  });

  /// Foto de perfil del usuario (miniatura); null = icono de persona.
  final Uint8List? avatar;

  /// Brasa: búsqueda píldora centrada en la barra superior (opcional).
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearch, onSearchChanged;
  final ValueChanged<int> onNavigate;
  final String sessionText;
  final bool activeSession;

  /// Toque en el chip de sesión; por omisión abre la página Jam.
  final VoidCallback? onSession;
  Widget _profileGlyph(double size, double iconSize) => avatar == null
      ? Icon(StudioSymbols.person, size: iconSize)
      : ClipOval(
          child: Image.memory(
            avatar!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                Icon(StudioSymbols.person, size: iconSize),
          ),
        );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      final modern = isModern(context);
      if (isBrasa(context)) return _brasa(context, constraints, largeText);
      return Container(
        height: largeText ? 60 : (modern ? 52 : 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: modern ? colors.surface : colors.surfaceContainerLowest,
          border: modern
              ? null
              : Border(bottom: BorderSide(color: colors.surfaceContainerHigh)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onPanStart: (_) => WindowControls.invoke('drag'),
              onDoubleTap: () => WindowControls.invoke('maximize'),
              child: Row(
                children: [
                  if (modern)
                    const _ModernLogo()
                  else
                    Image.asset(
                      'assets/design_idea/inicio_aurora_music_player_00.png',
                      width: 42,
                      height: 32,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  const SizedBox(width: 8),
                  if (constraints.maxWidth > (largeText ? 450 : 400))
                    Text(
                      'Aurora',
                      style: modern
                          ? TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -.18,
                              color: colors.onSurface,
                            )
                          : TextStyle(
                              fontFamily: 'Newsreader',
                              fontSize: 24,
                              color: colors.primary,
                            ),
                    ),
                ],
              ),
            ),
            if (constraints.maxWidth > 850 && !largeText) ...[
              const SizedBox(width: 16),
              SizedBox(
                height: 14,
                child: VerticalDivider(color: colors.surfaceContainerHighest),
              ),
              const SizedBox(width: 12),
              for (final item in [
                (2, 'Biblioteca'),
                (4, 'Modo Vinilo'),
                (6, 'Estudio Analógico'),
              ]) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onNavigate(item.$1),
                  child: Padding(
                    padding: modern
                        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
                        : EdgeInsets.zero,
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: modern ? 13 : 12,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (item.$1 != 6 && !modern)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text('/'),
                  ),
              ],
            ],
            // Zona vacía de la barra: arrastra la ventana y doble clic maximiza.
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => WindowControls.invoke('drag'),
                onDoubleTap: () => WindowControls.invoke('maximize'),
                child: const SizedBox.expand(),
              ),
            ),
            if (constraints.maxWidth > 700 && !largeText)
              InkWell(
                borderRadius: modern ? BorderRadius.circular(8) : null,
                onTap: onSession ?? () => onNavigate(9),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: modern
                      ? BoxDecoration(
                          color: activeSession
                              ? Tracky.mint
                              : colors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        )
                      : BoxDecoration(color: colors.surfaceContainer),
                  child: Row(
                    children: [
                      Icon(
                        StudioSymbols.wifiTethering,
                        size: 14,
                        color: modern && activeSession
                            ? Tracky.navy
                            : activeSession
                            ? colors.primaryContainer
                            : colors.outline,
                      ),
                      const SizedBox(width: 4),
                      StudioStamp(sessionText),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.circle,
                        size: 6,
                        color: activeSession
                            ? colors.primaryContainer
                            : colors.outline,
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 16),
            IconButton.filled(
              tooltip: 'Perfil y ajustes',
              style: IconButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                minimumSize: const Size(32, 32),
                padding: avatar == null
                    ? const EdgeInsets.all(6)
                    : EdgeInsets.zero,
              ),
              onPressed: () => onNavigate(7),
              icon: _profileGlyph(32, 18),
            ),
            if (WindowControls.supported) ...[
              const SizedBox(width: 12),
              for (final item in [
                ('minimize', StudioSymbols.minimize, 'Minimizar'),
                (
                  'maximize',
                  StudioSymbols.checkBoxOutlineBlank,
                  'Maximizar o restaurar',
                ),
                ('close', StudioSymbols.close, 'Cerrar ventana'),
              ])
                IconButton(
                  tooltip: item.$3,
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    if (!await WindowControls.invoke(item.$1) &&
                        context.mounted) {
                      showStudioPending(context, 'Control de ventana Windows');
                    }
                  },
                  icon: Icon(item.$2, size: 15),
                ),
            ],
          ],
        ),
      );
    },
  );

  Widget _brasa(BuildContext context, BoxConstraints box, bool largeText) {
    final wide = box.maxWidth > 700 && !largeText;
    final hasSearch = searchController != null && box.maxWidth > 560;
    return Container(
      height: largeText ? 64 : 56,
      color: Brasa.void_,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton.filled(
            tooltip: 'Inicio',
            style: IconButton.styleFrom(
              backgroundColor: Brasa.graphite,
              foregroundColor: Brasa.cream,
              minimumSize: const Size(40, 40),
            ),
            onPressed: () => onNavigate(0),
            icon: const Icon(StudioSymbols.home, size: 22),
          ),
          if (hasSearch)
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: TextField(
                    controller: searchController,
                    focusNode: searchFocus,
                    textInputAction: TextInputAction.search,
                    onTap: () => onNavigate(1),
                    onSubmitted: onSearch,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      hintText: '¿Qué quieres reproducir?',
                      prefixIcon: const Icon(Icons.search, size: 22),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: _pill(Colors.transparent),
                      enabledBorder: _pill(Colors.transparent),
                      focusedBorder: _pill(Brasa.cream),
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => WindowControls.invoke('drag'),
                onDoubleTap: () => WindowControls.invoke('maximize'),
                child: const SizedBox.expand(),
              ),
            ),
          if (wide)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Jam',
                child: Material(
                  color: Brasa.graphite,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: onSession ?? () => onNavigate(9),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            StudioSymbols.wifiTethering,
                            size: 16,
                            color: activeSession ? Brasa.cream : Brasa.steel,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            sessionText,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          IconButton.filled(
            tooltip: 'Perfil y ajustes',
            style: IconButton.styleFrom(
              backgroundColor: Brasa.graphite,
              foregroundColor: Brasa.cream,
              minimumSize: const Size(36, 36),
              padding: avatar == null ? null : EdgeInsets.zero,
            ),
            onPressed: () => onNavigate(7),
            icon: _profileGlyph(36, 18),
          ),
          if (WindowControls.supported) ...[
            const SizedBox(width: 8),
            for (final item in [
              ('minimize', StudioSymbols.minimize, 'Minimizar'),
              (
                'maximize',
                StudioSymbols.checkBoxOutlineBlank,
                'Maximizar o restaurar',
              ),
              ('close', StudioSymbols.close, 'Cerrar ventana'),
            ])
              IconButton(
                tooltip: item.$3,
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  if (!await WindowControls.invoke(item.$1) &&
                      context.mounted) {
                    showStudioPending(context, 'Control de ventana Windows');
                  }
                },
                icon: Icon(item.$2, size: 15),
              ),
          ],
        ],
      ),
    );
  }

  static OutlineInputBorder _pill(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(9999),
    borderSide: BorderSide(color: c),
  );
}

class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    super.key,
    required this.controller,
    required this.selected,
    required this.onNavigate,
    required this.onPlaylist,
    this.onCreatePlaylist,
    this.shortcuts,
    this.friendsBadge = 0,
  });
  final int friendsBadge;
  final VoidCallback? onCreatePlaylist;
  final ShortcutService? shortcuts;
  final AppController controller;
  final int selected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<MusicPlaylist> onPlaylist;
  @override
  Widget build(BuildContext context) {
    if (isBrasa(context)) return _brasa(context);
    final colors = Theme.of(context).colorScheme;
    final modern = isModern(context);
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: modern ? colors.surface : colors.surfaceContainerLow,
        border: modern
            ? null
            : Border(right: BorderSide(color: colors.surfaceContainerHigh)),
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _label(context, 'CONSOLA PRINCIPAL'),
                  const SizedBox(height: 12),
                  _nav(
                    context,
                    0,
                    'Inicio',
                    'Inicio',
                    StudioSymbols.home,
                    shortcuts?.labelOf(ShortcutId.home) ?? 'Ctrl+1',
                  ),
                  _nav(
                    context,
                    1,
                    'Búsqueda',
                    'Buscar',
                    StudioSymbols.search,
                    shortcuts?.labelOf(ShortcutId.search) ?? 'Ctrl+2',
                  ),
                  _nav(context, 8, 'DJ', 'DJ', StudioSymbols.explore, ''),
                  _nav(
                    context,
                    12,
                    'Artistas',
                    'Artistas',
                    Icons.mic_none_rounded,
                    '',
                  ),
                  if (controller.usesOfficialYouTubeMusic ||
                      controller.usesYouTubeWebAudio)
                    _nav(
                      context,
                      10,
                      'Acceso a YouTube Music',
                      'Acceso a YouTube Music',
                      Icons.music_video_outlined,
                      '',
                    ),
                  _nav(
                    context,
                    2,
                    'Biblioteca',
                    'Biblioteca',
                    StudioSymbols.libraryMusic,
                    shortcuts?.labelOf(ShortcutId.library) ?? 'Ctrl+3',
                  ),
                  _nav(
                    context,
                    3,
                    'Descargas',
                    'Descargas locales',
                    StudioSymbols.downloadDone,
                    shortcuts?.labelOf(ShortcutId.downloads) ?? 'Ctrl+4',
                  ),
                  if (controller.usesOfficialYouTubeMusic ||
                      controller.usesYouTubeWebAudio)
                    _nav(
                      context,
                      11,
                      'Descargar vídeos',
                      'Descargar vídeos',
                      Icons.video_file_outlined,
                      '',
                    ),
                  const SizedBox(height: 20),
                  Tooltip(
                    message: controller.downloadsDirectoryPath,
                    child: Container(
                      decoration: BoxDecoration(
                        color: modern
                            ? colors.surfaceContainerLow
                            : colors.surfaceContainerLowest,
                        borderRadius: modern ? BorderRadius.circular(8) : null,
                      ),
                      padding: EdgeInsets.all(modern ? 10 : 5),
                      child: Row(
                        children: [
                          const Icon(StudioSymbols.folder, size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              controller.downloadsDirectoryPath.replaceAll(
                                '\\',
                                '/',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                            ),
                          ),
                          const Icon(Icons.circle, size: 6),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _label(context, 'FIDELIDAD & EXPERIENCIA'),
                  const SizedBox(height: 12),
                  _nav(
                    context,
                    4,
                    'Modo Vinilo',
                    'Modo Vinilo',
                    StudioSymbols.album,
                    shortcuts?.labelOf(ShortcutId.vinyl) ?? 'Ctrl+I',
                  ),
                  _nav(
                    context,
                    6,
                    'Letras Dinámicas',
                    'Letras',
                    StudioSymbols.lyrics,
                    shortcuts?.labelOf(ShortcutId.lyrics) ?? 'Ctrl+L',
                  ),
                  _nav(
                    context,
                    13,
                    'Ecualizador',
                    'Ecualizador',
                    StudioSymbols.equalizer,
                    'EQ',
                  ),
                  _nav(
                    context,
                    7,
                    'Modo Foco / Sueño',
                    'Modo Foco / Sueño',
                    StudioSymbols.bedtime,
                    'Zz',
                    active: false,
                  ),
                  _nav(context, 9, 'Jam', 'Jam', StudioSymbols.groups, ''),
                  _nav(
                    context,
                    14,
                    'Amigos',
                    'Amigos',
                    Icons.people_outline,
                    friendsBadge > 0 ? '$friendsBadge' : '',
                  ),
                  _nav(
                    context,
                    5,
                    'Cola de reproducción',
                    'Cola de reproducción',
                    StudioSymbols.queueMusic,
                    '',
                  ),
                  const SizedBox(height: 20),
                  _label(context, 'ÁNIMOS & COLECCIONES'),
                  const SizedBox(height: 12),
                  for (final playlist in controller.playlists)
                    PlaylistPhotoMenu(
                      controller: controller,
                      playlist: playlist,
                      child: Padding(
                        // Margen para que el contorno de 2 px no se recorte.
                        padding: isSlush(context)
                            ? const EdgeInsets.fromLTRB(2, 3, 2, 3)
                            : EdgeInsets.zero,
                        child: TextButton(
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            foregroundColor: isSlush(context)
                                ? context.slush.ink
                                : colors.onSurfaceVariant,
                            backgroundColor: isSlush(context)
                                ? context.slush.paper
                                : null,
                            shape: isSlush(context)
                                ? StadiumBorder(side: context.slush.border)
                                : null,
                          ),
                          onPressed: () => onPlaylist(playlist),
                          child: Row(
                            children: [
                              Icon(
                                Icons.circle,
                                color: colors.onSurfaceVariant,
                                size: 10,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  playlist.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (controller.playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Aún no hay colecciones',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  _nav(
                    context,
                    7,
                    'Ajustes',
                    'Ajustes',
                    StudioSymbols.settings,
                    '',
                  ),
                ],
              ),
            ),
          ),
          Container(
            color: modern ? null : colors.surfaceContainerLowest,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const StudioStamp('SINCRONIZACIÓN DAC · NO MEDIDA'),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: controller.audio.isBuffering ? null : 0,
                  minHeight: 4,
                  borderRadius: modern ? BorderRadius.circular(8) : null,
                  color: modern ? Tracky.mint : colors.primaryContainer,
                ),
                const SizedBox(height: 6),
                Text(
                  controller.audio.isBuffering
                      ? 'Preparando buffer'
                      : 'Motor de reproducción listo',
                  style: TextStyle(fontSize: 10, color: colors.outline),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Brasa: sidebar de ~300 px sin borde, accesos arriba y panel «Tu biblioteca».
  Widget _brasa(BuildContext context) {
    final c = controller;
    final web = c.usesOfficialYouTubeMusic || c.usesYouTubeWebAudio;
    // (índice, título, tooltip, icono)
    final items = <(int, String, String, IconData)>[
      (2, 'Biblioteca', 'Biblioteca', StudioSymbols.libraryMusic),
      (3, 'Descargas', 'Descargas locales', StudioSymbols.downloadDone),
      if (web)
        (
          10,
          'Acceso a YouTube Music',
          'Acceso a YouTube Music',
          Icons.music_video_outlined,
        ),
      if (web)
        (11, 'Descargar vídeos', 'Descargar vídeos', Icons.video_file_outlined),
      (4, 'Modo Vinilo', 'Modo Vinilo', StudioSymbols.album),
      (6, 'Letras', 'Letras', StudioSymbols.lyrics),
      (9, 'Jam', 'Jam', StudioSymbols.groups),
      (
        14,
        friendsBadge > 0 ? 'Amigos ($friendsBadge)' : 'Amigos',
        'Amigos',
        Icons.people_outline,
      ),
      (13, 'Ecualizador', 'Ecualizador', StudioSymbols.equalizer),
      (
        5,
        'Cola de reproducción',
        'Cola de reproducción',
        StudioSymbols.queueMusic,
      ),
    ];
    Widget top(int i, String label, String tip, IconData icon) => Tooltip(
      message: tip,
      child: _BrasaTile(
        selected: selected == i,
        onTap: () => onNavigate(i),
        dense: true,
        leading: Icon(
          icon,
          size: 24,
          color: selected == i ? Brasa.cream : Brasa.cloud,
        ),
        title: label,
      ),
    );
    return Container(
      width: 300,
      color: Brasa.void_,
      padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Brasa.obsidian,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  top(0, 'Inicio', 'Inicio', StudioSymbols.home),
                  top(1, 'Búsqueda', 'Buscar', StudioSymbols.search),
                  top(8, 'DJ', 'DJ', StudioSymbols.explore),
                  top(12, 'Artistas', 'Artistas', Icons.mic_none_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            flex: 3,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Brasa.obsidian,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                    child: Row(
                      children: [
                        const Icon(
                          StudioSymbols.libraryMusic,
                          size: 24,
                          color: Brasa.cloud,
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Tu biblioteca',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Brasa.cloud,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final e in items)
                          Tooltip(
                            message: e.$3,
                            child: _BrasaTile(
                              selected: selected == e.$1,
                              onTap: () => onNavigate(e.$1),
                              dense: true,
                              leading: Icon(
                                e.$4,
                                size: 22,
                                color: selected == e.$1
                                    ? Brasa.cream
                                    : Brasa.cloud,
                              ),
                              title: e.$2,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BrasaSidebarPlaylists(
              controller: controller,
              onPlaylist: onPlaylist,
              onCreate: onCreatePlaylist,
            ),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Brasa.obsidian,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: top(7, 'Ajustes', 'Ajustes', StudioSymbols.settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, String value) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 8),
    child: isModern(context)
        ? Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          )
        : StudioStamp(value, color: Theme.of(context).colorScheme.outline),
  );
  Widget _nav(
    BuildContext context,
    int index,
    String label,
    String tooltip,
    IconData icon,
    String shortcut, {
    bool? active,
  }) {
    final colors = Theme.of(context).colorScheme;
    final chosen = active ?? selected == index;
    if (isModern(context)) {
      final slush = isSlush(context);
      final fg = slush
          ? (chosen ? Slush.ink : context.slush.ink)
          : chosen
          ? colors.onPrimary
          : colors.onSurfaceVariant;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Tooltip(
          message: tooltip,
          child: Material(
            color: slush
                ? (chosen ? Slush.mint : context.slush.paper)
                : chosen
                ? colors.primary
                : Colors.transparent,
            shape: slush
                ? StadiumBorder(side: context.slush.border)
                : const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onNavigate(index),
              child: Container(
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: fg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontSize: 14,
                          letterSpacing: -.14,
                          fontWeight: chosen
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (shortcut.isNotEmpty &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                      Text(
                        shortcut,
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: slush ? 1 : .6),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: chosen
              ? Color.alphaBlend(
                  AuroraStates.of(context).selected,
                  colors.surfaceContainerLow,
                )
              : colors.surfaceContainerLow,
          child: InkWell(
            onTap: () => onNavigate(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 42),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                border: chosen
                    ? Border(left: BorderSide(color: colors.primary, width: 3))
                    : null,
                boxShadow: chosen
                    ? const [
                        BoxShadow(
                          color: Color(0xff0a0908),
                          offset: Offset(1, 2),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: chosen ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: chosen
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                        fontSize: 14,
                        fontWeight: chosen ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (shortcut.isNotEmpty &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                    StudioStamp(shortcut, filled: true, color: colors.outline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila de la sidebar Brasa: portada/icono, título y subtítulo; activa = #231b16.
class _BrasaTile extends StatelessWidget {
  const _BrasaTile({
    required this.selected,
    required this.onTap,
    required this.leading,
    required this.title,
    this.dense = false,
  });
  final bool selected, dense;
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? Brasa.graphite : Colors.transparent,
    borderRadius: BorderRadius.circular(6),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      hoverColor: Brasa.graphite,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 8,
          vertical: dense ? 10 : 8,
        ),
        child: Row(
          children: [
            leading,
            SizedBox(width: dense ? 20 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: dense ? 16 : 14,
                      fontWeight: dense ? FontWeight.w700 : FontWeight.w600,
                      color: selected || !dense ? Brasa.cream : Brasa.cloud,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Logo Modern: círculo azul marino con símbolo de reproducir.
class _ModernLogo extends StatelessWidget {
  const _ModernLogo();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Tracky.navy, shape: BoxShape.circle),
    child: SizedBox.square(
      dimension: 32,
      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
    ),
  );
}
