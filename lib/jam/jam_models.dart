import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../core/models.dart';

enum JamMode { queueOnly, synchronized }

enum JamConnection { idle, hosting, connected, disconnected, closed }

enum JamRole { host, coHost, guest }

/// queued: suena en orden; suggested: «A continuación» propuesta (suena tras
/// las puestas en cola, ordenada por votos); pending: espera aprobación.
enum JamEntryStatus { queued, suggested, pending }

/// Alfabeto sin ambiguos (sin I, O, 0, 1). El servidor genera códigos de 8
/// (32^8 ≈ 1.1e12); se siguen aceptando los de 6 de salas creadas antes.
const jamCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
final _codePattern = RegExp(r'^[A-HJ-NP-Z2-9]{6}(?:[A-HJ-NP-Z2-9]{2})?$');

/// Devuelve el código en mayúsculas o null si no es un código válido.
String? jamNormalizeCode(String value) {
  final code = value.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  return _codePattern.hasMatch(code) ? code : null;
}

/// Nombre visible seguro: sin control, sin marcas bidireccionales, máx. 32.
String jamCleanName(String value, {String fallback = 'Invitado'}) {
  final clean = value
      .replaceAll(
        RegExp(r'[\x00-\x1f\x7f\u200e\u200f\u202a-\u202e\u2066-\u2069]'),
        '',
      )
      .trim();
  if (clean.isEmpty) return fallback;
  return clean.length > 32 ? clean.substring(0, 32).trim() : clean;
}

/// Tope del avatar decodificado (miniatura PNG/JPEG de perfil).
const jamMaxAvatarBytes = 24 * 1024;

/// Valida un avatar recibido (base64 de PNG/JPEG de hasta [jamMaxAvatarBytes]).
/// Devuelve null ante cualquier defecto: un avatar malo se ignora, nunca falla.
Uint8List? jamAvatarFromBase64(Object? raw) {
  // 24 KiB en base64 son 32768 caracteres; se corta antes de decodificar.
  if (raw is! String || raw.length < 12 || raw.length > 32768) return null;
  try {
    final b = base64Decode(raw);
    if (b.length < 8 || b.length > jamMaxAvatarBytes) return null;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    return png || jpeg ? b : null;
  } catch (_) {
    return null;
  }
}

class JamException implements Exception {
  const JamException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool isJamAddress(String address, {bool allowLoopback = false}) {
  final parsed = InternetAddress.tryParse(address);
  if (parsed == null ||
      parsed.type != InternetAddressType.IPv4 ||
      parsed.address != address) {
    return false;
  }
  final bytes = parsed.rawAddress;
  return (bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (allowLoopback && address == '127.0.0.1')) &&
      bytes[3] != 0 &&
      bytes[3] != 255;
}

String jamRandomSecret([int bytes = 32]) => base64Url
    .encode(List.generate(bytes, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String jamText(Object? value, {int max = 256, bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty) ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const JamException('Datos de Jam inválidos.');
  }
  return value.trim();
}

int jamInt(Object? value, {int max = 2147483647}) {
  if (value is! int || value < 0 || value > max) {
    throw const JamException('Datos de Jam inválidos.');
  }
  return value;
}

Map<String, dynamic> jamMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const JamException('Mensaje de Jam inválido.');
  }
  return value;
}

void jamKeys(Map<String, dynamic> value, Set<String> allowed) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw const JamException('Mensaje de Jam inválido.');
  }
}

String jamIdentifier(Object? value) {
  final id = jamText(value, max: 64);
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id)) {
    throw const JamException('Identificador de Jam inválido.');
  }
  return id;
}

class JamInvite {
  const JamInvite({
    required this.address,
    required this.port,
    required this.sessionId,
    required this.accessToken,
    required this.expiresAt,
  });

