import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../bridge/api/database.dart';
import '../core/models.dart';

/// Fachada Dart de la base de datos de la biblioteca. El SQL, el esquema y las
/// migraciones viven en `rust/crates/aurora_database`; aquí solo se codifican y
/// decodifican los modelos (el JSON de pistas pasa tal cual por Rust).
class LibraryDatabase {
  LibraryDatabase._(this.engine);

  /// Base en memoria. [setupSql] se ejecuta antes de las migraciones, para
  /// que las pruebas puedan construir esquemas antiguos.
  LibraryDatabase.memory({List<String> setupSql = const []})
    : engine = LibraryDb.openMemory(setupSql: setupSql);

  static Future<LibraryDatabase> open() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return LibraryDatabase._(
      LibraryDb.open(path: p.join(directory.path, 'aurora.sqlite')),
    );
  }

  /// Motor Rust: los consumidores de SQL puro (sync, seguidos) usan sus primitivas.
  final LibraryDb engine;

  Future<void> close() async => engine.dispose();

  /// Se llama tras cada cambio local sincronizable (SyncService lo escucha).
  void Function()? onLocalChange;

  static Uint8List _bytes(Float32List vector) => Uint8List.fromList(
    vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes),
  );

  /// Stores track embeddings keyed by track ID, keeping the newest 5000 rows.
  Future<void> upsertTrackVectors(
    Iterable<({Track track, Float32List vector})> entries,
  ) async {
    final items = entries.toList();
    if (items.isEmpty) return;
    engine.upsertTrackVectors(
      entries: [
        for (final item in items)
          VectorEntry(
            trackKey: item.track.id,
            trackJson: jsonEncode(item.track.toJson()),
            vector: item.vector,
          ),
      ],
    );
  }

  Future<int> countTrackVectors() async => engine.countTrackVectors();

  /// Cosine nearest neighbours of [query], best first.
  Future<List<({Track track, double score})>> nearestTracks(
    List<double> query, {
    int k = 20,
    Set<String> exclude = const {},
  }) async => [
    for (final row in engine.nearestTracks(
      query: query,
      k: k,
      exclude: exclude.toList(),
    ))
      (
        track: Track.fromJson(
          jsonDecode(row.trackJson) as Map<String, dynamic>,
        ),
        score: row.score,
      ),
  ];

  Future<Float32List?> readTasteProfile() async => engine.readTasteProfile();

  Future<void> saveTasteProfile(Float32List vector) async {
    engine.saveTaste(dims: vector.length, vector: _bytes(vector), mark: true);
    onLocalChange?.call();
  }

  Future<List<Track>> readTracks() async => [
    for (final json in engine.readTracks())
      Track.fromJson(jsonDecode(json) as Map<String, dynamic>),
  ];

  Future<void> saveTrack(Track track) async =>
      engine.saveTrack(id: track.id, data: jsonEncode(track.toJson()));

  Future<Set<String>> readFavorites() async => engine.readFavorites().toSet();

  Future<void> setFavorite(String id, bool selected) async {
    engine.setFavorite(id: id, selected: selected, mark: true);
    onLocalChange?.call();
  }

  Future<List<MusicPlaylist>> readPlaylists() async => [
    for (final row in engine.readPlaylists())
      MusicPlaylist(
        id: row.id,
        name: row.name,
        trackIds: (jsonDecode(row.tracksJson) as List).cast<String>(),
      ),
  ];

  Future<void> savePlaylist(MusicPlaylist playlist) async {
    engine.savePlaylist(
      id: playlist.id,
      name: playlist.name,
      tracksJson: jsonEncode(playlist.trackIds),
      mark: true,
    );
    onLocalChange?.call();
  }

  Future<void> deletePlaylist(String id) async {
    engine.deletePlaylist(id: id, mark: true);
    onLocalChange?.call();
  }

  /// Pistas y listas en una sola transacción (importación de Spotify).
  Future<void> saveTracksAndPlaylists(
    Iterable<Track> tracks,
    Iterable<MusicPlaylist> playlists,
  ) async {
    final lists = playlists.toList();
    engine.saveTracksAndPlaylists(
      tracks: [
        for (final track in tracks)
          TrackRow(id: track.id, data: jsonEncode(track.toJson())),
      ],
      playlists: [
        for (final playlist in lists)
          PlaylistRow(
            id: playlist.id,
            name: playlist.name,
            tracksJson: jsonEncode(playlist.trackIds),
          ),
      ],
    );
    for (var i = 0; i < lists.length; i++) {
      onLocalChange?.call();
    }
  }

  Future<void> recordPlay(String id) async {
    engine.recordPlay(id: id, mark: true);
    onLocalChange?.call();
  }

  Future<List<String>> readHistory() async => engine.readHistory();

  Future<void> saveDownload(DownloadJob job) async => engine.saveDownload(
    id: job.id,
    data: jsonEncode({
      'track': job.track.toJson(),
      'status': job.status.name,
      'progress': job.progress,
      'error': job.error,
      'localPath': job.localPath,
      'destinationRoot': job.destinationRoot,
    }),
  );

  Future<List<DownloadJob>> readDownloads() async =>
      engine.readDownloads().map((row) {
        final data = jsonDecode(row.data) as Map<String, dynamic>;
        final status = DownloadStatus.values.byName(data['status'] as String);
        final interrupted =
            status == DownloadStatus.downloading ||
            status == DownloadStatus.queued;
        return DownloadJob(
          id: row.id,
          track: Track.fromJson(data['track'] as Map<String, dynamic>),
          status: interrupted ? DownloadStatus.failed : status,
          progress: (data['progress'] as num).toDouble(),
          error: interrupted
              ? 'Descarga interrumpida. Puedes reintentar.'
              : data['error'] as String?,
          localPath: data['localPath'] as String?,
          destinationRoot: data['destinationRoot'] as String?,
        );
      }).toList();

  Future<void> deleteDownload(String id) async => engine.deleteDownload(id: id);
}
