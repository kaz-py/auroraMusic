/// Barras de escritorio del tema Brasa.
///
/// Dueño: tema Brasa. Barra superior y sidebar del escritorio; editar aquí no
/// afecta a los otros temas.
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/window_controls.dart';
import '../studio/studio_components.dart';
import '../studio/studio_navigation.dart';
import '../studio/studio_symbols.dart';
import '../../theme/brasa_sidebar_playlists.dart';
import '../../theme/brasa_theme.dart';

/// Barra superior Brasa.
Widget brasaTitleBar(
  StudioTitleBar bar,
  BuildContext context,
  BoxConstraints box,
  bool largeText,
) {
  final wide = box.maxWidth > 700 && !largeText;
  final hasSearch = bar.searchController != null && box.maxWidth > 560;
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
          onPressed: () => bar.onNavigate(0),
          icon: const Icon(StudioSymbols.home, size: 22),
        ),
        if (hasSearch)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: TextField(
                  controller: bar.searchController,
                  focusNode: bar.searchFocus,
                  textInputAction: TextInputAction.search,
                  onTap: () => bar.onNavigate(1),
                  onSubmitted: bar.onSearch,
                  onChanged: bar.onSearchChanged,
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
                  onTap: bar.onSession ?? () => bar.onNavigate(9),
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
                          color: bar.activeSession ? Brasa.cream : Brasa.steel,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          bar.sessionText,
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
        Builder(
          builder: (ctx) => IconButton.filled(
            tooltip: 'Perfil y ajustes',
            style: IconButton.styleFrom(
              backgroundColor: Brasa.graphite,
              foregroundColor: Brasa.cream,
              minimumSize: const Size(36, 36),
              padding: bar.avatar == null ? null : EdgeInsets.zero,
            ),
            onPressed: () => bar.profile(ctx),
            icon: bar.profileGlyph(36, 18),
          ),
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
                if (!await WindowControls.invoke(item.$1) && context.mounted) {
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

OutlineInputBorder _pill(Color c) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(9999),
  borderSide: BorderSide(color: c),
);

/// Sidebar Brasa: ~300 px sin borde, accesos arriba y panel «Tu biblioteca».
Widget brasaSidebar(StudioSidebar side, BuildContext context) {
  // (índice, título, tooltip, icono)
  final items = <(int, String, String, IconData)>[
    (2, 'Biblioteca', 'Biblioteca', StudioSymbols.libraryMusic),
    (3, 'Descargas', 'Descargas locales', StudioSymbols.downloadDone),
    (4, 'Modo Vinilo', 'Modo Vinilo', StudioSymbols.album),
    (6, 'Letras', 'Letras', StudioSymbols.lyrics),
    (9, 'Jam', 'Jam', StudioSymbols.groups),
    if (supabaseServicesEnabled)
      (
        14,
        side.friendsBadge > 0 ? 'Amigos (${side.friendsBadge})' : 'Amigos',
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
      selected: side.selected == i,
      onTap: () => side.onNavigate(i),
      dense: true,
      leading: Icon(
        icon,
        size: 24,
        color: side.selected == i ? Brasa.cream : Brasa.cloud,
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
                            selected: side.selected == e.$1,
                            onTap: () => side.onNavigate(e.$1),
                            dense: true,
                            leading: Icon(
                              e.$4,
                              size: 22,
                              color: side.selected == e.$1
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
            controller: side.controller,
            onPlaylist: side.onPlaylist,
            onCreate: side.onCreatePlaylist,
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
