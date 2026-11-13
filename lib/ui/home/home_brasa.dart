/// Dueño: tema Brasa.
///
/// Posee la portada (HomeMusicPage: maquetación de la página, introducción editorial y las tarjetas de estante: grupo, pista y reciente). La página vive en `brasa_home_page.dart`.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../studio/home_introduction.dart';
import 'brasa_home_page.dart';
import 'brasa_home_widgets.dart';
import 'home_theme.dart';

/// Brasa: implementación de [HomeTheme].
const HomeTheme brasaHome = BrasaHomeTheme();

class BrasaHomeTheme extends HomeTheme {
  const BrasaHomeTheme();

  @override
  Widget buildPage(BuildContext context, HomePageData d) =>
      BrasaHomePage(data: d);

  @override
  Widget introduction(
    BuildContext context,
    StudioHomeIntroduction intro,
    Track? track,
  ) => BrasaGreeting(name: intro.controller.profileName);

  @override
  Widget groupTile(
    BuildContext context, {
    required Track cover,
    required String title,
    required String count,
    required bool artist,
    required String tooltip,
    required VoidCallback onPlay,
  }) => BrasaCoverCard(
    cover: cover,
    title: title,
    subtitle: count,
    aspect: 1,
    round: artist,
    tooltip: tooltip,
    onTap: onPlay,
  );

  @override
  Widget trackTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
    String? reason,
  }) => BrasaCoverCard(
    cover: track,
    title: track.title,
    subtitle: reason ?? track.artist,
    aspect: 1,
    playing: controller.currentTrack?.id == track.id,
    tooltip: track.isPendingSpotifyMatch
        ? 'Elegir audio para ${track.title}'
        : '$actionLabel ${track.title}',
    onTap: onPlay,
  );

  @override
  Widget recentTile(
    BuildContext context, {
    required AppController controller,
    required Track track,
    required String actionLabel,
    required VoidCallback onPlay,
  }) => BrasaCoverCard(
    cover: track,
    title: track.title,
    subtitle: track.artist,
    aspect: 1,
    playing: controller.currentTrack?.id == track.id,
    tooltip: '$actionLabel ${track.title}',
    onTap: onPlay,
  );
}
