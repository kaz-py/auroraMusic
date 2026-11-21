import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/import/spotify_import.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

/// YouTube solo conoce «Hit Song» de «Artist».
class _YoutubeSource extends FakeSource {
  @override
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) async => SearchPage(
    tracks: query.contains('Hit Song')
        ? const [
            Track(
              id: 'yt:abcdefghijk',
              title: 'Hit Song',
              artist: 'Artist',
              duration: Duration(minutes: 3),
              pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
            ),
          ]
        : const [],
  );
}

void main() {
  test('lo importado de Spotify se empareja solo con YouTube', () async {
    final c = await createTestController(source: _YoutubeSource());
    addTearDown(() => closeTestController(c));
    (int, int)? finished;
    c.onSpotifyMatchFinished = (matched, total) => finished = (matched, total);

    await c.importSpotifyPlaylists([
      const SpotifyImportPlaylist(
        name: 'Lista',
        tracks: [
          SpotifyImportTrack(title: 'Hit Song', artist: 'Artist'),
          SpotifyImportTrack(title: 'Sin versión', artist: 'Nadie'),
        ],
      ),
    ]);
    for (var i = 0; i < 100 && finished == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(finished, (1, 2));
    final byTitle = {for (final t in c.tracks) t.title: t};
    expect(byTitle['Hit Song']!.isPendingSpotifyMatch, isFalse);
    expect(
      byTitle['Hit Song']!.pageUrl,
      'https://www.youtube.com/watch?v=abcdefghijk',
    );
    // Sin coincidencia fiable queda pendiente para elegirla a mano.
    expect(byTitle['Sin versión']!.isPendingSpotifyMatch, isTrue);
    expect(c.spotifyMatching, isFalse);
  });
}
