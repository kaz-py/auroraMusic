import 'dart:async';

import 'package:supabase/supabase.dart';

/// Capa de datos de Amigos (filas crudas). La implementación real habla con
/// Supabase; los tests usan una falsa.
abstract class FriendsData {
  Future<List<Map<String, dynamic>>> searchProfiles(
    String prefix, {
    required String excludeId,
    int limit = 20,
  });
  Future<List<Map<String, dynamic>>> profilesByIds(List<String> ids);
  Future<List<Map<String, dynamic>>> listRequests();
  Future<void> insertRequest(String toId);
  Future<void> setRequestStatus(String id, String status);
  Future<void> deleteRequest(String id);
  Future<void> insertShare(
    String toId,
    String kind,
    Map<String, Object?> payload,
    String? note,
  );

  /// Envíos en los dos sentidos, del más nuevo al más viejo. Con [peer], solo
  /// los de esa conversación.
  Future<List<Map<String, dynamic>>> listShares({
    required int limit,
    DateTime? before,
    String? peer,
  });
  Future<void> markSeen(List<String> ids);
  Future<int> countUnseen();

  /// Escucha altas/cambios dirigidos a este usuario. [onRequest] se llama con
  /// (evento, fila) para solicitudes; [onShare] con la fila nueva. Devuelve la
  /// función que cierra el canal.
  Future<Future<void> Function()> subscribe({
    required void Function(String event, Map<String, dynamic> row) onRequest,
    required void Function(Map<String, dynamic> row) onShare,
  });
}

final _uuid = RegExp(r'^[0-9a-fA-F-]{36}$');

class SupabaseFriendsData implements FriendsData {
  SupabaseFriendsData(this._client, this._uid);
  final SupabaseClient _client;
  final String _uid;

  @override
  Future<List<Map<String, dynamic>>> searchProfiles(
    String prefix, {
    required String excludeId,
    int limit = 20,
  }) async {
    // Escapa los comodines de LIKE para que el prefijo sea literal.
    final safe = prefix.replaceAllMapped(RegExp(r'[\\%_]'), (m) => '\\${m[0]}');
    final rows = await _client
        .from('profiles')
        .select('id,username,avatar_path')
        .ilike('username', '$safe%')
        .neq('id', excludeId)
        .order('username')
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> profilesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _client
        .from('profiles')
        .select('id,username,avatar_path')
        .inFilter('id', ids);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<List<Map<String, dynamic>>> listRequests() async {
    final rows = await _client
        .from('friend_requests')
        .select()
        .order('created_at', ascending: false)
        .limit(500);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> insertRequest(String toId) => _client
      .from('friend_requests')
      .insert({'from_id': _uid, 'to_id': toId, 'status': 'pending'});

  @override
  Future<void> setRequestStatus(String id, String status) =>
      _client.from('friend_requests').update({'status': status}).eq('id', id);

  @override
  Future<void> deleteRequest(String id) =>
      _client.from('friend_requests').delete().eq('id', id);

  @override
  Future<void> insertShare(
    String toId,
    String kind,
    Map<String, Object?> payload,
    String? note,
  ) => _client.from('shared_tracks').insert({
    'from_id': _uid,
    'to_id': toId,
    'kind': kind,
    'track': payload,
    'note': note,
  });

  @override
  Future<List<Map<String, dynamic>>> listShares({
    required int limit,
    DateTime? before,
    String? peer,
  }) async {
    // `peer` entra en un filtro `or` en texto: solo un uuid, sin inyección.
    if (peer != null && !_uuid.hasMatch(peer)) {
      throw ArgumentError.value(peer, 'peer');
    }
    var q = _client
        .from('shared_tracks')
        .select()
        .or(
          peer == null
              ? 'from_id.eq.$_uid,to_id.eq.$_uid'
              : 'and(from_id.eq.$_uid,to_id.eq.$peer),'
                    'and(from_id.eq.$peer,to_id.eq.$_uid)',
        );
    if (before != null) {
      q = q.lt('created_at', before.toUtc().toIso8601String());
    }
    final rows = await q.order('created_at', ascending: false).limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> markSeen(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('shared_tracks')
        .update({'seen': true})
        .eq('to_id', _uid)
        .inFilter('id', ids);
  }

  @override
  Future<int> countUnseen() => _client
      .from('shared_tracks')
      .count(CountOption.exact)
      .eq('to_id', _uid)
      .eq('seen', false);

  @override
  Future<Future<void> Function()> subscribe({
    required void Function(String event, Map<String, dynamic> row) onRequest,
    required void Function(Map<String, dynamic> row) onShare,
  }) async {
    PostgresChangeFilter eq(String col) => PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: col,
      value: _uid,
    );
    final channel = _client.channel('friends:$_uid');
    for (final col in const ['to_id', 'from_id']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'friend_requests',
        filter: eq(col),
        callback: (p) => onRequest(
          p.eventType.name,
          p.eventType == PostgresChangeEvent.delete ? p.oldRecord : p.newRecord,
        ),
      );
    }
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'shared_tracks',
      filter: eq('to_id'),
      callback: (p) => onShare(p.newRecord),
    );
    channel.subscribe();
    return () async {
      await _client.removeChannel(channel);
    };
  }
}
