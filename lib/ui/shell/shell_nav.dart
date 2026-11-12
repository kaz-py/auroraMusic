import 'package:flutter/widgets.dart';

/// Navegación del shell expuesta a quien la necesite sin conocer el chrome del
/// tema (tests de guarda, atajos externos). [AuroraShell] la monta por encima
/// de todo (también del modo letras): `tester.widget<ShellNav>(find.byType(ShellNav))`
/// o `ShellNav.of(context)`.
class ShellNav extends InheritedWidget {
  const ShellNav({
    super.key,
    required this.section,
    required this.navigate,
    required super.child,
  });

  /// Sección activa (ids estables de `shell_sections.dart`).
  final int section;

  /// Cambia de sección con la misma lógica que la barra del tema.
  final ValueChanged<int> navigate;

  static ShellNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellNav>();

  static ShellNav of(BuildContext context) => maybeOf(context)!;

  @override
  bool updateShouldNotify(ShellNav old) => section != old.section;
}

/// Zona de chrome pensada para ratón (barra de título de escritorio): la guarda
/// de objetivos táctiles no la exige de 44 px. Cada chrome la aplica solo a lo
/// que de verdad es de ratón.
class MouseOnlyRegion extends StatelessWidget {
  const MouseOnlyRegion({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
