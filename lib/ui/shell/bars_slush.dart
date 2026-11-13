/// Barras de escritorio del tema Slush.
///
/// Dueño: tema Slush. Barra superior y sidebar del escritorio; editar aquí no
/// afecta a los otros temas.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/feature_flags.dart';
import '../../core/models.dart';
import '../../core/window_controls.dart';
import '../../shortcuts/shortcut_service.dart';
import '../playlist_views/playlist_cover.dart';
import '../playlist_views/playlist_photo_menu.dart';
import '../playlist_views/playlist_view_mode.dart';
import '../studio/studio_components.dart';
import '../studio/studio_navigation.dart';
import '../studio/studio_symbols.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';

/// Barra superior Slush.
Widget slushTitleBar(
  StudioTitleBar bar,
  BuildContext context,
  BoxConstraints constraints,
  bool largeText,
) {
  final colors = Theme.of(context).colorScheme;
  return Container(
    height: largeText ? 60 : 52,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: colors.surface, border: null),
    child: Row(
      children: [
        GestureDetector(
          onPanStart: (_) => WindowControls.invoke('drag'),
          onDoubleTap: () => WindowControls.invoke('maximize'),
          child: Row(
            children: [
              const _ModernLogo(),
              const SizedBox(width: 8),
              if (constraints.maxWidth > (largeText ? 450 : 400))
                Text(
                  'Aurora',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.18,
                    color: colors.onSurface,
                  ),
                ),
            ],
          ),
        ),
        if (constraints.maxWidth > 850 && !largeText) ...[
          const SizedBox(width: 16),
          SizedBox(
            height: 14,
            child: VerticalDivider(color: colors.surfaceContainerHighest),
          ),
          const SizedBox(width: 12),
          for (final item in [
            (2, 'Biblioteca'),
            (4, 'Modo Vinilo'),
            (6, 'Estudio Analógico'),
          ]) ...[
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => bar.onNavigate(item.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
        // Zona vacía de la barra: arrastra la ventana y doble clic maximiza.
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => WindowControls.invoke('drag'),
            onDoubleTap: () => WindowControls.invoke('maximize'),
            child: const SizedBox.expand(),
          ),
        ),
        if (constraints.maxWidth > 700 && !largeText)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: bar.onSession ?? () => bar.onNavigate(9),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bar.activeSession
                    ? Tracky.mint
                    : colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    StudioSymbols.wifiTethering,
                    size: 14,
                    color: bar.activeSession ? Tracky.navy : colors.outline,
                  ),
                  const SizedBox(width: 4),
                  StudioStamp(
                    bar.sessionText,
                    color: bar.activeSession ? Tracky.navy : null,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: bar.activeSession ? Tracky.navy : colors.outline,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(width: 16),
        Builder(
          builder: (ctx) => IconButton.filled(
            tooltip: 'Perfil y ajustes',
            style: IconButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: colors.onPrimary,
              minimumSize: const Size(32, 32),
              padding: bar.avatar == null
                  ? const EdgeInsets.all(6)
                  : EdgeInsets.zero,
            ),
            onPressed: () => bar.profile(ctx),
            icon: bar.profileGlyph(32, 18),
          ),
        ),
        if (WindowControls.supported) ...[
          const SizedBox(width: 12),
          for (final item in [
            ('minimize', StudioSymbols.minimize, 'Minimizar'),
            (
              'maximize',
              StudioSymbols.checkBoxOutlineBlank,
              'Maximizar o restaurar',
            ),
            ('close', StudioSymbols.close, 'Cerrar ventana'),
          ])
            IconButton(
              tooltip: item.$3,
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                if (!await WindowControls.invoke(item.$1) && context.mounted) {
                  showStudioPending(context, 'Control de ventana Windows');
                }
              },
              icon: Icon(item.$2, size: 15),
            ),
        ],
      ],
    ),
  );
}

