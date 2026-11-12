/// Barras de escritorio del tema Modern.
///
/// Dueño: tema Modern. Barra superior y sidebar del escritorio; editar aquí no
/// afecta a los otros temas.
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/window_controls.dart';
import '../../shortcuts/shortcut_service.dart';
import '../playlist_views/playlist_photo_menu.dart';
import '../studio/studio_components.dart';
import '../studio/studio_navigation.dart';
import '../studio/studio_symbols.dart';
import '../../theme/modern_widgets.dart';

/// Barra superior Modern.
Widget modernTitleBar(
  StudioTitleBar bar,
  BuildContext context,
  BoxConstraints constraints,
  bool largeText,
) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    height: largeText ? 60 : 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: colors.surface, border: null),
    child: Row(
      children: [
        GestureDetector(
          onPanStart: (_) => WindowControls.invoke('drag'),
          onDoubleTap: () => WindowControls.invoke('maximize'),
          child: Row(
            children: [
              const _ModernLogo(),
              const SizedBox(width: 8),
              if (constraints.maxWidth > (largeText ? 450 : 400))
                Text(
                  'Aurora',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.18,
                    color: colors.onSurface,
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
              onTap: () => bar.onNavigate(item.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
            borderRadius: BorderRadius.circular(8),
            onTap: bar.onSession ?? () => bar.onNavigate(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bar.activeSession
                    ? Tracky.mint
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    StudioSymbols.wifiTethering,
                    size: 14,
                    color: bar.activeSession ? Tracky.navy : colors.outline,
                  ),
                  const SizedBox(width: 4),
                  StudioStamp(
                    bar.sessionText,
                    color: bar.activeSession ? Tracky.navy : null,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: bar.activeSession ? Tracky.navy : colors.outline,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 16),
        Builder(
          builder: (ctx) => IconButton.filled(
            tooltip: 'Perfil y ajustes',
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              minimumSize: const Size(32, 32),
              padding: bar.avatar == null
                  ? const EdgeInsets.all(6)
                  : EdgeInsets.zero,
            ),
            onPressed: () => bar.profile(ctx),
            icon: bar.profileGlyph(32, 18),
          ),
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

/// Sidebar Modern.
Widget modernSidebar(StudioSidebar side, BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    width: 260,
    decoration: BoxDecoration(color: colors.surface, border: null),
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
                  side,
                  context,
                  0,
                  'Inicio',
                  'Inicio',
                  StudioSymbols.home,
                  side.shortcuts?.labelOf(ShortcutId.home) ?? 'Ctrl+1',
                ),
                _nav(
                  side,
                  context,
                  1,
                  'Búsqueda',
                  'Buscar',
                  StudioSymbols.search,
                  side.shortcuts?.labelOf(ShortcutId.search) ?? 'Ctrl+2',
                ),
                _nav(side, context, 8, 'DJ', 'DJ', StudioSymbols.explore, ''),
                _nav(
                  side,
                  context,
                  12,
                  'Artistas',
                  'Artistas',
                  Icons.mic_none_rounded,
                  '',
                ),
                _nav(
                  side,
                  context,
                  2,
                  'Biblioteca',
                  'Biblioteca',
                  StudioSymbols.libraryMusic,
                  side.shortcuts?.labelOf(ShortcutId.library) ?? 'Ctrl+3',
                ),
                _nav(
                  side,
                  context,
                  3,
                  'Descargas',
                  'Descargas locales',
                  StudioSymbols.downloadDone,
                  side.shortcuts?.labelOf(ShortcutId.downloads) ?? 'Ctrl+4',
                ),
                const SizedBox(height: 20),
                Tooltip(
                  message: side.controller.downloadsDirectoryPath,
                  child: Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(StudioSymbols.folder, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            side.controller.downloadsDirectoryPath.replaceAll(
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
                  side,
                  context,
                  4,
                  'Modo Vinilo',
                  'Modo Vinilo',
                  StudioSymbols.album,
                  side.shortcuts?.labelOf(ShortcutId.vinyl) ?? 'Ctrl+I',
                ),
                _nav(
                  side,
                  context,
                  6,
                  'Letras Dinámicas',
                  'Letras',
                  StudioSymbols.lyrics,
                  side.shortcuts?.labelOf(ShortcutId.lyrics) ?? 'Ctrl+L',
                ),
                _nav(
                  side,
                  context,
                  13,
                  'Ecualizador',
                  'Ecualizador',
                  StudioSymbols.equalizer,
                  'EQ',
                ),
                _nav(
                  side,
                  context,
                  7,
                  'Modo Foco / Sueño',
                  'Modo Foco / Sueño',
                  StudioSymbols.bedtime,
                  'Zz',
                  active: false,
                ),
                _nav(side, context, 9, 'Jam', 'Jam', StudioSymbols.groups, ''),
                if (supabaseServicesEnabled)
                  _nav(
                    side,
                    context,
                    14,
                    'Amigos',
                    'Amigos',
                    Icons.people_outline,
                    side.friendsBadge > 0 ? '${side.friendsBadge}' : '',
                  ),
                _nav(
                  side,
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
                for (final playlist in side.controller.playlists)
                  PlaylistPhotoMenu(
                    controller: side.controller,
                    playlist: playlist,
                    child: Padding(
                      // Margen para que el contorno de 2 px no se recorte.
                      padding: EdgeInsets.zero,
                      child: TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          foregroundColor: colors.onSurfaceVariant,
                        ),
                        onPressed: () => side.onPlaylist(playlist),
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
                if (side.controller.playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Aún no hay colecciones',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                _nav(
                  side,
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const StudioStamp('SINCRONIZACIÓN DAC · NO MEDIDA'),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: side.controller.audio.isBuffering ? null : 0,
                minHeight: 4,
                borderRadius: BorderRadius.circular(8),
                color: Tracky.mint,
              ),
              const SizedBox(height: 6),
              Text(
                side.controller.audio.isBuffering
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

Widget _label(BuildContext context, String value) => Padding(
  padding: const EdgeInsets.only(top: 8, bottom: 8),
  child: Padding(
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
  ),
);

Widget _nav(
  StudioSidebar side,
  BuildContext context,
  int index,
  String label,
  String tooltip,
  IconData icon,
  String shortcut, {
  bool? active,
}) {
  final colors = Theme.of(context).colorScheme;
  final chosen = active ?? side.selected == index;
  final fg = chosen ? colors.onPrimary : colors.onSurfaceVariant;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Tooltip(
      message: tooltip,
      child: Material(
        color: chosen ? colors.primary : Colors.transparent,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => side.onNavigate(index),
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
                      fontWeight: chosen ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (shortcut.isNotEmpty &&
                    MediaQuery.textScalerOf(context).scale(1) <= 1.5)
                  Text(
                    shortcut,
                    style: TextStyle(
                      fontSize: 11,
                      color: fg.withValues(alpha: .8),
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
