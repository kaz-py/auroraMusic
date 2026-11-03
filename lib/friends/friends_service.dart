import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart' show PostgrestException;

import '../core/models.dart';
import '../jam/jam_models.dart' show jamNormalizeCode;
import 'friends_data.dart';

class FriendUser {
  const FriendUser({required this.id, required this.username, this.avatarUrl});
  final String id;
  final String username;
  final String? avatarUrl;
}

/// Solicitud vista desde mi lado: [user] es la otra persona.
class FriendRequestView {
  const FriendRequestView({
    required this.id,
    required this.user,
    required this.incoming,
    required this.status,
    required this.createdAt,
  });
  final String id;
  final FriendUser user;
  final bool incoming;
  final String status;
  final DateTime createdAt;
}

enum SharedKind { track, playlist, jam }

/// Playlist recibida (ya validada).
class SharedPlaylist {
  const SharedPlaylist({
    required this.name,
    required this.tracks,
    this.artworkUrl,
  });
  final String name;
  final List<Track> tracks;
  final String? artworkUrl;
}

/// Las invitaciones a una Jam caducan a las 2 h de enviarse.
const jamInviteTtl = Duration(hours: 2);
const maxSharedPlaylistTracks = 500;
const _maxPlaylistBytes = 240000;

class SharedItem {
  const SharedItem({
    required this.id,
    required this.peer,
    required this.mine,
    required this.track,
    required this.createdAt,
    required this.seen,
    this.note,
    this.kind = SharedKind.track,
    this.playlist,
    this.jamCode,
  });
  final String id;

  /// La otra persona de la conversación, sea quien sea el que envió.
  final FriendUser peer;

  /// Lo envié yo.
  final bool mine;

  /// Solo para [SharedKind.track]; en los demás es un marcador vacío.
  final Track track;
  final String? note;
  final DateTime createdAt;
  final bool seen;
  final SharedKind kind;
  final SharedPlaylist? playlist;
  final String? jamCode;

  bool jamExpired([DateTime? now]) =>
      (now ?? DateTime.now()).difference(createdAt) > jamInviteTtl;

  SharedItem withSeen() => SharedItem(
    id: id,
    peer: peer,
    mine: mine,
    track: track,
    createdAt: createdAt,
    seen: true,
    note: note,
    kind: kind,
    playlist: playlist,
    jamCode: jamCode,
  );
}

enum FriendsNoticeKind { request, share, playlist, jam }

class FriendsNotice {
  const FriendsNotice(this.kind, this.username, [this.peerId]);
  final FriendsNoticeKind kind;
  final String username;

  /// Amigo que envió (para abrir su chat); las solicitudes no lo llevan.
  final String? peerId;
}

/// Conversación con un amigo: último envío (cualquier sentido) y recibidos sin ver.
class FriendChat {
  const FriendChat({required this.peer, this.last, this.unseen = 0});
  final FriendUser peer;
  final SharedItem? last;
  final int unseen;
}

/// Ventana global de [FriendsService.refresh] y página de «anteriores».
const _recentSize = 100;
const _pageSize = 20;
const _maxNote = 200;

/// Amigos, solicitudes y canciones recibidas. Sin sesión no hace nada.
class FriendsService extends ChangeNotifier {
  FriendsService({
    required Listenable auth,
    required String? Function() currentUid,
    required FriendsData? Function(String uid) dataFor,
    required String? Function(String? avatarPath) avatarUrl,
  }) : _auth = auth,
       _uid = currentUid,
       _dataFor = dataFor,
       _avatarUrl = avatarUrl {
    _auth.addListener(_onAuth);
    _onAuth();
  }

  final Listenable _auth;
  final String? Function() _uid;
  final FriendsData? Function(String uid) _dataFor;
  final String? Function(String?) _avatarUrl;

