/// Barras de escritorio del tema Atelier.
///
/// Dueño: tema Atelier. La sidebar de 248 px reemplaza a la barra superior de
/// 40 px; arriba del contenido queda solo una franja fina (búsqueda, perfil y
/// controles de ventana). Editar aquí no afecta a los otros temas.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/feature_flags.dart';
import '../../core/models.dart';
import '../../core/window_controls.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/atelier_theme.dart';
import '../playlist_views/playlist_photo_menu.dart';
import '../studio/studio_components.dart';
import '../studio/studio_navigation.dart';
import '../studio/studio_symbols.dart';
import 'atelier_widgets.dart';

/// Franja superior del contenido (StudioTitleBar, Atelier).
Widget atelierTitleBar(
  StudioTitleBar bar,
  BuildContext context,
  BoxConstraints constraints,
  bool largeText,
) => AtelierTopStrip(
  avatar: bar.avatar,
  onProfile: bar.profile,
  searchController: bar.searchController,
  searchFocus: bar.searchFocus,
  onSearch: bar.onSearch,
  onSearchChanged: bar.onSearchChanged,
  sessionText: bar.sessionText,
  activeSession: bar.activeSession,
  onSession: bar.onSession ?? () => bar.onNavigate(9),
);

/// Franja de 48 px sobre el contenido: título de la sección (si lo hay),
/// búsqueda de solo subrayado, Jam, perfil y controles de ventana. Es zona de
/// arrastre de la ventana.
class AtelierTopStrip extends StatelessWidget {
  const AtelierTopStrip({
    super.key,
    required this.onProfile,
    this.avatar,
    this.title,
    this.searchController,
    this.searchFocus,
    this.onSearch,
    this.onSearchChanged,
    this.searchHint = 'Buscar canciones, artistas, letras',
    this.searchShortcut,
    this.sessionText,
    this.activeSession = false,
    this.onSession,
  });

  final Uint8List? avatar;
  final void Function(BuildContext anchor) onProfile;
  final String? title;
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearch, onSearchChanged;
  final String searchHint;
  final String? searchShortcut;
  final String? sessionText;
  final bool activeSession;
  final VoidCallback? onSession;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final large = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760 && !large;
        return Padding(
          padding: const EdgeInsets.fromLTRB(48, 8, 12, 4),
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (_) => WindowControls.invoke('drag'),
                    onDoubleTap: () => WindowControls.invoke('maximize'),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: title == null
                          ? null
                          : Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.serif(26),
                            ),
                    ),
                  ),
                ),
                if (onSearch != null)
                  SizedBox(
                    // La búsqueda cede ancho al chip de Jam y a los controles de
                    // ventana cuando hay panel derecho (contenido de ~800 px).
                    width: wide
                        ? (box.maxWidth - 560).clamp(220.0, 340.0)
                        : (box.maxWidth < 500 ? 160 : 220),
                    child: _SearchField(
                      controller: searchController,
                      focus: searchFocus,
                      hint: searchHint,
                      shortcut: wide ? searchShortcut : null,
                      onSubmitted: onSearch!,
                      onChanged: onSearchChanged,
                    ),
                  ),
                if (wide && sessionText != null && onSession != null) ...[
                  const SizedBox(width: 12),
                  _SessionChip(
                    text: sessionText!,
                    active: activeSession,
                    onTap: onSession!,
                  ),
                ],
                const SizedBox(width: 12),
                Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'Perfil y ajustes',
                    style: IconButton.styleFrom(
                      backgroundColor: t.ink,
                      foregroundColor: t.paper,
                      minimumSize: const Size(36, 36),
                      fixedSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => onProfile(ctx),
                    icon: avatar == null
                        ? const Icon(StudioSymbols.person, size: 18)
                        : ClipOval(
                            child: Image.memory(
                              avatar!,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                              cacheWidth: 108,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const Icon(StudioSymbols.person, size: 18),
                            ),
                          ),
                  ),
                ),
                if (WindowControls.supported) ...[
                  const SizedBox(width: 8),
                  for (final item in const [
                    ('minimize', Icons.remove, 'Minimizar'),
                    ('maximize', Icons.crop_square, 'Maximizar o restaurar'),
                    ('close', Icons.close, 'Cerrar ventana'),
                  ])
                    IconButton(
                      tooltip: item.$3,
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        if (!await WindowControls.invoke(item.$1) &&
                            context.mounted) {
                          showStudioPending(
                            context,
                            'Control de ventana Windows',
                          );
                        }
                      },
                      icon: Icon(item.$2, size: 17),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.hint,
    required this.shortcut,
    required this.onSubmitted,
    required this.onChanged,
  });
  final TextEditingController? controller;
  final FocusNode? focus;
  final String hint;
  final String? shortcut;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return TextField(
      controller: controller,
      focusNode: focus,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: t.ui(14),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: t.ui(14, color: t.muted),
        prefixIcon: Icon(Icons.search, size: 18, color: t.ink2),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 36,
        ),
        suffixText: shortcut,
        suffixStyle: t.mono(size: 11),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

