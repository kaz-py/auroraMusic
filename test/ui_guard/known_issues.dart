import 'guard_checks.dart';

/// Coordenadas de un caso de la matriz de la guarda.
class GuardCase {
  const GuardCase(this.theme, this.mode, this.width, this.scale, this.screen);
  final String theme, mode, screen;
  final int width;
  final double scale;

  @override
  String toString() => '$theme/$mode ${width}px x$scale · $screen';
}

/// Fallo ya conocido de la interfaz, aceptado temporalmente.
///
/// Cada entrada es una TODO: la guarda FALLA si la entrada se ejercita en la
/// matriz y ya no se reproduce, así que la lista solo puede encogerse. Al
/// arreglar el código, borra la entrada.
class KnownIssue {
  const KnownIssue({
    required this.id,
    required this.kind,
    required this.file,
    required this.reason,
    this.contains,
    this.themes,
    this.modes,
    this.screens,
    this.minWidth,
    this.maxWidth,
    this.scales,
  });

  /// Identificador corto y estable (aparece en los informes).
  final String id;
  final GuardKind kind;

  /// Archivo responsable y motivo, para quien arregle la entrada.
  final String file, reason;

  /// Subcadena obligatoria del detalle del fallo; null = cualquiera del tipo.
  final String? contains;

  /// Alcance; null = sin restricción en ese eje.
  final Set<String>? themes, modes, screens;
  final int? minWidth, maxWidth;
  final List<double>? scales;

  bool covers(GuardCase c) =>
      (themes?.contains(c.theme) ?? true) &&
      (modes?.contains(c.mode) ?? true) &&
      (screens?.contains(c.screen) ?? true) &&
      (minWidth == null || c.width >= minWidth!) &&
      (maxWidth == null || c.width <= maxWidth!) &&
      (scales?.contains(c.scale) ?? true) &&
      // El mínimo táctil solo se mide en móvil.
      (kind != GuardKind.hit || c.width < phoneMaxWidth);

  bool matches(GuardCase c, GuardViolation v) =>
      v.kind == kind &&
      covers(c) &&
      (contains == null || v.detail.contains(contains!));
}

/// Fallos conocidos de hoy. Debe encogerse, nunca crecer.
const knownIssues = <KnownIssue>[
  KnownIssue(
    id: 'transporte-artista-17px',
    kind: GuardKind.hit,
    file: 'lib/ui/studio/studio_transport.dart (GestureDetector del artista)',
    reason:
        'El nombre del artista en el reproductor de Atelier mide 17 px de alto '
        '(34 con texto x2): objetivo táctil < 40 px. Dale altura mínima 40 '
        '(p. ej. ConstrainedBox/padding vertical) sin mover el texto.',
    contains: 'GestureDetector "Mare Sol"',
    themes: {'atelier'},
  ),
  KnownIssue(
    id: 'buscar-filtros-38px',
    kind: GuardKind.hit,
    file: 'lib/ui/aurora_shell.dart (_searchPage: chips de fuente y de tipo)',
    reason:
        'Los chips "Audio · YouTube", "Metadatos · Spotify", "Canciones", '
        '"Álbumes"... miden 38 px de alto en móvil; el mínimo es 40.',
    contains: 'x38 (',
    themes: {'atelier'},
    screens: {'Búsqueda'},
  ),
  KnownIssue(
    id: 'buscar-desborde-texto-x2',
    kind: GuardKind.exception,
    file: 'lib/ui/aurora_shell.dart (_searchPage, cabecera/filtros)',
    reason:
        'Con texto al 200 % la cabecera de Búsqueda de Atelier desborda por '
        'abajo (49-117 px): la columna no hace scroll ni cede altura.',
    contains: 'lib/ui/aurora_shell.dart',
    themes: {'atelier'},
    screens: {'Búsqueda'},
    scales: [2.0],
  ),
  KnownIssue(
    id: 'inicio-verificado-contraste',
    kind: GuardKind.contrast,
    file: 'lib/ui/studio/home_introduction.dart (StudioSymbols.verified)',
    reason:
        'El icono "verificado" del Inicio de Atelier claro es #efd1bd sobre '
        '#fef2ea (1.32:1); necesita >= 3:1 (usar el acento oscuro).',
    contains: 'icono U+ef76',
    themes: {'atelier'},
    modes: {'light'},
    screens: {'Inicio'},
  ),
];
