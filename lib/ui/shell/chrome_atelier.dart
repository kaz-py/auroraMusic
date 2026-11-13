import '../jam/jam_widgets.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/atelier_theme.dart';
import '../right_panel/right_panel_atelier.dart';
import '../studio/home_introduction.dart';
import 'atelier_widgets.dart';
import 'bars_atelier.dart';
import 'shell_chrome.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';
import 'shell_sections.dart';

/// Dueño: tema Atelier («Papel y tinta»). Chrome del shell: sidebar de 248 px
/// (sin barra superior), franja de búsqueda/perfil, panel derecho con
/// pestañas, aviso de error y navegación móvil de cinco entradas con hoja «Más».
const atelierChrome = AtelierChrome();

class AtelierChrome extends ShellChrome {
  const AtelierChrome();

  @override
  Widget? topBar(BuildContext context, ShellScope scope) => null;

  @override
  Widget? sidebar(BuildContext context, ShellScope scope) {
    if (!scope.rail) return null;
    if (scope.wide) {
      return MouseOnlyRegion(
        child: AtelierSidebar(
          controller: scope.controller,
          selected: scope.section,
          onNavigate: scope.onNavigate,
          onPlaylist: scope.onOpenLibrary,
          onCreatePlaylist: scope.onCreatePlaylist,
          shortcuts: scope.shortcuts,
          friendsBadge: scope.friendsBadge,
        ),
      );
    }
    return ShellNarrowRail(
      scope: scope,
      kind: AuroraThemeKind.atelier,
      modern: false,
    );
  }

  @override
  Widget? aside(BuildContext context, ShellScope scope) {
    if (!scope.desktop ||
        scope.controller.jamPlaybackActive ||
        const [3, 5, 6, 7, 13, 11].contains(scope.section)) {
      return null;
    }
    return AtelierAside(
      controller: scope.controller,
      jam: scope.jam,
      onStartJam: scope.onStartJam,
      onJam: () => scope.onNavigate(9),
      onQueue: () => scope.onNavigate(scope.jamOn ? 9 : 5),
      onLyrics: () => scope.onNavigate(6),
    );
  }

  @override
  Widget? header(BuildContext context, ShellScope scope) {
    if (!scope.rail) {
      return scope.section == 4 ? null : _MobileHeader(scope: scope);
    }
    final c = scope.controller;
    final title = switch (scope.section) {
      0 || 3 || 4 => null,
      _ =>
        scope.playlist == null
            ? shellSectionTitles[scope.section]
            : c.playlists
                      .where((p) => p.id == scope.playlist!.id)
                      .firstOrNull
                      ?.name ??
                  shellSectionTitles[scope.section],
    };
    return MouseOnlyRegion(
      child: AtelierTopStrip(
        avatar: scope.avatar,
        onProfile: scope.onProfile,
        title: title,
        searchController: scope.section == 1 ? null : scope.searchController,
        searchFocus: scope.searchFocus,
        onSearch: scope.section == 1 ? null : scope.onSearch,
        onSearchChanged: scope.onSearchChanged,
        searchShortcut: scope.shortcuts.labelOf(ShortcutId.search),
        sessionText: scope.jamOn
            ? 'JAM · ${scope.jam!.peopleCount} ${scope.jam!.peopleCount == 1 ? 'PERSONA' : 'PERSONAS'}'
            : 'INICIAR UNA JAM',
        activeSession: scope.jamOn,
        onSession: scope.jamOn ? scope.onOpenJamPanel : scope.onStartJam,
      ),
    );
  }

