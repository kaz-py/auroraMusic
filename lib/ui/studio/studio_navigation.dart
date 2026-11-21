import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../shortcuts/shortcut_service.dart';
import '../../theme/aurora_tokens.dart';
import '../shell/bars_atelier.dart';
import '../shell/bars_brasa.dart';
import '../shell/bars_modern.dart';
import '../shell/bars_slush.dart';
import 'studio_symbols.dart';

class StudioTitleBar extends StatelessWidget {
  const StudioTitleBar({
    super.key,
    required this.onNavigate,
    required this.sessionText,
    this.activeSession = false,
    this.onSession,
    this.searchController,
    this.searchFocus,
    this.onSearch,
    this.onSearchChanged,
    this.avatar,
    this.onProfile,
  });

  /// Foto de perfil del usuario (miniatura); null = icono de persona.
  final Uint8List? avatar;

  /// Brasa: búsqueda píldora centrada en la barra superior (opcional).
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearch, onSearchChanged;
  final ValueChanged<int> onNavigate;
  final String sessionText;
  final bool activeSession;

  /// Toque en el chip de sesión; por omisión abre la página Jam.
  final VoidCallback? onSession;

  /// Toque en la foto de perfil: recibe el contexto del botón para anclar el
  /// menú; por omisión abre Ajustes.
  final void Function(BuildContext anchor)? onProfile;

  void profile(BuildContext anchor) =>
      onProfile == null ? onNavigate(7) : onProfile!(anchor);
  Widget profileGlyph(double size, double iconSize) => avatar == null
      ? Icon(StudioSymbols.person, size: iconSize)
      : ClipOval(
          child: Image.memory(
            avatar!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) =>
                Icon(StudioSymbols.person, size: iconSize),
          ),
        );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
      return switch (themeKindOf(context)) {
        AuroraThemeKind.atelier => atelierTitleBar(
          this,
          context,
          constraints,
          largeText,
        ),
        AuroraThemeKind.modern => modernTitleBar(
          this,
          context,
          constraints,
          largeText,
        ),
        AuroraThemeKind.brasa => brasaTitleBar(
          this,
          context,
          constraints,
          largeText,
        ),
        AuroraThemeKind.slush => slushTitleBar(
          this,
          context,
          constraints,
          largeText,
        ),
      };
    },
  );
}

class StudioSidebar extends StatelessWidget {
  const StudioSidebar({
    super.key,
    required this.controller,
    required this.selected,
    required this.onNavigate,
    required this.onPlaylist,
    this.onCreatePlaylist,
    this.shortcuts,
    this.friendsBadge = 0,
  });
  final int friendsBadge;
  final VoidCallback? onCreatePlaylist;
  final ShortcutService? shortcuts;
  final AppController controller;
  final int selected;
  final ValueChanged<int> onNavigate;
  final ValueChanged<MusicPlaylist> onPlaylist;
  @override
  Widget build(BuildContext context) => switch (themeKindOf(context)) {
    AuroraThemeKind.atelier => atelierSidebar(this, context),
    AuroraThemeKind.modern => modernSidebar(this, context),
    AuroraThemeKind.brasa => brasaSidebar(this, context),
    AuroraThemeKind.slush => slushSidebar(this, context),
  };
}
