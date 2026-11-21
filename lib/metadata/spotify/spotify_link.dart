import 'spotify_models.dart';

/// Referencia a algo público de Spotify sacada de lo que el usuario pega.
class SpotifyLink {
  const SpotifyLink(this.type, this.id);
  final SpotifyEntityType type;
  final String id;

  String get uri => 'spotify:${type.name}:$id';
  Uri get embedUri => Uri.https('open.spotify.com', '/embed/${type.name}/$id');
  Uri get pageUri => Uri.https('open.spotify.com', '/${type.name}/$id');

  @override
  bool operator ==(Object other) =>
      other is SpotifyLink && other.type == type && other.id == id;
  @override
  int get hashCode => Object.hash(type, id);
}

final _id = RegExp(r'^[A-Za-z0-9]{22}$');

SpotifyEntityType? _type(String value) {
  for (final type in SpotifyEntityType.values) {
    if (type.name == value) return type;
  }
  return null;
}

/// Entiende los enlaces que se copian de Spotify:
/// `https://open.spotify.com/playlist/ID?si=…`, con prefijo de idioma
/// (`/intl-es/…`), de usuario (`/user/x/playlist/ID`), de incrustación
/// (`/embed/playlist/ID`) y las URI `spotify:playlist:ID` o
/// `spotify:user:x:playlist:ID`. `null` si no es una referencia válida.
///
/// Solo se aceptan `https://open.spotify.com` (sin puerto ni usuario en la URL)
/// y `spotify:`: nunca otro servidor.
SpotifyLink? parseSpotifyLink(String text) {
  final value = text.trim();
  if (value.isEmpty || value.length > 400) return null;
  if (value.startsWith('spotify:')) {
    final parts = value.split(':');
    // spotify:playlist:ID  |  spotify:user:alguien:playlist:ID
    final tail = parts.length >= 5 && parts[1] == 'user'
        ? parts.sublist(3)
        : parts.sublist(1);
    if (tail.length != 2) return null;
    final type = _type(tail[0]);
    return type != null && _id.hasMatch(tail[1])
        ? SpotifyLink(type, tail[1])
        : null;
  }
  final url = Uri.tryParse(value);
  if (url == null ||
      url.scheme != 'https' ||
      url.host.toLowerCase() != 'open.spotify.com' ||
      url.userInfo.isNotEmpty ||
      url.hasPort) {
    return null;
  }
  var segments = [
    for (final s in url.pathSegments)
      if (s.isNotEmpty) s,
  ];
  // Prefijos que no cambian lo que es: /intl-es/, /embed/, /user/<nombre>/.
  if (segments.isNotEmpty &&
      RegExp(r'^intl-[a-z]{2}(-[A-Za-z]{2})?$').hasMatch(segments.first)) {
    segments = segments.sublist(1);
  }
  if (segments.isNotEmpty && segments.first == 'embed') {
    segments = segments.sublist(1);
  }
  if (segments.length >= 3 && segments.first == 'user') {
    segments = segments.sublist(2);
  }
  if (segments.length != 2) return null;
  final type = _type(segments[0]);
  return type != null && _id.hasMatch(segments[1])
      ? SpotifyLink(type, segments[1])
      : null;
}

/// Motivo claro cuando el texto pegado es algo de Spotify que no se puede leer.
String spotifyLinkProblem(String text) {
  final value = text.trim().toLowerCase();
  if (value.contains('/collection/tracks') || value.contains('/collection/')) {
    return 'Tus «Canciones que te gustan» son privadas: Spotify no las muestra sin iniciar sesión. Expórtalas con tus datos de Spotify (CSV/JSON).';
  }
  if (value.contains('spotify.link') || value.contains('spoti.fi')) {
    return 'Ese es un enlace corto de Spotify. Ábrelo en el navegador y copia la dirección completa (open.spotify.com/playlist/…).';
  }
  if (value.contains('open.spotify.com') || value.startsWith('spotify:')) {
    return 'No reconozco ese enlace de Spotify. Pega el de una playlist, álbum, artista o canción públicos.';
  }
  return 'Pega un enlace de Spotify (open.spotify.com/playlist/…) o una URI (spotify:playlist:…).';
}
