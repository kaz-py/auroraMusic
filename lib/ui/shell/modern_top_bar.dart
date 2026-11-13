/// Barra superior de escritorio del tema Modern: fina y transparente sobre el
/// aura (arrastre de ventana, búsqueda, chip de Jam, perfil y controles de
/// ventana). Dueño: tema Modern.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/window_controls.dart';
import '../../theme/modern_cristal.dart';
import '../studio/studio_components.dart';
import '../studio/studio_symbols.dart';

class ModernTopBar extends StatelessWidget {
  const ModernTopBar({
    super.key,
    required this.onNavigate,
    required this.sessionText,
    this.activeSession = false,
    this.onSession,
    this.searchController,
    this.searchFocus,
    this.onSearch,
    this.onSearchChanged,
    this.searchHint = '',
    this.avatar,
    this.onProfile,
  });

  final ValueChanged<int> onNavigate;
  final String sessionText;
  final bool activeSession;
  final VoidCallback? onSession;

  /// Sin controlador no hay campo de búsqueda (la página Buscar tiene el suyo).
  final TextEditingController? searchController;
  final FocusNode? searchFocus;
  final ValueChanged<String>? onSearch, onSearchChanged;

  /// Atajo de enfocar la búsqueda, como pista en el campo.
  final String searchHint;
  final Uint8List? avatar;
  final void Function(BuildContext anchor)? onProfile;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    return LayoutBuilder(
      builder: (context, box) {
        final showJam = box.maxWidth > 700 && !largeText;
        final drag = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => WindowControls.invoke('drag'),
          onDoubleTap: () => WindowControls.invoke('maximize'),
          child: const SizedBox.expand(),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
          child: SizedBox(
            height: largeText ? 56 : 44,
            child: Row(
              children: [
                if (searchController != null && box.maxWidth > 560)
                  Flexible(
                    flex: 0,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: _SearchPill(
                        controller: searchController!,
                        focus: searchFocus,
                        onSearch: onSearch,
                        onChanged: onSearchChanged,
                        hint: searchHint,
                      ),
                    ),
                  ),
                Expanded(child: drag),
                if (showJam)
                  _JamChip(
                    text: sessionText,
                    active: activeSession,
                    onTap: onSession ?? () => onNavigate(9),
                  ),
                const SizedBox(width: 12),
                Builder(
                  builder: (ctx) => Tooltip(
                    message: 'Perfil y ajustes',
                    child: InkResponse(
                      radius: 22,
                      onTap: () =>
                          onProfile == null ? onNavigate(7) : onProfile!(ctx),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.accentSoft,
                          border: Border.all(color: c.border),
                        ),
                        child: avatar == null
                            ? Icon(
                                StudioSymbols.person,
                                size: 18,
                                color: c.accent,
                              )
                            : ClipOval(
                                child: Image.memory(
                                  avatar!,
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  cacheWidth: 108,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, _, _) => Icon(
                                    StudioSymbols.person,
                                    size: 18,
                                    color: c.accent,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                if (WindowControls.supported) ...[
                  const SizedBox(width: 8),
                  for (final item in [
                    ('minimize', StudioSymbols.minimize, 'Minimizar'),
                    (
                      'maximize',
                      StudioSymbols.checkBoxOutlineBlank,
                      'Maximizar o restaurar',
                    ),
                    ('close', StudioSymbols.close, 'Cerrar ventana'),
                  ])
                    IconButton(
                      tooltip: item.$3,
                      visualDensity: VisualDensity.compact,
                      color: c.text2,
                      onPressed: () async {
                        if (!await WindowControls.invoke(item.$1) &&
                            context.mounted) {
                          showStudioPending(
                            context,
                            'Control de ventana Windows',
                          );
                        }
                      },
                      icon: Icon(item.$2, size: 15),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({
    required this.controller,
    required this.focus,
    required this.onSearch,
    required this.onChanged,
    required this.hint,
  });

  final TextEditingController controller;
  final FocusNode? focus;
  final ValueChanged<String>? onSearch, onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return ModernGlass(
      radius: 999,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            const SizedBox(width: 14),
            Icon(StudioSymbols.search, size: 16, color: c.text3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                textInputAction: TextInputAction.search,
                onSubmitted: onSearch,
                onChanged: onChanged,
                style: Cristal.ui(13.5, color: c.text),
                cursorColor: c.accent,
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  hintText: 'Buscar canciones, artistas…',
                  hintStyle: Cristal.ui(13.5, color: c.text3),
                ),
              ),
            ),
            if (hint.isNotEmpty) ...[
              Text(hint, style: Cristal.mono(10.5, color: c.text3)),
              const SizedBox(width: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _JamChip extends StatelessWidget {
  const _JamChip({
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final color = active ? c.signal : c.text2;
    return Material(
      color: active ? c.signalFill : c.glass,
      shape: StadiumBorder(
        side: BorderSide(color: active ? c.signalBorder : c.border),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? c.signal : c.text3,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Cristal.mono(
                  10.5,
                  weight: 600,
                  color: color,
                  tracking: .08,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