  String? _boundUid;
  FriendsData? _data;
  Future<void> Function()? _unsubscribe;
  int _epoch = 0;
  bool _disposed = false;
  final _notices = StreamController<FriendsNotice>.broadcast();
  final _profiles = <String, FriendUser>{};

  List<FriendUser> friends = const [];
  List<FriendRequestView> incoming = const [];
  List<FriendRequestView> outgoing = const [];

  /// Envíos en los dos sentidos, del más nuevo al más viejo.
  List<SharedItem> messages = const [];
  bool _allLoaded = false;
  final _threadDone = <String>{};
  final _loadingOlder = <String>{};
  bool loading = false;
  int unseenCount = 0;

  Stream<FriendsNotice> get notices => _notices.stream;
  bool get signedIn => _boundUid != null;

  void _onAuth() {
    final uid = _uid();
    if (uid == _boundUid) return;
    _teardown();
    _boundUid = uid;
    _data = uid == null ? null : _dataFor(uid);
    if (_data == null) {
      _boundUid = null;
      _notify();
      return;
    }
    unawaited(refresh());
    unawaited(_listen(_epoch));
  }

  void _teardown() {
    _epoch++;
    final off = _unsubscribe;
    _unsubscribe = null;
    if (off != null) unawaited(off().catchError((Object _) {}));
    _profiles.clear();
    friends = const [];
    incoming = outgoing = const [];
    messages = const [];
    _allLoaded = false;
    _threadDone.clear();
    _loadingOlder.clear();
    unseenCount = 0;
    loading = false;
  }

