import 'dart:async';
import 'dart:io';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/audio/eq_model.dart';
import 'package:aurora_music/audio_web/web_music_audio.dart';
import 'package:aurora_music/core/audio_backend.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeAudio extends AudioBackend {
  @override
  String? lastError;
  @override
  bool isPlaying = false;
  @override
  bool isBuffering = false;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = const Duration(minutes: 3);
  @override
  double volume = 0.75;
  @override
  final ValueNotifier<List<double>> spectrum = ValueNotifier<List<double>>(
    List.filled(32, 0),
  );

  /// Llamadas a setEqualizer (activo, bandas) para comprobar el EQ.
  bool eqSupported = true;
  @override
  bool get supportsEqualizer => eqSupported;
  final eqCalls = <(bool, List<EqBand>)>[];
  final completions = StreamController<void>.broadcast();
  @override
  Stream<void> get completed => completions.stream;
  ResolvedAudio? loaded;
  int loadCount = 0;

  /// Errors thrown by the next load() calls, one per call.
  final loadErrors = <Object>[];
  @override
  Future<void> initialize() async {}
  @override
  Future<void> load(
    ResolvedAudio source, {
    String? ffmpegExecutable,
    Duration start = Duration.zero,
  }) async {
    if (loadErrors.isNotEmpty) throw loadErrors.removeAt(0);
    loaded = source;
    loadCount++;
    position = start;
    lastError = null;
    notifyListeners();
  }

  @override
  Future<void> play() async {
    isPlaying = true;
    notifyListeners();
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    position = Duration.zero;
    notifyListeners();
  }

  /// Simula reproducción real: avanza la posición y avisa a los oyentes.
  void advanceTo(Duration value) {
    position = value;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration value) async {
    position = value;
    notifyListeners();
  }

  @override
  void setVolume(double value) {
    volume = value;
    notifyListeners();
  }

  @override
  void setEqualizer(
    bool enabled,
    List<EqBand> bands, {
    bool autoPreamp = true,
  }) {
    eqCalls.add((enabled, bands));
  }

  @override
  void setVisualizationEnabled(bool enabled) {}
  @override
  void dispose() {
    spectrum.dispose();
    unawaited(completions.close());
    super.dispose();
  }
}

class FakeSource extends SourceBackend {
  bool expiredStream = false;
  final playbackFailures = <String>[];
  @override
  bool isExpiredStream(Track track) => expiredStream;
  @override
  void reportPlaybackFailure(String message) => playbackFailures.add(message);
  @override
  void invalidateResolvedAudio(Track track) {
    expiredStream = false;
  }

  Completer<List<Track>>? pendingSearch;
  final searchQueries = <String>[];
  final searchLimits = <int>[];
  List<Track> searchMatches = [];
  Object? searchError;
  final resolved = <String>[];
  final pendingResolves = <String, Completer<ResolvedAudio>>{};
  int activeDownloads = 0;
  int maxActiveDownloads = 0;
  Completer<void>? downloadGate;
  Object? cookieError;
  @override
  String? cookieFile;
  @override
  Future<void> configureCookieFile(String? path) async {
    if (cookieError != null && path != null) throw cookieError!;
    cookieFile = path;
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    searchQueries.add(query);
    searchLimits.add(limit);
    if (searchError != null) throw searchError!;
    return pendingSearch?.future ?? searchMatches.take(limit).toList();
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) async => [];
  @override
  Future<ResolvedAudio> resolve(Track track) async {
    resolved.add(track.id);
    return pendingResolves[track.id]?.future ??
        ResolvedAudio(
          input: 'https://example.test/${track.id}',
          duration: track.duration,
        );
  }

  @override
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    activeDownloads++;
    if (activeDownloads > maxActiveDownloads) {
      maxActiveDownloads = activeDownloads;
    }
    try {
      await downloadGate?.future;
      onProgress?.call(0.5);
      await destination.writeAsBytes([1, 2, 3]);
    } finally {
      activeDownloads--;
    }
  }

  @override
  Future<void> cancel(String jobId) async {}
  @override
  Future<String> diagnose() async => 'Herramientas disponibles';
  @override
  Future<void> configureToolDirectory(String directory) async {
    toolDirectory = directory;
  }

  @override
  String? toolDirectory;
  @override
  String? get ffmpegExecutable => null;
  @override
  void dispose() {}
}

Future<AppController> createTestController({
  List<Track> tracks = const [],
  List<MusicPlaylist> playlists = const [],
  AudioBackend? audio,
  SourceBackend? source,
  Map<String, Object> preferences = const {},
}) async {
  // Los tests de cola exacta no quieren pistas sugeridas; auto_refill las pide.
  SharedPreferences.setMockInitialValues({
    'autoRefill': false,
    'themeKind': 'atelier',
    ...preferences,
  });
  final prefs = await SharedPreferences.getInstance();
  final directory = await Directory.systemTemp.createTemp('aurora_test_');
  final database = LibraryDatabase.memory();
  for (final track in tracks) {
    await database.saveTrack(track);
  }
  for (final playlist in playlists) {
    await database.savePlaylist(playlist);
  }
  final controller = AppController(
    audio: audio ?? FakeAudio(),
    source: source ?? FakeSource(),
    database: database,
    preferences: prefs,
    supportDirectory: directory,
  );
  await controller.initialize(mediaControls: false);
  return controller;
}

Future<void> closeTestController(AppController controller) async {
  controller.dispose();
  await controller.closed;
  if (await controller.supportDirectory.exists()) {
    await controller.supportDirectory.delete(recursive: true);
  }
}

/// Fake official-site bridge: no WebView, no network.
class FakeWebBridge extends WebMusicBridge {
  Uri? page;
  int builds = 0;
  bool disposed = false;
  final commands = <String>[];
  final values = <double?>[];
  final timeouts = <Duration>[];
  Map<String, dynamic> state = {
    'status': 'ready',
    'playing': false,
    'position': 12.5,
    'duration': 150,
  };

  /// Overrides the response to the next 'play' only.
  Map<String, dynamic>? playResult;
  Completer<Map<String, dynamic>?>? pending;

  @override
  Future<void> initialize() async {}
  @override
  Widget buildView() {
    builds++;
    return const ColoredBox(key: ValueKey('engine'), color: Colors.red);
  }

  @override
  Future<void> navigate(Uri uri) async => page = uri;
  @override
  Future<Map<String, dynamic>?> command(
    String action, {
    required String videoId,
    required int generation,
    double? value,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    commands.add(action);
    values.add(value);
    timeouts.add(timeout);
    if (pending != null) {
      final future = pending!.future;
      pending = null;
      return future;
    }
    if (action == 'play' && playResult != null) {
      final result = playResult!;
      playResult = null;
      return result;
    }
    if (action == 'play' && state['status'] == 'ready') {
      state = {...state, 'playing': true, 'ended': false};
    } else if (action == 'pause') {
      state = {...state, 'playing': false};
    }
    return {...state, 'generation': generation, 'videoId': videoId};
  }

  @override
  void dispose() => disposed = true;
}
