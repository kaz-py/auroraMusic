import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../core/queue_policy.dart';
import 'jam_models.dart';
import 'jam_peer.dart';
import 'jam_suggestions.dart';
import 'transport/jam_hub.dart';
import 'transport/jam_transport.dart';

part 'jam_service_remote.dart';
part 'jam_service_add.dart';

/// Host owns every mutation. Participant commands never carry playback/provider credentials.
class JamService extends ChangeNotifier {
  JamService({DateTime Function()? clock, this.allowLoopback = false})
    : clock = clock ?? DateTime.now;
  final DateTime Function() clock;
  final bool allowLoopback;
  JamConnection connection = JamConnection.idle;
  JamMode mode = JamMode.queueOnly;
  JamInvite? invite;
  String participantId = 'host';
  String? error;
  int revision = 0;
  int clockOffsetMs = 0;
  int? roundTripMs;
  List<JamQueueEntry> queue = [];
  List<JamParticipant> participants = [];

  /// Avatares validados por id de participante (misma instancia de bytes
  /// siempre, para que la caché de imágenes decodifique una sola vez).
  final Map<String, Uint8List> avatars = {};

  /// Foto de perfil de este dispositivo; se presenta al unirse.
  Uint8List? localAvatar;

  /// Invitados que anunciaron soporte de avatar: solo a ellos se les difunden.
  final Set<String> _avatarPeers = {};
  bool _avatarProbe = false, _hostLacksAvatar = false;
  JamPlayback? playback;
  Future<void> Function()? onSkip;
  HttpServer? _server;
  JamPeer? _client;
  HttpClient? _httpClient;
  Timer? _expiryTimer, _pingTimer;
  final Map<String, JamPeer> _sockets = {};
  final Map<String, String> _resumeTokens = {};
  final Map<String, List<DateTime>> _rates = {};
  final Set<String> _joiningIds = {};
  final Map<int, int> _pings = {};
  String? _resumeToken;
  String _name = '';
  int _generation = 0;
  int _pendingUpgrades = 0;
  bool _disposed = false;
  JamRules rules = const JamRules();
  JamTransport? _transport;
  JamHubHost? _hub;
  JamRoomInfo? _room;
  String _uid = '';
  Timer? _beatTimer, _retryTimer, _hostLostTimer;
  int _attempt = 0;
  bool _stopRetry = false;
  final Map<String, List<JamSuggestion>> _suggestions = {};
  final Map<String, DateTime> _lastSuggest = {};
  String? _lastCode;
  bool _handingOff = false;
  bool _background = false;
  Timer? _probeTimer, _hubWatch;

  /// Espera a que Realtime recupere solo el canal del anfitrión tras volver al
  /// primer plano antes de reabrirlo.
  @visibleForTesting
  Duration hubRecoveryDelay = const Duration(seconds: 10);
  final Set<String> _skipVotes = {};
  Future<void> Function(bool play)? onPlayPause;
  bool get isRemote => _transport != null;
  bool get isHost => connection == JamConnection.hosting;
  bool get connected => isHost || connection == JamConnection.connected;

  /// Conexión caída pero la Jam sigue siendo nuestra: se reconecta sola.
  bool get reconnecting =>
      connection == JamConnection.disconnected &&
      invite != null &&
      !_stopRetry &&
      !_disposed;
  JamParticipant? get me =>
      participants.where((p) => p.id == participantId).firstOrNull;
  Uint8List? avatarOf(String id) => avatars[id];

  /// Cambia el avatar propio: el anfitrión lo difunde; un invitado lo envía al
  /// anfitrión como comando `avatar` (límite propio de trama, ver _receiveCommand).
  void setLocalAvatar(Uint8List? bytes) {
    localAvatar = bytes;
    if (isHost) {
      _setAvatar('host', bytes);
    } else if (connected) {
      _sendMyAvatar();
    }
  }

  /// Anuncia la capacidad de avatar al anfitrión (data vacío si no hay foto).
  /// Un anfitrión antiguo contesta `error: invalid` (no cierra); eso se detecta
  /// con [_avatarProbe] y se deja de enviar avatares en esa conexión.
  void _sendMyAvatar() {
    if (isHost || _hostLacksAvatar) return;
    final bytes = localAvatar;
    _avatarProbe = true;
    _sendSocket(
      _client,
      jsonEncode({
        'kind': 'avatar',
        'data': bytes == null ? '' : base64Encode(bytes),
      }),
    );
  }

