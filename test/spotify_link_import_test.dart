import 'dart:convert';

import 'package:aurora_music/import/spotify_import.dart';
import 'package:aurora_music/import/spotify_link_import.dart';
import 'package:aurora_music/metadata/spotify/spotify_embed.dart';
import 'package:aurora_music/metadata/spotify/spotify_link.dart';
import 'package:aurora_music/metadata/spotify/spotify_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = '37i9dQZF1DXcBWIGoYBM5M';

String _page(Map<String, dynamic> entity) =>
    '<html><body><script id="__NEXT_DATA__" type="application/json">'
    '${jsonEncode({
      'props': {
        'pageProps': {
          'state': {
            'data': {'entity': entity},
          },
        },
      },
    })}</script></body></html>';

Map<String, dynamic> _row(int i) => {
  'uri': 'spotify:track:${'a' * 21}${i % 10}',
  'title': 'Canción $i',
  'subtitle': 'Artista $i, Invitado',
  'duration': 200000,
};

class _FakeEmbed extends SpotifyEmbedClient {
  _FakeEmbed(this.page);
  final SpotifyEmbedPage page;
  SpotifyLink? asked;
  @override
  Future<SpotifyEmbedPage> fetch(SpotifyLink link) async {
    asked = link;
    return page;
  }
}

