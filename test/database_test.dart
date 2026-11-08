import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interrupted downloads recover as retryable failures', () async {
    final database = LibraryDatabase.memory();
    addTearDown(database.close);
    await database.saveDownload(
      DownloadJob(
        id: 'interrupted',
        track: const Track(id: 'track', title: 'Título', artist: 'Artista'),
        status: DownloadStatus.downloading,
        progress: 0.4,
        destinationRoot: r'C:\Music',
      ),
    );
    final restored = (await database.readDownloads()).single;
    expect(restored.status, DownloadStatus.failed);
    expect(restored.progress, 0.4);
    expect(restored.error, contains('interrumpida'));
    expect(restored.destinationRoot, r'C:\Music');
  });
}
