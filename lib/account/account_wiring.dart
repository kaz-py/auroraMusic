import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../app_controller.dart';
import 'account_service.dart';
import 'sync_service.dart';

/// Crea cuenta + sincronización y las enlaza al controlador: con sesión, el
/// nombre mostrado es el usuario y el avatar de la nube sustituye al local.
Future<void> connectAccount(AppController c) async {
  // Servicios en línea desactivados (kSupabaseEnabled): no se crea ni el
  // cliente de Supabase; el resto de Aurora no depende de ello.
  if (!c.online.enabled) return;
  final accounts = AccountService();
  final sync = SyncService(
    accounts: accounts,
    database: c.database,
    preferences: c.preferences,
    onPulled: c.reloadLibrary,
  );
  c.accounts = accounts;
  c.sync = sync;
  String? lastAvatar;
  accounts.addListener(() {
    final p = accounts.profile;
    if (p == null) return;
    if (p.username.isNotEmpty) unawaited(c.setProfileName(p.username));
    final url = p.avatarUrl;
    if (url != null && url != lastAvatar) {
      lastAvatar = url;
      unawaited(
        _downloadAvatar(
          url,
        ).then((b) => b == null ? null : c.setProfileAvatar(b)),
      );
    }
  });
  // Nada de esto espera a la red: sin servidor (proyecto pausado, sin cuota o
  // sin conexión) Aurora arranca igual y lo reintenta sola cuando vuelva.
  Future<void> connect() async {
    if (!await c.online.available()) return;
    await accounts.init().timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    sync.start();
  }

  c.online.onRecovered(() => unawaited(connect()));
  unawaited(connect());
}

/// Descarga el PNG público del avatar (solo https, ≤ 64 KiB).
Future<Uint8List?> _downloadAvatar(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return null;
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final res = await (await http.getUrl(
      uri,
    )).close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200 || res.contentLength > 65536) return null;
    final out = BytesBuilder(copy: false);
    await for (final chunk in res) {
      out.add(chunk);
      if (out.length > 65536) return null;
    }
    return out.takeBytes();
  } catch (_) {
    return null;
  } finally {
    http.close(force: true);
  }
}
