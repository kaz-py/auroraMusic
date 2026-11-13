/// Sidebar flotante de cristal del tema Modern: 248 px con etiquetas y atajos,
/// o carril de 76 px solo con iconos y tooltip. Dueño: tema Modern.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/feature_flags.dart';
import '../../core/models.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/modern_cristal.dart';
import '../brand/aurora_logo.dart';
import '../playlist_views/playlist_photo_menu.dart';
import 'shell_sections.dart';

/// «Ctrl+3» -> «Ctrl 3» (formato mono del prototipo).
String modernShortcutText(ShortcutService? s, ShortcutId id) =>
    s == null ? '' : s.labelOf(id).replaceAll('+', ' ');

class ModernSidebar extends StatelessWidget {
  const ModernSidebar({
    super.key,
    required this.controller,
    required this.selected,
    required this.onNavigate,
    required this.onPlaylist,
    this.onCreatePlaylist,
    this.shortcuts,
    this.friendsBadge = 0,
    this.collapsed = false,
  });

  final AppController controller;
  final int selected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<MusicPlaylist> onPlaylist;
  final VoidCallback? onCreatePlaylist;
  final ShortcutService? shortcuts;
  final int friendsBadge;

  /// Carril de iconos (76 px) en lugar del panel expandido (248 px).
  final bool collapsed;

