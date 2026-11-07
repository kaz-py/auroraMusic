import '../friends_page.dart';
import '../../theme/slush_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../studio/studio_components.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../undo_snackbar.dart';
import 'jam_qr_code.dart';
import 'jam_session_panel.dart';
import 'jam_widgets.dart';

void _say(BuildContext context, String text) =>
    showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));

/// Inicia una Jam con un toque: en línea si hay servidor, si no en la red local.
/// Al terminar abre «Invitar»; [seed] añade esas canciones a la cola.
Future<void> startJamFlow(
  BuildContext context,
  JamController jam, {
  List<Track> seed = const [],
  String? name,
}) async {
  if (!jam.service.connected) {
    if (jam.remoteAvailable) {
      await jam.hostOnline(name);
    } else {
      await jam.loadAddresses();
      if (jam.addresses.isNotEmpty) await jam.host(jam.addresses.first, name);
    }
  }
  if (!context.mounted) return;
  if (!jam.service.connected) {
    _say(
      context,
      jam.error ?? 'No se pudo iniciar la Jam. Inténtalo de nuevo.',
    );
    return;
  }
  if (seed.isNotEmpty) jam.addTracks(seed);
  await showJamInviteSheet(context, jam);
}

/// «Invitar a un amigo»: solo con sesión y una Jam en línea (con código).
class JamInviteFriendButton extends StatelessWidget {
  const JamInviteFriendButton({super.key, required this.jam, this.style});
  final JamController jam;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final invite = jam.service.invite;
    if (invite == null || !invite.isRemote || !jam.active) {
      return const SizedBox.shrink();
    }
    return FriendsGate(
      builder: (context, f) => OutlinedButton.icon(
        key: const ValueKey('jam-invite-friend'),
        style: style,
        onPressed: () => showInviteFriendToJamSheet(context, f, invite.code),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Invitar a un amigo'),
      ),
    );
  }
}

Future<void> showJamInviteSheet(BuildContext context, JamController jam) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: jamSheetShape(context),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => _InviteSheet(jam: jam),
    );

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.jam});
  final JamController jam;
  @override
  Widget build(BuildContext context) {
    final invite = jam.service.invite;
    final remote = invite?.isRemote == true;
    final colors = Theme.of(context).colorScheme;
    final brasa = isBrasa(context);
    final modern = isModern(context);
    final slush = isSlush(context);
    // En la tarjeta oscura de Modern el texto va en blanco y los botones invertidos.
    // En Slush la tarjeta es violeta (blanco 6,5:1; white70 no llega a 4,5:1).
    final soft = slush
        ? Slush.onViolet
        : modern
        ? Colors.white70
        : colors.onSurfaceVariant;
    final onCard = modern
        ? TextStyle(color: slush ? Slush.onViolet : Colors.white)
        : const TextStyle();
    final inverse = FilledButton.styleFrom(
      backgroundColor: Colors.white,
      foregroundColor: Tracky.navy,
    );
    // Slush rellena el OutlinedButton de papel: sus botones llevan el
    // anillo de foco blanco propio de la tarjeta violeta.
    final ghost = slush
        ? jamOnVioletButton(context)
        : OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            overlayColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          );
    Future<void> copy(String text, String done) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _say(context, done);
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Invitar a la Jam',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Escanea el código QR o comparte el código. Todos pueden añadir canciones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (invite == null)
              const Text('Aún no hay una Jam activa.')
            else
              _card(modern, brasa, [
                slush
                    ? slushQrFrame(
                        context,
                        JamQrCode(data: invite.encode(), size: 200),
                      )
                    : JamQrCode(data: invite.encode(), size: 200),
                const SizedBox(height: 16),
                if (remote) ...[
                  modern || brasa
                      ? Text(
                          'CÓDIGO',
                          style: TextStyle(
                            fontSize: slush ? 12 : 11,
                            fontWeight: slush
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: soft,
                          ),
                        )
                      : const StudioStamp('CÓDIGO'),
                  SelectableText(
                    invite.code,
                    style: slush
                        ? jamCodeStyle(32, color: Slush.onViolet, spacing: 4)
                        : TextStyle(
                            fontFamily: modern || brasa ? null : 'monospace',
                            fontSize: brasa ? 24 : 32,
                            letterSpacing: brasa ? 2 : 6,
                            fontWeight: FontWeight.w700,
                            color: modern ? Colors.white : null,
                          ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    invite.encode(),
                    style: TextStyle(fontSize: 12, color: soft),
                  ),
                ] else
                  Text(
                    'Red local · ${invite.endpoint}',
                    style: onCard.copyWith(color: soft),
                  ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (remote)
                      OutlinedButton.icon(
                        style: modern ? ghost : null,
                        onPressed: () => copy(invite.code, 'Código copiado.'),
                        icon: const Icon(Icons.tag),
                        label: const Text('Copiar código'),
                      ),
                    JamInviteFriendButton(
                      jam: jam,
                      style: modern ? ghost : null,
                    ),
                    FilledButton.icon(
                      style: slush
                          ? jamOnVioletButton(context)
                          : modern
                          ? inverse
                          : null,
                      onPressed: () => copy(
                        remote
                            ? 'Únete a mi Jam en Aurora: ${invite.encode()} (código ${invite.code})'
                            : invite.encode(),
                        'Invitación copiada. Compártela solo con quien quieras.',
                      ),
                      icon: const Icon(Icons.ios_share),
                      label: Text(
                        remote ? 'Compartir enlace' : 'Copiar invitación',
                      ),
                    ),
                  ],
                ),
                if (!remote) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Red local: los dispositivos deben estar en el mismo Wi-Fi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: soft),
                  ),
                ],
              ]),
          ],
        ),
      ),
    );
  }

  Widget _card(bool modern, bool brasa, List<Widget> children) {
    final column = Column(mainAxisSize: MainAxisSize.min, children: children);
    if (brasa) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Brasa.obsidian,
          borderRadius: BorderRadius.circular(6),
          boxShadow: Brasa.cardShadow,
        ),
        child: column,
      );
    }
    return modern
        ? ModernCard(dark: true, feature: true, child: column)
        : column;
  }
}

/// Panel de la Jam: lateral en escritorio, hoja inferior en móvil.
Future<void> showJamPanel(BuildContext context, JamController jam) {
  final wide = Breakpoints.isWide(MediaQuery.sizeOf(context).width);
  final slush = isSlush(context);
  if (!wide) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      shape: jamSheetShape(context),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, scroll) =>
            JamSessionPanel(controller: jam, scroll: scroll),
      ),
    );
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar panel de la Jam',
    transitionDuration: slush
        ? SlushMotion.sheetIn
        : const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 440,
        height: double.infinity,
        child: Material(
          color: slush
              ? context.slush.raised
              : Theme.of(context).colorScheme.surface,
          shape: slush ? Border(left: context.slush.borderSoft) : null,
          child: SafeArea(child: JamSessionPanel(controller: jam)),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      if (slush && SlushMotion.reduce(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: animation,
            curve: slush ? SlushMotion.drawer : Curves.easeOutCubic,
          ),
        ),
        child: child,
      );
    },
  );
}
