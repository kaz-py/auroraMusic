import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Qué lado del shell controla un [PanelSeam].
enum PanelSide { left, right }

/// Paneles laterales plegables del escritorio: la barra izquierda pasa a su
/// carril de iconos y el panel derecho se oculta. Se recuerda entre sesiones.
class ShellPanels extends ChangeNotifier {
  ShellPanels(this._prefs) {
    _sidebarCollapsed = _prefs?.getBool(sidebarKey) ?? false;
    _asideHidden = _prefs?.getBool(asideKey) ?? false;
  }

  static const sidebarKey = 'shellSidebarCollapsed';
  static const asideKey = 'shellAsideHidden';

  final SharedPreferences? _prefs;
  late bool _sidebarCollapsed;
  late bool _asideHidden;

  /// La barra izquierda se muestra como carril de iconos.
  bool get sidebarCollapsed => _sidebarCollapsed;

  /// El panel derecho no se muestra.
  bool get asideHidden => _asideHidden;

  void toggle(PanelSide side) => side == PanelSide.left
      ? setSidebarCollapsed(!_sidebarCollapsed)
      : setAsideHidden(!_asideHidden);

  void setSidebarCollapsed(bool value) {
    if (value == _sidebarCollapsed) return;
    _sidebarCollapsed = value;
    _prefs?.setBool(sidebarKey, value);
    notifyListeners();
  }

  void setAsideHidden(bool value) {
    if (value == _asideHidden) return;
    _asideHidden = value;
    _prefs?.setBool(asideKey, value);
    notifyListeners();
  }
}

/// Costura fina entre un panel lateral y el contenido, con un asa para
/// plegarlo o desplegarlo. Usa el esquema de color del tema activo.
class PanelSeam extends StatefulWidget {
  const PanelSeam({
    super.key,
    required this.side,
    required this.open,
    required this.onToggle,
    this.shortcutLabel,
  });

  /// Lado del panel que controla.
  final PanelSide side;

  /// El panel está desplegado.
  final bool open;
  final VoidCallback onToggle;

  /// Atajo configurado para este panel (se muestra en la ayuda).
  final String? shortcutLabel;

  static const width = 14.0;

  @override
  State<PanelSeam> createState() => _PanelSeamState();
}

class _PanelSeamState extends State<PanelSeam> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final left = widget.side == PanelSide.left;
    // La flecha apunta hacia donde se moverá el panel.
    final pointsLeft = left == widget.open;
    final label = widget.open
        ? (left ? 'Plegar el panel izquierdo' : 'Ocultar el panel derecho')
        : (left ? 'Desplegar el panel izquierdo' : 'Mostrar el panel derecho');
    final shortcut = widget.shortcutLabel;
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: shortcut == null ? label : '$label ($shortcut)',
        waitDuration: const Duration(milliseconds: 500),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onToggle,
            child: SizedBox(
              width: PanelSeam.width,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: _hover ? 14 : 4,
                  height: _hover ? 44 : 36,
                  decoration: BoxDecoration(
                    color: _hover
                        ? colors.surfaceContainerHighest
                        : colors.onSurface.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(_hover ? 4 : 2),
                    border: _hover
                        ? Border.all(
                            color: colors.outlineVariant.withValues(alpha: .6),
                          )
                        : null,
                  ),
                  child: _hover
                      ? Icon(
                          pointsLeft
                              ? Icons.chevron_left_rounded
                              : Icons.chevron_right_rounded,
                          size: 14,
                          color: colors.onSurface,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
