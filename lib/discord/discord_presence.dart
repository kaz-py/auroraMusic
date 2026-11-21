import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../core/models.dart';

const discordClientId = String.fromEnvironment('AURORA_DISCORD_CLIENT_ID');

/// Rich Presence: Windows (tubería) y Linux (socket Unix), con client id.
bool get discordAvailable => _desktop && discordClientId.isNotEmpty;

/// Escritorio donde Discord tiene sentido, haya o no client id en la compilación.
bool get discordSupported => _desktop;

bool get _desktop => Platform.isWindows || Platform.isLinux;

/// Sockets IPC de Discord en Linux: `discord-ipc-N` en el directorio de
/// ejecución o temporal, también dentro de Flatpak y Snap.
List<String> discordSocketPaths(Map<String, String> environment) => [
  for (final directory in {
    environment['XDG_RUNTIME_DIR'],
    environment['TMPDIR'],
    environment['TMP'],
    environment['TEMP'],
    '/tmp',
  })
    if (directory != null && directory.isNotEmpty)
      for (final sandbox in const [
        '',
        'app/com.discordapp.Discord/',
        'snap.discord/',
      ])
        for (var i = 0; i < 10; i++) '$directory/${sandbox}discord-ipc-$i',
];

/// Trama IPC de Discord: int32le opcode + int32le longitud + JSON utf8.
Uint8List encodeDiscordFrame(int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final out = ByteData(8 + body.length)
    ..setInt32(0, opcode, Endian.little)
    ..setInt32(4, body.length, Endian.little);
  return Uint8List.view(out.buffer)..setRange(8, 8 + body.length, body);
}

/// Decodifica una trama completa al inicio de [bytes]; null si está incompleta.
({int opcode, Map<String, dynamic> payload, int length})? decodeDiscordFrame(
  List<int> bytes,
) {
  if (bytes.length < 8) return null;
  final head = ByteData.sublistView(Uint8List.fromList(bytes.sublist(0, 8)));
  final size = head.getInt32(4, Endian.little);
  if (size < 0 || bytes.length < 8 + size) return null;
  final json = jsonDecode(utf8.decode(bytes.sublist(8, 8 + size)));
  return (
    opcode: head.getInt32(0, Endian.little),
    payload: json is Map<String, dynamic> ? json : const {},
    length: 8 + size,
  );
}

/// Discord exige 2..128 caracteres en details/state/large_text; si no, rechaza
/// toda la actividad. Recorta con elipsis y rellena lo demasiado corto.
String discordText(String? text, [String fallback = 'Aurora Music']) {
  var t = (text ?? '').trim();
  if (t.isEmpty) t = fallback;
  final runes = t.runes.toList();
  if (runes.length > 128) t = '${String.fromCharCodes(runes.take(127))}…';
  return t.runes.length < 2 ? t.padRight(2, '\u00A0') : t;
}

/// Imagen grande: solo https de ≤256 caracteres; si no, el asset `aurora`.
String discordCover(String? url) =>
    url != null && url.startsWith('https://') && url.length <= 256
    ? url
    : 'aurora';

/// Identificador de grupo estable sin exponer el código de la Jam.
String discordPartyId(String? session) =>
    'aurora-jam-${sha256.convert(utf8.encode(session ?? 'jam')).toString().substring(0, 16)}';

/// Comando SET_ACTIVITY; [track] null borra la actividad. Con [jam] la
/// actividad dice que se escucha en una Jam (y [partySize] los oyentes).
Map<String, Object?> buildDiscordActivityCommand({
  required int pid,
  required String nonce,
  Track? track,
  Duration position = Duration.zero,
  DateTime? now,
  bool jam = false,
  int partySize = 0,
  String? partyId,
}) {
  Map<String, Object?>? activity;
  if (track != null) {
    final start =
        (now ?? DateTime.now()).millisecondsSinceEpoch -
        position.inMilliseconds;
    final end = start + track.duration.inMilliseconds;
    activity = {
      'type': 2,
      'details': discordText(track.title),
      'state': discordText(
        jam ? '${track.artist} · en una Jam' : track.artist,
        jam ? 'En una Jam' : 'Artista desconocido',
      ),
      'timestamps': {
        'start': start,
        if (track.duration > Duration.zero && end > start) 'end': end,
      },
      'assets': {
        'large_image': discordCover(track.artworkUrl),
        'large_text': discordText(track.album),
      },
      if (jam && partySize > 0)
        'party': {
          'id': discordPartyId(partyId),
          'size': [partySize, partySize < 16 ? 16 : partySize],
        },
    };
  }
  return {
    'cmd': 'SET_ACTIVITY',
    'args': {'pid': pid, 'activity': activity},
    'nonce': nonce,
  };
}

