import 'dart:convert';
import 'dart:typed_data';

import '../core/models.dart';
import '../library/library_database.dart';

/// Marca local de un elemento sincronizable (tabla sync_meta).
class SyncMeta {
  const SyncMeta(this.updatedAt, this.deleted, this.dirty);
  final int updatedAt; // ms desde epoch
  final bool deleted, dirty;
}

/// Claves del servidor que ganan sobre lo local: no hay copia local, o la
/// remota es más reciente (última escritura gana). Lo local pendiente que no
/// aparece aquí es lo que se sube. Las lápidas compiten igual que el resto.
Set<String> remoteWinners(
  Map<String, SyncMeta> local,
  Map<String, int> remote,
) => {
  for (final e in remote.entries)
    if (local[e.key] == null || e.value > local[e.key]!.updatedAt) e.key,
};

const _kinds = ['favorites', 'playlists', 'history', 'taste'];

/// Acceso a la base para sincronizar. Todo lo que escribe aquí es «ya
/// sincronizado» (dirty=0); los cambios del usuario pasan por LibraryDatabase.
extension SyncStore on LibraryDatabase {
  /// Elementos locales anteriores a la cuenta: ts 0 para que, ante conflicto,
  /// gane el servidor, y el resto se suba (unión).
  Future<void> seedSyncMeta() async => engine.seedSyncMeta();

  Future<void> markAllSyncDirty() async => engine.markAllSyncDirty();

  Future<Map<String, SyncMeta>> readSyncMeta(String kind) async => {
    for (final r in engine.readSyncMeta(kind: kind))
      r.key: SyncMeta(r.updatedAt, r.deleted, r.dirty),
  };

  /// Claves pendientes de subir (el historial se limita a las 500 más nuevas).
  Future<List<String>> dirtySyncKeys(String kind) async =>
      engine.dirtySyncKeys(kind: kind);

  Future<void> setSyncMeta(
    String kind,
    String key,
    int ts,
    bool deleted,
  ) async => engine.setSyncMeta(kind: kind, key: key, ts: ts, deleted: deleted);

  /// Quita «pendiente» solo si nadie lo cambió mientras se subía.
  Future<void> clearSyncDirty(
    String kind,
    String key,
    int sentTs,
    int serverTs,
  ) async => engine.clearSyncDirty(
    kind: kind,
    key: key,
    sentTs: sentTs,
    serverTs: serverTs,
  );

  Future<Map<String, dynamic>?> _trackJson(String id) async {
    final raw = engine.trackJson(id: id);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    // La ruta local no tiene sentido en otro dispositivo (y es privada).
    return json..remove('localPath');
  }

  Future<void> _saveTrackIfAbsent(Object? raw) async {
    if (raw is! Map || raw['title'] is! String || raw['artist'] is! String) {
      return;
    }
    final track = Track.fromJson(
      Map<String, dynamic>.from(raw)..remove('localPath'),
    );
    engine.saveTrackIfAbsent(id: track.id, data: jsonEncode(track.toJson()));
  }

  /// Fila a subir para [key], o null si no se puede (p. ej. pista desconocida).
  Future<Map<String, dynamic>?> buildSyncRow(
    String kind,
    String key,
    bool deleted,
  ) async {
    switch (kind) {
      case 'favorites':
        final track = await _trackJson(key);
        if (track == null && !deleted) return null;
        return {
          'track_id': key,
          'track': track ?? {'id': key},
          'deleted': deleted,
        };
      case 'playlists':
        if (deleted) {
          return {
            'id': key,
            'name': '-',
            'tracks': <Object>[],
            'deleted': true,
          };
        }
        final row = engine.playlistRow(id: key);
        if (row == null) return null;
        final ids = (jsonDecode(row.tracksJson) as List).cast<String>();
        var items = <Object>[
          for (final id in ids) await _trackJson(id) ?? {'id': id},
        ];
        if (jsonEncode(items).length > 500000) {
          items = [
            for (final id in ids) {'id': id},
          ];
        }
        return {'id': key, 'name': row.name, 'tracks': items, 'deleted': false};
      case 'history':
        final track = await _trackJson(key);
        final playedAt = engine.historyPlayedAt(id: key);
        if (track == null || playedAt == null) return null;
        return {
          'track_id': key,
          'track': track,
          'played_at': DateTime.fromMillisecondsSinceEpoch(
            playedAt,
            isUtc: true,
          ).toIso8601String(),
        };
      case 'taste':
        final row = engine.tasteRow();
        if (row == null) return null;
        return {
          'profile': {'dims': row.dims, 'v': base64Encode(row.vector)},
        };
    }
    return null;
  }

  /// Aplica una fila remota ya validada como ganadora. Devuelve false si estaba mal formada.
  Future<bool> applyRemoteRow(String kind, Map<String, dynamic> r) async {
    try {
      final deleted = r['deleted'] == true;
      switch (kind) {
        case 'favorites':
          final id = r['track_id'] as String;
          if (deleted) {
            engine.setFavorite(id: id, selected: false, mark: false);
          } else {
            await _saveTrackIfAbsent(r['track']);
            engine.setFavorite(id: id, selected: true, mark: false);
          }
        case 'playlists':
          final id = r['id'] as String;
          if (deleted) {
            engine.deletePlaylist(id: id, mark: false);
          } else {
            final items = (r['tracks'] as List).whereType<Map>().toList();
            for (final t in items) {
              await _saveTrackIfAbsent(t);
            }
            engine.savePlaylist(
              id: id,
              name: (r['name'] as String).trim(),
              tracksJson: jsonEncode([
                for (final t in items) t['id'] as String,
              ]),
              mark: false,
            );
          }
        case 'history':
          final id = r['track_id'] as String;
          await _saveTrackIfAbsent(r['track']);
          engine.recordPlay(
            id: id,
            playedAtMs: DateTime.parse(
              r['played_at'] as String,
            ).millisecondsSinceEpoch,
            mark: false,
          );
        case 'taste':
          final p = r['profile'] as Map;
          final dims = p['dims'] as int;
          final bytes = base64Decode(p['v'] as String);
          if (dims < 1 || dims > 4096 || bytes.length != dims * 4) return false;
          engine.saveTaste(
            dims: dims,
            vector: Uint8List.fromList(bytes),
            mark: false,
          );
        default:
          return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

List<String> get syncKinds => _kinds;