  /// Invitación de una sala en línea: solo lleva el código (8 caracteres; 6 en salas antiguas).
  JamInvite.remote({required String code, required this.expiresAt})
    : address = '',
      port = 0,
      sessionId = code,
      accessToken = '';
  final String address;
  final int port;
  final String sessionId;
  final String accessToken;
  final DateTime expiresAt;
  bool get isRemote => port == 0;
  String get code => sessionId;
  String get endpoint => isRemote ? sessionId : '$address:$port';
  String encode() => isRemote
      ? 'aurora://jam/$sessionId'
      : jsonEncode({
          'v': 1,
          'address': address,
          'port': port,
          'sessionId': sessionId,
          'accessToken': accessToken,
          'expiresAt': expiresAt.millisecondsSinceEpoch,
        });
  factory JamInvite.decode(
    String encoded, {
    bool allowLoopback = false,
    DateTime? now,
  }) {
    final remote = jamRemoteCodeFrom(encoded);
    if (remote != null) {
      return JamInvite.remote(
        code: remote,
        expiresAt: (now ?? DateTime.now()).add(const Duration(hours: 12)),
      );
    }
    try {
      if (encoded.length > 2048) throw const FormatException();
      final data = jamMap(jsonDecode(encoded));
      jamKeys(data, {
        'v',
        'address',
        'port',
        'sessionId',
        'accessToken',
        'expiresAt',
      });
      if (data['v'] != 1) throw const FormatException();
      final address = jamText(data['address'], max: 15);
      if (!isJamAddress(address, allowLoopback: allowLoopback)) {
        throw const FormatException();
      }
      final port = jamInt(data['port'], max: 65535);
      final id = jamIdentifier(data['sessionId']);
      final token = jamIdentifier(data['accessToken']);
      final expires = DateTime.fromMillisecondsSinceEpoch(
        jamInt(data['expiresAt'], max: 8640000000000000),
      );
      final current = now ?? DateTime.now();
      if (port == 0 ||
          id.length != 22 ||
          token.length != 43 ||
          !expires.isAfter(current) ||
          expires.difference(current) > const Duration(hours: 4, minutes: 5)) {
        throw const FormatException();
      }
      return JamInvite(
        address: address,
        port: port,
        sessionId: id,
        accessToken: token,
        expiresAt: expires,
      );
    } catch (_) {
      throw const JamException(
        'El QR no contiene una Jam local válida o ya venció.',
      );
    }
  }
}

/// Extrae el código de `aurora://jam/ABCD2345` o de un código suelto.
String? jamRemoteCodeFrom(String input) {
  input = input.trim();
  if (input.length > 64) return null;
  final uri = Uri.tryParse(input);
  if (uri != null && uri.scheme == 'aurora') {
    if (uri.host != 'jam' || uri.pathSegments.length != 1) return null;
    return jamNormalizeCode(uri.pathSegments.single);
  }
  return jamNormalizeCode(input);
}

String? jamYouTubeId(Track track) {
  final uri = Uri.tryParse(track.pageUrl ?? '');
  if (uri != null &&
      uri.scheme == 'https' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort) {
    String? id;
    if (uri.host == 'www.youtube.com' ||
        uri.host == 'music.youtube.com' ||
        uri.host == 'youtube.com' ||
        uri.host == 'm.youtube.com') {
      if (uri.path == '/watch') id = uri.queryParameters['v'];
      if (uri.pathSegments.length == 2 &&
          {'shorts', 'embed'}.contains(uri.pathSegments.first)) {
        id = uri.pathSegments.last;
      }
    } else if (uri.host == 'youtu.be' && uri.pathSegments.length == 1) {
      id = uri.pathSegments.first;
    }
    if (id != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return id;
  }
  return null;
}

final _artworkHost = RegExp(
  r'^(i\.ytimg\.com|img\.youtube\.com|i\.scdn\.co|'
  r'image-cdn-ak\.spotifycdn\.com|lh[3-6]\.googleusercontent\.com|'
  r'yt3\.googleusercontent\.com|yt3\.ggpht\.com)$',
);

/// Solo HTTPS y hosts de imagen conocidos (YouTube, googleusercontent, Spotify).
/// Las portadas de YouTube Music llevan el tamaño tras «=» (`=w544-h544`), que
/// se conserva; cualquier query o fragmento se descarta.
String? jamSafeArtwork(String? value) {
  final uri = Uri.tryParse(value ?? '');
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      !_artworkHost.hasMatch(uri.host) ||
      !RegExp(r'^/[A-Za-z0-9_./=-]*$').hasMatch(uri.path)) {
    return null;
  }
  final clean = 'https://${uri.host}${uri.path}';
  return clean.length > 512 ? null : clean;
}

