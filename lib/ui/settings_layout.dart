import 'package:flutter/material.dart';

import '../theme/slush_theme.dart';

/// Sección de Ajustes: [builder] solo se invoca si la sección está desplegada,
/// así lo que hay dentro no se construye hasta que se abre.
class SettingsSection {
  const SettingsSection({
    required this.title,
    required this.subtitle,
    required this.tab,
    required this.builder,
    this.keywords = '',
  });

  final String title;
  final String subtitle;
  final int tab;
  final String keywords;
  final List<Widget> Function() builder;

  /// [query] ya normalizada con [settingsFold].
  bool matches(String query) =>
      settingsFold('$title $subtitle $keywords').contains(query);
}

/// Minúsculas y sin tildes, para buscar «sueno» y encontrar «Sueño».
String settingsFold(String text) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final lower = text.toLowerCase();
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// Disposición de Ajustes: categorías con icono (riel en ancho, chips en
/// estrecho), buscador y secciones plegables. Solo se construye la categoría
/// activa y, dentro, las secciones desplegadas. Las tarjetas, los títulos y
/// los chips los pinta el shell con el tema activo.
class SettingsLayout extends StatefulWidget {
  const SettingsLayout({
    super.key,
    required this.tabs,
    required this.icons,
    required this.descriptions,
    required this.selected,
    required this.onSelect,
    required this.sections,
    required this.expanded,
    required this.openSerial,
    required this.card,
    required this.sectionTitle,
    required this.chip,
  });

  final List<String> tabs;
  final List<IconData> icons;
  final List<String> descriptions;
  final int selected;
  final ValueChanged<int> onSelect;
  final List<SettingsSection> sections;

  /// Memoria de secciones plegadas/desplegadas por título (la posee el shell,
  /// así sobrevive a salir de Ajustes). Ausente = solo la primera de la
  /// categoría está desplegada.
  final Map<String, bool> expanded;

  /// Cambia cuando algo pide abrir una sección concreta desde fuera.
  final int openSerial;
  final Widget Function(Widget child, bool compact) card;
  final Widget Function(String title, String subtitle) sectionTitle;
  final Widget Function(String label, bool selected, VoidCallback onTap) chip;

  static const breakpoint = 720.0;

  /// Con más coincidencias que esto, la búsqueda no despliega nada solo.
  static const maxAutoExpanded = 3;

  @override
  State<SettingsLayout> createState() => _SettingsLayoutState();
}

class _SettingsLayoutState extends State<SettingsLayout> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void didUpdateWidget(SettingsLayout old) {
    super.didUpdateWidget(old);
    if (old.openSerial != widget.openSerial) _setQuery('');
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _setQuery(String value) {
    if (_search.text != value) _search.text = value;
    if (_query == value) return;
    setState(() => _query = value);
  }

  void _select(int i) {
    _setQuery('');
    widget.onSelect(i);
  }

  Widget _searchField() => TextField(
    key: const ValueKey('settings-search'),
    controller: _search,
    textInputAction: TextInputAction.search,
    onChanged: (v) => setState(() => _query = v),
    decoration: InputDecoration(
      hintText: 'Buscar en Ajustes',
      prefixIcon: const Icon(Icons.search_rounded),
      suffixIcon: _query.isEmpty
          ? null
          : IconButton(
              tooltip: 'Borrar búsqueda',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => _setQuery(''),
            ),
    ),
  );

  Widget _header(BuildContext context, String title, String description) {
    final theme = Theme.of(context);
    final slush = isSlush(context);
    return Padding(
      padding: EdgeInsets.only(bottom: slush ? 24 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: slush
                  ? context.slush.ink2
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: slush ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    SettingsSection s, {
    required bool compact,
    required bool searching,
    required bool open,
  }) {
    final pad = compact ? 16.0 : 20.0;
    return widget.card(
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            key: ValueKey('${s.title}:${widget.openSerial}:$searching'),
            initiallyExpanded: open,
            onExpansionChanged: (v) {
              if (!searching) widget.expanded[s.title] = v;
            },
            tilePadding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
            childrenPadding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
            expandedAlignment: Alignment.centerLeft,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: widget.sectionTitle(s.title, s.subtitle),
            children: [_Lazy(s.builder)],
          ),
        ),
      ),
      compact,
    );
  }

  /// Secciones a mostrar y, con búsqueda, el aviso si no hay ninguna.
  List<Widget> _body(BuildContext context, bool compact) {
    final q = settingsFold(_query.trim());
    final searching = q.isNotEmpty;
    final shown = [
      for (final s in widget.sections)
        if (searching ? s.matches(q) : s.tab == widget.selected) s,
    ];
    if (searching && shown.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Sin resultados para «${_query.trim()}».',
            key: const ValueKey('settings-no-results'),
          ),
        ),
      ];
    }
    final autoOpen = shown.length <= SettingsLayout.maxAutoExpanded;
    return [
      for (var i = 0; i < shown.length; i++)
        _tile(
          context,
          shown[i],
          compact: compact,
          searching: searching,
          open: searching
              ? autoOpen
              : widget.expanded[shown[i].title] ?? i == 0,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < SettingsLayout.breakpoint;
      final searching = settingsFold(_query.trim()).isNotEmpty;
      final header = _header(
        context,
        searching ? 'Resultados' : widget.tabs[widget.selected],
        searching
            ? 'Coincidencias en todas las categorías.'
            : widget.descriptions[widget.selected],
      );
      final body = _body(context, compact);
      if (compact) {
        return ListView(
          padding: EdgeInsets.all(
            isSlush(context) ? SlushSpacing.margin(constraints.maxWidth) : 16,
          ),
          children: [
            _searchField(),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  for (var i = 0; i < widget.tabs.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: widget.chip(
                        widget.tabs[i],
                        !searching && widget.selected == i,
                        () => _select(i),
                      ),
                    ),
                ],
              ),
            ),
            header,
            ...body,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: isSlush(context) ? 280 : 248,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 24, 8, 24),
              children: [
                for (var i = 0; i < widget.tabs.length; i++)
                  _RailItem(
                    label: widget.tabs[i],
                    icon: widget.icons[i],
                    active: !searching && widget.selected == i,
                    onTap: () => _select(i),
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
                    maxWidth: isSlush(context) ? 1100 : 900,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _searchField(),
                      const SizedBox(height: 20),
                      header,
                      ...body,
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

/// Difiere [builder] hasta que la sección se despliega de verdad.
class _Lazy extends StatelessWidget {
  const _Lazy(this.builder);
  final List<Widget> Function() builder;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: builder());
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
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: slush ? 48 : 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: fg,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
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
