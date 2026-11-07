import 'package:flutter/material.dart';

import '../account/account_avatar.dart';
import '../app_controller.dart';
import '../ui/undo_snackbar.dart';

class ProfileSettings extends StatefulWidget {
  const ProfileSettings({super.key, required this.controller});
  final AppController controller;

  @override
  State<ProfileSettings> createState() => _ProfileSettingsState();
}

class _ProfileSettingsState extends State<ProfileSettings> {
  late final _name = TextEditingController(text: widget.controller.profileName);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.controller.setProfileName(_name.text);
    if (mounted && _name.text != widget.controller.profileName) {
      _name.text = widget.controller.profileName;
    }
  }

  Future<void> _pick() async {
    final error = await widget.controller.pickProfileAvatar();
    if (error != null && mounted) {
      showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final avatar = c.profileAvatar;
    final signedIn = c.accounts?.signedIn ?? false;
    if (signedIn && _name.text != c.profileName) _name.text = c.profileName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AccountAvatar(bytes: avatar, radius: 40),
            const SizedBox(width: 16),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('profile-choose-photo'),
                    onPressed: _pick,
                    icon: const Icon(Icons.photo_outlined),
                    label: const Text('Elegir foto'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('profile-remove-photo'),
                    onPressed: avatar == null
                        ? null
                        : () => c.setProfileAvatar(null),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Quitar foto'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('profile-name-field'),
          controller: _name,
          focusNode: _focus,
          maxLength: 24,
          enabled: !signedIn,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'Nombre de usuario'),
          onSubmitted: (_) => _save(),
        ),
        Text(
          signedIn
              ? 'Es el usuario de tu cuenta.'
              : 'Se muestra a los demás en la Jam.',
        ),
      ],
    );
  }
}
