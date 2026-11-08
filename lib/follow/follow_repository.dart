import 'dart:async';
import 'dart:convert';

import '../bridge/api/database.dart';
import '../library/library_database.dart';
import 'follow_models.dart';

/// Artistas seguidos y novedades en SQLite (tablas creadas en LibraryDatabase).
class FollowRepository {
  FollowRepository(this._db);
  final LibraryDatabase _db;
  final _changes = StreamController<List<FollowedArtist>>.broadcast();

  static FollowedArtist _artist(FollowedRow row) {
    Set<String> known;
    try {
      known = (jsonDecode(row.knownReleases) as List)
          .whereType<String>()
          .toSet();
    } catch (_) {
      known = {};
    }
    final checked = row.checkedAt;
    return FollowedArtist(
      browseId: row.browseId,
      name: row.name,
      imageUrl: row.imageUrl,
      followedAt: DateTime.fromMillisecondsSinceEpoch(row.followedAt),
      lastReleaseId: row.lastReleaseId,
      lastReleaseTitle: row.lastReleaseTitle,
      knownReleases: known,
      checkedAt: checked == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(checked),
    );
  }

  Future<List<FollowedArtist>> list() async =>
      _db.engine.followList().map(_artist).toList();

  /// Emite la lista actual y después cada cambio.
  Stream<List<FollowedArtist>> watch() async* {
    yield await list();
    yield* _changes.stream;
  }

  Future<void> _emit() async {
    if (!_changes.isClosed && _changes.hasListener) _changes.add(await list());
  }

  /// Seguir es idempotente: volver a seguir conserva fecha y línea base.
  Future<void> follow(
    String browseId,
    String name, {
    String? imageUrl,
    DateTime? at,
  }) async {
    _db.engine.followAdd(
      browseId: browseId,
      name: name,
      imageUrl: imageUrl,
      followedAt: (at ?? DateTime.now()).millisecondsSinceEpoch,
    );
    await _emit();
  }

  Future<void> unfollow(String browseId) async {
    _db.engine.followRemove(browseId: browseId);
    await _emit();
  }

  Future<void> saveCheck(FollowedArtist artist) async {
    _db.engine.followSaveCheck(
      browseId: artist.browseId,
      lastReleaseId: artist.lastReleaseId,
      lastReleaseTitle: artist.lastReleaseTitle,
      knownReleasesJson: jsonEncode(artist.knownReleases.toList()),
      checkedAt: artist.checkedAt?.millisecondsSinceEpoch,
    );
    await _emit();
  }

  Future<List<NewRelease>> news() async => [
    for (final row in _db.engine.newsList())
      NewRelease(
        id: row.releaseId,
        artistId: row.artistId,
        artistName: row.artistName,
        title: row.title,
        subtitle: row.subtitle,
        artworkUrl: row.artworkUrl,
        detectedAt: DateTime.fromMillisecondsSinceEpoch(row.detectedAt),
      ),
  ];

  Future<void> addNews(Iterable<NewRelease> releases) async {
    _db.engine.newsAdd(
      rows: [
        for (final r in releases)
          NewsRow(
            releaseId: r.id,
            artistId: r.artistId,
            artistName: r.artistName,
            title: r.title,
            subtitle: r.subtitle,
            artworkUrl: r.artworkUrl,
            detectedAt: r.detectedAt.millisecondsSinceEpoch,
          ),
      ],
    );
  }

  /// Sin [id] descarta todas («marcar como vistas»).
  Future<void> dismissNews([String? id]) async =>
      _db.engine.newsDismiss(releaseId: id);

  Future<void> pruneNews(DateTime olderThan) async =>
      _db.engine.newsPrune(olderThanMs: olderThan.millisecondsSinceEpoch);

  Future<void> close() => _changes.close();
}
