import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../ui/undo_snackbar.dart';
import 'account_avatar.dart';
import 'account_service.dart';

String syncAgo(DateTime? at, [DateTime? now]) {
  if (at == null) return 'Aún sin sincronizar';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inSeconds < 60) return 'Sincronizado hace un momento';
  if (d.inMinutes < 60) return 'Sincronizado hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'Sincronizado hace ${d.inHours} h';
  return 'Sincronizado hace ${d.inDays} d';
}

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key, required this.controller});
  final AppController controller;

  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  bool _creating = false, _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? ok}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (ok != null && mounted) _snack(ok);
      _password.clear();
    } on AccountException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'No se pudo completar la operación.';
    }
    if (mounted) setState(() => _busy = false);
  }

  void _snack(String text) =>
      showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));

  Future<void> _changeAvatar(AccountService accounts) async {
    final c = widget.controller;
    final before = c.profileAvatar;
    final error = await c.pickProfileAvatar();
    if (error != null) return _snack(error);
    final after = c.profileAvatar;
    if (after == null || identical(after, before)) return;
    await _run(() => accounts.setAvatar(after));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final accounts = c.accounts;
    if (accounts == null || !accounts.available) {
      return const Text(
        'Las cuentas no están configuradas en esta compilación '
        '(AURORA_SUPABASE_URL y AURORA_SUPABASE_ANON_KEY).',
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([accounts, if (c.sync != null) c.sync!]),
      builder: (context, _) {
        final profile = accounts.profile;
        return profile == null
            ? _signedOut(accounts)
            : _signedIn(accounts, profile);
      },
    );
  }

  Widget _signedIn(AccountService accounts, AccountProfile profile) {
    final c = widget.controller;
    final sync = c.sync;
    final status = sync == null
        ? ''
        : sync.syncing
        ? 'Sincronizando…'
        : sync.lastError ?? syncAgo(sync.lastSync);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AccountAvatar(bytes: c.profileAvatar, radius: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.username,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(status, key: const ValueKey('account-status')),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: sync == null || sync.syncing ? null : sync.syncNow,
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Sincronizar ahora'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _changeAvatar(accounts),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('Cambiar foto'),
            ),
            OutlinedButton.icon(
              onPressed: _busy || c.profileAvatar == null
                  ? null
                  : () => _run(() async {
                      await accounts.removeAvatar();
                      await c.setProfileAvatar(null);
                    }),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Quitar foto'),
            ),
            FilledButton.icon(
              key: const ValueKey('account-sign-out'),
              onPressed: _busy ? null : () => _run(accounts.signOut),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
            ),
          ],
        ),
        if (_error != null) _errorText(),
      ],
    );
  }

  Widget _errorText() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      _error!,
      key: const ValueKey('account-error'),
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );

  Widget _signedOut(AccountService accounts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Entrar')),
            ButtonSegment(value: true, label: Text('Crear cuenta')),
          ],
          selected: {_creating},
          onSelectionChanged: (v) => setState(() {
            _creating = v.first;
            _error = null;
          }),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('account-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'Correo'),
        ),
        const SizedBox(height: 12),
        if (_creating) ...[
          TextField(
            key: const ValueKey('account-username'),
            controller: _username,
            maxLength: 24,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Usuario',
              helperText: 'Minúsculas, números, _ y .',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const ValueKey('account-password'),
          controller: _password,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            helperText: 'Mínimo 8 caracteres',
          ),
          onSubmitted: (_) => _submit(accounts),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('account-submit'),
              onPressed: _busy ? null : () => _submit(accounts),
              child: Text(_creating ? 'Crear cuenta' : 'Entrar'),
            ),
            if (!_creating)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => accounts.resetPassword(_email.text),
                        ok: 'Si el correo existe, recibirás un enlace.',
                      ),
                child: const Text('Olvidé mi contraseña'),
              ),
          ],
        ),
        if (_error != null) _errorText(),
      ],
    );
  }

  Future<void> _submit(AccountService accounts) => _run(
    () => _creating
        ? accounts.signUp(
            email: _email.text,
            password: _password.text,
            username: _username.text.trim().toLowerCase(),
          )
        : accounts.signIn(email: _email.text, password: _password.text),
  );
}