  @override
  Widget errorBanner(BuildContext context, ShellScope scope) {
    final colors = Theme.of(context).colorScheme;
    final t = AtelierTokens.of(context);
    return Material(
      color: colors.errorContainer,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.ink)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colors.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                scope.controller.error!,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar aviso',
              onPressed: scope.controller.clearError,
              icon: Icon(Icons.close, color: colors.onErrorContainer),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget bottomNavigation(BuildContext context, ShellScope scope) {
    // El reproductor móvil trae su propio pie («Cola · N pistas»).
    if (scope.section == 4) return const SizedBox.shrink();
    final primary = primarySections(AuroraThemeKind.atelier, mobile: true);
    return _BottomNav(scope: scope, primary: primary);
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.scope, required this.primary});
  final ShellScope scope;
  final List<int> primary;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final more = !primary.contains(scope.section);
    return Material(
      color: t.paper,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.ink)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in primary)
                    Expanded(
                      child: _NavTab(
                        label: section == 3
                            ? 'Descargas'
                            : shellSectionTitles[section]!,
                        tooltip: section == 1 && scope.section != 1
                            ? 'Buscar música'
                            : shellSectionTitles[section]!,
                        icon: shellSectionIcons[section]!,
                        selected: scope.section == section,
                        onTap: () => scope.onNavigate(section),
                      ),
                    ),
                  Expanded(
                    child: _NavTab(
                      label: 'Más',
                      tooltip: 'Más vistas',
                      icon: Icons.more_horiz,
                      selected: more,
                      badge: scope.friendsBadge,
                      onTap: () => showAtelierMoreSheet(context, scope),
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
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });
  final String label, tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final color = selected ? t.accentText : t.ink2;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                height: 3,
                width: 28,
                color: selected ? t.accent : Colors.transparent,
              ),
              const SizedBox(height: 10),
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Icon(icon, size: 24, color: color),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: t.ui(
                      11,
                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja «Más»: las vistas que no caben en la barra inferior.
Future<void> showAtelierMoreSheet(BuildContext context, ShellScope scope) {
  final entries = <(int, String, IconData, int)>[
    (8, 'DJ', shellSectionIcons[8]!, 0),
    (12, 'Artistas', shellSectionIcons[12]!, 0),
    (11, 'Descargar vídeos', shellSectionIcons[11]!, 0),
    (9, 'Jam', shellSectionIcons[9]!, 0),
    if (supabaseServicesEnabled)
      (14, 'Amigos', shellSectionIcons[14]!, scope.friendsBadge),
    (4, 'Modo Vinilo', shellSectionIcons[4]!, 0),
    (5, 'Cola de reproducción', shellSectionIcons[5]!, 0),
    (6, 'Letras', shellSectionIcons[6]!, 0),
    (13, 'Ecualizador', shellSectionIcons[13]!, 0),
    (7, 'Ajustes', shellSectionIcons[7]!, 0),
  ];
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) {
      final t = AtelierTokens.of(sheet);
      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Más vistas', style: t.serif(26)),
            ),
            for (var i = 0; i < entries.length; i++)
              InkWell(
                onTap: () {
                  Navigator.pop(sheet);
                  scope.onNavigate(entries[i].$1);
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        (i + 1).toString().padLeft(2, '0'),
                        style: t.mono(size: 12, color: t.accentText),
                      ),
                      const SizedBox(width: 16),
                      Badge(
                        isLabelVisible: entries[i].$4 > 0,
                        label: Text('${entries[i].$4}'),
                        child: Icon(entries[i].$3, size: 20, color: t.ink2),
                      ),
                      const SizedBox(width: 16),
                      Expanded(child: Text(entries[i].$2, style: t.serif(19))),
                    ],
                  ),
                ),
              ),
            InkWell(
              onTap: () {
                Navigator.pop(sheet);
                showAtelierSleepSheet(context, scope.controller);
              },
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.rule)),
                ),
                child: Row(
                  children: [
                    Text(
                      (entries.length + 1).toString().padLeft(2, '0'),
                      style: t.mono(size: 12, color: t.accentText),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.bedtime_outlined, size: 20, color: t.ink2),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text('Temporizador de sueño', style: t.serif(19)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      );
    },
  );
}

/// Cabecera móvil: «Aurora» en cursiva, fecha (en Inicio) o título y perfil.
class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.scope});
  final ShellScope scope;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final home = scope.section == 0 && scope.playlist == null;
    final c = scope.controller;
    final title = home
        ? null
        : (scope.playlist == null
                  ? null
                  : c.playlists
                        .where((p) => p.id == scope.playlist!.id)
                        .firstOrNull
                        ?.name) ??
              shellSectionTitles[scope.section]!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
      child: Column(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              children: [
                if (home) ...[
                  Text('Aurora', style: t.serif(30, italic: true)),
                  Expanded(
                    child: Center(
                      child: Text(
                        atelierDateLabel(studioClock(), short: true),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.mono(size: 12),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.serif(28),
                    ),
                  ),
                if (!home && scope.section != 1)
                  IconButton(
                    tooltip: 'Buscar música',
                    onPressed: () => scope.onNavigate(1),
                    icon: const Icon(Icons.search),
                  ),
                Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'Perfil y ajustes',
                    style: IconButton.styleFrom(
                      backgroundColor: t.ink,
                      foregroundColor: t.paper,
                      fixedSize: const Size(44, 44),
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => scope.onProfile(ctx),
                    icon: scope.avatar == null
                        ? Text(
                            _initial(c.profileName),
                            style: t.serif(20, color: t.paper),
                          )
                        : ClipOval(
                            child: Image.memory(
                              scope.avatar!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              cacheWidth: 132,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.person, size: 20),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.only(top: 4),
            color: t.ink,
          ),
        ],
      ),
    );
  }

  static String _initial(String name) {
    final n = name.trim();
    return n.isEmpty
        ? 'A'
        : n.substring(0, math.min(1, n.length)).toUpperCase();
  }
}
