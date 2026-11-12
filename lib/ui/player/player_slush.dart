/// Dueño: tema Slush.
///
/// Posee el Modo Vinilo / reproductor completo (sección 4): maquetación y pintura del disco. La pantalla vive en `ui/slush/slush_player.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../theme/accent_transition.dart';
import '../../theme/slush_theme.dart';
import '../slush/slush_player.dart';
import 'player_theme.dart';

/// Slush: implementación de [PlayerTheme].
const PlayerTheme slushPlayer = SlushPlayerTheme();

class SlushPlayerTheme extends PlayerTheme {
  const SlushPlayerTheme();

  @override
  double get compactBreakpoint => Breakpoints.medium;

  @override
  bool get rebuildsOnAudio => false;

  @override
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) {
    final c = scope.controller;
    return SlushPlayerScreen(
      jam: scope.jam,
      controller: c,
      track: track,
      compact: compact,
      cassette: scope.cassette,
      onToggleCassette: () => scope.setCassette(!scope.cassette),
      onSection: scope.onSection,
      onBack: scope.onBack,
      recordBuilder: (size) {
        final p = context.slush;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return scope.record(
          context,
          c,
          track,
          math.max(0.0, size),
          PlayerDiscStyle(
            // Oscuro: el disco es el pozo `inset`; claro: vinilo negro.
            disc: dark ? p.inset : const Color(0xff111111),
            label: slushScreenColor(AccentScope.of(context, c.accentColor)),
            ring: p.line,
            ringWidth: SlushStroke.base,
            shadow: const [],
            groove: SlushPalette.dark.ink,
            grooveHi: .07,
            grooveLo: .03,
            pivot: p.line,
            arm: p.line,
            needle: p.line,
            slush: true,
          ),
        );
      },
    );
  }
}
