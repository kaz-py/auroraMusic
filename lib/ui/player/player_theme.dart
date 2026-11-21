import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../follow/follow_service.dart';
import '../../jam/jam_controller.dart';
import '../../theme/aurora_tokens.dart';
import 'player_atelier.dart';
import 'player_brasa.dart';
import 'player_modern.dart';
import 'player_slush.dart';

/// Colores y radios del disco: los cuatro temas comparten la misma lógica de
/// giro y seek (en vinyl_player.dart) y solo cambian la pintura.
class PlayerDiscStyle {
  const PlayerDiscStyle({
    required this.disc,
    required this.label,
    required this.ring,
    required this.ringWidth,
    required this.shadow,
    required this.groove,
    required this.grooveHi,
    required this.grooveLo,
    required this.pivot,
    required this.arm,
    required this.needle,
    this.slush = false,
  });
  final bool slush;
  final Color disc, label, ring, groove, pivot, arm, needle;
  final double ringWidth, grooveHi, grooveLo;
  final List<BoxShadow> shadow;
}

/// Disco giratorio compartido (vinyl_player.dart): [artSize] es el lado.
typedef PlayerRecordBuilder =
    Widget Function(
      BuildContext context,
      AppController controller,
      Track? track,
      double artSize,
      PlayerDiscStyle style,
    );

/// Estado y piezas compartidas que VinylPlayer reparte al tema vigente.
///
/// VinylPlayer conserva el estado (giro, seek, casete, vista de Modern) y la
/// lógica; el tema solo decide la maquetación y la pintura del disco.
class PlayerScope {
  const PlayerScope({
    required this.controller,
    required this.cassette,
    required this.modernPhoto,
    required this.setCassette,
    required this.setModernView,
    required this.record,
    required this.seekable,
    required this.liveDuration,
    this.follow,
    this.jam,
    this.onSection,
    this.onBack,
  });
  final AppController controller;
  final FollowService? follow;
  final JamController? jam;
  final ValueChanged<int>? onSection;
  final VoidCallback? onBack;

  /// Modo casete activo.
  final bool cassette;

  /// Modern: mostrar solo la portada (en lugar de vinilo o casete).
  final bool modernPhoto;
  final ValueChanged<bool> setCassette;

  /// 0 portada, 1 vinilo, 2 casete.
  final ValueChanged<int> setModernView;

  /// Disco con etiqueta de portada, seek por toque/arrastre y brazo.
  final PlayerRecordBuilder record;

  /// Toque y arrastre horizontal sobre [child] para buscar en la pista.
  final Widget Function(AppController c, double artSize, Widget child) seekable;

  /// Duración del audio, o la de la pista si aún no se conoce.
  final Duration Function() liveDuration;
}

/// Un tema del reproductor completo (sección 4). Cada tema vive en su
/// `player_<tema>.dart` y es el único dueño de su maquetación.
abstract class PlayerTheme {
  const PlayerTheme();

  /// Ancho por debajo del cual se usa la maquetación compacta.
  double get compactBreakpoint;

  /// Si el reproductor se reconstruye con cada tick del audio (si no, el
  /// tema escucha `controller.audio` solo donde lo necesita).
  bool get rebuildsOnAudio;

  /// Maquetación completa; [compact] ya viene resuelto con [compactBreakpoint].
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  );
}

/// Registro de temas del reproductor.
const Map<AuroraThemeKind, PlayerTheme> playerThemes = {
  AuroraThemeKind.atelier: atelierPlayer,
  AuroraThemeKind.modern: modernPlayer,
  AuroraThemeKind.brasa: brasaPlayer,
  AuroraThemeKind.slush: slushPlayer,
};

PlayerTheme playerThemeFor(AuroraThemeKind kind) => playerThemes[kind]!;

/// Tema de reproductor vigente en [context].
PlayerTheme playerThemeOf(BuildContext context) =>
    playerThemeFor(themeKindOf(context));

/// Primer artista de «A, B feat. C» (YouTube Music los lista juntos).
String primaryArtist(String artist) =>
    artist.split(RegExp(r'\s*(?:,|&|;|\sfeat\.?\s|\sft\.?\s)\s*')).first.trim();

String playerTime(Duration value) {
  final seconds = value.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
