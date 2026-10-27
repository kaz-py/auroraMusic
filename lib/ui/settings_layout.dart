import 'package:flutter/material.dart';

import '../theme/slush_theme.dart';

/// Disposición de Ajustes: riel vertical + rejilla de 2 columnas en ancho,
/// chips con scroll horizontal + una columna en estrecho. Solo layout: las
/// tarjetas y los chips los pinta el shell con el tema activo.
class SettingsLayout extends StatelessWidget {
  const SettingsLayout({
    super.key,
    required this.tabs,
    required this.icons,
    required this.descriptions,
    required this.selected,
    required this.onSelect,
    required this.cardCount,
    required this.card,
    required this.chip,
  });

  final List<String> tabs;
  final List<IconData> icons;
  final List<String> descriptions;
  final int selected;
  final ValueChanged<int> onSelect;
  final int cardCount;
  final Widget Function(int index, bool compact) card;
  final Widget Function(String label, bool selected, VoidCallback onTap) chip;

  static const breakpoint = 720.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < breakpoint;
      final theme = Theme.of(context);
      final header = Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tabs[selected], style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              descriptions[selected],
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: isSlush(context) ? FontWeight.w600 : null,
              ),
            ),
          ],
        ),
      );
      if (compact) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: chip(tabs[i], selected == i, () => onSelect(i)),
                    ),
                ],
              ),
            ),
            header,
            for (var i = 0; i < cardCount; i++) card(i, true),
          ],
        );
      }
      Widget column(int offset) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = offset; i < cardCount; i += 2) card(i, false),
          ],
        ),
      );
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 248,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 8, 24),
              children: [
                for (var i = 0; i < tabs.length; i++)
                  _RailItem(
                    label: tabs[i],
                    icon: icons[i],
                    active: selected == i,
                    onTap: () => onSelect(i),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 24, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isSlush(context) ? 1800 : 1100,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          column(0),
                          const SizedBox(width: 20),
                          column(1),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final slush = isSlush(context);
    final fg = slush
        ? (active ? Slush.ink : context.slush.ink)
        : active
        ? colors.onSecondaryContainer
        : colors.onSurface;
    final inactive = slush ? context.slush.paper : colors.surfaceContainerLow;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: DecoratedBox(
        decoration: slush && active
            ? ShapeDecoration(
                shape: const StadiumBorder(),
                shadows: context.slush.shadows,
              )
            : const BoxDecoration(),
        child: Material(
          color: active ? colors.secondaryContainer : inactive,
          shape: slush
              ? StadiumBorder(side: context.slush.border)
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: active
                        ? colors.onSecondaryContainer
                        : colors.outline,
                    width: active ? 2 : 1.5,
                  ),
                ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w600,
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
