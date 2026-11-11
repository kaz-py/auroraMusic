import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../import/spotify_import.dart';
import 'spotify_link.dart';
import 'spotify_models.dart';

/// Lo que sale de leer la página pública de incrustación de Spotify.
class SpotifyEmbedPage {
  const SpotifyEmbedPage({
    required this.name,
    required this.tracks,
    this.artworkUrl,
  });
  final String name;
  final List<SpotifyImportTrack> tracks;
  final String? artworkUrl;

  /// Spotify entrega como mucho 100 filas por página pública.
  bool get maybeTruncated => tracks.length >= SpotifyEmbedClient.pageLimit;
}

/// Lee playlists, álbumes, artistas y canciones **públicos** sin iniciar
/// sesión ni usar credenciales: pide `https://open.spotify.com/embed/<tipo>/<id>`
/// (la misma página que cualquier web incrusta) y toma los datos del JSON
/// `__NEXT_DATA__` que lleva dentro. No usa el token anónimo que esa página
/// también trae.
///
/// Es la interfaz de una página web, no una API: si Spotify cambia su forma,
/// [SpotifyEmbedException] lo dice y las demás vías (archivo, navegador) siguen.
class SpotifyEmbedClient {
  SpotifyEmbedClient({
    HttpClient Function()? clientFactory,
    this.timeout = const Duration(seconds: 15),
  }) : _factory = clientFactory ?? HttpClient.new;

  static const pageLimit = 100;
  static const maxBytes = 6 * 1024 * 1024;
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Safari/537.36';

  final HttpClient Function() _factory;
  final Duration timeout;

  Future<SpotifyEmbedPage> fetch(SpotifyLink link) async {
    final client = _factory()
      ..connectionTimeout = timeout
      ..userAgent = _userAgent
      ..autoUncompress = true;
    try {
      var target = link.embedUri;
      HttpClientResponse? response;
      // Las redirecciones se siguen a mano: solo dentro de open.spotify.com.
      for (var hops = 0; hops <= 3; hops++) {
        final request = await client.getUrl(target).timeout(timeout);
        request.followRedirects = false;
        request.headers
          ..set(HttpHeaders.acceptHeader, 'text/html')
          ..set(HttpHeaders.acceptLanguageHeader, 'es,en;q=0.8');
        response = await request.close().timeout(timeout);
        if (!response.isRedirect) break;
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        final next = location == null ? null : target.resolve(location);
        if (next == null ||
            next.scheme != 'https' ||
            next.host != 'open.spotify.com' ||
            hops == 3) {
          throw const SpotifyEmbedException(
            'Spotify redirigió a un lugar no permitido.',
          );
        }
        target = next;
      }
      final status = response!.statusCode;
      if (status == HttpStatus.notFound) {
        throw const SpotifyEmbedException(
          'Spotify no encuentra ese contenido. Puede ser privado o haberse borrado.',
        );
      }
      if (status != HttpStatus.ok) {
        await response.drain<void>();
        throw SpotifyEmbedException(
          status == HttpStatus.tooManyRequests
              ? 'Spotify pide esperar un poco. Inténtalo en unos minutos.'
              : 'Spotify respondió $status.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) {
          throw const SpotifyEmbedException(
            'La respuesta de Spotify es demasiado grande.',
          );
        }
      }
      return parse(
        utf8.decode(bytes.takeBytes(), allowMalformed: true),
        link.type,
      );
    } on TimeoutException {
      throw const SpotifyEmbedException(
        'Spotify tardó demasiado en responder.',
      );
    } on SocketException {
      throw const SpotifyEmbedException('Sin conexión con Spotify.');
    } on HandshakeException {
      throw const SpotifyEmbedException(
        'No se pudo verificar el certificado de Spotify.',
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Extrae nombre, portada y canciones del HTML de la página de incrustación.
  static SpotifyEmbedPage parse(String html, SpotifyEntityType type) {
    final match = RegExp(
      r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) {
      throw const SpotifyEmbedException(
        'Spotify cambió su página y ya no puedo leerla. Usa el navegador de Spotify o un archivo.',
      );
    }
    final Object? root;
    try {
      root = jsonDecode(match.group(1)!);
    } on FormatException {
      throw const SpotifyEmbedException(
        'La página de Spotify no se pudo interpretar.',
      );
    }
    final entity = spotifyMap(
      spotifyMap(
        spotifyMap(spotifyMap(spotifyMap(root)['props'])['pageProps'])['state'],
      )['data'],
    )['entity'];
    final data = spotifyMap(entity);
    if (data.isEmpty) {
      throw const SpotifyEmbedException(
        'Spotify no devolvió datos. El contenido puede ser privado o no existir.',
      );
    }
    final name = _text(data['name']) ?? _text(data['title']) ?? '';
    final artwork = _artwork(data);
    final tracks = <SpotifyImportTrack>[];
    final rows = spotifyItems(data['trackList']);
    for (final raw in rows) {
      final row = spotifyMap(raw);
      final uri = _text(row['uri']);
      final title = _text(row['title']);
      if (title == null || (uri != null && !uri.startsWith('spotify:track:'))) {
        continue;
      }
      tracks.add(
        SpotifyImportTrack(
          title: title,
          artist: _text(row['subtitle']) ?? '',
          uri: uri,
        ),
      );
    }
    // Una canción suelta: la página es la propia pista.
    if (rows.isEmpty && type == SpotifyEntityType.track) {
      final artists = [
        for (final a in spotifyItems(data['artists']))
          if (_text(spotifyMap(a)['name']) != null)
            _text(spotifyMap(a)['name'])!,
      ];
      final title = _text(data['title']) ?? _text(data['name']);
      if (title != null) {
        tracks.add(
          SpotifyImportTrack(
            title: title,
            artist: artists.isNotEmpty
                ? artists.join(', ')
                : (_text(data['subtitle']) ?? ''),
            uri: _text(data['uri']),
          ),
        );
      }
    }
    if (tracks.isEmpty) {
      throw const SpotifyEmbedException(
        'No encontré canciones en ese enlace. Puede estar vacío o ser privado.',
      );
    }
    return SpotifyEmbedPage(
      name: name.isEmpty ? 'Spotify' : name,
      tracks: tracks,
      artworkUrl: artwork,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  static String? _artwork(Map<String, dynamic> data) {
    for (final source in [
      ...spotifyItems(spotifyMap(data['visualIdentity'])['image']),
      ...spotifyItems(spotifyMap(data['coverArt'])['extractedColors']),
    ]) {
      final url = _text(spotifyMap(source)['url']);
      final uri = url == null ? null : Uri.tryParse(url);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        return url;
      }
    }
    return null;
  }
}

class SpotifyEmbedException implements Exception {
  const SpotifyEmbedException(this.message);
  final String message;
  @override
  String toString() => message;
}
