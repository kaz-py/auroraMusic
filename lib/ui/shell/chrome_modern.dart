import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/window_controls.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/modern_widgets.dart';
import '../jam/jam_widgets.dart';
import '../studio/session_aside.dart';
import '../studio/studio_navigation.dart';
import 'shell_chrome.dart';
import 'shell_header.dart';
import 'shell_nav.dart';
import 'shell_rail.dart';
import 'shell_sections.dart';

/// Dueño: tema Modern. Chrome del shell: barra de título, sidebar, panel
/// lateral, cabecera, aviso de error, navegación móvil y ancho máximo del
/// contenido.
const modernChrome = ModernChrome();

class ModernChrome extends ShellChrome {
  const ModernChrome();

  @override
  Widget? topBar(BuildContext context, ShellScope scope) {
    if (!(scope.rail || WindowControls.supported)) return null;
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
      kind: AuroraThemeKind.modern,
      modern: true,
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
      (!scope.wide || ![0, 3].contains(scope.section))
      ? ShellHeaderBar(scope: scope, modern: true)
      : null;

  @override
  Widget errorBanner(BuildContext context, ShellScope scope) => ModernBanner(
    message: scope.controller.error!,
    onClose: scope.controller.clearError,
  );

  @override
  Widget bottomNavigation(BuildContext context, ShellScope scope) {
    final primary = primarySections(AuroraThemeKind.modern, mobile: true);
    return NavigationBar(
      height: 64,
      selectedIndex: math.max(0, primary.indexOf(scope.section)),
      onDestinationSelected: (index) => scope.onNavigate(primary[index]),
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      indicatorColor: null,
      elevation: 0,
      destinations: List.generate(
        primary.length,
        (i) => NavigationDestination(
          icon: Icon(shellSectionIcons[primary[i]]),
          selectedIcon: null,
          label: primary[i] == 3
              ? 'Descargas'
              : shellSectionTitles[primary[i]]!,
          tooltip: shellSectionTitles[primary[i]],
        ),
      ),
    );
  }

  @override
  Widget contentFrame(BuildContext context, ShellScope scope, Widget child) =>
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: const [4, 5, 9, 11].contains(scope.section)
                ? double.infinity
                : 1600,
          ),
          child: child,
        ),
      );
}