String jamNormalized(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// Deliberately excludes local IDs/paths, extracted URLs, cookies and provider tokens.
class JamTrack {
  const JamTrack({
    required this.key,
    required this.title,
    required this.artist,
    required this.durationMs,
    this.youtubeId,
    this.spotifyUri,
    this.artworkUrl,
    this.localOnly = false,
  });
  final String key;
  final String title;
  final String artist;
  final int durationMs;
  final String? youtubeId;
  final String? spotifyUri;
  final String? artworkUrl;
  final bool localOnly;
  String get titleArtist => '${jamNormalized(title)}|${jamNormalized(artist)}';
  Set<String> get keys => {
    key,
    'text:$titleArtist',
    if (youtubeId != null) 'yt:$youtubeId',
    ?spotifyUri,
  };
  factory JamTrack.fromTrack(Track track) {
    final title = jamText(track.title);
    final artist = jamText(track.artist);
    final youtube = jamYouTubeId(track);
    final spotify =
        track.spotifyUri != null &&
            RegExp(
              r'^spotify:track:[a-zA-Z0-9]{22}$',
            ).hasMatch(track.spotifyUri!)
        ? track.spotifyUri
        : null;
    final key = youtube != null
        ? 'yt_$youtube'
        : spotify != null
        ? 'sp_${spotify.split(':').last}'
        : 'local_${sha256.convert(utf8.encode('${jamNormalized(title)}|${jamNormalized(artist)}')).toString().substring(0, 24)}';
    return JamTrack(
      key: key,
      title: title,
      artist: artist,
      durationMs: track.duration.inMilliseconds.clamp(0, 86400000),
      youtubeId: youtube,
      spotifyUri: spotify,
      artworkUrl: jamSafeArtwork(track.artworkUrl),
      localOnly: youtube == null && spotify == null,
    );
  }
  Map<String, Object?> toJson() => {
    'key': key,
    'title': title,
    'artist': artist,
    'durationMs': durationMs,
    'youtubeId': youtubeId,
    'spotifyUri': spotifyUri,
    'artworkUrl': artworkUrl,
    'localOnly': localOnly,
  };
  factory JamTrack.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'key',
      'title',
      'artist',
      'durationMs',
      'youtubeId',
      'spotifyUri',
      'artworkUrl',
      'localOnly',
    });
    final youtube = data['youtubeId'];
    final spotify = data['spotifyUri'];
    final artwork = data['artworkUrl'];
    if ((youtube != null &&
            (youtube is! String ||
                !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(youtube))) ||
        (spotify != null &&
            (spotify is! String ||
                !RegExp(
                  r'^spotify:track:[a-zA-Z0-9]{22}$',
                ).hasMatch(spotify))) ||
        (artwork != null &&
            (artwork is! String || jamSafeArtwork(artwork) != artwork)) ||
        data['localOnly'] is! bool) {
      throw const JamException('Metadatos de canción inválidos.');
    }
    final track = JamTrack(
      key: jamIdentifier(data['key']),
      title: jamText(data['title']),
      artist: jamText(data['artist']),
      durationMs: jamInt(data['durationMs'], max: 86400000),
      youtubeId: youtube as String?,
      spotifyUri: spotify as String?,
      artworkUrl: artwork as String?,
      localOnly: data['localOnly'] as bool,
    );
    final expected = JamTrack.fromTrack(
      Track(
        id: '',
        title: track.title,
        artist: track.artist,
        spotifyUri: track.spotifyUri,
        pageUrl: youtube == null
            ? null
            : 'https://www.youtube.com/watch?v=$youtube',
      ),
    );
    if (track.key != expected.key || track.localOnly != expected.localOnly) {
      throw const JamException('Identidad de canción inválida.');
    }
    return track;
  }
}

class JamPermissions {
  const JamPermissions({
    this.skip = false,
    this.reorder = false,
    this.remove = false,
    this.add = true,
    this.pause = false,
  });
  final bool skip, reorder, remove, add, pause;
  static const all = JamPermissions(
    skip: true,
    reorder: true,
    remove: true,
    pause: true,
  );
  JamPermissions copyWith({
    bool? skip,
    bool? reorder,
    bool? remove,
    bool? add,
    bool? pause,
  }) => JamPermissions(
    skip: skip ?? this.skip,
    reorder: reorder ?? this.reorder,
    remove: remove ?? this.remove,
    add: add ?? this.add,
    pause: pause ?? this.pause,
  );
  Map<String, bool> toJson() => {
    'skip': skip,
    'reorder': reorder,
    'remove': remove,
    'add': add,
    'pause': pause,
  };
  factory JamPermissions.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {'skip', 'reorder', 'remove', 'add', 'pause'});
    if (data['skip'] is! bool ||
        data['reorder'] is! bool ||
        data['remove'] is! bool ||
        data['add'] is! bool ||
        data['pause'] is! bool) {
      throw const JamException('Permisos inválidos.');
    }
    return JamPermissions(
      skip: data['skip'],
      reorder: data['reorder'],
      remove: data['remove'],
      add: data['add'],
      pause: data['pause'],
    );
  }
}

