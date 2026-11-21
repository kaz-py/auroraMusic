import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../app_controller.dart';
import '../core/models.dart';
import 'jam_models.dart';
import 'jam_service.dart';

int jamTargetPosition(
  JamPlayback state,
  int localTimeMs,
  int clockOffsetMs, {
  int? durationMs,
}) {
  final elapsed = state.isPlaying
      // 15 s: en línea el anfitrión solo publica al cambiar algo y cada ≤10 s.
      ? (localTimeMs + clockOffsetMs - state.serverTimeMs).clamp(0, 15000)
      : 0;
  final target = state.positionMs + elapsed;
  return durationMs != null && durationMs > 0
      ? target.clamp(0, durationMs)
      : target.clamp(0, 86400000);
}

/// No rate adjustment exists in AudioBackend, and a seek reloads the stream
/// (an audible gap): correct only past 1.5 s, and in one jump, not 500 ms steps.
const jamDriftDeadbandMs = 1500;

int? jamDriftCorrection({
  required int currentMs,
  required int targetMs,
  required int nowMs,
  required int? lastSeekMs,
}) {
  if (lastSeekMs != null && nowMs - lastSeekMs < 5000) return null;
  final drift = targetMs - currentMs;
  if (drift.abs() <= jamDriftDeadbandMs) return null;
  return currentMs + drift.clamp(-3000, 3000);
}

