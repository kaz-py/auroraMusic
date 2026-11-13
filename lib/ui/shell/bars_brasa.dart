/// Barras de escritorio del tema Brasa.
///
/// Dueño: tema Brasa. Barra superior y sidebar del escritorio; editar aquí no
/// afecta a los otros temas.
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/window_controls.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/brasa_sidebar_playlists.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/brasa_widgets.dart';
import '../studio/studio_components.dart';
import '../studio/studio_navigation.dart';
import '../studio/studio_symbols.dart';

/// Marca: cuadrado de brasa con brillo + «Aurora» en Fraunces.
class BrasaLogo extends StatelessWidget {
  const BrasaLogo({super.key, this.size = 34, this.showName = true});
  final double size;
  final bool showName;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * .32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xffffa468), Brasa.ember, Color(0xffe0562a)],
          ),
          boxShadow: [
            BoxShadow(
              color: Brasa.ember.withValues(alpha: .35),
              blurRadius: 16,
            ),
          ],
        ),
        child: SizedBox.square(dimension: size),
      ),
      if (showName) ...[
        const SizedBox(width: 12),
        Text('Aurora', style: Brasa.serif(24, height: 1)),
      ],
    ],
  );
}

/// Barra superior Brasa: marca a la izquierda, búsqueda, Jam, perfil y
/// controles de ventana, sobre el mismo tono que la sidebar.
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
        Tooltip(
          message: 'Inicio',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => bar.onNavigate(0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: BrasaLogo(showName: wide),
            ),
          ),
        ),
        if (hasSearch)
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: TextField(
                  controller: bar.searchController,
                  focusNode: bar.searchFocus,
                  textInputAction: TextInputAction.search,
                  onTap: () => bar.onNavigate(1),
                  onSubmitted: bar.onSearch,
                  onChanged: bar.onSearchChanged,
                  style: Brasa.sans(14),
                  decoration: InputDecoration(
                    hintText: '¿Qué quieres reproducir?',
                    hintStyle: Brasa.sans(14, color: Brasa.steel),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    fillColor: Brasa.graphite,
                    border: _pill(Colors.transparent),
                    enabledBorder: _pill(Colors.transparent),
                    focusedBorder: _pill(Brasa.ember),
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
                color: bar.activeSession
                    ? Brasa.ember.withValues(alpha: .16)
                    : Brasa.graphite,
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
                          color: bar.activeSession ? Brasa.ember : Brasa.steel,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          bar.sessionText,
                          style: Brasa.sans(
                            12,
                            weight: FontWeight.w700,
                            color: Brasa.cream,
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

/// Sidebar Brasa: 300 px por tono (sin bordes), destinos con atajo en mono,
/// etiquetas con punto de brasa, listas con muestra de color y Ajustes abajo.
Widget brasaSidebar(StudioSidebar side, BuildContext context) {
  String key(ShortcutId id, String fallback) =>
      side.shortcuts?.labelOf(id) ?? fallback;
  Widget tile(
    int i,
    String label,
    IconData icon, {
    String? tip,
    String? shortcut,
    int badge = 0,
  }) => Tooltip(
    message: tip ?? label,
    child: _BrasaTile(
      selected: side.selected == i,
      onTap: () => side.onNavigate(i),
      icon: icon,
      title: label,
      shortcut: shortcut,
      badge: badge,
    ),
  );
  return Container(
    width: 300,
    color: Brasa.void_,
    padding: const EdgeInsets.only(top: 4, bottom: 12),
    child: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              tile(
                0,
                'Inicio',
                StudioSymbols.home,
                shortcut: key(ShortcutId.home, 'Ctrl+1'),
              ),
              tile(
                1,
                'Búsqueda',
                StudioSymbols.search,
                tip: 'Buscar',
                shortcut: key(ShortcutId.search, 'Ctrl+2'),
              ),
              tile(8, 'DJ', StudioSymbols.explore),
              tile(12, 'Artistas', Icons.mic_none_rounded),
              tile(
                2,
                'Biblioteca',
                StudioSymbols.libraryMusic,
                shortcut: key(ShortcutId.library, 'Ctrl+3'),
              ),
              tile(
                3,
                'Descargas',
                StudioSymbols.downloadDone,
                tip: 'Descargas locales',
                shortcut: key(ShortcutId.downloads, 'Ctrl+4'),
              ),
              if (supabaseServicesEnabled)
                tile(
                  14,
                  side.friendsBadge > 0
                      ? 'Amigos (${side.friendsBadge})'
                      : 'Amigos',
                  Icons.people_outline,
                  tip: 'Amigos',
                ),
              const BrasaSectionLabel('Fidelidad & experiencia'),
              tile(
                4,
                'Modo Vinilo',
                StudioSymbols.album,
                shortcut: key(ShortcutId.vinyl, 'Ctrl+I'),
              ),
              tile(
                6,
                'Letras Dinámicas',
                StudioSymbols.lyrics,
                tip: 'Letras',
                shortcut: key(ShortcutId.lyrics, 'Ctrl+L'),
              ),
              tile(
                13,
                'Ecualizador',
                StudioSymbols.equalizer,
                shortcut: side.shortcuts == null
                    ? 'EQ'
                    : key(ShortcutId.equalizer, 'EQ'),
              ),
              tile(
                9,
                'Jam',
                StudioSymbols.groups,
                shortcut: side.shortcuts == null
                    ? null
                    : key(ShortcutId.jam, 'Ctrl+J'),
              ),
              tile(5, 'Cola de reproducción', StudioSymbols.queueMusic),
              BrasaSidebarPlaylists(
                controller: side.controller,
                onPlaylist: side.onPlaylist,
                onCreate: side.onCreatePlaylist,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            children: [
              tile(7, 'Ajustes', StudioSymbols.settings),
              const SizedBox(height: 8),
              _EngineCard(ready: side.controller.ready),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Tarjeta de estado del motor al pie de la sidebar.
class _EngineCard extends StatelessWidget {
  const _EngineCard({required this.ready});
  final bool ready;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: ready ? Brasa.amber : Brasa.steel,
              shape: BoxShape.circle,
              boxShadow: ready
                  ? [
                      BoxShadow(
                        color: Brasa.amber.withValues(alpha: .5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
            child: const SizedBox.square(dimension: 8),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MOTOR DE AUDIO',
                  style: Brasa.mono(
                    11,
                    color: Brasa.amber,
                    weight: FontWeight.w500,
                  ),
                ),
                Text(
                  ready ? 'Motor de reproducción listo' : 'Iniciando motor…',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Brasa.sans(12, color: Brasa.cloud),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Fila de la sidebar: activa = fondo graphite + barra de brasa con brillo en
/// el borde izquierdo + icono naranja; atajo en mono a la derecha.
class _BrasaTile extends StatelessWidget {
  const _BrasaTile({
    required this.selected,
    required this.onTap,
    required this.icon,
    required this.title,
    this.shortcut,
    this.badge = 0,
  });
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String title;
  final String? shortcut;
  final int badge;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected ? Brasa.graphite : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            hoverColor: Brasa.graphite,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: selected ? Brasa.ember : Brasa.cloud,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.sans(
                          14,
                          weight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? Brasa.cream : Brasa.cloud,
                        ),
                      ),
                    ),
                    if (shortcut != null) ...[
                      const SizedBox(width: 6),
                      Text(shortcut!, style: Brasa.mono(11, tracking: .02)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (selected)
        Positioned(
          left: -12,
          top: 0,
          bottom: 0,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Brasa.ember,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Brasa.ember.withValues(alpha: .6),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: const SizedBox(width: 4, height: 18),
            ),
          ),
        ),
    ],
  );
}
