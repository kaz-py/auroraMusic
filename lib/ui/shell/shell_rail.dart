import 'package:flutter/material.dart';

import '../../theme/aurora_tokens.dart';
import '../../theme/modern_widgets.dart';
import '../brand/aurora_logo.dart';
import 'shell_chrome.dart';
import 'shell_sections.dart';

/// Carril estrecho de iconos (ancho < 900) compartido por Atelier, Modern y
/// Brasa. [modern] activa la variante Modern; [kind] decide las secciones.
class ShellNarrowRail extends StatelessWidget {
  const ShellNarrowRail({
    super.key,
    required this.scope,
    required this.kind,
    required this.modern,
  });
  final ShellScope scope;
  final AuroraThemeKind kind;
  final bool modern;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 76,
      decoration: BoxDecoration(
        border: modern
            ? null
            : Border(
                right: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35),
                ),
              ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (modern)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Tracky.navy,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  )
                else
                  const AuroraLogo(size: 28),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final i in primarySections(kind, mobile: false))
                    _navItem(context, i),
                  const Divider(indent: 20, endIndent: 20, height: 18),
                  for (final i in [12, 11, 9, 14, 4, 5, 6, 13])
                    _navItem(context, i),
                ],
              ),
            ),
          ),
          _navItem(context, 7),
        ],
      ),
    );
  }

  Widget _navItem(BuildContext context, int index) {
    final colors = Theme.of(context).colorScheme;
    final active = scope.section == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: shellSectionTitles[index],
        child: Material(
          color: modern
              ? (active ? colors.primary : Colors.transparent)
              : active
              ? colors.primary.withValues(alpha: .12)
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(modern ? 999 : 8),
          child: InkWell(
            onTap: () => scope.onNavigate(index),
            borderRadius: BorderRadius.circular(modern ? 999 : 8),
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  Badge(
                    isLabelVisible: index == 14 && scope.friendsBadge > 0,
                    label: Text('${scope.friendsBadge}'),
                    child: Icon(
                      shellSectionIcons[index],
                      size: 19,
                      color: modern
                          ? (active
                                ? colors.onPrimary
                                : colors.onSurfaceVariant)
                          : active
                          ? colors.primary
                          : colors.onSurfaceVariant,
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