  List<_Entry> _entries(List<(int, String, ShortcutId?, String)> raw) => [
    for (final e in raw)
      _Entry(
        e.$1,
        e.$2,
        e.$3 == null ? e.$4 : modernShortcutText(shortcuts, e.$3!),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final main = _entries([
      (0, 'Inicio', ShortcutId.home, ''),
      (1, 'Buscar', ShortcutId.search, ''),
      (8, 'DJ', null, ''),
      (12, 'Artistas', null, ''),
      (2, 'Biblioteca', ShortcutId.library, ''),
      (3, 'Descargas', ShortcutId.downloads, ''),
      (11, 'Descargar vídeos', null, ''),
    ]);
    final fidelity = _entries([
      (4, 'Modo Vinilo', ShortcutId.vinyl, ''),
      (6, 'Letras', ShortcutId.lyrics, ''),
      (13, 'Ecualizador', ShortcutId.equalizer, ''),
      (9, 'Jam', ShortcutId.jam, ''),
      if (supabaseServicesEnabled) (14, 'Amigos', null, ''),
      (5, 'Cola', ShortcutId.queue, ''),
    ]);
    final playlists = controller.playlists;
    final width = collapsed ? 76.0 : 248.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: SizedBox(
        width: width,
        child: ModernGlass(
          radius: 24,
          clip: true,
          child: Column(
            children: [
              _Brand(collapsed: collapsed, onTap: () => onNavigate(0)),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: collapsed ? 8 : 10),
                  children: [
                    for (final e in main) _item(context, e),
                    _divider(c, 'FIDELIDAD & EXPERIENCIA'),
                    for (final e in fidelity.take(3)) _item(context, e),
                    // «Foco / Sueño» vive en Ajustes: no marca la sección.
                    _item(
                      context,
                      const _Entry(
                        7,
                        'Foco / Sueño',
                        'Zz',
                        icon: Icons.bedtime_outlined,
                      ),
                      activeOn: -1,
                    ),
                    for (final e in fidelity.skip(3)) _item(context, e),
                    _divider(
                      c,
                      'ÁNIMOS & COLECCIONES',
                      action: onCreatePlaylist == null
                          ? null
                          : IconButton(
                              tooltip: 'Crear colección',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints(
                                minWidth: 40,
                                minHeight: 40,
                              ),
                              color: c.text2,
                              onPressed: onCreatePlaylist,
                              icon: const Icon(Icons.add, size: 18),
                            ),
                    ),
                    for (var i = 0; i < playlists.length; i++)
                      _playlist(context, playlists[i], i),
                    if (playlists.isEmpty && !collapsed)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Text(
                          'Aún no hay colecciones',
                          style: Cristal.ui(12, color: c.text3),
                        ),
                      ),
                    const SizedBox(height: 4),
                    _item(context, _Entry(7, 'Ajustes', ''), activeOn: 7),
                  ],
                ),
              ),
              _Footer(collapsed: collapsed, buffering: _buffering),
            ],
          ),
        ),
      ),
    );
  }

  bool get _buffering => controller.audio.isBuffering;

  Widget _divider(Cristal c, String label, {Widget? action}) {
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Divider(height: 1, color: c.border),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 0, 4),
      child: Row(
        children: [
          Expanded(child: ModernLabel(label)),
          ?action,
        ],
      ),
    );
  }

  Widget _item(BuildContext context, _Entry e, {int? activeOn}) {
    final c = Cristal.of(context);
    final active = selected == (activeOn ?? e.id);
    final icon = e.icon ?? shellSectionIcons[e.id] ?? Icons.circle;
    final color = active ? c.accent : c.text2;
    final badge = e.id == 14 ? friendsBadge : 0;
    final tooltip = e.shortcut.isEmpty ? e.label : '${e.label}  ${e.shortcut}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        button: true,
        selected: active,
        label: e.label,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Material(
                color: active ? c.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onNavigate(e.id),
                  child: ConstrainedBox(
                    // Panel expandido = escritorio con puntero (prototipo ~32 px
                    // de paso); el riel táctil conserva 44.
                    constraints: BoxConstraints(minHeight: collapsed ? 44 : 38),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: collapsed ? 0 : 12,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisAlignment: collapsed
                            ? MainAxisAlignment.center
                            : MainAxisAlignment.start,
                        children: [
                          Badge(
                            isLabelVisible: badge > 0 && collapsed,
                            label: Text('$badge'),
                            child: Icon(icon, size: 20, color: color),
                          ),
                          if (!collapsed) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                e.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Cristal.ui(
                                  13.5,
                                  weight: active ? 700 : 600,
                                  color: active ? c.text : c.text2,
                                ),
                              ),
                            ),
                            if (badge > 0)
                              _Count(badge)
                            else if (e.shortcut.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(
                                flex: 0,
                                child: Text(
                                  e.shortcut,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cristal.mono(
                                    10.5,
                                    color: c.text3,
                                    tracking: .04,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (active)
                Positioned(
                  left: 0,
                  child: IgnorePointer(
                    child: Container(
                      width: 3,
                      height: 20,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playlist(BuildContext context, MusicPlaylist playlist, int i) {
    final c = Cristal.of(context);
    final dot = [c.signal, c.accent, c.vu, c.like][i % 4];
    final mark = Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: dot,
        borderRadius: BorderRadius.circular(collapsed ? 4 : 6),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: PlaylistPhotoMenu(
        controller: controller,
        playlist: playlist,
        child: Tooltip(
          message: playlist.name,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => onPlaylist(playlist),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: collapsed ? 44 : 38),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: collapsed ? 0 : 12,
                    vertical: 6,
                  ),
                  child: collapsed
                      ? Center(child: mark)
                      : Row(
                          children: [
                            mark,
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                playlist.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Cristal.ui(13, color: c.text2),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Entry {
  const _Entry(this.id, this.label, this.shortcut, {this.icon});
  final int id;
  final String label, shortcut;
  final IconData? icon;
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$n',
        style: Cristal.mono(10.5, weight: 700, color: c.onAccent),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onTap});
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return Semantics(
      button: true,
      label: 'Aurora, ir a Inicio',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(collapsed ? 0 : 20, 20, 0, 12),
          child: Row(
            mainAxisAlignment: collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              const AuroraLogo(size: 32),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Text(
                  'Aurora',
                  style: Cristal.ui(
                    18,
                    weight: 800,
                    color: c.text,
                    tracking: -.03,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.collapsed, required this.buffering});
  final bool collapsed;
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final led = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: buffering ? c.vu : c.signal,
      ),
    );
    final text = buffering
        ? 'Preparando buffer'
        : 'Motor de reproducción listo';
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Tooltip(
        message: text,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: EdgeInsets.symmetric(
            horizontal: collapsed ? 0 : 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: c.glass,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.border),
          ),
          child: collapsed
              ? Center(child: led)
              : Row(
                  children: [
                    led,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Cristal.mono(10, color: c.text3, tracking: .06),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