/// Presencia en Discord por IPC (tubería con nombre). Nunca lanza ni bloquea:
/// la E/S (bloqueante, con lectura de las respuestas de Discord) vive en un
/// Isolate propio que solo conserva el último estado pendiente.
class DiscordPresence {
  DiscordPresence({this.clientId = discordClientId});
  final String clientId;
  bool enabled = true;
  SendPort? _port;
  Isolate? _isolate;
  ReceivePort? _inbox;
  bool _spawning = false;
  String? _pendingCommand;
  String? _lastKey;
  int _nonce = 0;

  /// Último aviso del worker (depuración): «ok», «error: …» o «reconectando».
  String status = '';

  /// Llamar ante cualquier cambio; solo envía si cambió lo que se muestra.
  void update(
    Track? track, {
    required bool playing,
    Duration? position,
    bool jam = false,
    int partySize = 0,
    String? partyId,
  }) {
    final shown = enabled && playing ? track : null;
    final key = shown == null
        ? 'null'
        : '${shown.id}|${shown.title}|${shown.artist}|${shown.album}|'
              '${shown.artworkUrl}|$jam|$partySize';
    if (key == _lastKey) return;
    _lastKey = key;
    _send(
      buildDiscordActivityCommand(
        pid: pid,
        nonce: '${++_nonce}',
        track: shown,
        position: position ?? Duration.zero,
        jam: jam,
        partySize: partySize,
        partyId: partyId,
      ),
    );
  }

  void clear() {
    _lastKey = 'null';
    _send(buildDiscordActivityCommand(pid: pid, nonce: '${++_nonce}'));
  }

  void dispose() {
    if (_port != null) clear();
    final isolate = _isolate;
    _isolate = null;
    _port = null;
    _pendingCommand = null;
    _inbox?.close();
    // Deja que el worker envíe el borrado antes de matarlo.
    if (isolate != null) {
      Timer(const Duration(milliseconds: 400), () => isolate.kill());
    }
  }

  void _send(Map<String, Object?> command) {
    if (clientId.isEmpty || !_desktop) return;
    try {
      final json = jsonEncode(command);
      final port = _port;
      if (port != null) {
        port.send(json);
        return;
      }
      _pendingCommand = json;
      if (!_spawning) unawaited(_spawn());
    } catch (_) {}
  }

  Future<void> _spawn() async {
    _spawning = true;
    try {
      final inbox = ReceivePort();
      _inbox = inbox;
      inbox.listen((message) {
        if (message is SendPort) {
          _port = message;
          final pending = _pendingCommand;
          _pendingCommand = null;
          if (pending != null) message.send(pending);
        } else if (message is String) {
          status = message;
        }
      });
      final void Function((SendPort, String)) worker = Platform.isWindows
          ? _presenceWorker
          : _presenceWorkerUnix;
      _isolate = await Isolate.spawn(worker, (inbox.sendPort, clientId));
    } catch (_) {
      _spawning = false;
    }
  }
}

/// Lee una trama completa; lanza si la tubería se cerró.
({int opcode, Map<String, dynamic> payload}) _readFrame(RandomAccessFile f) {
  List<int> read(int n) {
    final out = <int>[];
    while (out.length < n) {
      final chunk = f.readSync(n - out.length);
      if (chunk.isEmpty) throw const FileSystemException('pipe closed');
      out.addAll(chunk);
    }
    return out;
  }

  final head = read(8);
  final size = ByteData.sublistView(
    Uint8List.fromList(head),
  ).getInt32(4, Endian.little);
  if (size < 0 || size > 1 << 20) throw const FormatException('bad frame');
  final frame = decodeDiscordFrame([...head, ...read(size)])!;
  return (opcode: frame.opcode, payload: frame.payload);
}