/// Reglas de la sala; solo el anfitrión las cambia.
class JamRules {
  const JamRules({
    this.maxGuests = 15,
    this.maxPerGuest = 10,
    this.votes = true,
    this.approve = false,
    this.open = true,
    this.suggest = true,
    this.autoplay = false,
  });
  final int maxGuests, maxPerGuest;
  final bool votes, approve, open, suggest;

  /// Autoplay de la Jam (apagado por defecto, como la Jam de Spotify: suena lo
  /// que añade la gente): si se enciende, el anfitrión mantiene la cola con
  /// sugerencias.
  final bool autoplay;
  JamRules copyWith({
    int? maxGuests,
    int? maxPerGuest,
    bool? votes,
    bool? approve,
    bool? open,
    bool? suggest,
    bool? autoplay,
  }) => JamRules(
    maxGuests: (maxGuests ?? this.maxGuests).clamp(1, 15),
    maxPerGuest: (maxPerGuest ?? this.maxPerGuest).clamp(1, 50),
    votes: votes ?? this.votes,
    approve: approve ?? this.approve,
    open: open ?? this.open,
    suggest: suggest ?? this.suggest,
    autoplay: autoplay ?? this.autoplay,
  );
  Map<String, Object> toJson() => {
    'maxGuests': maxGuests,
    'maxPerGuest': maxPerGuest,
    'votes': votes,
    'approve': approve,
    'open': open,
    'suggest': suggest,
    'autoplay': autoplay,
  };
  factory JamRules.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'maxGuests',
      'maxPerGuest',
      'votes',
      'approve',
      'open',
      'suggest',
      'autoplay',
    });
    if (data['votes'] is! bool ||
        data['approve'] is! bool ||
        data['open'] is! bool ||
        data['suggest'] is! bool ||
        (data['autoplay'] != null && data['autoplay'] is! bool)) {
      throw const JamException('Reglas inválidas.');
    }
    final guests = jamInt(data['maxGuests'], max: 15);
    final each = jamInt(data['maxPerGuest'], max: 50);
    if (guests < 1 || each < 1) throw const JamException('Reglas inválidas.');
    return JamRules(
      maxGuests: guests,
      maxPerGuest: each,
      votes: data['votes'],
      approve: data['approve'],
      open: data['open'],
      suggest: data['suggest'],
      autoplay: data['autoplay'] == true,
    );
  }
}

class JamParticipant {
  const JamParticipant({
    required this.id,
    required this.name,
    this.connected = true,
    this.permissions = const JamPermissions(),
    this.role = JamRole.guest,
    this.muted = false,
    this.listening = true,
  });
  final String id, name;
  final bool connected, muted, listening;
  final JamPermissions permissions;
  final JamRole role;
  bool get isHost => role == JamRole.host;

  /// Anfitrión y coanfitriones moderan y no tienen límites de invitado.
  bool get isStaff => role != JamRole.guest;
  JamParticipant copyWith({
    String? name,
    bool? connected,
    JamPermissions? permissions,
    JamRole? role,
    bool? muted,
    bool? listening,
  }) => JamParticipant(
    id: id,
    name: name ?? this.name,
    connected: connected ?? this.connected,
    permissions: permissions ?? this.permissions,
    role: role ?? this.role,
    muted: muted ?? this.muted,
    listening: listening ?? this.listening,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'connected': connected,
    'permissions': permissions.toJson(),
    'role': role.name,
    'muted': muted,
    'listening': listening,
  };
  factory JamParticipant.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'id',
      'name',
      'connected',
      'permissions',
      'role',
      'muted',
      'listening',
    });
    if (data['connected'] is! bool ||
        data['muted'] is! bool ||
        data['listening'] is! bool ||
        !JamRole.values.any((r) => r.name == data['role'])) {
      throw const JamException('Participante inválido.');
    }
    return JamParticipant(
      id: jamIdentifier(data['id']),
      name: jamText(data['name'], max: 32),
      connected: data['connected'],
      permissions: JamPermissions.fromJson(data['permissions']),
      role: JamRole.values.firstWhere((r) => r.name == data['role']),
      muted: data['muted'],
      listening: data['listening'],
    );
  }
}

