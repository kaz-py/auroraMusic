import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../account/account_avatar.dart';

/// Entrada del menú de perfil: a qué categoría de Ajustes lleva y, si aplica,
/// qué sección se despliega. [tab] null = «Ajustes» tal como se dejó.
typedef ProfileMenuEntry = ({
  IconData icon,
  String label,
  int? tab,
  String? section,
});

/// Categorías de Ajustes por índice (ver `_settingsTabs` en el shell).
const profileMenuEntries = <ProfileMenuEntry>[
  (
    icon: Icons.person_outline_rounded,
    label: 'Perfil',
    tab: 3,
    section: 'Perfil',
  ),
  (icon: Icons.tune_rounded, label: 'Ajustes', tab: null, section: null),
  (
    icon: Icons.manage_accounts_outlined,
    label: 'Cuenta y servicios',
    tab: 3,
    section: 'Cuenta',
  ),
  (icon: Icons.palette_outlined, label: 'Apariencia', tab: 0, section: null),
  (
    icon: Icons.play_circle_outline,
    label: 'Reproducción',
    tab: 1,
    section: null,
  ),
  (
    icon: Icons.mic_none_rounded,
    label: 'Comandos de voz',
    tab: 4,
    section: 'Comandos de voz',
  ),
  (
    icon: Icons.info_outline_rounded,
    label: 'Acerca de',
    tab: 5,
    section: 'Acerca de',
  ),
];

/// Menú anclado a la foto de perfil, al estilo del panel de usuario de
/// Discord o del menú de cuenta de Spotify: cabecera con foto y nombre, y
/// saltos directos a cada categoría de Ajustes.
Future<void> showProfileMenu(
  BuildContext anchor, {
  required String name,
  required String status,
  required Uint8List? avatar,
  required void Function(ProfileMenuEntry entry) onSelected,
}) async {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null || !box.attached) return;
  final position = RelativeRect.fromRect(
    Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    ),
    Offset.zero & overlay.size,
  );
  final theme = Theme.of(anchor);
  final picked = await showMenu<int>(
    context: anchor,
    position: position,
    constraints: const BoxConstraints(minWidth: 280, maxWidth: 280),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    items: [
      PopupMenuItem<int>(
        enabled: false,
        height: 72,
        child: Row(
          key: const ValueKey('profile-menu-header'),
          children: [
            AccountAvatar(bytes: avatar, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(),
      for (var i = 0; i < profileMenuEntries.length; i++) ...[
        if (i == profileMenuEntries.length - 1) const PopupMenuDivider(),
        PopupMenuItem<int>(
          value: i,
          child: Row(
            children: [
              Icon(profileMenuEntries[i].icon, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(profileMenuEntries[i].label)),
            ],
          ),
        ),
      ],
    ],
  );
  if (picked != null) onSelected(profileMenuEntries[picked]);
}
