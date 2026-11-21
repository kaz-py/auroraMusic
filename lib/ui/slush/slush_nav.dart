/// Navegación móvil de Slush 2.0: cápsula flotante de 5 ítems (Inicio, Buscar,
/// Biblioteca, DJ, Más) con el mini reproductor lila encima, y la hoja «Más».
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../shell/shell_sections.dart';

/// Ítems de la hoja «Más»: (sección, icono, etiqueta, color).
List<(int, IconData, String, Color)> slushMoreItems() => [
  (3, Icons.download_outlined, 'Descargas', Slush.lime),
  (12, Icons.mic_none_rounded, 'Artistas', Slush.yellow),
  (9, Icons.groups_outlined, 'Jam', Slush.mint),
  if (supabaseServicesEnabled) (14, Icons.people_outline, 'Amigos', Slush.pink),
  (4, Icons.album_outlined, 'Modo Vinilo', Slush.lilacHero),
  (5, Icons.queue_music, 'Cola de reproducción', Slush.lilacHero),
  (6, Icons.notes_rounded, 'Letras', Slush.yellow),
  (13, Icons.equalizer_rounded, 'Ecualizador', Slush.lime),
  (11, Icons.video_file_outlined, 'Descargar vídeos', Slush.pink),
  (7, Icons.tune_rounded, 'Ajustes', Slush.mint),
];

/// Abre la hoja «Más» y navega a la sección elegida.
Future<void> showSlushMoreSheet(
  BuildContext context, {
  required ValueChanged<int> onNavigate,
  int friendsBadge = 0,
}) async {
  final picked = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _MoreSheet(friendsBadge: friendsBadge),
  );
  if (picked != null) onNavigate(picked);
}

class _MoreSheet extends StatelessWidget {
  const _MoreSheet({required this.friendsBadge});
  final int friendsBadge;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final one = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return DecoratedBox(
      key: const ValueKey('slush-more-sheet'),
      decoration: ShapeDecoration(
        color: p.paper,
        shape: RoundedRectangleBorder(
          side: p.borderSoft,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SlushRadius.r32),
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.ink,
                  shape: const StadiumBorder(),
                ),
                child: const SizedBox(width: 44, height: 5),
              ),
            ),
            const SizedBox(height: 14),
            Text('Más', style: slushHeadline(30, color: p.ink)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final w = one ? box.maxWidth : (box.maxWidth - 12) / 2;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final (id, icon, label, color) in slushMoreItems())
                      SizedBox(
                        width: w,
                        child: _MoreTile(
                          icon: icon,
                          label: label,
                          color: color,
                          badge: id == 14 ? friendsBadge : 0,
                          onTap: () => Navigator.pop(context, id),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String label;
  final Color color;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return Padding(
      padding: const EdgeInsets.only(right: 3, bottom: 3),
      child: Semantics(
        button: true,
        label: label,
        child: SlushPressable(
          onTap: onTap,
          radius: SlushRadius.r16,
          minSize: 56,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: color,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(SlushRadius.r16),
                side: p.border,
              ),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    child: Icon(icon, size: 22, color: Slush.ink),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: Slush.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Zona inferior de Slush en móvil: mini reproductor lila (opcional) y
/// cápsula de papel con Inicio, Buscar, Biblioteca, DJ y «Más». El destino
/// activo es una píldora violeta con texto blanco.
class SlushBottomBar extends StatelessWidget {
  const SlushBottomBar({
    super.key,
    required this.section,
    required this.onNavigate,
    this.friendsBadge = 0,
    this.mini,
  });

  /// Sección activa del shell.
  final int section;
  final ValueChanged<int> onNavigate;
  final int friendsBadge;
  final Widget? mini;

  static const _icons = <int, IconData>{
    0: Icons.home_outlined,
    1: Icons.search_rounded,
    2: Icons.library_music_outlined,
    8: Icons.album_outlined,
  };
  static const _labels = <int, String>{
    0: 'Inicio',
    1: 'Buscar',
    2: 'Biblioteca',
    8: 'DJ',
  };

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final primary = primarySections(AuroraThemeKind.slush, mobile: true);
    final moreIndex = primary.length;
    final selected = primary.contains(section)
        ? primary.indexOf(section)
        : moreIndex;
    final w = MediaQuery.sizeOf(context).width;
    final itemW = (w - 24 - 12) / (primary.length + 1);
    // 360 px queda justo: con poco ancho solo el destino activo lleva etiqueta.
    final allLabels = itemW >= 66;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ?mini,
            Padding(
              padding: const EdgeInsets.only(right: 3, bottom: 3),
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: p.paper,
                  shadows: p.shadows,
                  shape: StadiumBorder(side: p.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Semantics(
                    container: true,
                    label: 'Navegación principal',
                    child: Row(
                      children: [
                        for (var i = 0; i <= moreIndex; i++)
                          Expanded(
                            child: _Tab(
                              icon: i == moreIndex
                                  ? Icons.menu_rounded
                                  : _icons[primary[i]]!,
                              label: i == moreIndex
                                  ? 'Más'
                                  : _labels[primary[i]]!,
                              active: i == selected,
                              showLabel: allLabels || i == selected,
                              badge: i == moreIndex ? friendsBadge : 0,
                              tooltip: i == moreIndex ? 'Más vistas' : null,
                              onTap: () => i == moreIndex
                                  ? showSlushMoreSheet(
                                      context,
                                      onNavigate: onNavigate,
                                      friendsBadge: friendsBadge,
                                    )
                                  : onNavigate(primary[i]),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.active,
    required this.showLabel,
    required this.onTap,
    this.badge = 0,
    this.tooltip,
  });
  final IconData icon;
  final String label;
  final bool active, showLabel;
  final int badge;
  final String? tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final fg = active ? Slush.onViolet : p.ink;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: Tooltip(
        message: tooltip ?? label,
        child: Center(
          child: SlushPressable(
            onTap: onTap,
            elevation: active ? SlushElevation.control : SlushElevation.none,
            minSize: 56,
            child: AnimatedContainer(
              duration: SlushMotion.select,
              curve: SlushMotion.easeOut,
              alignment: Alignment.center,
              constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: ShapeDecoration(
                color: active ? Slush.violet : p.paper,
                shape: StadiumBorder(side: active ? p.border : BorderSide.none),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    child: Icon(icon, size: 24, color: fg),
                  ),
                  if (showLabel)
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: fg,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
