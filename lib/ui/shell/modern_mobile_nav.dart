/// Navegación inferior móvil del tema Modern: cuatro destinos + «Más» (hoja
/// con el resto de vistas). Dueño: tema Modern.
library;

import 'package:flutter/material.dart';

import '../../core/feature_flags.dart';
import '../../theme/aurora_tokens.dart';
import '../../theme/modern_cristal.dart';
import 'shell_chrome.dart';
import 'shell_sections.dart';

class ModernBottomNav extends StatelessWidget {
  const ModernBottomNav({super.key, required this.scope});
  final ShellScope scope;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final primary = primarySections(AuroraThemeKind.modern, mobile: true);
    const labels = {0: 'Inicio', 1: 'Buscar', 2: 'Biblioteca', 3: 'Descargas'};
    return Material(
      color: c.canvas.withValues(alpha: .86),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 62),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in primary)
                  Expanded(
                    child: _Tab(
                      label: labels[s]!,
                      tooltip: shellSectionTitles[s]!,
                      icon: shellSectionIcons[s]!,
                      selected: scope.section == s,
                      onTap: () => scope.onNavigate(s),
                    ),
                  ),
                Expanded(
                  child: _Tab(
                    label: 'Más',
                    tooltip: 'Más vistas',
                    icon: Icons.more_horiz,
                    selected: !primary.contains(scope.section),
                    badge: scope.friendsBadge,
                    onTap: () => showModernMoreSheet(context, scope),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final String label, tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final color = selected ? c.text : c.text3;
    return Semantics(
      button: true,
      selected: selected,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? c.accentSoft : Colors.transparent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Badge(
                    isLabelVisible: badge > 0,
                    label: Text('$badge'),
                    child: Icon(
                      icon,
                      size: 22,
                      color: selected ? c.accent : c.text3,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Cristal.ui(
                      11.5,
                      weight: selected ? 700 : 600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja «Más»: las vistas que no caben en la barra inferior.
Future<void> showModernMoreSheet(BuildContext context, ShellScope scope) {
  final entries = <(int, String, int)>[
    (8, 'DJ', 0),
    (12, 'Artistas', 0),
    (4, 'Modo Vinilo', 0),
    (6, 'Letras', 0),
    (13, 'Ecualizador', 0),
    (5, 'Cola de reproducción', 0),
    (9, 'Jam', 0),
    if (supabaseServicesEnabled) (14, 'Amigos', scope.friendsBadge),
    (11, 'Descargar vídeos', 0),
    (7, 'Ajustes', 0),
  ];
  final c = Cristal.of(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Color.alphaBlend(c.glassHover, c.canvas),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              'Más',
              style: Cristal.ui(22, weight: 800, color: c.text, tracking: -.03),
            ),
          ),
          for (final e in entries)
            _SheetRow(
              icon: shellSectionIcons[e.$1]!,
              label: e.$2,
              badge: e.$3,
              selected: scope.section == e.$1,
              onTap: () {
                Navigator.pop(sheet);
                scope.onNavigate(e.$1);
              },
            ),
          _SheetRow(
            icon: Icons.create_new_folder_outlined,
            label: 'Importar archivos',
            enabled: scope.controller.ready,
            onTap: () {
              Navigator.pop(sheet);
              scope.controller.importFiles();
            },
          ),
        ],
      ),
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
    this.selected = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int badge;
  final bool selected, enabled;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? c.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.glass,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Badge(
                      isLabelVisible: badge > 0,
                      label: Text('$badge'),
                      child: Icon(
                        icon,
                        size: 20,
                        color: !enabled
                            ? c.text3
                            : selected
                            ? c.accent
                            : c.text2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      label,
                      style: Cristal.ui(
                        15,
                        weight: selected ? 700 : 600,
                        color: enabled ? c.text : c.text3,
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
