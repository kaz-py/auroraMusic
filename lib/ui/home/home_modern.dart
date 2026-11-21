/// Dueño: tema Modern «Cristal y aura».
///
/// Posee la portada (HomeMusicPage: maquetación en `modern_home_page.dart`,
/// tarjetas de estante en `modern_home_widgets.dart`).
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../studio/home_introduction.dart';
import '../studio/studio_symbols.dart';
import 'home_theme.dart';
import 'modern_home_page.dart';
import 'modern_home_widgets.dart';

/// Modern: implementación de [HomeTheme].
const HomeTheme modernHome = ModernHomeTheme();

class ModernHomeTheme extends HomeTheme {
  const ModernHomeTheme();

  @override
  Widget buildPage(BuildContext context, HomePageData d) =>
      ModernHomePage(data: d);

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) => Align(
    alignment: Alignment.centerLeft,
    child: ModernHomePill(
      accent: true,
      icon: StudioSymbols.search,
      label: 'Encontrar música',
      onTap: intro.onSearch,
    ),
  );

  @override
  Widget groupTile(
    BuildContext context, {
    required Track cover,
    required String title,
    required String count,
    required bool artist,
    required String tooltip,
    required VoidCallback onPlay,
  }) => ModernHomeTile(
    track: cover,
    title: title,
    subtitle: count,
    round: artist,
    tooltip: tooltip,
    onPlay: onPlay,
  );

  @override
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  }) => ModernHomeTile(
    track: track,
    title: track.title,
    subtitle: track.artist,
    caption: reason,
    tooltip: track.isPendingSpotifyMatch
        ? 'Elegir audio para ${track.title}'
        : '$actionLabel ${track.title}',
    onPlay: onPlay,
  );

  @override
  Widget recentTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
  }) => ModernHomeTile(
    track: track,
    title: track.title,
    subtitle: track.artist,
    tooltip: '$actionLabel ${track.title}',
    onPlay: onPlay,
  );
}
