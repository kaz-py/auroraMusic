import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/window_controls.dart';
import '../../theme/slush_theme.dart';

/// Pestañas de la barra superior: (sección del shell, etiqueta).
const slushTabs = <(int, String)>[
  (0, 'INICIO'),
  (1, 'BUSCAR'),
  (12, 'ARTISTAS'),
  (2, 'BIBLIOTECA'),
  (3, 'DESCARGAS'),
  (8, 'DJ'),
  (9, 'JAM'),
  (14, 'AMIGOS'),
];

Widget _round(
  BuildContext context,
  String tip,
  IconData icon,
  VoidCallback? onTap, {
  double size = 34,
}) => Tooltip(
  message: tip,
  child: Material(
    color: context.slush.paper,
    shape: CircleBorder(side: context.slush.border),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * .52, color: context.slush.ink),
      ),
    ),
  ),
);

/// Barra superior en píldora: logo, pestañas, búsqueda, «Iniciar Jam» y «+».
class SlushTopBar extends StatelessWidget {
  const SlushTopBar({
    super.key,
    required this.selected,
    required this.onNavigate,
    required this.onSession,
    required this.onAdd,
    this.sessionText = 'INICIAR JAM',
  });
  final int selected;
  final ValueChanged<int> onNavigate;
  final VoidCallback onSession, onAdd;
  final String sessionText;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final tabs = Semantics(
      container: true,
      label: 'Navegación principal',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.slush.paper,
          shape: StadiumBorder(side: context.slush.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (section, label) in slushTabs)
                _Tab(
                  label,
                  active: section == selected,
                  onTap: () => onNavigate(section),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.slush.paper,
          shape: StadiumBorder(side: context.slush.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              GestureDetector(
                onPanStart: (_) => WindowControls.invoke('drag'),
                onDoubleTap: () => WindowControls.invoke('maximize'),
                child: Semantics(
                  label: 'Aurora',
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: context.slush.paper,
                      shape: CircleBorder(side: context.slush.border),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            fontFamily: 'Bagel Fat One',
                            fontSize: 18,
                            color: context.slush.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                // El arrastre de ventana va debajo: no compite con los toques.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => WindowControls.invoke('drag'),
                        onDoubleTap: () => WindowControls.invoke('maximize'),
                      ),
                    ),
                    FittedBox(fit: BoxFit.scaleDown, child: tabs),
                  ],
                ),
              ),
              _round(
                context,
                'Buscar',
                Icons.search,
                () => onNavigate(1),
                size: 32,
              ),
              const SizedBox(width: 8),
              Material(
                color: context.slush.ink,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onSession,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: SlushControl.touch,
                      minHeight: SlushControl.dense,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          size: 14,
                          color: context.slush.paper,
                        ),
                        if (Breakpoints.isWide(w)) ...[
                          const SizedBox(width: 6),
                          Text(
                            sessionText,
                            style: TextStyle(
                              color: context.slush.paper,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _round(context, 'Crear lista', Icons.add, onAdd, size: 32),
              const SizedBox(width: 8),
              _round(
                context,
                'Ajustes',
                Icons.tune,
                () => onNavigate(7),
                size: 32,
              ),
              if (WindowControls.supported) ...[
                const SizedBox(width: 6),
                for (final (op, icon, tip) in const [
                  ('minimize', Icons.remove, 'Minimizar'),
                  ('maximize', Icons.crop_square, 'Maximizar o restaurar'),
                  ('close', Icons.close, 'Cerrar ventana'),
                ])
                  IconButton(
                    tooltip: tip,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => WindowControls.invoke(op),
                    icon: Icon(icon, size: 15),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab(this.label, {required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    // 32 con puntero fino (denso), 44 táctil.
    final fine = RendererBinding.instance.mouseTracker.mouseIsConnected;
    final minHeight = fine ? SlushControl.dense : SlushControl.touch;
    final fill = widget.active
        ? p.ink
        : _hover
        ? p.hoverFill
        : Colors.transparent;
    return Semantics(
      button: true,
      selected: widget.active,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: SlushMotion.hover,
            curve: SlushMotion.easeOut,
            constraints: BoxConstraints(minHeight: minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            alignment: Alignment.center,
            decoration: ShapeDecoration(
              color: fill,
              shape: const StadiumBorder(),
            ),
            foregroundDecoration: _focus
                ? ShapeDecoration(shape: StadiumBorder(side: p.focusRing))
                : null,
            child: Text(
              widget.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: .3,
                color: widget.active ? p.paper : p.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