class JamPlaybackBridge extends ChangeNotifier {
  JamPlaybackBridge({
    required this.app,
    required this.service,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final AppController app;
  final JamService service;
  final DateTime Function() clock;
  bool enabled = false;
  bool loading = false;
  String? warning;
  String? currentEntryId;
  final Map<String, Track> _ownTracks = {};
  Track? _originalTrack;
  Duration _originalPosition = Duration.zero;
  bool _originalPlaying = false;
  int _generation = 0;
  int? _lastSeekMs;
  bool _forceResync = false, _lastPlaying = false;
  String? _requestedEntryId, _failedEntryId;
  String? _resolvingVideoId;
  JamPlayback? _pending;
  Future<void>? _draining;
  bool _disposed = false;
  Future<void>? _disabling;
  Future<void>? _enabling;

  /// Entrada que este dispositivo no pudo reproducir (sin audio disponible).
  String? get failedEntryId => _failedEntryId;

  void remember(Track track) {
    final key = JamTrack.fromTrack(track).key;
    if (_ownTracks.length >= 200 && !_ownTracks.containsKey(key)) {
      _ownTracks.remove(_ownTracks.keys.first);
    }
    _ownTracks[key] = track;
  }

  Future<void> enable() =>
      _enabling ??= _enable().whenComplete(() => _enabling = null);
  Future<void> _enable() async {
    await _disabling;
    if (enabled) return;
    _originalTrack = app.currentTrack;
    _originalPosition = app.audio.position;
    _originalPlaying = app.audio.isPlaying;
    enabled = true;
    await app.beginJamPlayback();
    warning = null;
    _notify();
  }

  Future<void> disable() =>
      _disabling ??= _disable().whenComplete(() => _disabling = null);
  Future<void> _disable() async {
    await _enabling;
    if (!enabled) return;
    enabled = false;
    ++_generation;
    final video = _resolvingVideoId;
    if (video != null) {
      unawaited(app.source.cancel('resolve:$video').catchError((Object _) {}));
    }
    _pending = null;
    _requestedEntryId = null;
    // Let an already-started native load finish before restoring personal audio.
    await _draining;
    currentEntryId = null;
    app.setJamNowPlaying(null);
    _failedEntryId = null;
    _lastPlaying = false;
    loading = false;
    await app.endJamPlayback();
    final original = _originalTrack;
    final available =
        original != null && app.queue.any((track) => track.id == original.id);
    // Do not resurrect removed entries or overwrite queue edits made during the Jam.
    if (_originalPlaying && available) {
      final context = List<Track>.from(app.queue);
      await app.playTrack(original, context: context);
      await app.seek(_originalPosition);
    } else {
      // Paused/unloaded personal sessions remain paused; AppController keeps its resume position.
      await app.persistSession();
    }
    _originalTrack = null;
    warning = null;
    _notify();
  }

  Future<void> apply(JamPlayback state) {
    if (!enabled || _disposed) return Future.value();
    _pending = state;
    if (state.entryId != _requestedEntryId) {
      _requestedEntryId = state.entryId;
      ++_generation;
    }
    return _draining ??= _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    while (_pending != null && enabled && !_disposed) {
      final state = _pending!;
      _pending = null;
      final generation = _generation;
      final entry = service.queue
          .where((entry) => entry.id == state.entryId)
          .firstOrNull;
      if (entry == null) {
        await app.audio.pause();
        currentEntryId = null;
        app.setJamNowPlaying(null);
        _notify();
        continue;
      }
      if (_failedEntryId == entry.id) continue;
      try {
        if (currentEntryId != entry.id) {
          loading = true;
          warning = null;
          _notify();
          await app.audio.pause();
          final track = await _resolveTrack(entry.track);
          if (!enabled || generation != _generation || _disposed) continue;
          _resolvingVideoId = jamYouTubeId(track);
          final resolved = await app.source.resolve(track);
          _resolvingVideoId = null;
          if (!enabled || generation != _generation || _disposed) continue;
          final latest = _pending?.entryId == entry.id ? _pending! : state;
          final start = jamTargetPosition(
            latest,
            clock().millisecondsSinceEpoch,
            service.clockOffsetMs,
            durationMs: resolved.duration.inMilliseconds,
          );
          await app.audio.load(resolved, start: Duration(milliseconds: start));
          if (!enabled || generation != _generation || _disposed) {
            await app.audio.pause();
            continue;
          }
          currentEntryId = entry.id;
          app.setJamParty(
            service.invite?.sessionId,
            service.participants.where((p) => p.connected).length,
          );
          app.setJamNowPlaying(track);
          unawaited(app.noteJamPlay(track).catchError((Object _) {}));
          _lastSeekMs = clock().millisecondsSinceEpoch;
        } else if (!app.audio.isBuffering) {
          final now = clock().millisecondsSinceEpoch;
          final target = jamTargetPosition(
            state,
            now,
            service.clockOffsetMs,
            durationMs: app.audio.duration.inMilliseconds,
          );
          final current = app.audio.position.inMilliseconds;
          // Tras reconectar o salir de pausa se salta directo a la posición.
          final force = _forceResync || (state.isPlaying && !_lastPlaying);
          _forceResync = false;
          final correction = force
              ? ((target - current).abs() > jamDriftDeadbandMs ? target : null)
              : jamDriftCorrection(
                  currentMs: current,
                  targetMs: target,
                  nowMs: now,
                  lastSeekMs: _lastSeekMs,
                );
          if (correction != null) {
            await app.audio.seek(Duration(milliseconds: correction));
            _lastSeekMs = now;
          }
        }
        if (!enabled || generation != _generation || _disposed) continue;
        final latest = _pending?.entryId == entry.id ? _pending! : state;
        if (latest.isPlaying && !app.audio.isPlaying) await app.audio.play();
        if (!latest.isPlaying && app.audio.isPlaying) await app.audio.pause();
        _lastPlaying = latest.isPlaying;
        loading = false;
        _notify();
      } catch (_) {
        if (!enabled || generation != _generation || _disposed) continue;
        _failedEntryId = entry.id;
        loading = false;
        warning =
            'Esta canción no está disponible con tus fuentes de audio. La cola compartida sigue funcionando.';
        try {
          await app.audio.pause();
        } catch (_) {}
        _notify();
      }
    }
  }

  Future<Track> _resolveTrack(JamTrack metadata) async {
    // Prefer real library files over an online entry with the same origin.
    final own = _ownTracks[metadata.key];
    if (own != null && (!own.isLocal || await File(own.localPath!).exists())) {
      return own;
    }
    for (final track in [...app.tracks, ...app.queue, ...app.searchResults]) {
      if (track.isPendingSpotifyMatch) continue;
      final candidate = JamTrack.fromTrack(track);
      if (candidate.keys.any(metadata.keys.contains) &&
          (!track.isLocal || await File(track.localPath!).exists())) {
        return track;
      }
    }
    if (metadata.localOnly) {
      throw const JamException(
        'El archivo local no está disponible en este dispositivo.',
      );
    }
    if (metadata.youtubeId != null) {
      return Track(
        id: 'yt:${metadata.youtubeId}',
        title: metadata.title,
        artist: metadata.artist,
        pageUrl: 'https://www.youtube.com/watch?v=${metadata.youtubeId}',
        spotifyUri: metadata.spotifyUri,
        duration: Duration(milliseconds: metadata.durationMs),
        artworkUrl: metadata.artworkUrl,
      );
    }
    final matches = await app.source.search(
      '${metadata.artist} ${metadata.title}',
      limit: 5,
    );
    final exact = matches
        .where(
          (track) =>
              jamNormalized(track.title) == jamNormalized(metadata.title) &&
              jamNormalized(track.artist) == jamNormalized(metadata.artist) &&
              !track.isPendingSpotifyMatch,
        )
        .firstOrNull;
    if (exact == null) {
      throw const JamException(
        'No existe una coincidencia fiable de esta canción.',
      );
    }
    warning =
        'Se usa una coincidencia de tu proveedor; la versión puede diferir y la sincronía exacta no está garantizada.';
    return exact;
  }

  /// La próxima actualización recoloca la posición sin esperar el enfriamiento.
  void resync() => _forceResync = true;

  Future<void> retry() async {
    _failedEntryId = null;
    if (service.playback != null) await apply(service.playback!);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    unawaited(disable().catchError((Object _) {}));
    super.dispose();
  }
}
