import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../core/window_controls.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/brasa_theme.dart';
import '../jam/jam_widgets.dart';
import '../right_panel/brasa_aside.dart';
import '../studio/studio_navigation.dart';
import 'shell_chrome.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';
import 'shell_sections.dart';

/// Dueño: tema Brasa. Chrome del shell: barra de título con búsqueda,
/// sidebar de 300 px por tono, panel lateral, aviso de error y navegación
/// móvil (Inicio · Buscar · DJ · Biblioteca · Más).
const brasaChrome = BrasaChrome();

class BrasaChrome extends ShellChrome {
  const BrasaChrome();

  @override
  Widget? topBar(BuildContext context, ShellScope scope) {
    if (!(scope.rail || WindowControls.supported)) return null;
    return MouseOnlyRegion(
      child: StudioTitleBar(
        onNavigate: scope.onNavigate,
        onProfile: scope.onProfile,
        avatar: scope.avatar,
        searchController: scope.rail ? scope.searchController : null,
        searchFocus: scope.searchFocus,
        onSearch: scope.onSearch,
        onSearchChanged: scope.onSearchChanged,
        sessionText: scope.jamOn
            ? 'Jam · ${scope.jam!.peopleCount} ${scope.jam!.peopleCount == 1 ? 'persona' : 'personas'}'
            : 'Iniciar una Jam',
        activeSession: scope.jamOn,
        onSession: scope.jamOn ? scope.onOpenJamPanel : scope.onStartJam,
      ),
    );
  }

  @override
  Widget? sidebar(BuildContext context, ShellScope scope) {
    if (!scope.rail) return null;
    if (scope.wide) {
      return StudioSidebar(
        controller: scope.controller,
        selected: scope.section,
        onNavigate: scope.onNavigate,
        onPlaylist: scope.onOpenLibrary,
        onCreatePlaylist: scope.onCreatePlaylist,
        shortcuts: scope.shortcuts,
        friendsBadge: scope.friendsBadge,
      );
    }
    return ShellNarrowRail(
      scope: scope,
      kind: AuroraThemeKind.brasa,
      modern: false,
    );
  }

  @override
  Widget? aside(BuildContext context, ShellScope scope) {
    // Como en el prototipo: el panel de cola solo acompaña al reproductor.
    if (!scope.desktop ||
        scope.controller.jamPlaybackActive ||
        scope.section != 4) {
      return null;
    }
    return BrasaAside(
      controller: scope.controller,
      jam: scope.jam,
      onStartJam: scope.onStartJam,
      onJam: () => scope.onNavigate(9),
      onQueue: () => scope.onNavigate(scope.jamOn ? 9 : 5),
    );
  }

  /// Móvil: titular serif + buscar. Inicio (portada propia) y el reproductor
  /// (cabecera propia) no llevan cabecera del shell.
  @override
  Widget? header(BuildContext context, ShellScope scope) =>
      scope.rail || scope.section == 0 || scope.section == 4
      ? null
      : _BrasaMobileHeader(scope: scope);

