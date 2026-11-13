/// Cabeceras y aviso de error del chrome Modern: titular de página interior,
/// saludo móvil de Inicio y banner de cristal. Dueño: tema Modern.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/modern_cristal.dart';
import 'shell_chrome.dart';
import 'shell_sections.dart';

/// Nombre de la página: lista abierta de Biblioteca o título de la sección.
String modernPageTitle(ShellScope scope) =>
    (scope.playlist == null
        ? null
        : scope.controller.playlists
              .where((p) => p.id == scope.playlist!.id)
              .firstOrNull
              ?.name) ??
    shellSectionTitles[scope.section]!;

/// Titular de página interior (escritorio y móvil).
class ModernPageHeader extends StatelessWidget {
  const ModernPageHeader({super.key, required this.scope});
  final ShellScope scope;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final rail = scope.rail;
    final c0 = scope.controller;
    return Padding(
      padding: rail
          ? const EdgeInsets.fromLTRB(32, 12, 32, 16)
          : const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              modernPageTitle(scope),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Cristal.ui(
                rail ? 28 : 24,
                weight: 800,
                color: c.text,
                tracking: -.03,
                height: 1.15,
              ),
            ),
          ),
          if (rail)
            IconButton(
              tooltip: 'Importar archivos de audio',
              color: c.text2,
              onPressed: c0.ready ? c0.importFiles : null,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          if (!rail && scope.section != 1)
            IconButton(
              tooltip: 'Buscar música',
              color: c.text2,
              onPressed: () => scope.onNavigate(1),
              icon: const Icon(Icons.search),
            ),
        ],
      ),
    );
  }
}

/// Saludo móvil de Inicio: avatar, día/franja, «Buenas noches, Pablo» y
/// botón de búsqueda de cristal.
class ModernGreetingHeader extends StatelessWidget {
  const ModernGreetingHeader({super.key, required this.scope});
  final ShellScope scope;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final now = DateTime.now();
    final name = scope.controller.profileName;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 8),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => Tooltip(
              message: 'Perfil y ajustes',
              child: InkResponse(
                radius: 30,
                onTap: () => scope.onProfile(ctx),
                child: _Avatar(
                  bytes: scope.avatar,
                  initial: name.trim().isEmpty
                      ? null
                      : name.trim().characters.first.toUpperCase(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ModernLabel(modernDayPart(now)),
                const SizedBox(height: 2),
                Text(
                  modernGreeting(now, name),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Cristal.ui(
                    24,
                    weight: 800,
                    color: c.text,
                    tracking: -.03,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Buscar música',
            child: Material(
              color: c.glass,
              shape: CircleBorder(side: BorderSide(color: c.border)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => scope.onNavigate(1),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(Icons.search, color: c.text),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.bytes, required this.initial});
  final Uint8List? bytes;
  final String? initial;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.signal, c.accent],
        ),
      ),
      child: Center(
        child: initial == null
            ? Icon(Icons.person_outline, color: c.onAccent, size: 24)
            : Text(
                initial!,
                style: Cristal.ui(18, weight: 800, color: c.onAccent),
              ),
      ),
    );
    return SizedBox(
      width: 48,
      height: 48,
      child: bytes == null
          ? fallback
          : ClipOval(
              child: Image.memory(
                bytes!,
                fit: BoxFit.cover,
                cacheWidth: 144,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

/// Aviso de error del controlador: cristal con borde coral.
class ModernGlassBanner extends StatelessWidget {
  const ModernGlassBanner({super.key, required this.message, this.onClose});
  final String message;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = Cristal.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: ModernGlass(
        radius: 16,
        fill: Color.alphaBlend(c.like.withValues(alpha: .14), c.glass),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: c.like, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(message, style: Cristal.ui(13.5, color: c.text)),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar aviso',
                color: c.text2,
                onPressed: onClose,
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
