/// Barras de escritorio del tema Modern.
///
/// Dueño: tema Modern. `StudioTitleBar`/`StudioSidebar` delegan aquí; el chrome
/// Modern usa directamente `ModernTopBar` y `ModernSidebar`.
library;

import 'package:flutter/material.dart';

import '../studio/studio_navigation.dart';
import 'modern_sidebar.dart';
import 'modern_top_bar.dart';

/// Barra superior Modern.
Widget modernTitleBar(
  StudioTitleBar bar,
  BuildContext context,
  BoxConstraints constraints,
  bool largeText,
) => ModernTopBar(
  onNavigate: bar.onNavigate,
  sessionText: bar.sessionText,
  activeSession: bar.activeSession,
  onSession: bar.onSession,
  searchController: bar.searchController,
  searchFocus: bar.searchFocus,
  onSearch: bar.onSearch,
  onSearchChanged: bar.onSearchChanged,
  avatar: bar.avatar,
  onProfile: bar.onProfile,
);

/// Sidebar Modern.
Widget modernSidebar(StudioSidebar side, BuildContext context) => ModernSidebar(
  controller: side.controller,
  selected: side.selected,
  onNavigate: side.onNavigate,
  onPlaylist: side.onPlaylist,
  onCreatePlaylist: side.onCreatePlaylist,
  shortcuts: side.shortcuts,
  friendsBadge: side.friendsBadge,
);
