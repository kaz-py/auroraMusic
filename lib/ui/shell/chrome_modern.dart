import 'package:flutter/material.dart';

import '../../core/window_controls.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/modern_cristal.dart';
import '../jam/jam_widgets.dart';
import '../right_panel/modern_aside_panel.dart';
import '../studio/session_aside.dart';
import 'modern_header.dart';
import 'modern_mobile_nav.dart';
import 'modern_sidebar.dart';
import 'modern_top_bar.dart';
import 'shell_chrome.dart';
import 'shell_nav.dart';

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
      child: ModernTopBar(
        onNavigate: scope.onNavigate,
        onProfile: scope.onProfile,
        avatar: scope.avatar,
        // La página Buscar lleva su propio campo (comparte el foco).
        searchController: scope.rail && scope.section != 1
            ? scope.searchController
            : null,
        searchFocus: scope.searchFocus,
        onSearch: scope.onSearch,
        onSearchChanged: scope.onSearchChanged,
        searchHint: modernShortcutText(scope.shortcuts, ShortcutId.searchFocus),
        sessionText: scope.jamOn
            ? 'JAM · ${scope.jam!.peopleCount} ${scope.jam!.peopleCount == 1 ? 'PERSONA' : 'PERSONAS'} · ${scope.jam!.roleLabel.toUpperCase()}'
            : 'INICIAR UNA JAM',
        activeSession: scope.jamOn,
        onSession: scope.jamOn ? scope.onOpenJamPanel : scope.onStartJam,
      ),
    );
  }

  @override
  Widget backdrop(BuildContext context, ShellScope scope, Widget child) =>
      ListenableBuilder(
        listenable: scope.controller,
        builder: (context, _) =>
            ModernAura(track: scope.controller.nowTrack, child: child),
      );

  @override
  Widget? sidebar(BuildContext context, ShellScope scope) {
    if (!scope.rail) return null;
    return ModernSidebar(
      controller: scope.controller,
      selected: scope.section,
      onNavigate: scope.onNavigate,
      onPlaylist: scope.onOpenLibrary,
      onCreatePlaylist: scope.onCreatePlaylist,
      shortcuts: scope.shortcuts,
      friendsBadge: scope.friendsBadge,
      // Carril de iconos en anchos medios y en el reproductor (4).
      collapsed: !scope.wide || scope.section == 4,
    );
  }

  @override
  Widget? aside(BuildContext context, ShellScope scope) {
    if (!scope.desktop) return null;
    // Reproduciendo: panel Cola / Ahora suena / Letras del prototipo.
    if (scope.section == 4) return ModernAside(scope: scope);
    // Inicio no lleva panel (el prototipo lo deja libre; la Jam se abre desde
    // la barra superior).
    if (scope.section == 0 ||
        scope.controller.jamPlaybackActive ||
        const [3, 5, 6, 7, 13, 11].contains(scope.section)) {
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
  Widget? header(BuildContext context, ShellScope scope) {
    // El reproductor (4) dibuja su propia cabecera.
    if (scope.section == 4) return null;
    if (!scope.rail) {
      return scope.section == 0 && scope.playlist == null
          ? ModernGreetingHeader(scope: scope)
          : ModernPageHeader(scope: scope);
    }
    return scope.wide && const [0, 3].contains(scope.section)
        ? null
        : ModernPageHeader(scope: scope);
  }

  @override
  Widget errorBanner(BuildContext context, ShellScope scope) =>
      ModernGlassBanner(
        message: scope.controller.error!,
        onClose: scope.controller.clearError,
      );

  @override
  Widget bottomNavigation(BuildContext context, ShellScope scope) =>
      // El reproductor móvil (4) ocupa toda la pantalla, sin barra inferior.
      scope.section == 4
      ? const SizedBox.shrink()
      : ModernBottomNav(scope: scope);

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
