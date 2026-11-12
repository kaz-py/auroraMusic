import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/window_controls.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/brasa_theme.dart';
import '../jam/jam_widgets.dart';
import '../studio/session_aside.dart';
import '../studio/studio_navigation.dart';
import 'shell_chrome.dart';
import 'shell_header.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';
import 'shell_sections.dart';

/// Dueño: tema Brasa. Chrome del shell: barra de título con búsqueda,
/// sidebar, panel lateral, aviso de error y navegación móvil.
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
    if (!scope.desktop ||
        scope.controller.jamPlaybackActive ||
        const [3, 4, 5, 6, 7, 13, 11].contains(scope.section)) {
      return null;
    }
    return StudioSessionAside(
      controller: scope.controller,
      jam: scope.jam,
      onStartJam: scope.onStartJam,
      onJam: () => scope.onNavigate(9),
      onQueue: () => scope.onNavigate(scope.jamOn ? 9 : 5),
    );
  }

  @override
  Widget? header(BuildContext context, ShellScope scope) =>
      !scope.rail && (!scope.wide || ![0, 3].contains(scope.section))
      ? ShellHeaderBar(scope: scope, modern: false)
      : null;

  @override
  Widget errorBanner(BuildContext context, ShellScope scope) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
    child: Material(
      color: Brasa.graphite,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
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
                style: const TextStyle(fontSize: 14, color: Brasa.cream),
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
    return NavigationBar(
      height: 64,
      selectedIndex: math.max(0, primary.indexOf(scope.section)),
      onDestinationSelected: (index) => scope.onNavigate(primary[index]),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      backgroundColor: Brasa.void_,
      indicatorColor: Brasa.cream,
      elevation: 0,
      destinations: List.generate(
        primary.length,
        (i) => NavigationDestination(
          icon: Icon(shellSectionIcons[primary[i]]),
          selectedIcon: SizedBox(
            width: 64,
            height: 32,
            child: DecoratedBox(
              decoration: const ShapeDecoration(
                color: Brasa.cream,
                shape: StadiumBorder(),
              ),
              child: Icon(shellSectionIcons[primary[i]], color: Brasa.void_),
            ),
          ),
          label: primary[i] == 3
              ? 'Descargas'
              : shellSectionTitles[primary[i]]!,
          tooltip: shellSectionTitles[primary[i]],
        ),
      ),
    );
  }
}
