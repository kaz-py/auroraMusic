import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';

import '../../core/window_controls.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../shell/shell_nav.dart';

/// Foto de perfil circular; al tocarla abre el menú de perfil anclado a ella.
class SlushProfileButton extends StatelessWidget {
  const SlushProfileButton({
    super.key,
    required this.avatar,
    required this.onProfile,
    this.size = 34,
    this.initial,
  });
  final Uint8List? avatar;
  final void Function(BuildContext anchor) onProfile;
  final double size;

  /// Inicial que se muestra sin foto (por omisión, un icono de persona).
  final String? initial;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (anchor) => Tooltip(
      message: 'Perfil y ajustes',
      child: Material(
        color: avatar == null ? Slush.pink : context.slush.paper,
        shape: CircleBorder(side: context.slush.border),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => onProfile(anchor),
          child: SizedBox.square(
            dimension: size,
            child: avatar == null
                ? (initial != null && initial!.isNotEmpty
                      ? Center(
                          child: Text(
                            initial!,
                            style: slushHeadline(
                              size * .42,
                              height: 1,
                              color: Slush.ink,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.person_outline_rounded,
                          size: 24,
                          color: Slush.ink,
                        ))
                : Image.memory(
                    avatar!,
                    fit: BoxFit.cover,
                    cacheWidth: (size * 3).round(),
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => Icon(
                      Icons.person_outline_rounded,
                      size: size * .52,
                      color: context.slush.ink,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Cabecera de escritorio: búsqueda en píldora, chip lima de Jam, perfil y
/// controles de ventana. [compact] (reproductor a pantalla completa) deja solo
/// el arrastre de ventana y sus botones.
class SlushDesktopHeader extends StatelessWidget {
  const SlushDesktopHeader({
    super.key,
    required this.searchController,
    required this.searchFocus,
    required this.onSearch,
    required this.onSession,
    required this.onProfile,
    required this.sessionText,
    this.avatar,
    this.initial,
    this.shortcut = 'Ctrl+2',
    this.compact = false,
  });
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;
  final VoidCallback onSession;
  final void Function(BuildContext anchor) onProfile;
  final String sessionText;
  final Uint8List? avatar;
  final String? initial;
  final String shortcut;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final controls = WindowControls.supported
        ? MouseOnlyRegion(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (op, icon, tip, fill) in [
                  ('minimize', Icons.remove, 'Minimizar', p.paper),
                  (
                    'maximize',
                    Icons.crop_square,
                    'Maximizar o restaurar',
                    p.paper,
                  ),
                  ('close', Icons.close, 'Cerrar ventana', Slush.pink),
                ])
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 3),
                    child: Tooltip(
                      message: tip,
                      child: SlushPressable(
                        onTap: () => WindowControls.invoke(op),
                        minSize: 36,
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: fill,
                            shape: CircleBorder(side: p.border),
                          ),
                          child: SizedBox.square(
                            dimension: 36,
                            child: Icon(
                              icon,
                              size: 16,
                              color: fill == Slush.pink ? Slush.ink : p.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        : null;
    final drag = Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => WindowControls.invoke('drag'),
        onDoubleTap: () => WindowControls.invoke('maximize'),
      ),
    );
    if (compact) {
      if (controls == null) return const SizedBox.shrink();
      return SizedBox(
        height: 48,
        child: Stack(
          children: [
            drag,
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: controls,
              ),
            ),
          ],
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    return Stack(
      children: [
        drag,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 3, bottom: 3),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: p.paper,
                        shadows: p.shadows,
                        shape: StadiumBorder(side: p.border),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 18),
                          Icon(Icons.search_rounded, size: 20, color: p.ink),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              focusNode: searchFocus,
                              textInputAction: TextInputAction.search,
                              onSubmitted: onSearch,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: p.ink,
                              ),
                              decoration: InputDecoration(
                                isDense: false,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                hintText: 'Buscar canciones, artistas, álbumes',
                                hintStyle: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: p.ink2,
                                ),
                              ),
                            ),
                          ),
                          if (wide)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: p.ink2, width: 1.5),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    shortcut,
                                    style: slushMono(
                                      10.5,
                                      color: p.ink2,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 3, bottom: 3),
                child: SlushPressable(
                  onTap: onSession,
                  semanticLabel: sessionText,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Slush.lime,
                      shape: StadiumBorder(side: p.border),
                    ),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.groups_rounded,
                            size: 18,
                            color: Slush.ink,
                          ),
                          if ((wide ||
                                  MediaQuery.sizeOf(context).width >= 760) &&
                              MediaQuery.textScalerOf(context).scale(14) <=
                                  21) ...[
                            const SizedBox(width: 8),
                            Text(
                              sessionText,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Slush.ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(right: 3, bottom: 3),
                child: SlushProfileButton(
                  avatar: avatar,
                  onProfile: onProfile,
                  initial: initial,
                  size: 48,
                ),
              ),
              ?controls,
            ],
          ),
        ),
      ],
    );
  }
}

const _weekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

/// «Buenas noches, Pablo» según la hora.
String slushGreeting(DateTime now, String name) {
  final h = now.hour;
  final hi = h < 6
      ? 'Buenas noches'
      : h < 13
      ? 'Buenos días'
      : h < 20
      ? 'Buenas tardes'
      : 'Buenas noches';
  return name.trim().isEmpty ? hi : '$hi, ${name.trim()}';
}

/// «Jueves · 12 nov».
String slushDateLine(DateTime now) =>
    '${_weekdays[now.weekday - 1]} · ${now.day} ${_months[now.month - 1]}';

/// Cabecera del Inicio móvil: fecha, saludo grande y avatar rosa.
class SlushMobileGreeting extends StatelessWidget {
  const SlushMobileGreeting({
    super.key,
    required this.name,
    required this.onProfile,
    this.avatar,
    this.now,
  });
  final String name;
  final Uint8List? avatar;
  final void Function(BuildContext anchor) onProfile;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final t = now ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  slushDateLine(t),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: p.ink2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slushGreeting(t, name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: slushHeadline(34, height: 1.05, color: p.ink),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(right: 3, bottom: 3),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: p.shadowsFor(SlushElevation.card),
              ),
              child: SlushProfileButton(
                avatar: avatar,
                onProfile: onProfile,
                initial: name.trim().isEmpty
                    ? null
                    : name.trim().characters.first.toUpperCase(),
                size: 52,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Trama de puntos (22 px) del fondo de Slush 2.0; un solo `CustomPaint`
/// dentro de `RepaintBoundary`, no se repinta al cambiar el contenido.
class SlushDotBackdrop extends StatelessWidget {
  const SlushDotBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DotsPainter(
                  p.ink.withValues(alpha: dark ? .07 : .13),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[
      for (var y = 11.0; y < size.height; y += 22)
        for (var x = 11.0; x < size.width; x += 22) Offset(x, y),
    ];
    canvas.drawPoints(
      PointMode.points,
      pts,
      Paint()
        ..color = color
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}
