import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import '../app_controller.dart';
import '../core/models.dart';
import '../core/queue_policy.dart';
import 'jam_models.dart';
import 'jam_service.dart';
import 'jam_suggestions.dart';
import 'transport/jam_config.dart';
import 'transport/jam_transport.dart';
import 'transport/supabase_jam_transport.dart';
import '../sources/innertube_source.dart';
import 'jam_playback_bridge.dart';

/// Dónde se abre una Jam nueva.
enum JamHostMode { auto, online, lan }

class JamController extends ChangeNotifier with WidgetsBindingObserver {
  JamController({
    required this.app,
    JamService? service,
    JamTransport? transport,
    this.suggestionAdapter,
    this.topUpTimeout = const Duration(seconds: 8),
  }) : service = service ?? JamService(),
       _transport = transport {
    bridge = JamPlaybackBridge(app: app, service: this.service);
    this.service.addListener(_sessionChanged);
    bridge.addListener(_notify);
    this.service.onSkip = next;
    this.service.onPlayPause = (play) async {
      if (play != app.audio.isPlaying) await togglePlayback();
    };
    _completed = app.audio.completed.listen((_) {
      if (this.service.isHost && bridge.enabled) unawaited(next());
    });
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // Sin binding (pruebas de lógica): se puede llamar a [lifecycleChanged].
    }
  }
  bool _observing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      lifecycleChanged(state);

  /// Segundo plano (paused/hidden/detached) ≠ salir de la Jam: solo se pausan
  /// los relojes de silencio; al volver se re-sincroniza. `inactive` es
  /// transitorio (diálogos, barra de notificaciones) y se ignora.
  void lifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        service.appResumed();
        // Al volver, el invitado retoma la posición del anfitrión.
        if (service.connected && !service.isHost) bridge.resync();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        service.appBackgrounded();
      case AppLifecycleState.inactive:
        break;
    }
  }

  final AppController app;
  JamTransport? _transport;

  /// Motor de sugerencias inyectable (pruebas); por defecto YouTube + perfil local.
  final JamSuggestionAdapter Function()? suggestionAdapter;
  final Duration topUpTimeout;

  /// Transporte en línea (Supabase); no está disponible sin --dart-define.
  JamTransport get remote =>
      _transport ??= SupabaseJamTransport(JamSupabaseConfig.fromEnvironment);
  bool get remoteAvailable => remote.available;
  String? get remoteProblem => remote.unavailableReason;
  Timer? _suggestTimer, _refreshLater;
  DateTime? _nextRefreshAt;
  String? _lastEntryId;
  bool _suggesting = false, _cancelAdd = false;

  /// Pistas por delante que el anfitrión mantiene siempre en la cola.
  static const minAhead = kQueueLookahead;
  static const _maxFailSkips = 5;
  // _optOut: este invitado eligió no escuchar; _ended: la cola se agotó.
  bool _optOut = false, _ended = false, _toppingUp = false;
  bool _wasConnected = false, _listening = false;
  int _failStreak = 0;
  DateTime? _topUpBackoff;
  final Set<String> _skipped = {};

  /// Avance de «añadir en lotes» (playlist larga); la UI lo escucha.
  final ValueNotifier<JamAddProgress> addProgress = ValueNotifier(
    const JamAddProgress(),
  );

  // --- API estable para la UI -------------------------------------------
  /// Rol y permisos del usuario actual en la Jam.
  bool get isHost => service.isHost;
  bool get active => service.connected;
  JamRole get role => service.me?.role ?? JamRole.guest;
  JamMode get mode => service.mode;
  JamPermissions get _perm => service.me?.permissions ?? const JamPermissions();
  bool get _muted => service.me?.muted ?? false;
  bool get canPause => isHost || _perm.pause;
  bool get canSkip => isHost || _perm.skip;

  /// Play/pausa/saltar (los invitados se enrutan al anfitrión si hay permiso).
  bool get canControlPlayback => canPause || canSkip;
  bool get canAdd => active && !_muted && (isHost || _perm.add);
  bool get canReorder => isHost || _perm.reorder;
  bool get canRemove => isHost || _perm.remove;
  String get hostName => service.participants
      .firstWhere(
        (p) => p.isHost,
        orElse: () => const JamParticipant(id: 'host', name: 'el anfitrión'),
      )
      .name;
  List<JamParticipant> get participants => service.participants;

  /// Sugerencias de todo el grupo, intercaladas (round-robin por persona).
  List<GroupSuggestion> get groupSuggestions => service.groupSuggestions;

  /// Autoplay de la Jam (activo por defecto). Solo lo cambia el anfitrión.
  bool get autoplayEnabled => service.rules.autoplay;
  Future<void> setAutoplay(bool on) => _run(() async {
    await service.setRules(service.rules.copyWith(autoplay: on));
    if (on) _autoplay();
  });

  final JamService service;
  late final JamPlaybackBridge bridge;
  bool busy = false, searching = false;
  String? error;
  List<String> addresses = [];
  List<Track> results = [];
  Timer? _broadcastTimer;
  StreamSubscription<void>? _completed;
  int _searchGeneration = 0;
  bool _disposed = false;
  bool _hostLoading = false;
  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    busy = true;
    error = null;
    _notify();
    try {
      await action();
    } catch (failure) {
      error = failure is JamException
          ? failure.message
          : 'No se pudo completar la acción de Jam.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> loadAddresses() => _run(() async {
    addresses = await JamService.localAddresses();
    if (addresses.isEmpty) {
      throw const JamException(
        'No encontramos una dirección privada. Conéctate a una red Wi-Fi o Ethernet.',
      );
    }
  });

  /// Nombre efectivo: el explícito, si no el del perfil y si no [fallback].
  String _nameOr(String? name, String fallback) {
    final given = name?.trim() ?? '';
    return given.isNotEmpty
        ? given
        : app.profileName.trim().isNotEmpty
        ? app.profileName.trim()
        : fallback;
  }

  /// Foto del perfil de [id]: la propia sale del perfil, el resto de la Jam.
  Uint8List? avatarOf(String id) =>
      id == service.participantId && app.profileAvatar != null
      ? app.profileAvatar
      : service.avatarOf(id);

  Future<void> host(String address, String? name) => _run(() async {
    await bridge.disable();
    service.localAvatar = app.profileAvatar;
    await service.host(address: address, name: _nameOr(name, 'Anfitrión'));
    _startHostTimer();
    _startSuggestions();
    unawaited(_beginSession());
  });
  void _startHostTimer() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (bridge.enabled && !_hostLoading && service.isHost) _publish();
      if (service.isHost) _autoplay();
    });
  }

  Future<void> hostOnline(String? name) => _run(() async {
    await bridge.disable();
    service.localAvatar = app.profileAvatar;
    await service.hostRemote(remote, name: _nameOr(name, 'Anfitrión'));
    _startHostTimer();
    _startSuggestions();
    unawaited(_beginSession());
  });

  /// Crea la Jam si aún no hay una: [JamHostMode.auto] la abre en línea si hay
  /// servidor y, si no, en la red local. Devuelve si queda conectada (si no,
  /// el motivo está en [error]). La usan la interfaz y la API de control remoto.
  Future<bool> startHosting({
    String? name,
    JamHostMode mode = JamHostMode.auto,
  }) async {
    if (service.connected) return true;
    final online = switch (mode) {
      JamHostMode.online => true,
      JamHostMode.lan => false,
      JamHostMode.auto => remoteAvailable,
    };
    if (online) {
      if (!remoteAvailable) {
        error = remoteProblem ?? 'La Jam en línea no está disponible.';
        _notify();
        return false;
      }
      await hostOnline(name);
    } else {
      await loadAddresses();
      if (addresses.isNotEmpty) await host(addresses.first, name);
    }
    return service.connected;
  }

  /// Al crear la Jam: modo «Escuchando» y la pista actual pasa a ser la
  /// primera de la cola, con su posición, para que todos la oigan igual.
  Future<void> _beginSession() async {
    _optOut = false;
    _ended = false;
    _failStreak = 0;
    _skipped.clear();
    try {
      service.setMode(JamMode.synchronized);
      final track = app.currentTrack;
      if (track != null && service.isHost) {
        final position = app.audio.position.inMilliseconds;
        bridge.remember(track);
        final result = await service.addMany([
          JamTrack.fromTrack(track),
        ], mode: JamAddMode.playNow);
        final id = result.firstEntryId;
        final entry = service.queue.where((e) => e.id == id).firstOrNull;
        if (entry != null) await _play(entry, startMs: position);
      }
    } on JamException {
      // Pista no compartible: la Jam arranca igual con la siguiente.
    } catch (_) {}
    _autoplay();
    _sessionChanged();
  }

  Future<void> join(String code, String? name) => _run(() async {
    _optOut = false;
    await bridge.disable();
    service.localAvatar = app.profileAvatar;
    final who = _nameOr(name, 'Invitado');
    if (jamRemoteCodeFrom(code) != null) {
      await service.joinRemote(remote, code, name: who);
      _startSuggestions();
    } else {
      await service.join(JamInvite.decode(code), name: who);
      _startSuggestions();
    }
  });

  /// Enlace `aurora://jam/CODIGO` recibido del sistema (Android/Windows).
  Future<void> joinFromLink(String link, String name) {
    // El enlace del sistema llega con el nombre genérico: manda el del perfil.
    if (name.trim() == 'Invitado') name = '';
    final code = jamRemoteCodeFrom(link);
    if (code == null) {
      error = 'El enlace de Jam no es válido.';
      _notify();
      return Future.value();
    }
    return join(code, name);
  }

  /// Cada dispositivo calcula SUS sugerencias con SU perfil y publica solo
  /// pistas públicas (máx. 5 cada 60 s). Nada del perfil sale del equipo.
  void _startSuggestions() {
    _suggestTimer?.cancel();
    _nextRefreshAt = null;
    _cancelAdd = false;
    unawaited(refreshSuggestions());
    _suggestTimer = Timer.periodic(
      jamSuggestionsInterval + const Duration(seconds: 5),
      (_) => unawaited(refreshSuggestions()),
    );
  }

  /// Como mucho una publicación por minuto; si llega antes, se difiere.
  Future<void> refreshSuggestions() async {
    if (_suggesting || !service.connected || _disposed) return;
    final wait = _nextRefreshAt?.difference(DateTime.now());
    if (wait != null && wait > Duration.zero) {
      _refreshLater ??= Timer(wait, () {
        _refreshLater = null;
        unawaited(refreshSuggestions());
      });
      return;
    }
    _nextRefreshAt = DateTime.now().add(
      jamSuggestionsInterval + const Duration(seconds: 2),
    );
    _suggesting = true;
    try {
      final items = await _adapter().build(current: app.nowTrack);
      if (items.isNotEmpty && service.connected) {
        service.publishSuggestions(items);
      }
    } on JamException {
      // Límite de ritmo o permiso desactivado: se reintenta en el siguiente ciclo.
    } catch (_) {
    } finally {
      _suggesting = false;
    }
  }

  Future<void> reconnect() => _run(service.reconnect);
  Future<void> leave() => _run(() async {
    _broadcastTimer?.cancel();
    _suggestTimer?.cancel();
    _refreshLater?.cancel();
    _nextRefreshAt = null;
    _cancelAdd = true;
    _skipped.clear();
    _ended = false;
    await service.close();
    await bridge.disable();
  });
  Future<void> setMode(JamMode mode) => _run(() async {
    service.setMode(mode);
    if (mode == JamMode.queueOnly) {
      await bridge.disable();
    } else {
      _ended = false;
      _sessionChanged(); // retoma en la posición actual
    }
  });
  Future<void> setListening(bool listen) => _run(() async {
    if (listen) {
      if (!service.connected || service.mode != JamMode.synchronized) {
        throw const JamException(
          'El anfitrión debe habilitar reproducción sincronizada.',
        );
      }
      _optOut = false;
      await bridge.enable();
      bridge.resync();
      if (service.playback != null) await bridge.apply(service.playback!);
    } else {
      _optOut = true;
      await bridge.disable();
    }
    try {
      service.announceListening(listen);
    } on JamException {
      // Sin conexión: se informa al reconectar.
    }
  });

  /// «Reproducir ahora»: opcional, el anfitrión también puede dejar que suene solo.
  Future<void> play(JamQueueEntry entry) => _run(() async {
    if (!service.isHost) {
      throw const JamException('El anfitrión controla la reproducción.');
    }
    _failStreak = 0;
    await _play(entry);
  });

  Future<void> _play(JamQueueEntry entry, {int startMs = 0}) async {
    if (!service.isHost || _disposed) return;
    _hostLoading = true;
    _ended = false;
    try {
      await bridge.enable();
      final state = JamPlayback(
        sequence: (service.playback?.sequence ?? 0) + 1,
        entryId: entry.id,
        isPlaying: true,
        positionMs: startMs,
        serverTimeMs: service.clock().millisecondsSinceEpoch,
      );
      await bridge.apply(state);
      if (bridge.failedEntryId == entry.id) {
        // Sin audio para esta pista en el anfitrión: se pasa a la siguiente.
        _skipped.add(entry.id);
        final upcoming = _failStreak++ < _maxFailSkips
            ? _nextEntry(after: entry.id)
            : null;
        _hostLoading = false;
        if (upcoming != null) {
          await _play(upcoming);
        } else {
          _ended = true;
        }
        return;
      }
      _failStreak = 0;
      _publish(entryId: entry.id, playing: true);
    } finally {
      _hostLoading = false;
    }
  }

  Future<void> togglePlayback() => _run(() async {
    if (!service.isHost) {
      if (!canPause) throw JamException('Lo controla $hostName.');
      service.requestPlayPause(!(service.playback?.isPlaying ?? false));
      return;
    }
    if (!bridge.enabled) return;
    if (app.audio.isPlaying) {
      await app.audio.pause();
    } else {
      await app.audio.play();
    }
    _publish();
  });
  Future<void> seek(Duration position) => _run(() async {
    if (!service.isHost || !bridge.enabled) return;
    await app.audio.seek(position);
    _publish();
  });
  Future<void> next() async {
    if (!service.isHost) {
      try {
        if (!canSkip) throw JamException('Lo controla $hostName.');
        service.skip();
      } on JamException catch (failure) {
        error = _friendly(failure);
        _notify();
      }
      return;
    }
    var upcoming = _nextEntry();
    if (upcoming == null && service.rules.autoplay) {
      service.promoteSuggested();
      upcoming = _nextEntry();
      if (upcoming == null) {
        _topUpBackoff = null;
        await _topUp();
        upcoming = _nextEntry();
      }
    }
    if (upcoming != null) {
      _failStreak = 0;
      await _play(upcoming);
    } else {
      _ended = true;
      await app.audio.pause();
      _publish();
    }
  }

  JamQueueEntry? _nextEntry({String? after}) {
    after ??= service.playback?.entryId ?? bridge.currentEntryId;
    final current = service.queue.indexWhere((entry) => entry.id == after);
    for (var i = current + 1; i < service.queue.length; i++) {
      final e = service.queue[i];
      if (e.playable &&
          !_skipped.contains(e.id) &&
          (service.rules.autoplay || e.status != JamEntryStatus.suggested)) {
        return e;
      }
    }
    return null;
  }

  /// Autoplay: con menos de [minAhead] pistas por delante, sube sugerencias.
  void _autoplay() {
    if (!service.isHost || !service.connected || !service.rules.autoplay) {
      return;
    }
    if (service.upcomingQueued >= minAhead) return;
    if (service.promoteSuggested(target: minAhead) == 0) {
      unawaited(refreshSuggestions());
    }
    unawaited(_topUp());
  }

  JamSuggestionAdapter _adapter({int count = jamSuggestionsPerPerson}) =>
      suggestionAdapter?.call() ?? _defaultAdapter(count);

  JamSuggestionAdapter _defaultAdapter(int count) => JamSuggestionAdapter(
    api: app.suggestionsApi,
    taste: () => app.selfTaste,
    mode: app.djMode,
    count: count,
    related: (track) {
      final source = app.source;
      final id = track.id.startsWith('yt:') ? track.id.substring(3) : null;
      return source is InnerTubeSource && id != null
          ? source.related(id)
          : Future.value(const []);
    },
    seeds: () => app.recentTracks,
    favorites: () => [
      for (final t in app.tracks)
        if (app.favoriteIds.contains(t.id)) t,
    ],
    local: () => app.queue,
    rank: app.rankForJam,
  );

  List<JamTrack> _wire(Iterable<Track> tracks) {
    final online = <JamTrack>[], local = <JamTrack>[];
    for (final t in tracks) {
      try {
        final wire = JamTrack.fromTrack(t);
        bridge.remember(t);
        (wire.localOnly ? local : online).add(wire);
      } on JamException {
        continue;
      }
    }
    return [...online, ...local]; // lo local solo suena en este equipo
  }

  /// Mantiene ≥ [minAhead] pistas por delante: grupo, motor de sugerencias,
  /// biblioteca, favoritos no sonados y, al final, repetir lo ya sonado.
  /// Jamás deja la cola vacía aunque el motor falle o tarde.
  Future<void> _topUp() async {
    if (_toppingUp ||
        _disposed ||
        !service.isHost ||
        !service.connected ||
        !service.rules.autoplay ||
        service.upcomingQueued >= minAhead) {
      return;
    }
    final wait = _topUpBackoff?.difference(DateTime.now());
    if (wait != null && wait > Duration.zero) return;
    _toppingUp = true;
    final start = service.upcomingQueued;
    int short() => minAhead - service.upcomingQueued;
    try {
      service.promoteSuggested(target: minAhead);
      if (short() > 0) {
        try {
          final items = await _adapter(
            count: 20,
          ).build(current: app.nowTrack).timeout(topUpTimeout);
          service.addAutoplay([for (final i in items) i.track], need: short());
        } catch (_) {
          // Motor lento, sin red o con error: sigue el respaldo local.
        }
      }
      final recent = <String>{};
      for (final t in app.recentTracks.take(20)) {
        try {
          recent.addAll(JamTrack.fromTrack(t).keys);
        } on JamException {
          continue;
        }
      }
      bool fresh(JamTrack t) => !t.keys.any(recent.contains);
      final library = _wire([...app.queue, ...app.tracks]);
      if (short() > 0) {
        service.addAutoplay(library.where(fresh).toList(), need: short());
      }
      if (short() > 0) {
        final favorites = _wire(
          app.tracks.where((t) => app.favoriteIds.contains(t.id)),
        );
        service.addAutoplay(
          [...favorites.where(fresh), ...favorites.where((t) => !fresh(t))],
          need: short(),
          repeat: true,
        );
      }
      if (short() > 0) {
        service.addAutoplay(
          [...library, for (final e in service.queue) e.track],
          need: short(),
          repeat: true,
        );
      }
    } finally {
      _toppingUp = false;
    }
    // Sin nada que añadir (biblioteca vacía): se reintenta en unos segundos.
    // Un repertorio más corto que [minAhead] no es fallo: solo se espera si
    // no se añadió nada y la cola está de verdad corta.
    _topUpBackoff =
        service.upcomingQueued <= start &&
            service.upcomingQueued < _maxFailSkips
        ? DateTime.now().add(const Duration(seconds: 10))
        : null;
  }

  /// Añade pistas a la Jam. Devuelve false (y deja [error]) si no hay permiso.
  /// Las listas largas se envían por lotes; observa [addProgress].
  bool addTracks(List<Track> tracks, {JamAddMode mode = JamAddMode.end}) {
    if (!canAdd) {
      error = !active
          ? 'Únete a una Jam para añadir canciones.'
          : _muted
          ? 'El anfitrión te silenció.'
          : 'El anfitrión no permite añadir canciones.';
      _notify();
      return false;
    }
    error = null;
    final wire = <JamTrack>[];
    for (final t in tracks) {
      try {
        wire.add(JamTrack.fromTrack(t));
        bridge.remember(t);
      } on JamException {
        continue; // datos inválidos: no entran
      }
    }
    _cancelAdd = false;
    unawaited(() async {
      try {
        final result = await service.addMany(
          wire,
          mode: mode,
          onProgress: (p) {
            if (!_disposed) addProgress.value = p;
          },
          cancelled: () => _cancelAdd || _disposed,
        );
        if (mode == JamAddMode.playNow && result.firstEntryId != null) {
          final entry = service.queue.firstWhere(
            (e) => e.id == result.firstEntryId,
          );
          if (service.isHost) {
            _failStreak = 0;
            await _play(entry);
          }
        }
      } on JamException catch (failure) {
        error = _friendly(failure);
        if (!_disposed) addProgress.value = JamAddProgress(message: error);
      }
      _notify();
    }());
    return true;
  }

  /// Añade una playlist de la biblioteca local (las pistas se resuelven por id).
  Future<void> addPlaylist(
    MusicPlaylist playlist, {
    JamAddMode mode = JamAddMode.end,
  }) async {
    final byId = {for (final t in app.tracks) t.id: t};
    final found = [
      for (final id in playlist.trackIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (found.isEmpty) {
      error = 'La playlist «${playlist.name}» no tiene canciones.';
      _notify();
      return;
    }
    addTracks(found, mode: mode);
  }

  void cancelAdd() => _cancelAdd = true;

  /// Añade una sugerencia del grupo con un toque.
  void addSuggestion(GroupSuggestion s) {
    try {
      service.addTrack(s.track);
      error = null;
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
  }

  void add(Track track) {
    try {
      bridge.remember(track);
      service.addTrack(JamTrack.fromTrack(track));
      error = null;
    } on JamException catch (failure) {
      error = failure.message == 'rate'
          ? 'Espera unos segundos antes de agregar más canciones.'
          : failure.message;
    }
    _notify();
  }

  void remove(JamQueueEntry entry) {
    try {
      service.remove(entry.id);
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
  }

  void reorder(JamQueueEntry entry, int to) {
    try {
      service.reorder(entry.id, to);
    } on JamException catch (failure) {
      error = _friendly(failure);
    }
    _notify();
  }

  String _friendly(JamException failure) => failure.message == 'permissions'
      ? 'El anfitrión no habilitó ese permiso.'
      : failure.message == 'rate'
      ? 'Espera unos segundos antes de cambiar la cola.'
      : failure.message == 'limit'
      ? 'Llegaste al límite de canciones que puedes agregar.'
      : failure.message == 'muted'
      ? 'El anfitrión te silenció.'
      : failure.message == 'full'
      ? 'La cola compartida llegó al límite de 200 canciones.'
      : failure.message;
  void setPermissions(String id, JamPermissions permissions) {
    try {
      service.setPermissions(id, permissions);
    } on JamException catch (failure) {
      error = failure.message;
    }
    _notify();
  }

  Future<void> search(String query) async {
    final generation = ++_searchGeneration;
    query = query.trim();
    results = [];
    searching = query.isNotEmpty;
    error = null;
    _notify();
    if (query.isEmpty) return;
    if (query.length > 300) {
      searching = false;
      error = 'La búsqueda es demasiado larga.';
      _notify();
      return;
    }
    try {
      final matches = await app.source.search(query, limit: 12);
      if (!_disposed && generation == _searchGeneration) results = matches;
    } catch (_) {
      if (!_disposed && generation == _searchGeneration) {
        error =
            'No se pudieron buscar canciones. Puedes agregar desde tu biblioteca.';
      }
    } finally {
      if (!_disposed && generation == _searchGeneration) {
        searching = false;
        _notify();
      }
    }
  }

  void _publish({String? entryId, bool? playing}) {
    service.publishPlayback(
      entryId: entryId ?? bridge.currentEntryId,
      playing: playing ?? (app.audio.isPlaying && !app.audio.isBuffering),
      positionMs: app.audio.position.inMilliseconds,
    );
  }

  void _sessionChanged() {
    if (_disposed) return;
    final entry = service.playback?.entryId;
    if (entry != _lastEntryId) {
      _lastEntryId = entry;
      if (entry != null && service.connected) {
        unawaited(refreshSuggestions()); // la pista cambió: nuevas ideas
      }
    }
    _autoplay();
    if (service.isHost &&
        service.isRemote &&
        !(_broadcastTimer?.isActive ?? false)) {
      _startHostTimer(); // tras recibir el mando por traspaso
    }
    final conn = service.connection;
    if (conn == JamConnection.closed || conn == JamConnection.idle) {
      if (bridge.enabled) unawaited(bridge.disable());
    } else if (!service.isHost && service.connected) {
      // Reconectar: se vuelve a la posición del anfitrión sin enfriamiento.
      if (!_wasConnected) bridge.resync();
      if (service.mode == JamMode.queueOnly) {
        if (bridge.enabled) unawaited(bridge.disable());
      } else if (!_optOut) {
        unawaited(_listen());
      }
    } else if (service.isHost &&
        bridge.enabled &&
        !_hostLoading &&
        service.playback?.entryId == null &&
        bridge.currentEntryId != null) {
      _ended = true;
      unawaited(app.audio.pause());
    }
    _wasConnected = service.connected;
    _autostart();
    _notify();
  }

  /// Invitado en modo «Escuchando»: suena solo, sin pulsar nada.
  Future<void> _listen() async {
    if (_listening) return;
    _listening = true;
    try {
      final first = !bridge.enabled;
      await bridge.enable();
      if (first) {
        try {
          service.announceListening(true);
        } on JamException {
          // Se informa en el siguiente cambio.
        }
      }
      final state = service.playback;
      if (state != null && service.mode == JamMode.synchronized && !_optOut) {
        await bridge.apply(state);
      }
    } catch (_) {
    } finally {
      _listening = false;
    }
  }

  /// Anfitrión «Escuchando» sin nada sonando: empieza solo la pista actual o
  /// la siguiente de la cola (cola vacía → arranca al añadir; sin Reproducir).
  void _autostart() {
    if (!service.isHost ||
        service.mode != JamMode.synchronized ||
        _hostLoading ||
        _disposed) {
      return;
    }
    if (!(_ended || bridge.currentEntryId == null)) return;
    final state = service.playback;
    final current = service.queue
        .where((e) => e.id == state?.entryId && !_skipped.contains(e.id))
        .firstOrNull;
    final resume = current != null && !_ended;
    final target = resume ? current : _nextEntry(after: state?.entryId);
    if (target == null) return;
    _hostLoading = true; // evita arranques dobles hasta que _play lo tome
    unawaited(_play(target, startMs: resume ? state!.positionMs : 0));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    _searchGeneration++;
    _broadcastTimer?.cancel();
    _suggestTimer?.cancel();
    _refreshLater?.cancel();
    addProgress.dispose();
    unawaited(_completed?.cancel());
    service.removeListener(_sessionChanged);
    bridge.removeListener(_notify);
    service.dispose();
    bridge.dispose();
    super.dispose();
  }
}