  Future<void> _listen(int epoch) async {
    try {
      final off = await _data!.subscribe(
        onRequest: (event, row) => _onRequestEvent(epoch, event, row),
        onShare: (row) => _onShare(epoch, row),
      );
      if (epoch != _epoch) {
        unawaited(off().catchError((Object _) {}));
      } else {
        _unsubscribe = off;
      }
    } catch (_) {
      // Sin tiempo real sigue funcionando con refresh manual.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---- carga ----

  Future<void> refresh() async {
    final data = _data, epoch = _epoch, uid = _boundUid;
    if (data == null || uid == null) return;
    loading = true;
    _notify();
    try {
      await _loadRequests(data, uid, epoch);
      await _loadRecent(data, epoch);
      final unseen = await data.countUnseen();
      if (epoch == _epoch) unseenCount = unseen;
    } catch (_) {
      // Mantiene lo último que se tenía.
    }
    if (epoch == _epoch) loading = false;
    _notify();
  }

  Future<void> _ensureProfiles(FriendsData data, Iterable<String> ids) async {
    final missing = ids.where((i) => !_profiles.containsKey(i)).toSet();
    if (missing.isEmpty) return;
    for (final row in await data.profilesByIds(missing.toList())) {
      final user = _userFrom(row);
      if (user != null) _profiles[user.id] = user;
    }
  }

  FriendUser? _userFrom(Map<String, dynamic> row) {
    final id = row['id'];
    final name = row['username'];
    if (id is! String || name is! String) return null;
    return FriendUser(
      id: id,
      username: name,
      avatarUrl: _avatarUrl(row['avatar_path'] as String?),
    );
  }

  Future<void> _loadRequests(FriendsData data, String uid, int epoch) async {
    final rows = await data.listRequests();
    final others = [
      for (final r in rows) (r['from_id'] == uid ? r['to_id'] : r['from_id']),
    ].whereType<String>();
    await _ensureProfiles(data, others);
    if (epoch != _epoch) return;
    final f = <FriendUser>[];
    final inc = <FriendRequestView>[];
    final out = <FriendRequestView>[];
    for (final r in rows) {
      final mine = r['from_id'] == uid;
      final other = _profiles[(mine ? r['to_id'] : r['from_id']) as String?];
      final status = r['status'];
      final id = r['id'];
      if (other == null || status is! String || id is! String) continue;
      if (status == 'accepted') {
        f.add(other);
      } else if (status == 'pending') {
        final v = FriendRequestView(
          id: id,
          user: other,
          incoming: !mine,
          status: status,
          createdAt: _date(r['created_at']),
        );
        (mine ? out : inc).add(v);
      }
    }
    f.sort(
      (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
    );
    friends = f;
    incoming = inc;
    outgoing = out;
  }

  /// Id de la otra persona de una fila, sea quien sea el que envió.
  String? _otherId(Map<String, dynamic> r) {
    final other = r['from_id'] == _boundUid ? r['to_id'] : r['from_id'];
    return other is String ? other : null;
  }

  List<SharedItem> _sorted(Iterable<SharedItem> items) =>
      [...items]..sort((a, b) {
        final byDate = b.createdAt.compareTo(a.createdAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });

  /// Ventana global de los últimos [_recentSize] envíos. Lo cargado antes de
  /// ella (páginas «anteriores» de un hilo) se conserva.
  Future<void> _loadRecent(FriendsData data, int epoch) async {
    final rows = await data.listShares(limit: _recentSize);
    await _ensureProfiles(data, rows.map(_otherId).whereType<String>());
    if (epoch != _epoch) return;
    final items = [for (final r in rows) ?_itemFrom(r)];
    if (rows.length < _recentSize) {
      messages = items;
      _allLoaded = true;
      return;
    }
    _allLoaded = false;
    final cutoff = _date(rows.last['created_at']);
    messages = _sorted(
      {
        for (final i in messages)
          if (i.createdAt.isBefore(cutoff)) i.id: i,
        for (final i in items) i.id: i,
      }.values,
    );
  }

  /// Hilo con un amigo, del más nuevo al más viejo, sin Jams caducadas.
  List<SharedItem> threadWith(String peerId) => [
    for (final i in messages)
      if (i.peer.id == peerId && !(i.kind == SharedKind.jam && i.jamExpired()))
        i,
  ];

  bool hasOlderWith(String peerId) =>
      !_allLoaded && !_threadDone.contains(peerId);

  /// Carga una página más antigua del hilo con [peerId].
  Future<void> loadOlderWith(String peerId) async {
    final data = _data, epoch = _epoch;
    if (data == null || !hasOlderWith(peerId) || !_loadingOlder.add(peerId)) {
      return;
    }
    try {
      // `messages` va del más nuevo al más viejo: el último del amigo es el
      // más viejo (cuenta también las Jams caducadas).
      DateTime? before;
      for (final i in messages) {
        if (i.peer.id == peerId) before = i.createdAt;
      }
      final rows = await data.listShares(
        limit: _pageSize,
        peer: peerId,
        before: before,
      );
      await _ensureProfiles(data, rows.map(_otherId).whereType<String>());
      if (epoch != _epoch) return;
      final older = [for (final r in rows) ?_itemFrom(r)];
      messages = _sorted(
        {
          for (final i in messages) i.id: i,
          for (final i in older) i.id: i,
        }.values,
      );
      if (rows.length < _pageSize) _threadDone.add(peerId);
    } catch (_) {
      // El botón «Cargar anteriores» sigue disponible para reintentar.
    } finally {
      if (epoch == _epoch) {
        _loadingOlder.remove(peerId);
        _notify();
      }
    }
  }

  /// Una conversación por amigo: primero las que tienen envíos (la más
  /// reciente arriba), luego las vacías por nombre.
  List<FriendChat> get chats {
    final used = <FriendChat>[], empty = <FriendChat>[];
    for (final f in friends) {
      final thread = threadWith(f.id);
      final chat = FriendChat(
        peer: f,
        last: thread.firstOrNull,
        unseen: thread.where((i) => !i.mine && !i.seen).length,
      );
      (chat.last == null ? empty : used).add(chat);
    }
    used.sort((a, b) => b.last!.createdAt.compareTo(a.last!.createdAt));
    empty.sort(
      (a, b) => a.peer.username.toLowerCase().compareTo(
        b.peer.username.toLowerCase(),
      ),
    );
    return [...used, ...empty];
  }

  DateTime _date(Object? v) =>
      DateTime.tryParse('$v')?.toLocal() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  SharedItem? _itemFrom(Map<String, dynamic> r) {
    final mine = r['from_id'] == _boundUid;
    final peer = _profiles[_otherId(r)];
    final id = r['id'];
    if (peer == null || id is! String) return null;
    final kind = switch (r['kind']) {
      null || 'track' => SharedKind.track,
      'playlist' => SharedKind.playlist,
      'jam' => SharedKind.jam,
      _ => null,
    };
    if (kind == null) return null;
    final payload = r['track'];
    var track = const Track(id: '-', title: '', artist: '');
    SharedPlaylist? playlist;
    String? code;
    switch (kind) {
      case SharedKind.track:
        final t = trackFromShared(payload);
        if (t == null) return null;
        track = t;
      case SharedKind.playlist:
        playlist = playlistFromShared(payload);
        if (playlist == null) return null;
      case SharedKind.jam:
        code = jamCodeFromShared(payload);
        if (code == null) return null;
    }
    final note = r['note'];
    return SharedItem(
      id: id,
      peer: peer,
      mine: mine,
      track: track,
      kind: kind,
      playlist: playlist,
      jamCode: code,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      createdAt: _date(r['created_at']),
      seen: r['seen'] == true,
    );
  }

  // ---- tiempo real ----

  Future<void> _onRequestEvent(
    int epoch,
    String event,
    Map<String, dynamic> row,
  ) async {
    final data = _data, uid = _boundUid;
    if (epoch != _epoch || data == null || uid == null) return;
    try {
      await _loadRequests(data, uid, epoch);
      if (event == 'insert' && row['to_id'] == uid) {
        final name = _profiles[row['from_id']]?.username;
        if (name != null) _emit(FriendsNotice(FriendsNoticeKind.request, name));
      }
    } catch (_) {}
    _notify();
  }

  Future<void> _onShare(int epoch, Map<String, dynamic> row) async {
    final data = _data;
    if (epoch != _epoch || data == null) return;
    try {
      // Tiempo real solo trae lo dirigido a mí: el otro es `from_id`.
      await _ensureProfiles(data, [row['from_id']].whereType<String>());
      if (epoch != _epoch) return;
      final item = _itemFrom(row);
      if (item == null || messages.any((i) => i.id == item.id)) return;
      messages = _sorted([item, ...messages]);
      if (!item.seen) unseenCount++;
      _emit(
        FriendsNotice(
          switch (item.kind) {
            SharedKind.track => FriendsNoticeKind.share,
            SharedKind.playlist => FriendsNoticeKind.playlist,
            SharedKind.jam => FriendsNoticeKind.jam,
          },
          item.peer.username,
          item.peer.id,
        ),
      );
    } catch (_) {}
    _notify();
  }

  void _emit(FriendsNotice n) {
    if (!_notices.isClosed) _notices.add(n);
  }

  // ---- acciones (devuelven mensaje de error o null) ----

  Future<List<FriendUser>> searchUsers(String prefix) async {
    final q = prefix.trim();
    final data = _data, uid = _boundUid;
    if (q.length < 3 || data == null || uid == null) return const [];
    final rows = await data.searchProfiles(q, excludeId: uid);
    return [
      for (final r in rows) ?_userFrom(r),
    ].where((u) => u.id != uid).toList();
  }

  /// Estado de relación con [userId] para la búsqueda.
  String relationTo(String userId) {
    if (friends.any((u) => u.id == userId)) return 'friend';
    if (outgoing.any((r) => r.user.id == userId)) return 'sent';
    if (incoming.any((r) => r.user.id == userId)) return 'incoming';
    return 'none';
  }

  Future<String?> _run(Future<void> Function(FriendsData d) body) async {
    final data = _data;
    if (data == null) return 'Inicia sesión para usar Amigos.';
    try {
      await body(data);
      await refresh();
      return null;
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'Ya hay una solicitud con esa persona.';
      if (e.code == '42501') return 'No tienes permiso para hacer eso.';
      if (e.message.contains('Demasiados')) {
        return 'Demasiados envíos; prueba en un rato.';
      }
      return 'No se pudo completar. Inténtalo de nuevo.';
    } catch (_) {
      return 'Sin conexión. Inténtalo de nuevo.';
    }
  }

  Future<String?> sendRequest(String userId) {
    if (userId == _boundUid) {
      return Future.value('No puedes añadirte a ti mismo.');
    }
    return _run((d) => d.insertRequest(userId));
  }

  Future<String?> accept(String requestId) =>
      _run((d) => d.setRequestStatus(requestId, 'accepted'));

  Future<String?> decline(String requestId) =>
      _run((d) => d.setRequestStatus(requestId, 'declined'));

  /// Cancela una solicitud enviada.
  Future<String?> cancelRequest(String requestId) =>
      _run((d) => d.deleteRequest(requestId));

  Future<String?> removeFriend(String userId) async {
    // La fila de amistad se localiza entre las solicitudes aceptadas.
    return _run((d) async {
      final uid = _boundUid;
      final rows = await d.listRequests();
      for (final r in rows) {
        final pair = {r['from_id'], r['to_id']};
        if (r['status'] == 'accepted' && pair.containsAll([uid, userId])) {
          await d.deleteRequest(r['id'] as String);
        }
      }
    });
  }

  Future<String?> shareTrack(String friendId, Track track, {String? note}) {
    if (track.isLocal) {
      return Future.value('Las canciones locales no se pueden enviar.');
    }
    if (!friends.any((f) => f.id == friendId)) {
      return Future.value('Solo puedes enviar a tus amigos.');
    }
    return _run(
      (d) => d.insertShare(
        friendId,
        SharedKind.track.name,
        trackForShare(track),
        _cleanNote(note),
      ),
    );
  }

  String? _cleanNote(String? note) {
    final n = note?.trim();
    return n == null || n.isEmpty ? null : _cut(n, _maxNote);
  }

  /// Envía una copia de la playlist (sin pistas locales ni pendientes).
  Future<String?> sharePlaylist(
    String friendId,
    String name,
    List<Track> tracks, {
    String? note,
  }) {
    if (!friends.any((f) => f.id == friendId)) {
      return Future.value('Solo puedes enviar a tus amigos.');
    }
    final payload = playlistForShare(name, tracks);
    if (payload == null) {
      return Future.value(
        'La lista no tiene canciones que se puedan enviar (las locales no viajan).',
      );
    }
    return _run(
      (d) => d.insertShare(
        friendId,
        SharedKind.playlist.name,
        payload,
        _cleanNote(note),
      ),
    );
  }

  /// Invita a un amigo a la Jam [code] (solo código remoto válido).
  Future<String?> shareJamInvite(String friendId, String code) {
    final clean = jamNormalizeCode(code);
    if (clean == null) {
      return Future.value('Esta Jam no se puede compartir por código.');
    }
    if (!friends.any((f) => f.id == friendId)) {
      return Future.value('Solo puedes invitar a tus amigos.');
    }
    return _run(
      (d) =>
          d.insertShare(friendId, SharedKind.jam.name, {'code': clean}, null),
    );
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final data = _data;
    // Solo cuentan los recibidos: lo enviado nace «visto» para mí.
    final unseen = {
      for (final i in messages)
        if (!i.mine && !i.seen && ids.contains(i.id)) i.id,
    };
    if (data == null || unseen.isEmpty) return;
    messages = [
      for (final i in messages) unseen.contains(i.id) ? i.withSeen() : i,
    ];
    unseenCount = (unseenCount - unseen.length).clamp(0, 1 << 30);
    _notify();
    try {
      await data.markSeen(unseen.toList());
    } catch (_) {
      // El siguiente refresh reconcilia.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuth);
    _teardown();
    unawaited(_notices.close());
    super.dispose();
  }
}

/// JSON mínimo que viaja: sin ruta local ni estado interno.
Map<String, Object?> trackForShare(Track t) => {
  'id': t.id,
  'title': _cut(t.title, 200),
  'artist': _cut(t.artist, 200),
  'durationMs': t.duration.inMilliseconds,
  'artworkUrl': _httpOrNull(t.artworkUrl),
  'album': t.album == null ? null : _cut(t.album!, 200),
  'genres': t.genres.take(5).map((g) => _cut(g, 40)).toList(),
};

String _cut(String s, int n) => s.length > n ? s.substring(0, n) : s;

String? _httpOrNull(String? url) {
  final u = url == null ? null : Uri.tryParse(url);
  return u != null &&
          (u.scheme == 'https' || u.scheme == 'http') &&
          url!.length <= 1000
      ? url
      : null;
}

/// Reconstruye una pista recibida; es entrada no confiable, así que se valida
/// y se descartan campos peligrosos (ruta local, enlaces no http).
Track? trackFromShared(Object? json) {
  if (json is! Map) return null;
  final id = json['id'], title = json['title'], artist = json['artist'];
  if (id is! String || title is! String || artist is! String) return null;
  if (id.isEmpty || id.length > 64 || title.isEmpty) return null;
  final ms = json['durationMs'];
  return Track(
    id: id,
    title: _cut(title, 200),
    artist: _cut(artist, 200),
    duration: Duration(
      milliseconds: ms is num ? ms.toInt().clamp(0, 86400000) : 0,
    ),
    artworkUrl: _httpOrNull(json['artworkUrl'] as String?),
    album: json['album'] is String ? _cut(json['album'] as String, 200) : null,
    genres:
        (json['genres'] as List?)?.whereType<String>().take(5).toList() ??
        const [],
  );
}

/// JSON de una playlist para enviar; null si no queda ninguna pista válida
/// o el tamaño excede el límite.
Map<String, Object?>? playlistForShare(String name, List<Track> tracks) {
  final seen = <String>{};
  final list = <Map<String, Object?>>[];
  for (final t in tracks) {
    if (t.isLocal ||
        t.spotifyMatchPending ||
        t.id.isEmpty ||
        t.id.length > 64) {
      continue;
    }
    if (!seen.add(t.id)) continue;
    list.add(trackForShare(t));
    if (list.length >= maxSharedPlaylistTracks) break;
  }
  if (list.isEmpty) return null;
  final payload = <String, Object?>{
    'name': _cut(name.trim().isEmpty ? 'Playlist' : name.trim(), 100),
    'tracks': list,
  };
  return jsonEncode(payload).length > _maxPlaylistBytes ? null : payload;
}

/// Entrada no confiable: valida tipos, longitudes y que las pistas sean sanas.
SharedPlaylist? playlistFromShared(Object? json) {
  if (json is! Map) return null;
  final name = json['name'], raw = json['tracks'];
  if (name is! String || name.trim().isEmpty || raw is! List) return null;
  final seen = <String>{};
  final tracks = <Track>[];
  for (final item in raw.take(maxSharedPlaylistTracks)) {
    final t = trackFromShared(item);
    if (t != null && seen.add(t.id)) tracks.add(t);
  }
  if (tracks.isEmpty) return null;
  return SharedPlaylist(
    name: _cut(name.trim(), 100),
    tracks: tracks,
    artworkUrl: tracks.map((t) => t.artworkUrl).whereType<String>().firstOrNull,
  );
}

/// Código de Jam de una invitación recibida, o null si no es válido.
String? jamCodeFromShared(Object? json) {
  if (json is! Map) return null;
  final code = json['code'];
  return code is String ? jamNormalizeCode(code) : null;
}
