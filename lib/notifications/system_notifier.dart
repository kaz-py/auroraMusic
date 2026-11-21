import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../friends/friends_service.dart';

/// Texto del aviso de un amigo (el mismo para la barra interna y el sistema).
String friendsNoticeMessage(FriendsNotice n) => switch (n.kind) {
  FriendsNoticeKind.share => '${n.username} te envió una canción',
  FriendsNoticeKind.playlist => '${n.username} te envió una lista',
  FriendsNoticeKind.jam => '${n.username} te invita a su Jam',
  FriendsNoticeKind.request => '${n.username} quiere ser tu amigo',
};

/// Notificaciones del sistema (Windows, Android, Linux) para cuando la app está
/// abierta pero no a la vista. Con la app cerrada no llega nada: haría falta un
/// servicio de «push» externo.
class SystemNotifier {
  SystemNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static bool get supported =>
      Platform.isWindows || Platform.isAndroid || Platform.isLinux;

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  /// Al tocar un aviso: el `payload` es el id del amigo (vacío en solicitudes).
  void Function(String? payload)? onTap;

  static const _channel = AndroidNotificationDetails(
    'friends',
    'Amigos',
    channelDescription: 'Canciones, listas e invitaciones que te envían',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<bool> _init() => _ready ??= () async {
    if (!supported) return false;
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
          windows: WindowsInitializationSettings(
            appName: 'Aurora',
            appUserModelId: 'com.aurora.AuroraMusic',
            guid: '6c0f5a7e-3b1d-4f0e-9a52-7d8e1b4c2f90',
          ),
        ),
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
      );
      if (ok == false) return false;
      if (Platform.isAndroid) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (_) {
      return false; // sin notificaciones del sistema: queda el aviso interno
    }
  }();

  /// `false` si no se pudo mostrar (plataforma sin soporte, permiso denegado…).
  Future<bool> showFriend(FriendsNotice n) async {
    if (!await _init()) return false;
    try {
      await _plugin.show(
        id: n.hashCode & 0x7fffffff,
        title: 'Aurora',
        body: friendsNoticeMessage(n),
        notificationDetails: const NotificationDetails(
          android: _channel,
          linux: LinuxNotificationDetails(),
        ),
        payload: n.peerId ?? '',
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
