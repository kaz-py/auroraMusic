import 'package:flutter/material.dart';

import '../../theme/aurora_tokens.dart';

// Los ids de sección son estables: no se renumeran al quitar una.
const shellSectionTitles = <int, String>{
  0: 'Inicio',
  1: 'Buscar',
  2: 'Biblioteca',
  3: 'Descargas locales',
  4: 'Modo Vinilo',
  5: 'Cola de reproducción',
  6: 'Letras',
  7: 'Ajustes',
  8: 'DJ',
  9: 'Jam',
  11: 'Descargar vídeos',
  12: 'Artistas',
  13: 'Ecualizador',
  14: 'Amigos',
};
const shellSectionIcons = <int, IconData>{
  0: Icons.home_outlined,
  1: Icons.search,
  2: Icons.library_music_outlined,
  3: Icons.download_outlined,
  4: Icons.album_outlined,
  5: Icons.queue_music,
  6: Icons.lyrics_outlined,
  7: Icons.tune,
  8: Icons.explore_outlined,
  9: Icons.groups_outlined,
  11: Icons.video_file_outlined,
  12: Icons.mic_none_rounded,
  13: Icons.equalizer,
  14: Icons.people_outline,
};
const _primarySections = [0, 1, 8, 2, 3];

/// Slush móvil: Inicio, Buscar, Biblioteca, DJ y «Más» (hoja con el resto,
/// ver `slush_nav.dart`).
const _slushMobilePrimarySections = [0, 1, 2, 8];

/// Atelier móvil: cuatro pestañas y «Más» (hoja con el resto, ver
/// `chrome_atelier.dart`).
const _atelierMobilePrimarySections = [0, 1, 2, 3];

/// Brasa móvil: Inicio, Buscar, DJ, Biblioteca y «Más» (hoja con el resto, ver
/// `chrome_brasa.dart`).
const _brasaMobilePrimarySections = [0, 1, 8, 2];

/// Modern móvil: Inicio, Buscar, Biblioteca, Descargas y «Más» (hoja con el
/// resto, ver `modern_mobile_nav.dart`).
const _modernMobilePrimarySections = [0, 1, 2, 3];

/// Secciones de la navegación principal. Móvil (sin carril): la barra
/// inferior; Slush y Atelier llevan las suyas.
List<int> primarySections(AuroraThemeKind kind, {required bool mobile}) =>
    !mobile
    ? _primarySections
    : switch (kind) {
        AuroraThemeKind.slush => _slushMobilePrimarySections,
        AuroraThemeKind.atelier => _atelierMobilePrimarySections,
        AuroraThemeKind.brasa => _brasaMobilePrimarySections,
        AuroraThemeKind.modern => _modernMobilePrimarySections,
      };