  @override
  Widget errorBanner(BuildContext context, ShellScope scope) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: Material(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(
              Icons.error_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                scope.controller.error!,
                style: Brasa.sans(14, color: Brasa.cream),
              ),
            ),
            IconButton(
              tooltip: 'Cerrar aviso',
              onPressed: scope.controller.clearError,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget bottomNavigation(BuildContext context, ShellScope scope) {
    final primary = primarySections(AuroraThemeKind.brasa, mobile: true);
    final moreIndex = primary.length;
    final selected = primary.contains(scope.section)
        ? primary.indexOf(scope.section)
        : moreIndex;
    Widget icon(IconData data, bool on) =>
        Icon(data, color: on ? Brasa.ember : Brasa.cloud);
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        backgroundColor: Brasa.void_,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Brasa.ember.withValues(alpha: .2),
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => Brasa.sans(
            11,
            weight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? Brasa.cream : Brasa.cloud,
            height: 1.2,
          ),
        ),
      ),
      child: NavigationBar(
        height: 72,
        selectedIndex: math.min(selected, moreIndex),
        onDestinationSelected: (index) => index == moreIndex
            ? showBrasaMoreSheet(context, scope)
            : scope.onNavigate(primary[index]),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (var i = 0; i < primary.length; i++)
            NavigationDestination(
              icon: icon(shellSectionIcons[primary[i]]!, false),
              selectedIcon: icon(shellSectionIcons[primary[i]]!, true),
              label: primary[i] == 1
                  ? 'Buscar'
                  : shellSectionTitles[primary[i]]!,
              tooltip: shellSectionTitles[primary[i]],
            ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: scope.friendsBadge > 0,
              label: Text('${scope.friendsBadge}'),
              child: icon(Icons.more_horiz, false),
            ),
            selectedIcon: icon(Icons.more_horiz, true),
            label: 'Más',
            tooltip: 'Más vistas',
          ),
        ],
      ),
    );
  }
}

class _BrasaMobileHeader extends StatelessWidget {
  const _BrasaMobileHeader({required this.scope});
  final ShellScope scope;

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    final name = scope.playlist == null
        ? null
        : c.playlists
              .where((p) => p.id == scope.playlist!.id)
              .firstOrNull
              ?.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name ?? shellSectionTitles[scope.section]!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brasa.serif(26, height: 1.15),
            ),
          ),
          if (scope.section != 1)
            IconButton(
              tooltip: 'Buscar música',
              onPressed: () => scope.onNavigate(1),
              icon: const Icon(Icons.search),
            ),
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => scope.onNavigate(7),
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
    );
  }
}

/// Hoja «Más» de la navegación móvil: perfil, importar y el resto de vistas.
Future<void> showBrasaMoreSheet(BuildContext context, ShellScope scope) {
  final items = <(int, String, IconData)>[
    (3, 'Descargas', shellSectionIcons[3]!),
    (12, 'Artistas', shellSectionIcons[12]!),
    (11, 'Descargar vídeos', shellSectionIcons[11]!),
    (9, 'Jam', shellSectionIcons[9]!),
    if (supabaseServicesEnabled)
      (
        14,
        scope.friendsBadge > 0 ? 'Amigos (${scope.friendsBadge})' : 'Amigos',
        shellSectionIcons[14]!,
      ),
    (4, 'Modo Vinilo', shellSectionIcons[4]!),
    (5, 'Cola de reproducción', shellSectionIcons[5]!),
    (6, 'Letras', shellSectionIcons[6]!),
    (13, 'Ecualizador', shellSectionIcons[13]!),
    (7, 'Ajustes', shellSectionIcons[7]!),
  ];
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Brasa.graphite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text('Más', style: Brasa.serif(24)),
            ),
            if (scope.controller.ready)
              _MoreTile(
                icon: Icons.create_new_folder_outlined,
                label: 'Importar archivos',
                onTap: () {
                  Navigator.pop(sheet);
                  scope.controller.importFiles();
                },
              ),
            _MoreTile(
              icon: Icons.account_circle_outlined,
              label: 'Perfil',
              onTap: () {
                Navigator.pop(sheet);
                scope.onProfile(context);
              },
            ),
            for (final (id, label, icon) in items)
              _MoreTile(
                icon: icon,
                label: label,
                selected: scope.section == id,
                onTap: () {
                  Navigator.pop(sheet);
                  scope.onNavigate(id);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Material(
      color: selected ? Brasa.ash : Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: selected ? Brasa.ember : Brasa.ash,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SizedBox.square(
                    dimension: 40,
                    child: Icon(
                      icon,
                      size: 22,
                      color: selected ? Brasa.onEmber : Brasa.cloud,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: Brasa.sans(
                      16,
                      weight: FontWeight.w500,
                      color: selected ? Brasa.ember : Brasa.cream,
                    ),
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