class _SessionChip extends StatelessWidget {
  const _SessionChip({
    required this.text,
    required this.active,
    required this.onTap,
  });
  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: active ? t.accent : t.rule),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                StudioSymbols.wifiTethering,
                size: 14,
                color: active ? t.accentText : t.muted,
              ),
              const SizedBox(width: 6),
              Text(
                text,
                maxLines: 1,
                style: t.mono(
                  size: 10.5,
                  color: active ? t.accentText : t.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sidebar Atelier (StudioSidebar).
Widget atelierSidebar(StudioSidebar side, BuildContext context) =>
    AtelierSidebar(
      controller: side.controller,
      selected: side.selected,
      onNavigate: side.onNavigate,
      onPlaylist: side.onPlaylist,
      onCreatePlaylist: side.onCreatePlaylist,
      shortcuts: side.shortcuts,
      friendsBadge: side.friendsBadge,
    );

/// Sidebar de 248 px: logo con doble filete, navegación con atajos mono,
/// secciones con filete y etiqueta, chip de carpeta discontinuo y pie de
/// estado del motor.
class AtelierSidebar extends StatelessWidget {
  const AtelierSidebar({
    super.key,
    required this.controller,
    required this.selected,
    required this.onNavigate,
    required this.onPlaylist,
    this.onCreatePlaylist,
    this.shortcuts,
    this.friendsBadge = 0,
  });
  final AppController controller;
  final int selected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<MusicPlaylist> onPlaylist;
  final VoidCallback? onCreatePlaylist;
  final ShortcutService? shortcuts;
  final int friendsBadge;

  String _key(ShortcutId id, String fallback) =>
      shortcuts?.labelOf(id) ?? fallback;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final c = controller;
    final sleeping = c.sleepRemaining != null;
    Widget nav(
      int index,
      String label,
      IconData icon,
      String shortcut, {
      VoidCallback? onTap,
      bool? active,
      String? tooltip,
    }) => _NavItem(
      label: label,
      tooltip: tooltip ?? label,
      icon: icon,
      shortcut: shortcut,
      active: active ?? selected == index,
      onTap: onTap ?? () => onNavigate(index),
    );
    return Container(
      width: 248,
      color: t.panel,
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => WindowControls.invoke('drag'),
            onDoubleTap: () => WindowControls.invoke('maximize'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aurora',
                    style: t.serif(32, italic: true, height: 1.05),
                  ),
                  const SizedBox(height: 4),
                  Text('MÚSICA · Nº ${_issue()}', style: t.mono(size: 10.5)),
                  const SizedBox(height: 10),
                  Container(height: 1, color: t.ink),
                  const SizedBox(height: 2),
                  Container(height: 1, color: t.rule),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  nav(
                    0,
                    'Inicio',
                    Icons.home_outlined,
                    _key(ShortcutId.home, 'Ctrl+1'),
                  ),
                  nav(
                    1,
                    'Búsqueda',
                    Icons.search,
                    _key(ShortcutId.search, 'Ctrl+2'),
                    tooltip: 'Buscar',
                  ),
                  nav(8, 'DJ', StudioSymbols.explore, ''),
                  nav(12, 'Artistas', Icons.mic_none_rounded, ''),
                  nav(
                    2,
                    'Biblioteca',
                    StudioSymbols.libraryMusic,
                    _key(ShortcutId.library, 'Ctrl+3'),
                  ),
                  nav(
                    3,
                    'Descargas',
                    StudioSymbols.downloadDone,
                    _key(ShortcutId.downloads, 'Ctrl+4'),
                    tooltip: 'Descargas locales',
                  ),
                  nav(11, 'Vídeos', Icons.video_file_outlined, ''),
                  const SizedBox(height: 10),
                  Tooltip(
                    message: c.downloadsDirectoryPath,
                    child: InkWell(
                      onTap: () => onNavigate(3),
                      child: AtelierDashedBox(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 36),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.folder_outlined,
                                  size: 16,
                                  color: t.ink2,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Música · ${c.tracks.length} pistas',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.ui(12.5, color: t.ink2),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const _Label('FIDELIDAD & EXPERIENCIA'),
                  nav(
                    4,
                    'Modo Vinilo',
                    StudioSymbols.album,
                    _key(ShortcutId.vinyl, 'Ctrl+I'),
                  ),
                  nav(
                    6,
                    'Letras Dinámicas',
                    StudioSymbols.lyrics,
                    _key(ShortcutId.lyrics, 'Ctrl+L'),
                    tooltip: 'Letras',
                    active: false,
                  ),
                  nav(13, 'Ecualizador', StudioSymbols.equalizer, 'EQ'),
                  nav(
                    7,
                    'Modo Foco / Sueño',
                    StudioSymbols.bedtime,
                    sleeping ? '${atelierSleepLabel(c)}' : 'Zz',
                    active: sleeping,
                    onTap: () => showAtelierSleepSheet(context, c),
                  ),
                  nav(9, 'Jam', StudioSymbols.groups, ''),
                  if (supabaseServicesEnabled)
                    nav(
                      14,
                      'Amigos',
                      Icons.people_outline,
                      friendsBadge > 0 ? '$friendsBadge' : '',
                    ),
                  nav(5, 'Cola de reproducción', StudioSymbols.queueMusic, ''),
                  _Label(
                    'ÁNIMOS & COLECCIONES',
                    trailing: onCreatePlaylist == null
                        ? null
                        : IconButton(
                            tooltip: 'Crear lista',
                            visualDensity: VisualDensity.compact,
                            onPressed: onCreatePlaylist,
                            icon: const Icon(Icons.add, size: 18),
                          ),
                  ),
                  for (final playlist in c.playlists)
                    PlaylistPhotoMenu(
                      controller: c,
                      playlist: playlist,
                      child: _NavItem(
                        label: playlist.name,
                        tooltip: playlist.name,
                        icon: Icons.music_note_outlined,
                        shortcut: '',
                        active: false,
                        onTap: () => onPlaylist(playlist),
                      ),
                    ),
                  if (c.playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 12,
                      ),
                      child: Text(
                        'Aún no hay colecciones',
                        style: t.ui(12.5, color: t.muted),
                      ),
                    ),
                  nav(7, 'Ajustes', Icons.tune, '', active: selected == 7),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 1, color: t.ink),
                const SizedBox(height: 10),
                Text(
                  'SINCRONIZACIÓN DAC · NO MEDIDA',
                  maxLines: 2,
                  style: t.mono(size: 10),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: t.ok,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        c.audio.isBuffering
                            ? 'Preparando buffer'
                            : 'Motor de reproducción listo',
                        style: t.ui(12, color: t.ink2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Número de la «edición» (semana del año).
  static int _issue() {
    final now = DateTime.now();
    return (now.difference(DateTime(now.year)).inDays ~/ 7) + 1;
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 0, 2),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.rule)),
        ),
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            Expanded(child: Text(text, maxLines: 2, style: t.mono(size: 10.5))),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.shortcut,
    required this.active,
    required this.onTap,
  });
  final String label, tooltip, shortcut;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final showKey =
        shortcut.isNotEmpty && MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: active ? t.paper : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: active ? t.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 17, color: active ? t.accentText : t.ink2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.ui(
                        14,
                        weight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? t.ink : t.ink2,
                      ),
                    ),
                  ),
                  if (showKey) Text(shortcut, style: t.mono(size: 10.5)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