  void _setAvatar(String id, Uint8List? bytes) {
    if (bytes == null) {
      if (avatars.remove(id) == null) return;
    } else {
      avatars[id] = bytes;
    }
    final data = _avatarMessage(id);
    for (final entry in _sockets.entries) {
      if (entry.key != id && _avatarPeers.contains(entry.key)) {
        _sendSocket(entry.value, data);
      }
    }
    _notify();
  }

  String _avatarMessage(String id) => jsonEncode({
    'kind': 'avatar',
    'id': id,
    'data': avatars[id] == null ? '' : base64Encode(avatars[id]!),
  });

  void _sendAvatarsTo(String id) {
    for (final other in avatars.keys) {
      if (other != id) _sendSocket(_sockets[id], _avatarMessage(other));
    }
  }

  String participantName(String id) =>
      participants.where((p) => p.id == id).firstOrNull?.name ?? 'Participante';
  static const connectionHelp =
      'No se pudo conectar. Comprueba la misma red Wi-Fi, el aislamiento del router y el permiso de firewall de Aurora.';

  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return interfaces
        .expand((i) => i.addresses)
        .map((a) => a.address)
        .where((a) => isJamAddress(a))
        .toSet()
        .toList();
  }

  Future<void> host({
    required String address,
    required String name,
    Duration lifetime = const Duration(hours: 4),
  }) async {
    if (!isJamAddress(address, allowLoopback: allowLoopback) ||
        lifetime <= Duration.zero ||
        lifetime > const Duration(hours: 4)) {
      throw const JamException(
        'Selecciona una dirección privada de tu red local.',
      );
    }
    name = jamText(name, max: 32);
    await close();
    final generation = ++_generation;
    try {
      final server = await HttpServer.bind(
        InternetAddress(address),
        0,
        backlog: 16,
      );
      if (_disposed || generation != _generation) {
        await server.close(force: true);
        return;
      }
      _server = server;
      server.idleTimeout = const Duration(seconds: 10);
      invite = JamInvite(
        address: address,
        port: server.port,
        sessionId: jamRandomSecret(16),
        accessToken: jamRandomSecret(),
        expiresAt: clock().add(lifetime),
      );
      connection = JamConnection.hosting;
      participantId = 'host';
      participants = [
        JamParticipant(
          id: 'host',
          name: name,
          role: JamRole.host,
          permissions: JamPermissions.all,
        ),
      ];
      if (localAvatar != null) avatars['host'] = localAvatar!;
      error = null;
      server.listen(
        (request) {
          unawaited(
            _accept(request).catchError((Object _) async {
              try {
                request.response.statusCode = HttpStatus.forbidden;
                await request.response.close();
              } catch (_) {}
            }),
          );
        },
        onError: (_) {
          error = connectionHelp;
          _notify();
        },
      );
      _expiryTimer = Timer(lifetime, () {
        unawaited(close());
      });
      _changed();
    } catch (_) {
      connection = JamConnection.closed;
      error = connectionHelp;
      _notify();
      throw const JamException(connectionHelp);
    }
  }

  Future<void> _accept(HttpRequest request) async {
    final session = invite;
    final remote = request.connectionInfo?.remoteAddress.address;
    if (_pendingUpgrades >= 16 ||
        session == null ||
        !isHost ||
        !session.expiresAt.isAfter(clock()) ||
        remote == null ||
        !isJamAddress(remote, allowLoopback: allowLoopback) ||
        request.method != 'GET' ||
        request.uri.path != '/jam/${session.sessionId}' ||
        request.uri.hasQuery ||
        request.headers.value('origin') != null ||
        !_equalSecret(
          request.headers.value('authorization') ?? '',
          'Bearer ${session.accessToken}',
        ) ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    _pendingUpgrades++;
    String? reservedId;
    try {
      final name = jamText(
        Uri.decodeComponent(request.headers.value('x-aurora-name') ?? ''),
        max: 32,
      );
      final requestedId = request.headers.value('x-aurora-participant');
      final requestedResume = request.headers.value('x-aurora-resume');
      String id;
      if (requestedId != null || requestedResume != null) {
        if (requestedId == null ||
            requestedResume == null ||
            requestedId == 'host' ||
            requestedId.length != 16 ||
            requestedResume.length != 43 ||
            !_resumeTokens.containsKey(requestedId) ||
            !participants.any((person) => person.id == requestedId) ||
            _joiningIds.contains(requestedId) ||
            !_equalSecret(_resumeTokens[requestedId] ?? '', requestedResume) ||
            _sockets.containsKey(requestedId)) {
          throw const JamException('Reconexión inválida.');
        }
        id = requestedId;
      } else {
        if (participants.length + _pendingUpgrades > 16) {
          throw const JamException(
            'La Jam llegó a su límite de participantes.',
          );
        }
        id = jamRandomSecret(12);
      }
      _joiningIds.add(id);
      reservedId = id;
      final socket = WebSocketPeer(await WebSocketTransformer.upgrade(request));
      if (!isHost || invite != session) {
        await socket.close();
        return;
      }
      _sockets[id] = socket;
      _resumeTokens.putIfAbsent(id, () => jamRandomSecret());
      final prior = participants.where((p) => p.id == id).firstOrNull;
      participants = [
        ...participants.where((p) => p.id != id),
        JamParticipant(
          id: id,
          name: name,
          permissions: prior?.permissions ?? const JamPermissions(),
        ),
      ];
      socket.add(
        jsonEncode({
          'kind': 'welcome',
          'participantId': id,
          'resumeToken': _resumeTokens[id],
        }),
      );
      socket.listen(
        (message) => _receiveCommand(id, message),
        onDone: () => _disconnected(id, socket),
        onError: (_) => _disconnected(id, socket),
      );
      _changed();
    } catch (_) {
      try {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      } catch (_) {}
    } finally {
      if (reservedId != null) _joiningIds.remove(reservedId);
      _pendingUpgrades--;
    }
  }

  Future<void> join(JamInvite session, {required String name}) async {
    // Revalidate constructed invitations too; URLs/hostnames never reach the transport.
    session = JamInvite.decode(
      session.encode(),
      allowLoopback: allowLoopback,
      now: clock(),
    );
    name = jamText(name, max: 32);
    await close();
    invite = session;
    _name = name;
    _resumeToken = null;
    participantId = '';
    await reconnect();
  }

  Future<void> reconnect() async {
    final session = invite;
    if (session == null || !session.expiresAt.isAfter(clock())) {
      throw const JamException(
        'La invitación de Jam venció. Solicita un QR nuevo.',
      );
    }
    final generation = ++_generation;
    final ready = Completer<void>();
    _avatarProbe = _hostLacksAvatar = false;
    error = null;
    connection = JamConnection.disconnected;
    _notify();
    try {
      await _client?.close();
      _httpClient?.close(force: true);
      final JamPeer socket = _transport != null
          ? await _remotePeer(session)
          : await _lanPeer(session);
      if (_disposed || generation != _generation) {
        await socket.close();
        return;
      }
      _client = socket;
      if (_background && socket is JamGuestPeer) socket.pause();
      socket.listen(
        (message) {
          if (_disposed || generation != _generation) return;
          try {
            final data = _message(message, maxBytes: 1024 * 1024);
            switch (data['kind']) {
              case 'welcome':
                jamKeys(data, {'kind', 'participantId', 'resumeToken'});
                final id = jamIdentifier(data['participantId']);
                final resume = jamIdentifier(data['resumeToken']);
                if (id == 'host' ||
                    (_transport == null && resume.length != 43)) {
                  throw const JamException('Identidad inválida.');
                }
                participantId = id;
                _resumeToken = resume;
              case 'state':
                _snapshot(data);
                if (participantId.isEmpty ||
                    !participants.any((p) => p.id == participantId)) {
                  throw const JamException('Participante ausente.');
                }
                connection = JamConnection.connected;
                if (!ready.isCompleted) ready.complete();
                _notify();
              case 'pong':
                jamKeys(data, {'kind', 'sent', 'serverTimeMs'});
                _avatarProbe = false;
                final sent = jamInt(data['sent'], max: 8640000000000000);
                final before = _pings.remove(sent);
                if (before != null) {
                  final after = clock().millisecondsSinceEpoch;
                  final roundTrip = after - before;
                  if (roundTrip >= 0 && roundTrip < 10000) {
                    roundTripMs = roundTrip;
                    clockOffsetMs =
                        jamInt(data['serverTimeMs'], max: 8640000000000000) -
                        (before + roundTrip ~/ 2);
                    _notify();
                  }
                }
              case 'playback':
                jamKeys(data, {'kind', 'playback'});
                final state = JamPlayback.fromJson(data['playback']);
                if (state.entryId != null &&
                    !queue.any((entry) => entry.id == state.entryId)) {
                  throw const JamException('Pista de reproducción inválida.');
                }
                if (playback == null || state.sequence >= playback!.sequence) {
                  playback = state;
                }
                _notify();
              case 'avatar':
                jamKeys(data, {'kind', 'id', 'data'});
                final who = jamIdentifier(data['id']);
                if (data['data'] == '') {
                  avatars.remove(who);
                } else {
                  final bytes = jamAvatarFromBase64(data['data']);
                  if (bytes != null) avatars[who] = bytes;
                }
                _notify();
              case 'kicked':
                jamKeys(data, {'kind'});
                _endRemote('Te expulsaron de la Jam.');
              case 'handoff':
                jamKeys(data, {'kind', 'to', 'from'});
                _handoff(
                  jamIdentifier(data['to']),
                  jamIdentifier(data['from']),
                );
              case 'error':
                jamKeys(data, {'kind', 'code'});
                if (!{
                  'permissions',
                  'rate',
                  'full',
                  'invalid',
                  'limit',
                  'muted',
                }.contains(data['code'])) {
                  throw const JamException('Código de error inválido.');
                }
                if (_avatarProbe && data['code'] == 'invalid') {
                  // Anfitrión antiguo: no entiende `avatar`; se ignora sin aviso.
                  _avatarProbe = false;
                  _hostLacksAvatar = true;
                  return;
                }
                error = _commandError(data['code']);
                _notify();
              case 'closed':
                jamKeys(data, {'kind'});
                connection = JamConnection.closed;
                _endRemote('El anfitrión cerró la Jam.');
              default:
                throw const JamException('Protocolo de Jam inválido.');
            }
          } catch (_) {
            error = 'La Jam recibió un mensaje inválido.';
            if (!ready.isCompleted) {
              ready.completeError(
                const JamException('La sesión no respondió correctamente.'),
              );
            }
            unawaited(socket.close(WebSocketStatus.policyViolation));
            _notify();
          }
        },
        onError: (Object _) {
          if (generation == _generation) {
            _clientDisconnected();
            if (!ready.isCompleted) {
              ready.completeError(const JamException(connectionHelp));
            }
          }
        },
        onDone: () {
          if (generation == _generation) {
            _clientDisconnected();
            if (!ready.isCompleted) {
              ready.completeError(const JamException(connectionHelp));
            }
          }
        },
      );
      await ready.future.timeout(
        Duration(seconds: _transport == null ? 5 : 12),
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(
        // En línea cada ping es una llamada al servidor (3 escrituras y un
        // mensaje): 20 s bastan para mantener el reloj sincronizado.
        Duration(seconds: _transport == null ? 2 : 20),
        (_) => _ping(),
      );
      _sendMyAvatar();
      _ping();
      _attempt = 0;
      _hostLostTimer?.cancel();
    } catch (failure) {
      if (generation != _generation || _disposed) return;
      _httpClient?.close(force: true);
      await _client?.close();
      _client = null;
      connection = JamConnection.disconnected;
      _lastCode = failure is JamRemoteException ? failure.code : null;
      error = failure is JamException ? failure.message : connectionHelp;
      _notify();
      _scheduleRetry();
      throw JamException(error!);
    }
  }

  Future<JamPeer> _lanPeer(JamInvite session) async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    // A redirect can never leak authorization to another host or port.
    http.connectionFactory = (uri, proxyHost, proxyPort) {
      if (uri.host != session.address ||
          uri.port != session.port ||
          proxyHost != null) {
        throw const JamException('Destino de conexión de Jam inválido.');
      }
      return Socket.startConnect(
        InternetAddress(session.address),
        session.port,
      );
    };
    http.findProxy = (_) => 'DIRECT';
    _httpClient = http;
    return WebSocketPeer(
      await WebSocket.connect(
        'ws://${session.address}:${session.port}/jam/${session.sessionId}',
        customClient: http,
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
          'X-Aurora-Name': Uri.encodeComponent(_name),
          if (_resumeToken != null) ...{
            'X-Aurora-Participant': participantId,
            'X-Aurora-Resume': _resumeToken!,
          },
        },
      ).timeout(const Duration(seconds: 6)),
    );
  }

  void _snapshot(Map<String, dynamic> data) {
    jamKeys(data, {
      'kind',
      'revision',
      'mode',
      'queue',
      'participants',
      'playback',
      'rules',
    });
    final next = jamInt(data['revision']);
    if (next < revision) return;
    final rawQueue = data['queue'];
    final rawPeople = data['participants'];
    if (rawQueue is! List ||
        rawQueue.length > 200 ||
        rawPeople is! List ||
        rawPeople.length > 16 ||
        rawPeople.isEmpty ||
        !JamMode.values.any((v) => v.name == data['mode'])) {
      throw const JamException('Estado de Jam inválido.');
    }
    final entries = rawQueue.map(JamQueueEntry.fromJson).toList();
    final people = rawPeople.map(JamParticipant.fromJson).toList();
    if (entries.map((e) => e.id).toSet().length != entries.length ||
        people.map((p) => p.id).toSet().length != people.length ||
        !people.any((p) => p.id == 'host') ||
        entries.any((e) => !people.any((p) => p.id == e.addedBy))) {
      throw const JamException('Estado de Jam inválido.');
    }
    final state = data['playback'] == null
        ? null
        : JamPlayback.fromJson(data['playback']);
    if (state?.entryId != null &&
        !entries.any((entry) => entry.id == state!.entryId)) {
      throw const JamException('Pista de reproducción inválida.');
    }
    if (data['rules'] != null) rules = JamRules.fromJson(data['rules']);
    revision = next;
    queue = entries;
    participants = people;
    avatars.removeWhere((id, _) => !people.any((p) => p.id == id));
    mode = JamMode.values.firstWhere((v) => v.name == data['mode']);
    if (state != null &&
        (playback == null || state.sequence >= playback!.sequence)) {
      playback = state;
    }
  }

  void _receiveCommand(String id, Object? message) {
    try {
      if (!isHost || invite == null || !invite!.expiresAt.isAfter(clock())) {
        return;
      }
      _takeRequest(id);
      // Solo el avatar (base64 de hasta 24 KiB) puede superar los 8 KiB.
      final isAvatar =
          message is String && message.startsWith('{"kind":"avatar"');
      final data = _message(message, maxBytes: isAvatar ? 40960 : 8192);
      _command(id, data);
    } on JamException catch (failure) {
      _sendSocket(
        _sockets[id],
        jsonEncode({
          'kind': 'error',
          'code':
              {
                'permissions',
                'rate',
                'full',
                'limit',
                'muted',
              }.contains(failure.message)
              ? failure.message
              : 'invalid',
        }),
      );
      if (failure.message == 'rate') {
        unawaited(_sockets[id]?.close(WebSocketStatus.policyViolation));
      }
    } catch (_) {
      _sendSocket(
        _sockets[id],
        jsonEncode({'kind': 'error', 'code': 'invalid'}),
      );
    }
  }

  void _command(String id, Map<String, dynamic> data) {
    final participant = participants
        .where((p) => p.id == id && p.connected)
        .firstOrNull;
    if (participant == null) throw const JamException('permissions');
    switch (data['kind']) {
      case 'add':
        jamKeys(data, {'kind', 'track', 'suggested'});
        if (participant.muted) throw const JamException('muted');
        if (!participant.permissions.add) {
          throw const JamException('permissions');
        }
        final track = JamTrack.fromJson(data['track']);
        final dup = queue.indexWhere(
          (entry) => entry.track.keys.any(track.keys.contains),
        );
        if (dup >= 0) {
          // Añadir una sugerida «A continuación» la sube a la cola normal.
          final old = queue[dup];
          if (old.status == JamEntryStatus.suggested &&
              old.id != playback?.entryId) {
            queue = [...queue]
              ..[dup] = old.copyWith(
                status: rules.approve && !participant.isStaff
                    ? JamEntryStatus.pending
                    : JamEntryStatus.queued,
                addedBy: id,
              );
            _changed();
          }
          return;
        }
        if (queue.length >= 200) throw const JamException('full');
        if (!participant.isStaff &&
            queue.where((e) => e.addedBy == id).length >= rules.maxPerGuest) {
          throw const JamException('limit');
        }
        queue = [
          ...queue,
          JamQueueEntry(
            id: jamRandomSecret(12),
            track: track,
            addedBy: id,
            status: participant.isStaff
                ? (data['suggested'] == true
                      ? JamEntryStatus.suggested
                      : JamEntryStatus.queued)
                : rules.approve
                ? JamEntryStatus.pending
                : JamEntryStatus.queued,
          ),
        ];
        _changed();
      case 'suggest':
        jamKeys(data, {'kind', 'items'});
        final raw = data['items'];
        if (!rules.suggest || participant.muted) {
          throw const JamException('permissions');
        }
        if (raw is! List || raw.length > jamSuggestionsPerPerson) {
          throw const JamException('invalid');
        }
        final last = _lastSuggest[id];
        if (last != null && clock().difference(last) < jamSuggestionsInterval) {
          throw const JamException('rate');
        }
        _suggestions[id] = raw.map(JamSuggestion.fromJson).toList();
        _lastSuggest[id] = clock();
        _rebuildSuggested();
        _changed();
      case 'vote':
        jamKeys(data, {'kind', 'entryId', 'v'});
        if (!rules.votes || participant.muted) {
          throw const JamException('permissions');
        }
        _vote(id, jamIdentifier(data['entryId']), jamInt(data['v'], max: 1));
      case 'voteskip':
        jamKeys(data, {'kind'});
        if (!rules.votes || participant.muted) {
          throw const JamException('permissions');
        }
        _skipVotes.add(id);
        final voters = participants.where((p) => p.connected).length;
        if (_skipVotes.length * 2 > voters) {
          _skipVotes.clear();
          unawaited(onSkip?.call());
        }
        _notify();
      case 'pause':
        jamKeys(data, {'kind', 'play'});
        if (!participant.permissions.pause || data['play'] is! bool) {
          throw const JamException('permissions');
        }
        unawaited(onPlayPause?.call(data['play'] as bool));
      case 'avatar':
        jamKeys(data, {'kind', 'data'});
        // Un avatar inválido se ignora sin error ni cierre de sesión.
        if (id != 'host' && _avatarPeers.add(id)) _sendAvatarsTo(id);
        if (data['data'] == '') {
          if (id != 'host') _setAvatar(id, null);
        } else {
          final bytes = jamAvatarFromBase64(data['data']);
          if (bytes != null && id != 'host') _setAvatar(id, bytes);
        }
      case 'listen':
        jamKeys(data, {'kind', 'on'});
        if (data['on'] is! bool) throw const JamException('invalid');
        participants = [
          for (final p in participants)
            p.id == id ? p.copyWith(listening: data['on'] as bool) : p,
        ];
        _changed();
      case 'remove':
        jamKeys(data, {'kind', 'entryId'});
        if (!participant.permissions.remove) {
          throw const JamException('permissions');
        }
        final entryId = jamIdentifier(data['entryId']);
        queue = queue.where((entry) => entry.id != entryId).toList();
        if (playback?.entryId == entryId) {
          playback = JamPlayback(
            sequence: (playback?.sequence ?? 0) + 1,
            serverTimeMs: clock().millisecondsSinceEpoch,
          );
        }
        _changed();
      case 'reorder':
        jamKeys(data, {'kind', 'entryId', 'to'});
        if (!participant.permissions.reorder) {
          throw const JamException('permissions');
        }
        final entryId = jamIdentifier(data['entryId']);
        final target = jamInt(data['to'], max: 199);
        final index = queue.indexWhere((entry) => entry.id == entryId);
        if (index < 0 || target >= queue.length) {
          throw const JamException('invalid');
        }
        final copy = [...queue];
        final entry = copy.removeAt(index);
        copy.insert(target, entry);
        queue = copy;
        _changed();
      case 'skip':
        jamKeys(data, {'kind'});
        if (!participant.permissions.skip) {
          throw const JamException('permissions');
        }
        unawaited(
          onSkip?.call().catchError((Object _) {
            error = 'No se pudo avanzar la reproducción.';
            _notify();
          }),
        );
      case 'ping':
        jamKeys(data, {'kind', 'sent'});
        final sent = jamInt(data['sent'], max: 8640000000000000);
        _sendSocket(
          _sockets[id],
          jsonEncode({
            'kind': 'pong',
            'sent': sent,
            'serverTimeMs': clock().millisecondsSinceEpoch,
          }),
        );
      case 'leave':
        jamKeys(data, {'kind'});
        // Keep public author information for existing queue entries, invalidate reconnect permission.
        _resumeTokens.remove(id);
        unawaited(_sockets[id]?.close());
      default:
        throw const JamException('invalid');
    }
  }

  void addTrack(JamTrack track) =>
      _sendCommand({'kind': 'add', 'track': track.toJson()});
  void remove(String entryId) =>
      _sendCommand({'kind': 'remove', 'entryId': entryId});
  void reorder(String entryId, int to) =>
      _sendCommand({'kind': 'reorder', 'entryId': entryId, 'to': to});
  void skip() => _sendCommand({'kind': 'skip'});

  /// Publica las sugerencias de este dispositivo (máx. 5, cada 60 s).
  void publishSuggestions(List<JamSuggestion> items) => _sendCommand({
    'kind': 'suggest',
    'items': [for (final i in items.take(jamSuggestionsPerPerson)) i.toJson()],
  });
  void voteSkip() => _sendCommand({'kind': 'voteskip'});

  /// [v]: 1 a favor, -1 en contra, 0 quita el voto.
  void vote(String entryId, int v) =>
      _sendCommand({'kind': 'vote', 'entryId': entryId, 'v': v});
  void requestPlayPause(bool play) =>
      _sendCommand({'kind': 'pause', 'play': play});
  void announceListening(bool on) {
    if (connected && !isHost) _sendCommand({'kind': 'listen', 'on': on});
  }

  /// Sugerencias («A continuación»): solo las añade el anfitrión.
  void addSuggested(JamTrack track) {
    if (!isHost) return;
    _command('host', {
      'kind': 'add',
      'track': track.toJson(),
      'suggested': true,
    });
  }

  void _sendCommand(Map<String, dynamic> command) {
    if (!connected) {
      throw const JamException(
        'Vuelve a conectar con la Jam para modificar la cola.',
      );
    }
    if (isHost) {
      _takeRequest('host');
      _command('host', command);
    } else {
      if (!_sendSocket(_client, jsonEncode(command))) {
        throw const JamException(connectionHelp);
      }
    }
  }

  void _takeRequest(String id) {
    final rates = _rates.putIfAbsent(id, () => []);
    rates.removeWhere(
      (time) => clock().difference(time) >= const Duration(seconds: 5),
    );
    if (rates.length >= 10) throw const JamException('rate');
    rates.add(clock());
  }

  void setPermissions(String id, JamPermissions permissions) {
    if (!isHost || id == 'host') {
      throw const JamException('Solo el anfitrión puede cambiar permisos.');
    }
    participants = participants
        .map(
          (person) => person.id == id
              ? person.copyWith(permissions: permissions)
              : person,
        )
        .toList();
    _changed();
  }

  void setMode(JamMode value) {
    if (!isHost) {
      throw const JamException('Solo el anfitrión puede cambiar el modo.');
    }
    mode = value;
    _changed();
  }

  void publishPlayback({
    String? entryId,
    required bool playing,
    required int positionMs,
  }) {
    if (!isHost) return;
    if (entryId != null && !queue.any((e) => e.id == entryId)) return;
    playback = JamPlayback(
      sequence: (playback?.sequence ?? 0) + 1,
      entryId: entryId,
      isPlaying: playing,
      positionMs: positionMs.clamp(0, 86400000),
      serverTimeMs: clock().millisecondsSinceEpoch,
    );
    final message = jsonEncode({
      'kind': 'playback',
      'playback': playback!.toJson(),
    });
    for (final socket in _sockets.values) {
      _sendSocket(socket, message);
    }
    _notify();
  }

  void _ping() {
    if (connection != JamConnection.connected) return;
    _pings.clear();
    final sent = clock().millisecondsSinceEpoch;
    _pings[sent] = sent;
    _sendSocket(_client, jsonEncode({'kind': 'ping', 'sent': sent}));
  }

  void _changed() {
    revision++;
    _broadcast();
    _notify();
  }

  void _broadcast() {
    if (!isHost) return;
    _prune();
    avatars.removeWhere((id, _) => !participants.any((p) => p.id == id));
    final data = jsonEncode({
      'kind': 'state',
      'revision': revision,
      'mode': mode.name,
      'queue': queue.map((e) => e.toJson()).toList(),
      'participants': participants.map((p) => p.toJson()).toList(),
      'playback': playback?.toJson(),
      'rules': rules.toJson(),
    });
    for (final socket in _sockets.values) {
      _sendSocket(socket, data);
    }
  }

  void _disconnected(String id, JamPeer socket) {
    if (_sockets[id] != socket) return;
    _sockets.remove(id);
    _avatarPeers.remove(id);
    participants = participants
        .map((p) => p.id == id ? p.copyWith(connected: false) : p)
        .toList();
    if (isHost) _changed();
  }

  void _clientDisconnected() {
    _pingTimer?.cancel();
    _probeTimer?.cancel();
    if (connection != JamConnection.closed) {
      connection = JamConnection.disconnected;
      error = isRemote ? _remoteLostMessage() : connectionHelp;
      _scheduleRetry();
    }
    _notify();
  }

  Future<void> close() async {
    ++_generation;
    _expiryTimer?.cancel();
    _pingTimer?.cancel();
    _probeTimer?.cancel();
    _hubWatch?.cancel();
    _pings.clear();
    final server = _server;
    _server = null;
    final client = _client;
    _client = null;
    if (client != null && client.isOpen) {
      _sendSocket(client, jsonEncode({'kind': 'leave'}));
    }
    if (isHost) {
      for (final socket in _sockets.values) {
        if (socket.isOpen) _sendSocket(socket, jsonEncode({'kind': 'closed'}));
      }
    }
    await _closeRemote();
    final sockets = [..._sockets.values];
    _sockets.clear();
    connection = JamConnection.closed;
    mode = JamMode.queueOnly;
    invite = null;
    _resumeToken = null;
    _resumeTokens.clear();
    _rates.clear();
    _suggestions.clear();
    _lastSuggest.clear();
    _joiningIds.clear();
    queue = [];
    participants = [];
    avatars.clear();
    _avatarPeers.clear();
    playback = null;
    revision = 0;
    clockOffsetMs = 0;
    roundTripMs = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    await Future.wait([
      if (client != null) client.close(),
      ...sockets.map((socket) => socket.close()),
    ]);
    await server?.close(force: true);
    _notify();
  }

  /// Testable transport interruption; reconnection retains ephemeral participant credentials.
  Future<void> disconnect() async {
    _pingTimer?.cancel();
    await _client?.close();
    _client = null;
    _clientDisconnected();
  }

  // --- Ciclo de vida: el segundo plano no cierra la Jam ---------------------
  // Android congela red y temporizadores de una app sin audio; al volver, los
  // relojes de silencio vencen aunque nadie se haya ido. Aquí se pausan y, al
  // reanudar, se re-sincroniza (latido, hello, reconexión inmediata).

  bool get inBackground => _background;

  void appBackgrounded() {
    if (_background || _disposed) return;
    _background = true;
    _hub?.pause();
    final client = _client;
    if (client is JamGuestPeer) client.pause();
    _announceBackground(true);
  }

  void appResumed() {
    if (!_background) return;
    _background = false;
    if (_disposed ||
        connection == JamConnection.closed ||
        connection == JamConnection.idle) {
      return;
    }
    _announceBackground(false);
    _hub?.resume();
    _heartbeatNow();
    if (isHost) {
      if (isRemote) {
        _broadcast(); // estado fresco para quien se perdió mensajes
        _watchHub();
      }
      return;
    }
    final client = _client;
    if (client is JamGuestPeer) client.resume();
    if (connection == JamConnection.disconnected) {
      if (_stopRetry || _terminalError || invite == null) return;
      _retryTimer?.cancel();
      _attempt = 0;
      reconnect().catchError((Object _) {});
    } else {
      _probe();
    }
  }

  /// Comprueba que el enlace sigue vivo (un socket puede quedar a medias tras
  /// el segundo plano): sin pong en 6 s se reconecta con el token de reanudación.
  void _probe() {
    _ping();
    final sent = _pings.keys.firstOrNull;
    final generation = _generation;
    _probeTimer?.cancel();
    if (sent == null) return;
    _probeTimer = Timer(const Duration(seconds: 6), () {
      if (_disposed ||
          generation != _generation ||
          connection != JamConnection.connected ||
          !_pings.containsKey(sent)) {
        return;
      }
      unawaited(disconnect());
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    super.dispose();
  }
}

Map<String, dynamic> _message(Object? message, {required int maxBytes}) {
  if (message is! String ||
      message.length > maxBytes ||
      utf8.encode(message).length > maxBytes) {
    throw const JamException('invalid');
  }
  try {
    return jamMap(jsonDecode(message));
  } catch (_) {
    throw const JamException('invalid');
  }
}

bool _equalSecret(String left, String right) {
  if (left.isEmpty || left.length != right.length || left.length > 128) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < left.length; i++) {
    difference |= left.codeUnitAt(i) ^ right.codeUnitAt(i);
  }
  return difference == 0;
}

String _commandError(Object? code) => switch (code) {
  'permissions' => 'El anfitrión no habilitó ese permiso.',
  'rate' => 'Demasiadas solicitudes. Espera unos segundos.',
  'full' => 'La cola compartida llegó al límite de 200 canciones.',
  'limit' => 'Llegaste al límite de canciones que puedes agregar.',
  'muted' => 'El anfitrión te silenció.',
  _ => 'La solicitud de Jam no es válida.',
};

bool _sendSocket(JamPeer? socket, String data) =>
    socket != null && socket.isOpen && socket.add(data);