class JamQueueEntry {
  const JamQueueEntry({
    required this.id,
    required this.track,
    required this.addedBy,
    this.status = JamEntryStatus.queued,
    this.up = const [],
    this.down = const [],
    this.suggestedFor,
  });
  final String id, addedBy;

  /// Participante para quien se sugirió/autoañadió la pista (null si la puso
  /// alguien a mano). La UI muestra «Sugerida para {nombre}».
  final String? suggestedFor;
  final JamTrack track;
  final JamEntryStatus status;

  /// Ids de quienes votaron a favor / en contra (un voto por persona).
  final List<String> up, down;
  int get score => up.length - down.length;
  bool get playable => status != JamEntryStatus.pending;
  JamQueueEntry copyWith({
    JamEntryStatus? status,
    List<String>? up,
    List<String>? down,
    String? addedBy,
  }) => JamQueueEntry(
    id: id,
    track: track,
    addedBy: addedBy ?? this.addedBy,
    status: status ?? this.status,
    up: up ?? this.up,
    down: down ?? this.down,
    suggestedFor: suggestedFor,
  );
  Map<String, Object> toJson() => {
    'id': id,
    'track': track.toJson(),
    'addedBy': addedBy,
    'status': status.name,
    'up': up,
    'down': down,
    'suggestedFor': ?suggestedFor,
  };
  factory JamQueueEntry.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'id',
      'track',
      'addedBy',
      'status',
      'up',
      'down',
      'suggestedFor',
    });
    List<String> votes(Object? value) {
      if (value is! List || value.length > 16) {
        throw const JamException('Votos inválidos.');
      }
      final ids = value.map(jamIdentifier).toList();
      if (ids.toSet().length != ids.length) {
        throw const JamException('Votos inválidos.');
      }
      return ids;
    }

    if (!JamEntryStatus.values.any((v) => v.name == data['status'])) {
      throw const JamException('Estado de canción inválido.');
    }
    return JamQueueEntry(
      id: jamIdentifier(data['id']),
      track: JamTrack.fromJson(data['track']),
      addedBy: jamIdentifier(data['addedBy']),
      status: JamEntryStatus.values.firstWhere((v) => v.name == data['status']),
      up: votes(data['up']),
      down: votes(data['down']),
      suggestedFor: data['suggestedFor'] == null
          ? null
          : jamIdentifier(data['suggestedFor']),
    );
  }
}

class JamPlayback {
  const JamPlayback({
    required this.sequence,
    required this.serverTimeMs,
    this.entryId,
    this.isPlaying = false,
    this.positionMs = 0,
  });
  final int sequence, serverTimeMs, positionMs;
  final String? entryId;
  final bool isPlaying;
  Map<String, Object?> toJson() => {
    'sequence': sequence,
    'serverTimeMs': serverTimeMs,
    'entryId': entryId,
    'isPlaying': isPlaying,
    'positionMs': positionMs,
  };
  factory JamPlayback.fromJson(Object? raw) {
    final data = jamMap(raw);
    jamKeys(data, {
      'sequence',
      'serverTimeMs',
      'entryId',
      'isPlaying',
      'positionMs',
    });
    if (data['isPlaying'] is! bool) {
      throw const JamException('Reproducción inválida.');
    }
    return JamPlayback(
      sequence: jamInt(data['sequence']),
      serverTimeMs: jamInt(data['serverTimeMs'], max: 8640000000000000),
      entryId: data['entryId'] == null ? null : jamIdentifier(data['entryId']),
      isPlaying: data['isPlaying'],
      positionMs: jamInt(data['positionMs'], max: 86400000),
    );
  }
}

/// Sugerencia del grupo lista para mostrar: pista, para quién y por qué.
class GroupSuggestion {
  const GroupSuggestion({
    required this.entryId,
    required this.track,
    required this.forId,
    required this.forName,
    required this.reason,
  });
  final String entryId, forId, forName, reason;
  final JamTrack track;
}

enum JamAddMode { end, playNext, playNow, shuffle }

/// Avance observable de «añadir en lotes».
class JamAddProgress {
  const JamAddProgress({
    this.done = 0,
    this.total = 0,
    this.running = false,
    this.dropped = 0,
    this.message,
  });
  final int done, total, dropped;
  final bool running;

  /// Resumen legible: tope aplicado y qué se descartó.
  final String? message;
}