void main() {
  group('parseSpotifyLink', () {
    final want = SpotifyLink(SpotifyEntityType.playlist, _id);

    test('acepta las formas que se copian de Spotify', () {
      for (final text in [
        'https://open.spotify.com/playlist/$_id',
        '  https://open.spotify.com/playlist/$_id?si=abc123&pt=x  ',
        'https://open.spotify.com/intl-es/playlist/$_id',
        'https://open.spotify.com/intl-pt-BR/playlist/$_id?si=1',
        'https://open.spotify.com/embed/playlist/$_id?utm_source=oembed',
        'https://open.spotify.com/user/alguien/playlist/$_id',
        'spotify:playlist:$_id',
        'spotify:user:alguien:playlist:$_id',
      ]) {
        expect(parseSpotifyLink(text), want, reason: text);
      }
      expect(
        parseSpotifyLink('https://open.spotify.com/album/$_id')?.type,
        SpotifyEntityType.album,
      );
    });

    test('rechaza otros servidores, puertos, credenciales e ids raros', () {
      for (final text in [
        '',
        'playlist/$_id',
        'http://open.spotify.com/playlist/$_id',
        'https://evil.example/playlist/$_id',
        'https://open.spotify.com.evil.example/playlist/$_id',
        'https://user@open.spotify.com/playlist/$_id',
        'https://open.spotify.com:8443/playlist/$_id',
        'https://open.spotify.com/playlist/corto',
        'https://open.spotify.com/playlist/$_id/extra',
        'https://open.spotify.com/show/$_id',
        'spotify:playlist:corto',
        'spotify:playlist:$_id:extra',
      ]) {
        expect(parseSpotifyLink(text), isNull, reason: text);
      }
    });

    test('explica por qué no sirve un enlace de Spotify', () {
      expect(
        spotifyLinkProblem('https://open.spotify.com/collection/tracks'),
        contains('privadas'),
      );
      expect(spotifyLinkProblem('https://spotify.link/abc'), contains('corto'));
      expect(spotifyLinkProblem('hola'), contains('Pega un enlace'));
    });
  });

  group('SpotifyEmbedClient.parse', () {
    test('lee nombre, portada y canciones de una playlist', () {
      final page = SpotifyEmbedClient.parse(
        _page({
          'name': 'Éxitos España',
          'visualIdentity': {
            'image': [
              {'url': 'https://i.scdn.co/image/x'},
            ],
          },
          'trackList': [
            _row(1),
            _row(2),
            {'uri': 'spotify:episode:zzz', 'title': 'Podcast'},
            {'uri': 'spotify:track:bbbbbbbbbbbbbbbbbbbbbb', 'title': ' '},
          ],
        }),
        SpotifyEntityType.playlist,
      );
      expect(page.name, 'Éxitos España');
      expect(page.artworkUrl, 'https://i.scdn.co/image/x');
      expect(page.tracks.map((t) => t.title), ['Canción 1', 'Canción 2']);
      expect(page.tracks.first.artist, 'Artista 1, Invitado');
      expect(page.tracks.first.uri, startsWith('spotify:track:'));
      expect(page.maybeTruncated, isFalse);
    });

    test('con 100 filas avisa de que puede faltar el resto', () {
      final page = SpotifyEmbedClient.parse(
        _page({
          'name': 'Larga',
          'trackList': [for (var i = 0; i < 100; i++) _row(i)],
        }),
        SpotifyEntityType.playlist,
      );
      expect(page.maybeTruncated, isTrue);
    });

    test('una canción suelta es su propia lista', () {
      final page = SpotifyEmbedClient.parse(
        _page({
          'name': 'Solo',
          'uri': 'spotify:track:cccccccccccccccccccccc',
          'artists': [
            {'name': 'A'},
            {'name': 'B'},
          ],
        }),
        SpotifyEntityType.track,
      );
      expect(page.tracks.single.title, 'Solo');
      expect(page.tracks.single.artist, 'A, B');
    });

    test('páginas sin datos fallan con un motivo legible', () {
      expect(
        () => SpotifyEmbedClient.parse(
          '<html></html>',
          SpotifyEntityType.playlist,
        ),
        throwsA(
          isA<SpotifyEmbedException>().having(
            (e) => e.message,
            'm',
            contains('cambió'),
          ),
        ),
      );
      expect(
        () => SpotifyEmbedClient.parse(_page({}), SpotifyEntityType.playlist),
        throwsA(isA<SpotifyEmbedException>()),
      );
      expect(
        () => SpotifyEmbedClient.parse(
          _page({'name': 'Vacía', 'trackList': []}),
          SpotifyEntityType.playlist,
        ),
        throwsA(
          isA<SpotifyEmbedException>().having(
            (e) => e.message,
            'm',
            contains('canciones'),
          ),
        ),
      );
    });
  });

  group('SpotifyLinkImporter', () {
    SpotifyEmbedPage page(int n) => SpotifyEmbedPage(
      name: 'Lista',
      tracks: [for (var i = 0; i < n; i++) SpotifyImportTrackFixture.make(i)],
    );

    test('importa de la página pública y pide la lista correcta', () async {
      final embed = _FakeEmbed(page(3));
      final result = await SpotifyLinkImporter(
        embed: embed,
      ).import('https://open.spotify.com/intl-es/playlist/$_id?si=1');
      expect(embed.asked, SpotifyLink(SpotifyEntityType.playlist, _id));
      expect(result.playlist.name, 'Lista');
      expect(result.playlist.tracks, hasLength(3));
      expect(result.truncated, isFalse);
      expect(result.via, 'embed');
    });

    test('con 100 y sin catálogo avisa de que está recortada', () async {
      final result = await SpotifyLinkImporter(
        embed: _FakeEmbed(page(100)),
      ).import('spotify:playlist:$_id');
      expect(result.truncated, isTrue);
      expect(result.playlist.tracks, hasLength(100));
    });

    test('un enlace que no es de Spotify falla sin tocar la red', () async {
      final embed = _FakeEmbed(page(1));
      await expectLater(
        SpotifyLinkImporter(embed: embed).import('https://example.com/x'),
        throwsA(isA<SpotifyEmbedException>()),
      );
      expect(embed.asked, isNull);
    });
  });
}

class SpotifyImportTrackFixture {
  static SpotifyImportTrack make(int i) => SpotifyEmbedClient.parse(
    _page({
      'name': 'x',
      'trackList': [_row(i)],
    }),
    SpotifyEntityType.playlist,
  ).tracks.single;
}
