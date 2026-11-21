/// Dueño: tema Modern.
///
/// Posee el reproductor completo (sección 4). Escritorio: portada y datos a la
/// izquierda, letras grandes en el centro (la cola y la Jam viven en el aside
/// del shell). Compacto: ver `modern_player_mobile.dart`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/modern_cristal.dart';
import '../follow_widgets.dart';
import '../studio/equalizer_panel.dart';
import '../studio/studio_transport.dart' show transportJamAudio;
import 'modern_player_mobile.dart';
import 'modern_player_parts.dart';
import 'player_theme.dart';

/// Modern: implementación de [PlayerTheme].
const PlayerTheme modernPlayer = ModernPlayerTheme();

class ModernPlayerTheme extends PlayerTheme {
  const ModernPlayerTheme();

  @override
  double get compactBreakpoint => 760;

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
    if (compact) {
      return buildModernMobilePlayer(context, scope, track, constraints);
    }
    final c = scope.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([
        c,
        c.eq,
        if (scope.jam != null) scope.jam!,
      ]),
      builder: (context, _) {
        final shown = transportJamAudio(c, scope.jam)
            ? (c.nowTrack ?? track)
            : track;
        return _DesktopPlayer(
          scope: scope,
          track: shown,
          constraints: constraints,
        );
      },
    );
  }
}

class _DesktopPlayer extends StatelessWidget {
  const _DesktopPlayer({
    required this.scope,
    required this.track,
    required this.constraints,
  });

  final PlayerScope scope;
  final Track? track;
  final BoxConstraints constraints;

  AppController get c => scope.controller;

  @override
  Widget build(BuildContext context) {
    final p = Cristal.of(context);
    final t = track;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 720.0;
    final side = math.max(
      200.0,
      math.min(360.0, math.min(constraints.maxWidth * .36, height - 260)),
    );
    final photo = scope.modernPhoto && t != null;
    final Widget cover = photo
        ? scope.seekable(c, side, ModernCover(track: t, size: side))
        : scope.record(context, c, t, side, modernDiscStyle(p));
    final left = SizedBox(
      width: side,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          cover,
          const SizedBox(height: 28),
          _title(context, p),
          const SizedBox(height: 4),
          _artistLine(context, p),
          const SizedBox(height: 14),
          _chips(context),
          const SizedBox(height: 16),
          _viewPicker(p),
        ],
      ),
    );
    final lyrics = Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 40),
        child: ModernLyricsPreview(
          controller: c,
          onOpen: scope.onSection == null ? null : () => scope.onSection!(6),
        ),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: SizedBox(
        height: math.max(height - 48, 520),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(child: left),
            lyrics,
          ],
        ),
      ),
    );
  }

  Widget _title(BuildContext context, Cristal p) => Text(
    track?.title ?? 'Nada sonando',
    maxLines: 3,
    overflow: TextOverflow.ellipsis,
    style: Cristal.ui(
      34,
      weight: 800,
      color: p.text,
      tracking: -.03,
      height: 1.1,
    ),
  );

  Widget _artistLine(BuildContext context, Cristal p) {
    final t = track;
    final name = primaryArtist(t?.artist ?? '');
    final fav = t != null && c.favoriteIds.contains(t.id);
    final album = t?.album?.trim();
    final detail = [
      t?.artist ?? 'Elige una canción de tu biblioteca',
      if (album != null && album.isNotEmpty) album,
    ].join(' · ');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        MouseRegion(
          cursor: t == null ? MouseCursor.defer : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: t == null ? null : () => c.openArtist(t.artist),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Cristal.ui(16, weight: 500, color: p.text2),
                ),
              ),
            ),
          ),
        ),
        if (scope.follow != null && t != null && name.isNotEmpty)
          FollowButton(service: scope.follow!, name: name),
        if (t != null)
          IconButton(
            tooltip: fav ? 'Quitar de favoritos' : 'Añadir a favoritos',
            color: fav ? p.like : p.text2,
            onPressed: () => c.toggleFavorite(t),
            icon: Icon(
              fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            ),
          ),
      ],
    );
  }

  Widget _chips(BuildContext context) {
    final t = track;
    if (t == null) return const SizedBox.shrink();
    final sleep = modernSleepLabel(c);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ModernSignalChip(label: modernFormatLabel(t)),
        if (c.eq.active)
          ModernGlassChip(
            icon: Icons.equalizer_rounded,
            label: 'EQ · ${c.eq.presetName ?? 'Personalizado'}',
            tooltip: 'Abrir el ecualizador',
            onTap: () => showEqualizerSheet(context, c),
          ),
        if (sleep != null)
          ModernGlassChip(
            icon: Icons.bedtime_outlined,
            label: sleep,
            tooltip: 'Cambiar el temporizador de sueño',
            onTap: () => showModernSleepSheet(context, c),
          ),
      ],
    );
  }

  /// Portada / vinilo / casete: ninguna vista desaparece.
  Widget _viewPicker(Cristal p) => SegmentedButton<int>(
    key: const ValueKey('modern-view-picker'),
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      foregroundColor: p.text2,
      selectedForegroundColor: p.accent,
      selectedBackgroundColor: p.accentSoft,
      side: BorderSide(color: p.border),
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(44, 40),
    ),
    segments: const [
      ButtonSegment(
        value: 0,
        icon: Icon(Icons.image_outlined),
        tooltip: 'Ver portada',
      ),
      ButtonSegment(
        value: 1,
        icon: Icon(Icons.album_outlined),
        tooltip: 'Ver vinilo',
      ),
      ButtonSegment(
        value: 2,
        icon: Icon(Icons.sd_card_outlined),
        tooltip: 'Ver casete',
      ),
    ],
    selected: {if (scope.modernPhoto) 0 else if (scope.cassette) 2 else 1},
    onSelectionChanged: (s) => scope.setModernView(s.first),
  );
}
