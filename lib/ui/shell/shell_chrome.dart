import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/aurora_tokens.dart';
import '../mini_player/mini_player_host.dart';
import 'chrome_atelier.dart';
import 'chrome_brasa.dart';
import 'chrome_modern.dart';
import 'chrome_slush.dart';

/// Lo que el shell pone a disposición de los chrome de cada tema: estado de
/// navegación y callbacks. Se construye en cada `build` de `AuroraShell`.
class ShellScope {
  const ShellScope({
    required this.controller,
    required this.section,
    required this.rail,
    required this.wide,
    required this.desktop,
    required this.jam,
    required this.jamOn,
    required this.friendsBadge,
    required this.playlist,
    required this.likesSelected,
    required this.spotifySearch,
    required this.settingsTabLabel,
    required this.shortcuts,
    required this.searchController,
    required this.searchFocus,
    required this.onNavigate,
    required this.onProfile,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onStartJam,
    required this.onOpenJamPanel,
    required this.onCreatePlaylist,
    required this.onOpenLibrary,
    required this.miniPlayer,
  });

  final AppController controller;

  /// Sección activa (ids de `shell_sections.dart`).
  final int section;

  /// Ancho ≥ 600 (carril/barra de escritorio), ≥ 900 (sidebar ancha) y ≥ 1200
  /// (con panel lateral derecho).
  final bool rail, wide, desktop;

  /// Jam del shell y si hay sesión conectada o reconectando.
  final JamController? jam;
  final bool jamOn;
  final int friendsBadge;

  /// Biblioteca: lista abierta y «Me gusta» seleccionado.
  final MusicPlaylist? playlist;
  final bool likesSelected;

  /// Buscar: la pestaña de Spotify está activa.
  final bool spotifySearch;

  /// Título de la pestaña activa de Ajustes.
  final String settingsTabLabel;

  final ShortcutService shortcuts;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<int> onNavigate;

  /// Menú de perfil anclado al botón que recibe.
  final void Function(BuildContext anchor) onProfile;

  /// Búsqueda lanzada desde la barra superior / al cambiar el texto.
  final ValueChanged<String> onSearch, onSearchChanged;
  final VoidCallback onStartJam, onOpenJamPanel, onCreatePlaylist;
  final ValueChanged<MusicPlaylist> onOpenLibrary;

  /// Mini reproductor del shell para la ubicación pedida.
  final Widget Function(MiniPlayerPlacement placement) miniPlayer;

  Uint8List? get avatar => controller.profileAvatar;
}

/// Piezas de chrome que `AuroraShell.build()` ensambla. Un archivo
/// `chrome_<tema>.dart` por tema; el shell solo elige con [shellChromeFor].
///
/// La sección 6 (modo letras) queda FUERA de todo chrome: el shell la
/// resuelve antes de llamar a nada de aquí.
abstract class ShellChrome {
  const ShellChrome();

  /// Barra superior de escritorio (`null`: ninguna).
  Widget? topBar(BuildContext context, ShellScope scope);

  /// Barra lateral (`null`: ninguna). El shell solo la pide con carril.
  Widget? sidebar(BuildContext context, ShellScope scope);

  /// Panel lateral derecho (`null`: ninguno); solo existe en escritorio
  /// (`scope.desktop`).
  Widget? aside(BuildContext context, ShellScope scope);

  /// Cabecera de la página (`null`: ninguna).
  Widget? header(BuildContext context, ShellScope scope);

  /// Aviso de error del controlador.
  Widget errorBanner(BuildContext context, ShellScope scope);

  /// Navegación inferior móvil (solo se pide sin carril).
  Widget bottomNavigation(BuildContext context, ShellScope scope);

  /// Fondo a ventana completa detrás de barra, sidebar, contenido y barra de
  /// reproducción (Modern: aura de portada). Por defecto no añade nada.
  Widget backdrop(BuildContext context, ShellScope scope, Widget child) =>
      child;

  /// Envuelve el contenido completo del cuerpo (tras cabecera y avisos).
  Widget contentFrame(BuildContext context, ShellScope scope, Widget child) =>
      child;

  /// Envuelve la página de la sección actual (transición entre secciones).
  Widget pageTransition(BuildContext context, ShellScope scope, Widget child) =>
      child;

  /// El tema pinta el marco de esta sección (titular, píldoras, tarjeta): el
  /// shell no añade su cabecera; ver [pageFrame].
  bool ownsPageFrame(ShellScope scope) => false;

  /// [child] dentro del marco del tema si la sección actual lo pide.
  Widget framed(BuildContext context, ShellScope scope, Widget child) =>
      ownsPageFrame(scope) ? pageFrame(context, scope, child) : child;

  /// Marco de página de las secciones que lo piden ([ownsPageFrame]).
  Widget pageFrame(BuildContext context, ShellScope scope, Widget child) =>
      child;

  /// Página propia del tema para [section] (cola 5, ecualizador 13); `null`:
  /// la genérica.
  Widget? sectionOverride(
    BuildContext context,
    ShellScope scope,
    int section,
  ) => null;
}

/// Registro por tema, como `miniPlayerThemes`.
const Map<AuroraThemeKind, ShellChrome> shellChromes = {
  AuroraThemeKind.atelier: atelierChrome,
  AuroraThemeKind.modern: modernChrome,
  AuroraThemeKind.brasa: brasaChrome,
  AuroraThemeKind.slush: slushChrome,
};

ShellChrome shellChromeFor(AuroraThemeKind kind) => shellChromes[kind]!;
