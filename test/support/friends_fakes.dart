import 'package:aurora_music/friends/friends_data.dart';
import 'package:aurora_music/friends/friends_service.dart';
import 'package:flutter/foundation.dart';

class FakeAuth extends ChangeNotifier {
  String? uid;
  void set(String? v) {
    uid = v;
    notifyListeners();
  }
}

/// Capa de datos falsa. Aplica el filtro de las RLS de `shared_tracks`
/// (filas donde soy remitente o destinatario) pero no la caducidad de las Jams.
class FakeData implements FriendsData {
  FakeData(this.me);
  final String me;
  final profiles = <String, Map<String, dynamic>>{
    'u1': {'id': 'u1', 'username': 'ana', 'avatar_path': null},
    'u2': {'id': 'u2', 'username': 'beto', 'avatar_path': null},
    'u3': {'id': 'u3', 'username': 'carla', 'avatar_path': null},
  };
  final requests = <Map<String, dynamic>>[];
  final shares = <Map<String, dynamic>>[];
  void Function(String, Map<String, dynamic>)? onRequest;
  void Function(Map<String, dynamic>)? onShare;
  bool unsubscribed = false;
  Map<String, Object?>? lastTrack;
  String? lastKind;

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String prefix, {
    required String excludeId,
    int limit = 20,
  }) async => [
    for (final p in profiles.values)
      if ((p['username'] as String).startsWith(prefix) && p['id'] != excludeId)
        p,
  ];
  @override
  Future<List<Map<String, dynamic>>> profilesByIds(List<String> ids) async => [
    for (final i in ids)
      if (profiles[i] != null) profiles[i]!,
  ];
  @override
  Future<List<Map<String, dynamic>>> listRequests() async => [...requests];
  @override
  Future<void> insertRequest(String toId) async => requests.add({
    'id': 'r${requests.length}',
    'from_id': me,
    'to_id': toId,
    'status': 'pending',
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });
  @override
  Future<void> setRequestStatus(String id, String status) async =>
      requests.firstWhere((r) => r['id'] == id)['status'] = status;
  @override
  Future<void> deleteRequest(String id) async =>
      requests.removeWhere((r) => r['id'] == id);
  @override
  Future<void> insertShare(
    String toId,
    String kind,
    Map<String, Object?> payload,
    String? note,
  ) async {
    lastKind = kind;
    lastTrack = payload;
    shares.add({
      'id': 'm${shares.length}',
      'from_id': me,
      'to_id': toId,
      'kind': kind,
      'track': payload,
      'note': note,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'seen': false,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> listShares({
    required int limit,
    DateTime? before,
    String? peer,
  }) async {
    final rows = [
      for (final s in shares)
        if ((s['from_id'] == me || s['to_id'] == me) &&
            (peer == null || s['from_id'] == peer || s['to_id'] == peer) &&
            (before == null ||
                DateTime.parse(s['created_at'] as String).isBefore(before)))
          s,
    ]..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at']));
    return rows.take(limit).toList();
  }

  @override
  Future<void> markSeen(List<String> ids) async {
    for (final s in shares) {
      if (ids.contains(s['id'])) s['seen'] = true;
    }
  }

  /// Como el servidor: solo cuentan los recibidos.
  @override
  Future<int> countUnseen() async =>
      shares.where((s) => s['to_id'] == me && s['seen'] != true).length;
  @override
  Future<Future<void> Function()> subscribe({
    required void Function(String, Map<String, dynamic>) onRequest,
    required void Function(Map<String, dynamic>) onShare,
  }) async {
    this.onRequest = onRequest;
    this.onShare = onShare;
    return () async => unsubscribed = true;
  }
}

Map<String, dynamic> share(int i, {String from = 'u1', bool seen = false}) => {
  'id': 's$i',
  'from_id': from,
  'to_id': 'me',
  'track': {'id': 'v$i', 'title': 'Canción $i', 'artist': 'Artista'},
  'note': i == 0 ? 'Escúchala' : null,
  'created_at': DateTime.utc(2026, 1, 1, 0, i).toIso8601String(),
  'seen': seen,
};

Map<String, dynamic> req(String id, String from, String to, String status) => {
  'id': id,
  'from_id': from,
  'to_id': to,
  'status': status,
  'created_at': DateTime.now().toUtc().toIso8601String(),
};

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Servicio ya con sesión (`me`), amigos y envíos en los dos sentidos:
/// ana (u1) y beto (u2) son amigos, carla (u3) solo tiene una solicitud
/// pendiente. Los envíos con ana: recibida (hace 6 min), enviada (4),
/// lista (3) e invitación a Jam (1); con beto, una recibida (10).
FriendsService seededFriendsService({DateTime? now}) {
  final t = now ?? DateTime.now();
  String ago(int minutes) =>
      t.subtract(Duration(minutes: minutes)).toUtc().toIso8601String();
  final auth = FakeAuth();
  final data = FakeData('me');
  data.requests
    ..add(req('a', 'u1', 'me', 'accepted'))
    ..add(req('b', 'me', 'u2', 'accepted'))
    ..add(req('c', 'u3', 'me', 'pending'));
  data.shares
    ..add({...share(1), 'note': 'Escúchala', 'created_at': ago(6)})
    ..add({
      'id': 's2',
      'from_id': 'me',
      'to_id': 'u1',
      'kind': 'track',
      'track': {'id': 'v2', 'title': 'Canción 2', 'artist': 'Artista'},
      'note': 'Te va a gustar',
      'created_at': ago(4),
      'seen': false,
    })
    ..add({
      ...share(3),
      'kind': 'playlist',
      'created_at': ago(3),
      'track': {
        'name': 'Mix de ana',
        'tracks': [
          {'id': 'a', 'title': 'T', 'artist': 'A'},
        ],
      },
    })
    ..add({
      ...share(4),
      'kind': 'jam',
      'created_at': ago(1),
      'track': {'code': 'ABCD2345'},
    })
    ..add({...share(5, from: 'u2'), 'created_at': ago(10)});
  auth.uid = 'me';
  return FriendsService(
    auth: auth,
    currentUid: () => auth.uid,
    dataFor: (_) => data,
    avatarUrl: (_) => null,
  );
}