/// Worker: conecta, saluda, lee READY y por cada actividad escribe y lee la
/// respuesta. Si falla, reintenta cada 30 s reenviando solo la última.
void _presenceWorker((SendPort, String) args) {
  final (toMain, clientId) = args;
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  RandomAccessFile? pipe;
  String? latest;
  var dirty = false;
  var nextTry = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? timer;

  void drop() {
    try {
      pipe?.closeSync();
    } catch (_) {}
    pipe = null;
  }

  bool connect() {
    if (DateTime.now().isBefore(nextTry)) return false;
    nextTry = DateTime.now().add(const Duration(seconds: 30));
    for (var i = 0; i < 10; i++) {
      RandomAccessFile? candidate;
      try {
        // La ruta \\.\pipe\ falla en dart:io (errno 53); GLOBALROOT sí abre.
        candidate = File(
          r'\\?\GLOBALROOT\Device\NamedPipe\discord-ipc-'
          '$i',
        ).openSync(mode: FileMode.append);
        candidate.writeFromSync(
          encodeDiscordFrame(0, {'v': 1, 'client_id': clientId}),
        );
        final ready = _readFrame(candidate);
        if (ready.payload['evt'] == 'READY') {
          pipe = candidate;
          return true;
        }
      } catch (_) {}
      try {
        candidate?.closeSync();
      } catch (_) {}
    }
    toMain.send('sin Discord');
    return false;
  }

  void flush() {
    timer = null;
    final json = latest;
    if (json == null || !dirty) return;
    if (pipe == null && !connect()) {
      final wait = nextTry.difference(DateTime.now());
      timer = Timer(wait.isNegative ? Duration.zero : wait, flush);
      return;
    }
    try {
      pipe!.writeFromSync(
        encodeDiscordFrame(1, jsonDecode(json) as Map<String, Object?>),
      );
      final reply = _readFrame(pipe!);
      if (reply.opcode == 2) throw const FormatException('closed');
      dirty = false;
      toMain.send(
        reply.payload['evt'] == 'ERROR'
            ? 'error: ${reply.payload['data']}'
            : 'ok',
      );
    } catch (_) {
      drop();
      toMain.send('reconectando');
      timer = Timer(const Duration(seconds: 30), flush);
    }
  }

  inbox.listen((message) {
    if (message is! String) return;
    latest = message; // solo importa la última
    dirty = true;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 50), flush);
  });
}

/// Worker de Linux: lo mismo que [_presenceWorker] sobre un socket Unix, que en
/// dart:io solo es asíncrono.
Future<void> _presenceWorkerUnix((SendPort, String) args) async {
  final (toMain, clientId) = args;
  final inbox = ReceivePort();
  toMain.send(inbox.sendPort);
  Socket? socket;
  final buffer = <int>[];
  Completer<({int opcode, Map<String, dynamic> payload})>? reply;
  String? latest;
  var dirty = false;
  var busy = false;
  Timer? timer;

  void drop() {
    socket?.destroy();
    socket = null;
    buffer.clear();
    final waiting = reply;
    reply = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(const SocketException('closed'));
    }
  }

  void received(List<int> data) {
    buffer.addAll(data);
    try {
      for (
        var frame = decodeDiscordFrame(buffer);
        frame != null;
        frame = decodeDiscordFrame(buffer)
      ) {
        buffer.removeRange(0, frame.length);
        final waiting = reply;
        reply = null;
        waiting?.complete((opcode: frame.opcode, payload: frame.payload));
      }
    } on FormatException {
      drop();
    }
  }

  Future<({int opcode, Map<String, dynamic> payload})> next() {
    final waiting = reply = Completer();
    return waiting.future.timeout(const Duration(seconds: 10));
  }

  Future<bool> connect() async {
    for (final path in discordSocketPaths(Platform.environment)) {
      if (FileSystemEntity.typeSync(path) !=
          FileSystemEntityType.unixDomainSock) {
        continue;
      }
      try {
        final candidate = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        );
        socket = candidate;
        candidate.listen(received, onError: (_) => drop(), onDone: drop);
        candidate.add(encodeDiscordFrame(0, {'v': 1, 'client_id': clientId}));
        if ((await next()).payload['evt'] == 'READY') return true;
      } catch (_) {}
      drop();
    }
    toMain.send('sin Discord');
    return false;
  }

  Future<void> flush() async {
    timer = null;
    if (busy || latest == null || !dirty) return;
    busy = true;
    try {
      if (socket == null && !await connect()) {
        timer = Timer(const Duration(seconds: 30), flush);
        return;
      }
      dirty = false;
      socket!.add(
        encodeDiscordFrame(1, jsonDecode(latest!) as Map<String, Object?>),
      );
      final answer = await next();
      if (answer.opcode == 2) throw const FormatException('closed');
      toMain.send(
        answer.payload['evt'] == 'ERROR'
            ? 'error: ${answer.payload['data']}'
            : 'ok',
      );
    } catch (_) {
      dirty = true;
      drop();
      toMain.send('reconectando');
      timer = Timer(const Duration(seconds: 30), flush);
    } finally {
      busy = false;
      // Llegó otra actividad mientras se enviaba esta.
      if (dirty && timer == null) timer = Timer(Duration.zero, flush);
    }
  }

  inbox.listen((message) {
    if (message is! String) return;
    latest = message; // solo importa la última
    dirty = true;
    timer?.cancel();
    timer = Timer(const Duration(milliseconds: 50), flush);
  });
}