/// Sidebar Slush 2.0: tarjeta de papel flotante de 272 px con logo-pegatina,
/// navegación en píldoras, mosaico de color «Fidelidad & experiencia»,
/// colecciones con miniatura y pie con estado del motor.
Widget slushSidebar(StudioSidebar side, BuildContext context) {
  final p = context.slush;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  String kbd(ShortcutId id, String fallback) =>
      side.shortcuts?.labelOf(id) ?? fallback;
  final c = side.controller;
  final path = c.downloadsDirectoryPath.replaceAll('\\', '/');
  return SizedBox(
    width: 272 + 16,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      child: Container(
        key: const ValueKey('slush-sidebar'),
        decoration: ShapeDecoration(
          color: p.paper,
          shadows: p.shadows,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SlushRadius.r32),
            side: p.borderSoft,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    const SizedBox(height: 12),
                    Semantics(
                      container: true,
                      label: 'Navegación principal',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _NavPill(
                            side,
                            0,
                            'Inicio',
                            Icons.home_outlined,
                            '',
                            tooltip: 'Inicio',
                          ),
                          _NavPill(
                            side,
                            1,
                            'Búsqueda',
                            Icons.search_rounded,
                            kbd(ShortcutId.search, 'Ctrl+2'),
                            tooltip: 'Buscar',
                          ),
                          _NavPill(
                            side,
                            8,
                            'DJ',
                            Icons.album_outlined,
                            '',
                            tooltip: 'DJ',
                          ),
                          _NavPill(
                            side,
                            12,
                            'Artistas',
                            Icons.mic_none_rounded,
                            '',
                            tooltip: 'Artistas',
                          ),
                          _NavPill(
                            side,
                            2,
                            'Biblioteca',
                            Icons.library_music_outlined,
                            kbd(ShortcutId.library, 'Ctrl+3'),
                            tooltip: 'Biblioteca',
                          ),
                          _NavPill(
                            side,
                            3,
                            'Descargas',
                            Icons.download_outlined,
                            kbd(ShortcutId.downloads, 'Ctrl+4'),
                            tooltip: 'Descargas locales',
                          ),
                          if (supabaseServicesEnabled)
                            _NavPill(
                              side,
                              14,
                              'Amigos',
                              Icons.people_outline,
                              side.friendsBadge > 0
                                  ? '${side.friendsBadge}'
                                  : '',
                              tooltip: 'Amigos',
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Tooltip(
                      message: c.downloadsDirectoryPath,
                      child: CustomPaint(
                        painter: _DashedPill(p.ink2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.folder_open, size: 16, color: p.ink),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Música · $path',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: p.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _label(context, 'FIDELIDAD & EXPERIENCIA'),
                    _Mosaic(
                      scale: scale,
                      tiles: [
                        _Tile(
                          side,
                          4,
                          'Modo Vinilo',
                          Icons.album_outlined,
                          kbd(ShortcutId.vinyl, 'Ctrl+I'),
                          Slush.lime,
                        ),
                        _Tile(
                          side,
                          6,
                          'Letras dinámicas',
                          Icons.notes_rounded,
                          kbd(ShortcutId.lyrics, 'Ctrl+L'),
                          Slush.yellow,
                        ),
                        _Tile(
                          side,
                          13,
                          'Ecualizador',
                          Icons.equalizer_rounded,
                          'EQ',
                          Slush.lilacHero,
                        ),
                        _Tile(
                          side,
                          7,
                          'Modo Foco / Sueño',
                          Icons.nightlight_outlined,
                          'Zz',
                          Slush.pink,
                          active: false,
                        ),
                        _Tile(
                          side,
                          9,
                          'Jam',
                          Icons.groups_outlined,
                          '',
                          Slush.mint,
                        ),
                        _Tile(
                          side,
                          5,
                          'Cola de reproducción',
                          Icons.queue_music,
                          c.queue.isEmpty ? '' : '${c.queue.length}',
                          p.paper,
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: _labelText(context, 'ÁNIMOS & COLECCIONES'),
                          ),
                          if (side.onCreatePlaylist != null)
                            Tooltip(
                              message: 'Crear lista',
                              child: InkResponse(
                                radius: 22,
                                onTap: side.onCreatePlaylist,
                                child: const SizedBox.square(
                                  dimension: 44,
                                  child: Icon(Icons.add_rounded, size: 20),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    for (final playlist in c.playlists)
                      PlaylistPhotoMenu(
                        controller: c,
                        playlist: playlist,
                        child: _PlaylistRow(
                          controller: c,
                          playlist: playlist,
                          onTap: () => side.onPlaylist(playlist),
                        ),
                      ),
                    if (c.playlists.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Aún no hay colecciones',
                          style: TextStyle(fontSize: 12, color: p.ink2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Row(
                children: [
                  Tooltip(
                    message: 'Ajustes',
                    child: SlushPressable(
                      onTap: () => side.onNavigate(7),
                      radius: SlushRadius.r16,
                      minSize: 48,
                      child: _face(
                        context,
                        color: p.paper,
                        radius: SlushRadius.r16,
                        child: SizedBox.square(
                          dimension: 48,
                          child: Icon(
                            Icons.tune_rounded,
                            size: 20,
                            color: p.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EngineStatus(buffering: c.audio.isBuffering),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Cara opaca de un control (relleno + contorno de 2 px).
Widget _face(
  BuildContext context, {
  required Color color,
  required double radius,
  required Widget child,
  bool border = true,
}) => DecoratedBox(
  decoration: ShapeDecoration(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border ? context.slush.border : BorderSide.none,
    ),
  ),
  child: child,
);

Widget _labelText(BuildContext context, String value) => Padding(
  padding: const EdgeInsets.only(left: 2),
  child: Text(
    value,
    style: slushMono(10.5, color: context.slush.ink2, letterSpacing: 1),
  ),
);

Widget _label(BuildContext context, String value) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 8),
  child: _labelText(context, value),
);

/// Logo-pegatina inclinado -6° + «Aurora» en Bricolage 800.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return GestureDetector(
      onPanStart: (_) => WindowControls.invoke('drag'),
      onDoubleTap: () => WindowControls.invoke('maximize'),
      child: Semantics(
        label: 'Aurora',
        child: Row(
          children: [
            Transform.rotate(
              angle: -.105,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: Slush.violet,
                  shadows: p.shadowsFor(SlushElevation.control),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: p.border,
                  ),
                ),
                child: const SizedBox.square(
                  dimension: 44,
                  child: Icon(Icons.auto_awesome, size: 22, color: Slush.lime),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FittedBox(
                alignment: Alignment.centerLeft,
                fit: BoxFit.scaleDown,
                child: Text(
                  'Aurora',
                  maxLines: 1,
                  style: slushHeadline(32, height: 1.1, color: p.ink),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Atajo como `kbd`: contorno fino y mono.
class _Kbd extends StatelessWidget {
  const _Kbd(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color, width: 1.5),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      child: Text(
        label,
        maxLines: 1,
        style: slushMono(10, color: color, letterSpacing: 0),
      ),
    ),
  );
}

/// Ítem de navegación en píldora; activo = violeta, texto blanco y sombra.
class _NavPill extends StatelessWidget {
  const _NavPill(
    this.side,
    this.index,
    this.label,
    this.icon,
    this.kbd, {
    required this.tooltip,
  });
  final StudioSidebar side;
  final int index;
  final String label, kbd, tooltip;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final active = side.selected == index;
    final fg = active ? Slush.onViolet : p.ink;
    final showKbd =
        kbd.isNotEmpty && MediaQuery.textScalerOf(context).scale(1) <= 1.5;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 3, 3),
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          selected: active,
          child: SlushPressable(
            onTap: () => side.onNavigate(index),
            elevation: active ? SlushElevation.control : SlushElevation.none,
            minSize: 44,
            child: _face(
              context,
              color: active ? Slush.violet : p.paper,
              radius: SlushRadius.pill,
              border: active,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (showKbd) _Kbd(kbd, active ? Slush.onViolet : p.ink2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mosaico de 2 columnas (1 con texto muy grande).
class _Mosaic extends StatelessWidget {
  const _Mosaic({required this.tiles, required this.scale});
  final List<Widget> tiles;
  final double scale;

  @override
  Widget build(BuildContext context) {
    if (scale > 1.5) return Column(children: tiles);
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                Expanded(child: tiles[i + 1]),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tile de color: icono + atajo arriba, etiqueta abajo; activo = anillo violeta.
class _Tile extends StatelessWidget {
  const _Tile(
    this.side,
    this.index,
    this.label,
    this.icon,
    this.kbd,
    this.color, {
    this.active,
  });
  final StudioSidebar side;
  final int index;
  final String label, kbd;
  final IconData icon;
  final Color color;
  final bool? active;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final on = active ?? side.selected == index;
    final vivid = color != p.paper;
    final fg = vivid ? Slush.ink : p.ink;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SlushRadius.r16 + 4),
          border: on ? Border.all(color: p.violetAccent, width: 3) : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(on ? 2 : 0),
          child: Semantics(
            button: true,
            selected: on,
            label: label,
            child: SlushPressable(
              onTap: () => side.onNavigate(index),
              radius: SlushRadius.r16,
              minSize: 54,
              child: _face(
                context,
                color: color,
                radius: SlushRadius.r16,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 60),
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 18, color: fg),
                          const Spacer(),
                          if (kbd.isNotEmpty)
                            Flexible(
                              child: Text(
                                kbd,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: slushMono(
                                  9.5,
                                  color: fg,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12.5,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({
    required this.controller,
    required this.playlist,
    required this.onTap,
  });
  final AppController controller;
  final MusicPlaylist playlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SlushRadius.r16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.fromBorderSide(p.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PlaylistCover(
                  playlist: playlist,
                  tracks: playlistCoverTracks(controller, playlist),
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                playlist.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: p.ink,
                ),
              ),
            ),
            Text(
              '${playlist.trackIds.length}',
              style: TextStyle(
                fontSize: 12,
                color: p.ink2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

/// Píldora lila de estado del motor (punto menta = listo).
class _EngineStatus extends StatelessWidget {
  const _EngineStatus({required this.buffering});
  final bool buffering;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: dark ? p.raised : Slush.lilac,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SlushRadius.r16),
          side: p.border,
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DAC · NO MEDIDA',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: slushMono(9.5, color: p.ink, letterSpacing: .4),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: buffering ? Slush.yellow : Slush.mint,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: p.line, width: 1.5),
                    ),
                  ),
                  child: const SizedBox.square(dimension: 8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    buffering
                        ? 'Preparando buffer'
                        : 'Motor de reproducción listo',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, height: 1.15, color: p.ink2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Contorno discontinuo de píldora (carpeta de música).
class _DashedPill extends CustomPainter {
  const _DashedPill(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(1),
      Radius.circular(size.height / 2),
    );
    final path = Path()..addRRect(r);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPill old) => old.color != color;
}

/// Logo Modern: círculo azul marino con símbolo de reproducir.
class _ModernLogo extends StatelessWidget {
  const _ModernLogo();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Tracky.navy, shape: BoxShape.circle),
    child: SizedBox.square(
      dimension: 32,
      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
    ),
  );
}
