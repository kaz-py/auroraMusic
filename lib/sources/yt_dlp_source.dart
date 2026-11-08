import 'dart:async';
import '../bridge/api/cache.dart' as rust;
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/models.dart';
import '../core/artwork_metadata.dart';
import '../core/source_backend.dart';
import 'progressive_audio_relay.dart';
import 'youtube_request_policy.dart';
import 'ytdlp_updater.dart';

class YtDlpSource extends SourceBackend {
  YtDlpSource(
    this._preferences, {
    Future<Duration?> Function(File)? audioDuration,
    bool? androidOverride,
    YouTubeRequestPolicy? requestPolicy,
    DateTime Function()? now,
  }) : _audioDurationOverride = audioDuration {
    _androidOverride = androidOverride;
    _requests = requestPolicy ?? YouTubeRequestPolicy();
    _now = now ?? DateTime.now;
    _requests.onBlocked = (until) => unawaited(
      _preferences.setInt('youtubeCooldownUntil', until.millisecondsSinceEpoch),
    );
    final cooldown = _preferences.getInt('youtubeCooldownUntil');
    if (cooldown != null) {
      _requests.restoreCooldown(DateTime.fromMillisecondsSinceEpoch(cooldown));
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final args = call.arguments as Map;
        _progress[args['jobId']]?.call((args['progress'] as num).toDouble());
      }
    });
  }
  final SharedPreferences _preferences;
  final Future<Duration?> Function(File)? _audioDurationOverride;
  late final bool? _androidOverride;
  late final YouTubeRequestPolicy _requests;
  late final DateTime Function() _now;
  final Map<String, ({ResolvedAudio audio, DateTime expires})> _streamCache =
      {};
  final Map<String, Future<ResolvedAudio>> _streamRequests = {};
  final Map<String, ({List<Track> tracks, DateTime expires})> _listingCache =
      {};
  final Map<String, Future<List<Track>>> _listingRequests = {};
  int get requestsStarted => _requests.requestsStarted;
  YtDlpUpdater? _updater;
  Future<void>? _updateTask;
  Timer? _firstUpdate, _updateTimer;
  Directory? _updateDirectory;
  bool _toolsRecoveryFailed = false;
  bool Function() _playbackActive = () => false;
  void Function() _onUpdate = () {};
  @override
  String? toolUpdateMessage;
  @override
  bool get updatingTools => _updateTask != null;

  @override
  Future<void> initializeUpdates({
    required bool Function() isPlaybackActive,
    required void Function() onStatusChanged,
  }) async {
    _playbackActive = isPlaybackActive;
    _onUpdate = onStatusChanged;
    _updateDirectory = await getApplicationSupportDirectory();
    if (!_isAndroid && Platform.isWindows && toolDirectory != null) {
      _configureUpdater();
      final recovered = await _updater!.recoverPendingInstallation();
      if (recovered.status == YtDlpUpdateStatus.failed) {
        _toolsRecoveryFailed = true;
        throw StateError(
          recovered.error ?? 'Repara la carpeta de yt-dlp antes de reproducir.',
        );
      }
    }
    _firstUpdate?.cancel();
    _updateTimer?.cancel();
    _firstUpdate = Timer(
      const Duration(seconds: 20),
      () => unawaited(checkForUpdates()),
    );
    _updateTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(checkForUpdates()),
    );
  }

  void _configureUpdater() {
    final directory = toolDirectory;
    if (directory == null || _updateDirectory == null) return;
    final executable = File(p.join(directory, 'yt-dlp.exe'));
    if (_updater?.executable.path == executable.path) return;
    _updater = YtDlpUpdater(
      executable: executable,
      stateFile: File(
        p.join(
          _updateDirectory!.path,
          'yt-dlp-updates',
          '${sha256.convert(utf8.encode(p.normalize(executable.absolute.path).toLowerCase()))}.json',
        ),
      ),
      canUpdate: () =>
          !_disposed && !_playbackActive() && _activeOperations == 0,
    );
  }

  @override
  Future<void> checkForUpdates() {
    if (_disposed || _playbackActive() || _activeOperations > 0) {
      return Future.value();
    }
    return _updateTask ??= _checkForUpdates().whenComplete(() {
      _updateTask = null;
      _onUpdate();
    });
  }

  Future<void> _checkForUpdates() async {
    try {
      final YtDlpUpdateResult result;
      if (_isAndroid) {
        final data =
            jsonDecode(await _invokeNative('updateNightly', {})) as Map;
        result = YtDlpUpdateResult(
          YtDlpUpdateStatus.values.byName(data['status'] as String),
          version: data['version'] as String?,
          error: data['error'] as String?,
        );
      } else if (Platform.isWindows) {
        _configureUpdater();
        if (_updater == null) return;
        result = await _updater!.checkForUpdate();
      } else {
        return;
      }
      toolUpdateMessage = switch (result.status) {
        YtDlpUpdateStatus.updated =>
          'yt-dlp nightly ${result.version} actualizado y verificado.',
        YtDlpUpdateStatus.upToDate =>
          'yt-dlp nightly ${result.version}: versión actual verificada.',
        YtDlpUpdateStatus.throttled =>
          'Nightly: se comprueba como máximo una vez cada 24 horas.',
        YtDlpUpdateStatus.deferred =>
          'Actualización pospuesta hasta que termine la reproducción o la solicitud.',
        YtDlpUpdateStatus.failed =>
          result.error ??
              'No se pudo actualizar yt-dlp; se conserva la versión anterior.',
      };
    } catch (_) {
      toolUpdateMessage =
          'No se pudo comprobar nightly. La versión instalada se conserva.';
    }
  }

  bool get _isAndroid => _androidOverride ?? Platform.isAndroid;
  static const _channel = MethodChannel('aurora/source');
  final Map<String, Process> _jobs = {};
  final Map<String, Set<String>> _resolveJobs = {};
  final Set<String> _startingJobs = {};
  final Set<String> _cancelled = {};
  int _resolveCancellation = 0;
  final Map<String, void Function(double)> _progress = {};
  int _activeOperations = 0;
  bool _clearingCache = false;
  bool _changingCookie = false;
  bool _experimentalProgressive = false;
  bool _disposed = false;
  ProgressiveAudioRelay? _progressive;
  Future<File>? _progressiveDownload;
  String? _progressiveVideoId;

  @override
  bool get supportsExperimentalProgressivePlayback =>
      Platform.isWindows && !_isAndroid;

  @override
  void setExperimentalProgressivePlayback(bool enabled) {
    _experimentalProgressive =
        enabled && supportsExperimentalProgressivePlayback;
  }

  @override
  String? get cookieFile => _preferences.getString('cookieFile');

  @override
  Future<void> configureCookieFile(String? path) async {
    if (_activeOperations > 0 || _changingCookie) {
      throw StateError(
        'Espera a que terminen las búsquedas o descargas antes de cambiar la sesión.',
      );
    }
    _changingCookie = true;
    try {
      if (path == null) {
        await _preferences.remove('cookieFile');
        return;
      }
      final absolute = await _validateCookieFile(path);
      await _preferences.setString('cookieFile', absolute);
    } finally {
      _changingCookie = false;
    }
  }

  Future<T> _operation<T>(Future<T> Function() execute) async {
    if (_updater?.isInstalling ?? false) await _updateTask;
    if (_toolsRecoveryFailed) {
      throw StateError(
        'No se pudo recuperar yt-dlp. Repara o vuelve a configurar la carpeta de herramientas.',
      );
    }
    if (_disposed) throw StateError('La fuente de audio esta cerrada.');
    if (_changingCookie) {
      throw StateError('Espera a que termine el cambio de sesión.');
    }
    if (_clearingCache) {
      throw StateError('Espera a que termine la limpieza de la caché.');
    }
    _activeOperations++;
    try {
      return await execute();
    } finally {
      _activeOperations--;
    }
  }

  Future<String> _validateCookieFile(String path) async {
    final file = File(path).absolute;
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError(
        'El archivo de sesión no está disponible. Impórtalo nuevamente.',
      );
    }
    final length = await file.length();
    if (length == 0 || length > 1024 * 1024) {
      throw ArgumentError(
        'El archivo de sesión debe ocupar como máximo 1 MiB.',
      );
    }
    final String text;
    try {
      text = await file.readAsString();
    } on FormatException {
      throw ArgumentError(
        'El archivo de sesión tiene un formato inválido. Expórtalo nuevamente.',
      );
    }
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty ||
        !const {
          '# Netscape HTTP Cookie File',
          '# HTTP Cookie File',
        }.contains(lines.first)) {
      throw ArgumentError('Usa un archivo de cookies en formato Netscape.');
    }
    // Validate without including any cookie value in errors or diagnostics.
    var youtubeRows = 0;
    for (var line in lines.skip(1)) {
      if (line.startsWith('#HttpOnly_')) line = line.substring(10);
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields = line.split('\t');
      if (fields.length != 7 ||
          fields[0].isEmpty ||
          !const {'TRUE', 'FALSE'}.contains(fields[1]) ||
          fields[0].startsWith('.') != (fields[1] == 'TRUE') ||
          !const {'TRUE', 'FALSE'}.contains(fields[3]) ||
          (fields[4].isNotEmpty && int.tryParse(fields[4]) == null)) {
        throw ArgumentError(
          'El archivo de sesión tiene un formato inválido. Expórtalo nuevamente.',
        );
      }
      if (const {'youtube.com', '.youtube.com'}.contains(fields[0])) {
        youtubeRows++;
      }
    }
    if (youtubeRows == 0) {
      throw ArgumentError(
        'El archivo de sesión debe incluir cookies de YouTube.',
      );
    }
    return file.path;
  }

  static bool get _desktop => Platform.isWindows || Platform.isLinux;

  // `.exe` en Windows; en Linux, el binario sin extensión.
  static String _exe(String name) => Platform.isWindows ? '$name.exe' : name;

  // Deno es opcional en Linux: yt-dlp usa otro intérprete de JS si lo hay.
  static List<String> get _requiredTools => [
    _exe('yt-dlp'),
    _exe('ffmpeg'),
    _exe('ffprobe'),
    if (Platform.isWindows) 'deno.exe',
  ];

  static bool _hasTools(String directory) =>
      _requiredTools.every((n) => File(p.join(directory, n)).existsSync());

  // Linux: herramientas del sistema (p. ej. `apt install yt-dlp ffmpeg`).
  static String? _onPath(String name) {
    for (final directory in (Platform.environment['PATH'] ?? '').split(':')) {
      final file = p.join(directory, name);
      if (directory.isNotEmpty && File(file).existsSync()) return file;
    }
    return null;
  }

  @override
  String? get toolDirectory {
    final configured = _preferences.getString('toolDirectory');
    if (configured != null) return configured;
    if (!_desktop) return null;
    final adjacent = p.join(p.dirname(Platform.resolvedExecutable), 'tools');
    if (_hasTools(adjacent)) return adjacent;
    final system = Platform.isLinux ? _onPath('yt-dlp') : null;
    return system != null && _hasTools(p.dirname(system))
        ? p.dirname(system)
        : null;
  }

  @override
  String? get ffmpegExecutable {
    if (!_desktop) return null;
    final directory = toolDirectory;
    if (directory != null) return p.join(directory, _exe('ffmpeg'));
    return Platform.isLinux ? _onPath('ffmpeg') : null;
  }

  static const _safe = [
    '--ignore-config',
    '--no-plugin-dirs',
    '--no-remote-components',
    '--no-warnings',
    '--sleep-requests',
    '1',
    '--socket-timeout',
    '15',
    '--retries',
    '0',
    '--extractor-retries',
    '0',
    '--fragment-retries',
    '0',
  ];
  static const _maxCachedAudioBytes = 512 * 1024 * 1024;
  static const _maxAudioFileBytes = _maxCachedAudioBytes;
  static final _videoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static String redactError(String message) =>
      message.replaceAllMapped(RegExp(r'https?://[^\s<>"\x27]+'), (match) {
        final uri = Uri.tryParse(match.group(0)!);
        if (uri == null) return '[URL]';
        return uri.replace(userInfo: '', query: '', fragment: '').toString();
      });

  static String sourceError(String message) {
    final sanitized = redactError(message);
    final normalized = sanitized.toLowerCase();
    final failure = YouTubeRequestPolicy.classify(message);
    if (failure == YouTubeFailure.blocked) {
      return 'YouTube limitó las solicitudes o pidió una verificación. Aurora pausa los reintentos durante 1 minuto; YouTube puede mantener la restricción más tiempo. Los archivos locales siguen disponibles.';
    }
    if (failure == YouTubeFailure.unavailable) {
      return 'Este contenido de YouTube no está disponible públicamente. Prueba otro enlace.';
    }
    if (failure == YouTubeFailure.accessDenied) {
      return 'YouTube rechazó el acceso (403). Esto no demuestra que el enlace haya vencido ni que toda la red esté bloqueada. Aurora pausa los reintentos durante 1 minuto.';
    }
    if (normalized.contains('cookie')) {
      return 'YouTube rechazó el archivo de sesión. Renueva tu sesión opcional en Ajustes.';
    }
    return sanitized.length > 2000
        ? '${sanitized.substring(0, 2000)}…'
        : sanitized;
  }

  Future<String> _native(String method, Map<String, Object?> arguments) async {
    if (const {
      'search',
      'playlist',
      'resolve',
      'download',
      'downloadVideo',
      'cacheAudio',
      'progressiveInfo',
      'progressiveAudio',
    }.contains(method)) {
      return _operation(
        () => _requests.run(
          () {
            final jobId = arguments['jobId'] as String?;
            if (jobId != null) _throwIfResolveCancelled(jobId);
            return _invokeNative(method, arguments);
          },
          retryTransient: const {
            'search',
            'playlist',
            'resolve',
          }.contains(method),
        ),
      );
    }
    return _invokeNative(method, arguments);
  }

  Future<String> _invokeNative(
    String method,
    Map<String, Object?> arguments,
  ) async {
    final cookie = cookieFile;
    if (cookie != null &&
        const {
          'search',
          'playlist',
          'resolve',
          'download',
          'downloadVideo',
          'cacheAudio',
          'progressiveInfo',
          'progressiveAudio',
        }.contains(method)) {
      arguments = {
        ...arguments,
        'cookieFile': await _validateCookieFile(cookie),
      };
    }
    try {
      return (await _channel.invokeMethod<String>(method, arguments)) ?? '';
    } on PlatformException catch (error) {
      _requests.recordFailure(error.message ?? '');
      throw StateError(sourceError(error.message ?? 'Error de la fuente.'));
    }
  }

  static Uri validateYouTube(String value) {
    final uri = Uri.tryParse(value);
    const hosts = {
      'youtube.com',
      'www.youtube.com',
      'music.youtube.com',
      'm.youtube.com',
      'youtu.be',
    };
    if (uri == null ||
        uri.scheme != 'https' ||
        !hosts.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443)) {
      throw ArgumentError('Usa un enlace HTTPS de YouTube.');
    }
    return uri;
  }

  /// Accepts a single public video URL, never a Music page or playlist.
  static Uri validateVideoUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        !const {
          'www.youtube.com',
          'youtu.be',
        }.contains(uri.host.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        uri.queryParameters.containsKey('list')) {
      throw ArgumentError(
        'Usa un enlace HTTPS público de un video de YouTube.',
      );
    }
    final id = uri.host.toLowerCase() == 'youtu.be'
        ? (uri.pathSegments.length == 1 ? uri.pathSegments.single : '')
        : uri.path == '/watch'
        ? uri.queryParameters['v'] ?? ''
        : uri.pathSegments.length == 2 &&
              const {'shorts', 'live', 'embed'}.contains(uri.pathSegments[0])
        ? uri.pathSegments[1]
        : '';
    if (!_videoIdPattern.hasMatch(id) ||
        (uri.host.toLowerCase() == 'www.youtube.com' &&
            uri.path == '/watch' &&
            uri.queryParametersAll.entries.any(
              (entry) =>
                  (entry.key != 'v' &&
                      entry.key != 't' &&
                      entry.key != 'start') ||
                  entry.value.length != 1,
            ))) {
      throw ArgumentError('El enlace debe identificar un solo video público.');
    }
    return uri;
  }

  @override
  Future<void> configureToolDirectory(String directory) async {
    final absolute = Directory(directory).absolute.path;
    for (final name in _requiredTools) {
      if (!await File(p.join(absolute, name)).exists()) {
        throw StateError('Falta $name en la carpeta.');
      }
    }
    await _preferences.setString('toolDirectory', absolute);
    if (_updateDirectory != null) {
      _configureUpdater();
      final recovered = await _updater!.recoverPendingInstallation();
      _toolsRecoveryFailed = recovered.status == YtDlpUpdateStatus.failed;
      if (_toolsRecoveryFailed) {
        throw StateError(recovered.error ?? 'No se pudo recuperar yt-dlp.');
      }
    }
  }

  Future<String> _run(
    List<String> arguments, {
    String? jobId,
    void Function(double)? onProgress,
  }) async {
    return _operation(
      () => arguments.contains('--version')
          ? _runWindows(arguments, jobId: jobId, onProgress: onProgress)
          : _requests.run(
              () =>
                  _runWindows(arguments, jobId: jobId, onProgress: onProgress),
              retryTransient: jobId == null,
            ),
    );
  }

  Future<String> _runWindows(
    List<String> arguments, {
    String? jobId,
    void Function(double)? onProgress,
  }) async {
    if (!_desktop) {
      throw UnsupportedError('Esta fuente requiere Windows, Linux o Android.');
    }
    final directory = toolDirectory;
    if (directory == null) {
      throw StateError(
        'Selecciona la carpeta de yt-dlp, FFmpeg y Deno en Ajustes.',
      );
    }
    final executable = p.join(directory, _exe('yt-dlp'));
    if (!await File(executable).exists()) {
      throw StateError('No se encuentra ${_exe('yt-dlp')}.');
    }
    final deno = p.join(directory, _exe('deno'));
    if (jobId != null && _cancelled.remove(jobId)) {
      throw StateError('Descarga cancelada.');
    }
    final process = await Process.start(executable, [
      ..._safe,
      if (cookieFile != null) ...[
        '--cookies',
        await _validateCookieFile(cookieFile!),
      ],
      if (await File(deno).exists()) ...['--js-runtimes', 'deno:$deno'],
      '--ffmpeg-location',
      directory,
      ...arguments,
    ], runInShell: false);
    final id = jobId ?? 'operation-${DateTime.now().microsecondsSinceEpoch}';
    _jobs[id] = process;
    if (!id.startsWith('resolve-')) _startingJobs.remove(id);
    if (_cancelled.contains(id)) {
      await _killTree(process);
    }
    final output = StringBuffer(), errors = StringBuffer();
    int outputBytes = 0;
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .forEach((line) {
          final previousBytes = outputBytes;
          outputBytes += line.length;
          if (outputBytes > 8 * 1024 * 1024) {
            if (previousBytes <= 8 * 1024 * 1024) {
              unawaited(_killTree(process));
            }
            return;
          }
          output.writeln(line);
          if (onProgress != null && line.startsWith('AURORA_PROGRESS:')) {
            final percent = double.tryParse(
              line.substring(16).trim().replaceAll('%', ''),
            );
            if (percent != null) onProgress((percent / 100).clamp(0, 1));
          }
        });
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach((chunk) {
          if (errors.length < 8192) errors.write(chunk);
        });
    try {
      final code = await process.exitCode.timeout(
        jobId == null
            ? const Duration(seconds: 90)
            : const Duration(minutes: 30),
        onTimeout: () async {
          await _killTree(process);
          throw TimeoutException('La fuente tardó demasiado.');
        },
      );
      await Future.wait([stdoutDone, stderrDone]);
      if (_cancelled.remove(id)) throw StateError('Descarga cancelada.');
      if (outputBytes > 8 * 1024 * 1024) {
        throw StateError('La respuesta supera el límite permitido.');
      }
      if (code != 0) {
        _requests.recordFailure(errors.toString());
        throw StateError('yt-dlp: ${sourceError(errors.toString().trim())}');
      }
      return output.toString();
    } finally {
      _jobs.remove(id);
    }
  }

  Future<void> _killTree(Process process) async {
    try {
      if (!Platform.isWindows) return;
      final taskkill = p.join(
        Platform.environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'taskkill.exe',
      );
      await Process.run(taskkill, [
        '/PID',
        '${process.pid}',
        '/T',
        '/F',
      ], runInShell: false);
    } on ProcessException {
      // The process may already have exited while its streams were draining.
    } finally {
      process.kill();
    }
  }

  Track _track(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    return Track(
      id: 'yt:$id',
      title: json['title']?.toString() ?? 'Sin título',
      artist:
          (json['artist'] ?? json['uploader'] ?? json['channel'] ?? 'YouTube')
              .toString(),
      duration: Duration(
        milliseconds: ((json['duration'] as num? ?? 0) * 1000).round(),
      ),
      artworkUrl: selectArtworkUrl(json),
      pageUrl: 'https://www.youtube.com/watch?v=$id',
    );
  }

  /// Prefer declared resolution; lower quality YouTube defaults are fallback.
  @visibleForTesting
  static String? selectArtworkUrl(Map<String, dynamic> json) {
    final candidates = <({String url, double width, bool lowQuality})>[];
    void add(Object? value, [Object? width]) {
      if (value is! String) return;
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return;
      }
      final file = uri.pathSegments.lastOrNull?.toLowerCase() ?? '';
      final lowQuality =
          file.contains('hqdefault') || file.contains('mqdefault');
      final fallback = artworkWidthHint(value).toDouble();
      final pixels = width is num && width.isFinite && width > 0
          ? width.toDouble()
          : fallback;
      candidates.add((url: value, width: pixels, lowQuality: lowQuality));
    }

    final thumbnails = json['thumbnails'];
    if (thumbnails is List) {
      for (final entry in thumbnails.whereType<Map>()) {
        add(entry['url'], entry['width']);
      }
    }
    add(json['thumbnail']);
    if (candidates.isEmpty) return null;
    final hasPreferred = candidates.any(
      (image) => !image.lowQuality && image.width >= 500,
    );
    final selected =
        candidates.where((image) => !hasPreferred || !image.lowQuality).toList()
          ..sort((a, b) => b.width.compareTo(a.width));
    return selected.first.url;
  }

  Future<List<Track>> _listing(String target, int limit, String method) {
    final key = '$method:$limit:$target';
    final cached = _listingCache[key];
    if (cached != null && _now().isBefore(cached.expires)) {
      return Future.value(List.of(cached.tracks));
    }
    return _listingRequests.putIfAbsent(key, () {
      final future = _fetchListing(target, limit, method).then((tracks) {
        if (_listingCache.length >= 64) {
          _listingCache.remove(_listingCache.keys.first);
        }
        _listingCache[key] = (
          tracks: List.unmodifiable(tracks),
          expires: _now().add(const Duration(minutes: 5)),
        );
        return tracks;
      });
      return future.whenComplete(() {
        _listingRequests.remove(key);
      });
    });
  }

  Future<List<Track>> _fetchListing(
    String target,
    int limit,
    String method,
  ) async {
    final String raw;
    if (_isAndroid) {
      raw = await _native(method, {'target': target, 'limit': limit});
    } else {
      raw = await _run([
        '--flat-playlist',
        '--dump-single-json',
        '--playlist-end',
        '$limit',
        '--',
        target,
      ]);
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return ((data['entries'] as List?) ?? [data])
        .whereType<Map>()
        .map((e) => _track(Map<String, dynamic>.from(e)))
        .where((t) => t.id != 'yt:')
        .take(limit)
        .toList();
  }

  @override
  Future<List<Track>> search(String query, {int limit = 20}) async {
    final text = query.trim();
    if (text.isEmpty) return [];
    if (text.length > 500) {
      throw ArgumentError('La búsqueda es demasiado larga.');
    }
    final count = limit.clamp(1, 50);
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
      return _listing(validateYouTube(text).toString(), count, 'playlist');
    }
    return _listing('ytsearch$count:$text', count, 'search');
  }

  @override
  Future<List<Track>> importPlaylist(Uri url) =>
      _listing(validateYouTube(url.toString()).toString(), 200, 'playlist');
  @override
  Future<ResolvedAudio> resolve(Track track) async {
    final cancellation = _resolveCancellation;
    final progressiveEnabled = _experimentalProgressive;
    await _closeProgressive();
    if (_isAndroid && cancellation != _resolveCancellation) {
      throw StateError('Resolución cancelada.');
    }
    if (track.isLocal && await File(track.localPath!).exists()) {
      return ResolvedAudio(input: track.localPath!, duration: track.duration);
    }
    if (track.isLocal && track.pageUrl == null) {
      throw StateError(
        'El archivo local ya no está disponible. Impórtalo nuevamente.',
      );
    }
    final target = validateYouTube(track.pageUrl ?? '').toString();
    if (progressiveEnabled && supportsExperimentalProgressivePlayback) {
      final result = await _resolveProgressiveAudio(track, target);
      if (result != null) return result;
    }
    if (_desktop && !_isAndroid) {
      return _resolveWindowsAudio(track, target);
    }
    if (_isAndroid) return _resolveAndroidAudio(track, target);
    final raw = Platform.isAndroid
        ? await _native('resolve', {'target': target})
        : await _run([
            '--no-playlist',
            '-f',
            'bestaudio/best',
            '--dump-single-json',
            '--',
            target,
          ]);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final url = data['url'] as String?;
    if (url == null || Uri.tryParse(url)?.scheme != 'https') {
      throw StateError('No hay audio disponible.');
    }
    return ResolvedAudio(
      input: url,
      headers: (data['http_headers'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v.toString()),
      ),
      duration: Duration(
        milliseconds: ((data['duration'] as num? ?? 0) * 1000).round(),
      ),
    );
  }

  Future<ResolvedAudio> _resolveWindowsAudio(
    Track track,
    String target,
  ) => _operation(() async {
    final uri = Uri.parse(target);
    final targetId = uri.host == 'youtu.be'
        ? (uri.pathSegments.isEmpty ? null : uri.pathSegments.first)
        : uri.queryParameters['v'];
    final isYouTubeId = track.id.startsWith('yt:');
    final videoId = isYouTubeId ? track.id.substring(3) : targetId ?? '';
    if (!_videoIdPattern.hasMatch(videoId)) {
      throw ArgumentError('El identificador del video no es v\u00e1lido.');
    }
    if (isYouTubeId && targetId != videoId) {
      throw ArgumentError(
        'El identificador del video no coincide con el enlace.',
      );
    }

    final jobId = 'resolve-$videoId-${DateTime.now().microsecondsSinceEpoch}';
    _resolveJobs.putIfAbsent(videoId, () => <String>{}).add(jobId);
    _startingJobs.add(jobId);
    try {
      if (toolDirectory == null) {
        throw StateError(
          'Selecciona la carpeta de yt-dlp, FFmpeg y Deno en Ajustes.',
        );
      }
      final cache = await _audioCacheDirectory();
      final cachePath = await cache.resolveSymbolicLinks();

      final cached = File(p.join(cachePath, '$videoId.audio'));
      final cachedDuration = await _cachedAudioDuration(
        cached,
        expectedDuration: track.duration,
      );
      _throwIfResolveCancelled(jobId);
      if (cachedDuration != null) {
        await cached.setLastModified(DateTime.now());
        await _pruneAudioCache(cache, protect: cached);
        _throwIfResolveCancelled(jobId);
        return ResolvedAudio(input: cached.path, duration: cachedDuration);
      }
      final cachedType = await FileSystemEntity.type(
        cached.path,
        followLinks: false,
      );
      if (cachedType != FileSystemEntityType.notFound) {
        if (cachedType != FileSystemEntityType.file) {
          throw StateError('El archivo de audio en cach\u00e9 no es seguro.');
        }
        await cached.delete();
      }

      await _pruneAudioCache(cache);
      final staging = await cache.createTemp('.aurora-yt-$videoId-');
      try {
        await _run([
          '--no-playlist',
          '-f',
          'bestaudio/best',
          '--max-filesize',
          '${_maxAudioFileBytes ~/ (1024 * 1024)}M',
          '--newline',
          '--progress-template',
          'download:AURORA_PROGRESS:%(progress._percent_str)s',
          '-o',
          p.join(staging.path, 'audio.%(ext)s'),
          '--',
          target,
        ], jobId: jobId);
        final outputs = await staging
            .list(followLinks: false)
            .where(
              (entity) =>
                  entity is File &&
                  RegExp(
                    r'^audio\.[A-Za-z0-9]{1,8}$',
                  ).hasMatch(p.basename(entity.path)),
            )
            .toList();
        if (outputs.length != 1 || outputs.single is! File) {
          throw StateError(
            'La descarga no produjo un \u00fanico archivo de audio.',
          );
        }
        final downloaded = outputs.single as File;
        final length = await downloaded.length();
        final duration = length <= _maxAudioFileBytes
            ? await _audioDuration(downloaded)
            : null;
        if (length == 0 || duration == null) {
          throw StateError(
            'La descarga de audio est\u00e1 incompleta o no es v\u00e1lida.',
          );
        }
        _throwIfResolveCancelled(jobId);
        if (!_durationMatches(duration, track.duration)) {
          throw StateError(
            'La duraci\u00f3n del audio descargado no coincide con el video.',
          );
        }
        if (await cached.exists()) {
          final existingDuration = await _cachedAudioDuration(
            cached,
            expectedDuration: track.duration,
          );
          _throwIfResolveCancelled(jobId);
          if (existingDuration != null) {
            await cached.setLastModified(DateTime.now());
            _throwIfResolveCancelled(jobId);
            await _pruneAudioCache(cache, protect: cached);
            _throwIfResolveCancelled(jobId);
            return ResolvedAudio(
              input: cached.path,
              duration: existingDuration,
            );
          }
          final type = await FileSystemEntity.type(
            cached.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.file) await cached.delete();
          if (type != FileSystemEntityType.notFound &&
              type != FileSystemEntityType.file) {
            throw StateError('El archivo de audio en cach\u00e9 no es seguro.');
          }
        }
        _throwIfResolveCancelled(jobId);
        try {
          await downloaded.rename(cached.path);
        } on FileSystemException {
          final existingDuration = await _cachedAudioDuration(
            cached,
            expectedDuration: track.duration,
          );
          _throwIfResolveCancelled(jobId);
          if (existingDuration == null) rethrow;
          await cached.setLastModified(DateTime.now());
          await _pruneAudioCache(cache, protect: cached);
          _throwIfResolveCancelled(jobId);
          return ResolvedAudio(input: cached.path, duration: existingDuration);
        }
        _throwIfResolveCancelled(jobId);
        await _pruneAudioCache(cache, protect: cached);
        _throwIfResolveCancelled(jobId);
        return ResolvedAudio(input: cached.path, duration: duration);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    } finally {
      _startingJobs.remove(jobId);
      final jobs = _resolveJobs[videoId];
      jobs?.remove(jobId);
      if (jobs?.isEmpty ?? false) _resolveJobs.remove(videoId);
      _cancelled.remove(jobId);
    }
  });

  /// One yt-dlp extraction of a streamable HTTPS URL; never downloads audio.
  Future<ResolvedAudio> resolveStreamUrl(Track track) => _resolveAndroidAudio(
    track,
    validateYouTube(track.pageUrl ?? '').toString(),
  );

  Future<ResolvedAudio> _resolveAndroidAudio(Track track, String target) {
    final uri = Uri.parse(target);
    final targetId = uri.host == 'youtu.be'
        ? uri.pathSegments.firstOrNull
        : uri.queryParameters['v'];
    final videoId = track.id.startsWith('yt:')
        ? track.id.substring(3)
        : targetId ?? '';
    if (!_videoIdPattern.hasMatch(videoId) || targetId != videoId) {
      throw ArgumentError(
        'El identificador del video no coincide con el enlace.',
      );
    }
    final cached = _streamCache[videoId];
    if (cached != null &&
        _now().add(const Duration(minutes: 2)).isBefore(cached.expires)) {
      return Future.value(cached.audio);
    }
    return _streamRequests.putIfAbsent(videoId, () {
      final future = _fetchAndroidStream(track, target, videoId);
      return future.whenComplete(() {
        _streamRequests.remove(videoId);
      });
    });
  }

  Future<ResolvedAudio> _fetchAndroidStream(
    Track track,
    String target,
    String videoId,
  ) async {
    final jobId = 'resolve-$videoId-${_now().microsecondsSinceEpoch}';
    _resolveJobs.putIfAbsent(videoId, () => <String>{}).add(jobId);
    _startingJobs.add(jobId);
    try {
      final raw = _isAndroid
          ? await _native('resolve', {'target': target, 'jobId': jobId})
          : await _run([
              '--no-playlist',
              '-f',
              'bestaudio',
              '--dump-single-json',
              '--',
              target,
            ]);
      _throwIfResolveCancelled(jobId);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final input = data['url'] as String?;
      final uri = input == null ? null : Uri.tryParse(input);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw StateError('No hay una URL HTTPS reproducible disponible.');
      }
      final headers = <String, String>{};
      for (final entry in (data['http_headers'] as Map? ?? {}).entries) {
        final name = entry.key.toString(), value = entry.value.toString();
        if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(name) ||
            value.contains('\r') ||
            value.contains('\n')) {
          throw StateError('La fuente devolvió cabeceras de audio inválidas.');
        }
        // Credentials stay in the resolver; only ordinary stream headers cross.
        if (const {
          'cookie',
          'authorization',
          'proxy-authorization',
        }.contains(name.toLowerCase())) {
          continue;
        }
        headers[name] = value;
      }
      final duration = (data['duration'] as num?)?.toDouble();
      final audio = ResolvedAudio(
        input: input!,
        headers: headers,
        duration: duration != null && duration.isFinite && duration > 0
            ? Duration(milliseconds: (duration * 1000).round())
            : track.duration,
      );
      final expirySeconds = int.tryParse(
        uri.queryParameters['expire'] ?? uri.queryParameters['expires'] ?? '',
      );
      final expires = expirySeconds == null
          ? _now().add(const Duration(minutes: 10))
          : DateTime.fromMillisecondsSinceEpoch(expirySeconds * 1000);
      if (!expires.isAfter(_now())) {
        throw StateError(
          'La fuente devolvió una URL de audio vencida. No se inició la reproducción.',
        );
      }
      if (_streamCache.length >= 32) {
        _streamCache.remove(_streamCache.keys.first);
      }
      _streamCache[videoId] = (audio: audio, expires: expires);
      return audio;
    } finally {
      _startingJobs.remove(jobId);
      final jobs = _resolveJobs[videoId];
      jobs?.remove(jobId);
      if (jobs?.isEmpty ?? false) _resolveJobs.remove(videoId);
      _cancelled.remove(jobId);
    }
  }

  String? _videoId(Track track) {
    final page = Uri.tryParse(track.pageUrl ?? '');
    return page?.host == 'youtu.be'
        ? page?.pathSegments.firstOrNull
        : page?.queryParameters['v'];
  }

  @override
  void invalidateResolvedAudio(Track track) =>
      _streamCache.remove(_videoId(track));

  @override
  bool isExpiredStream(Track track) {
    final cached = _streamCache[_videoId(track)];
    if (cached == null) return false;
    final uri = Uri.tryParse(cached.audio.input);
    final seconds = int.tryParse(
      uri?.queryParameters['expire'] ?? uri?.queryParameters['expires'] ?? '',
    );
    return seconds != null &&
        !_now().isBefore(DateTime.fromMillisecondsSinceEpoch(seconds * 1000));
  }

  @override
  void reportPlaybackFailure(String message) =>
      _requests.recordFailure(message);

  static bool _durationMatches(Duration actual, Duration expected) =>
      expected <= Duration.zero ||
      (actual.inMilliseconds - expected.inMilliseconds).abs() <=
          (expected.inMilliseconds * 0.02).clamp(5000, 10000);

  void _throwIfResolveCancelled(String jobId) {
    if (_disposed || _cancelled.contains(jobId)) {
      throw StateError('Descarga cancelada.');
    }
  }

  Future<void> _closeProgressive() async {
    final relay = _progressive;
    final download = _progressiveDownload;
    _progressive = null;
    _progressiveDownload = null;
    _progressiveVideoId = null;
    await relay?.dispose();
    await download?.then<void>(
      (_) {},
      onError: (Object _, StackTrace stack) {},
    );
  }

  Future<ResolvedAudio?> _resolveProgressiveAudio(
    Track track,
    String target,
  ) => _operation(() async {
    final uri = Uri.parse(target);
    final targetId = uri.host == 'youtu.be'
        ? (uri.pathSegments.isEmpty ? null : uri.pathSegments.first)
        : uri.queryParameters['v'];
    final videoId = track.id.startsWith('yt:')
        ? track.id.substring(3)
        : targetId ?? '';
    if (!_videoIdPattern.hasMatch(videoId) || targetId != videoId) {
      throw ArgumentError(
        'El identificador del video no coincide con el enlace.',
      );
    }
    final jobId =
        'progressive-$videoId-${DateTime.now().microsecondsSinceEpoch}';
    _resolveJobs.putIfAbsent(videoId, () => <String>{}).add(jobId);
    _startingJobs.add(jobId);
    var backgroundOwnsJob = false;
    try {
      final cache = await _audioCacheDirectory();
      final cached = File(
        p.join(await cache.resolveSymbolicLinks(), '$videoId.audio'),
      );
      final cachedDuration = await _cachedAudioDuration(
        cached,
        expectedDuration: track.duration,
      );
      _throwIfResolveCancelled(jobId);
      if (cachedDuration != null) {
        await cached.setLastModified(DateTime.now());
        return ResolvedAudio(input: cached.path, duration: cachedDuration);
      }
      final cachedType = await FileSystemEntity.type(
        cached.path,
        followLinks: false,
      );
      if (cachedType != FileSystemEntityType.notFound) {
        if (cachedType != FileSystemEntityType.file) {
          throw StateError('El archivo de audio en cache no es seguro.');
        }
        await cached.delete();
      }
      const selection = 'bestaudio[ext=webm][protocol=https]/bestaudio/best';
      final raw = _isAndroid
          ? await _native('progressiveInfo', {'target': target, 'jobId': jobId})
          : await _run([
              '--no-playlist',
              '-f',
              selection,
              '--dump-single-json',
              '--',
              target,
            ], jobId: jobId);
      _throwIfResolveCancelled(jobId);
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final format = data['format_id']?.toString() ?? '';
      final seconds = (data['duration'] as num?)?.toDouble() ?? 0;
      // Moov-at-end MP4, fragmented DASH/HLS and unknown duration retain the
      // existing validated full-download path. yt-dlp owns every remote request.
      if (data['ext'] != 'webm' ||
          data['protocol'] != 'https' ||
          !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(format) ||
          !seconds.isFinite ||
          seconds <= 0) {
        return null;
      }
      final expected = Duration(milliseconds: (seconds * 1000).round());
      if (!_durationMatches(expected, track.duration)) {
        throw StateError('La duracion del audio no coincide con el video.');
      }
      final reportedSize = data['filesize'];
      final total =
          reportedSize is num &&
              reportedSize.isFinite &&
              reportedSize > 0 &&
              reportedSize == reportedSize.roundToDouble()
          ? reportedSize.toInt()
          : null;
      if (total != null && total > _maxAudioFileBytes) {
        throw StateError('El audio supera el limite de 512 MiB.');
      }
      // Reserve disk space before growing the private input. Unknown-size audio
      // reserves the full cap; publication never duplicates the staged file.
      await _pruneAudioCache(cache, reserveBytes: total ?? _maxAudioFileBytes);
      _throwIfResolveCancelled(jobId);
      final staging = await cache.createTemp('.aurora-progressive-$videoId-');
      final growing = File(p.join(staging.path, 'audio.webm'));
      ProgressiveAudioRelay? session;
      final completed = _operation(() async {
        try {
          _throwIfResolveCancelled(jobId);
          if (_isAndroid) {
            await _native('progressiveAudio', {
              'target': target,
              'videoId': videoId,
              'directory': staging.path,
              'jobId': jobId,
              'formatId': format,
            });
          } else {
            await _run([
              '--no-playlist',
              '-f',
              '$format[ext=webm][protocol=https]',
              '--no-part',
              '--no-continue',
              '--fixup',
              'never',
              '--max-filesize',
              '512M',
              '-o',
              growing.path,
              '--',
              target,
            ], jobId: jobId);
          }
          _throwIfResolveCancelled(jobId);
          if (await FileSystemEntity.type(growing.path, followLinks: false) !=
              FileSystemEntityType.file) {
            throw StateError(
              'La descarga no produjo un archivo de audio seguro.',
            );
          }
          final length = await growing.length();
          if (length <= 0 ||
              length > _maxAudioFileBytes ||
              (total != null && length != total)) {
            throw StateError('La descarga de audio esta incompleta.');
          }
          final duration = await _audioDuration(growing);
          if (duration == null ||
              !_durationMatches(duration, expected) ||
              !_durationMatches(duration, track.duration)) {
            throw StateError(
              'La duracion del audio descargado no coincide con el video.',
            );
          }
          await _validateProgressiveDecode(growing, jobId);
          _throwIfResolveCancelled(jobId);
          final relay = session;
          if (relay == null) {
            await growing.rename(cached.path);
          } else {
            await relay.publishTo(cached);
          }
          await _pruneAudioCache(cache, protect: cached);
          return cached;
        } finally {
          if (await staging.exists()) await staging.delete(recursive: true);
          _finishResolveJob(videoId, jobId);
        }
      });
      backgroundOwnsJob = true;
      ProgressiveAudioRelay relay;
      try {
        relay = await ProgressiveAudioRelay.start(
          file: growing,
          completed: completed,
          expectedBytes: total,
          cancel: () => _cancelProgressiveJob(jobId),
        );
      } catch (_) {
        await _cancelProgressiveJob(jobId);
        await completed.catchError((Object _) => cached);
        rethrow;
      }
      _progressive = relay;
      _progressiveDownload = completed;
      session = relay;
      _progressiveVideoId = videoId;
      try {
        await relay.waitUntilReady();
        _throwIfResolveCancelled(jobId);
        return ResolvedAudio(
          input: relay.uri.toString(),
          duration: expected,
          validateCompletion: () async {
            await relay.settled;
            if (!relay.isComplete) {
              throw StateError(
                'La descarga de audio fallo. Vuelve a intentar.',
              );
            }
          },
        );
      } catch (_) {
        await _closeProgressive();
        rethrow;
      }
    } finally {
      if (!backgroundOwnsJob) _finishResolveJob(videoId, jobId);
    }
  });

  void _finishResolveJob(String videoId, String jobId) {
    _startingJobs.remove(jobId);
    final jobs = _resolveJobs[videoId];
    jobs?.remove(jobId);
    if (jobs?.isEmpty ?? false) _resolveJobs.remove(videoId);
    _cancelled.remove(jobId);
  }

  Future<void> _cancelProgressiveJob(String jobId) async {
    if (!_startingJobs.contains(jobId)) return;
    _cancelled.add(jobId);
    if (_isAndroid) {
      await _channel.invokeMethod<void>('cancel', {'jobId': jobId});
    } else {
      final process = _jobs[jobId];
      if (process != null) await _killTree(process);
    }
  }

  Future<void> _validateProgressiveDecode(File file, String jobId) async {
    _throwIfResolveCancelled(jobId);
    if (_audioDurationOverride != null) return;
    if (_isAndroid) {
      await _native('validateProgressiveAudio', {
        'path': file.path,
        'jobId': jobId,
      });
      return;
    }
    final process = await Process.start(ffmpegExecutable!, [
      '-nostdin',
      '-v',
      'error',
      '-xerror',
      '-err_detect',
      'explode',
      '-i',
      file.path,
      '-map',
      '0:a:0',
      '-vn',
      '-f',
      'null',
      '-',
    ], runInShell: false);
    _jobs[jobId] = process;
    final drains = Future.wait([
      process.stdout.drain<void>(),
      process.stderr.drain<void>(),
    ]);
    try {
      final code = await process.exitCode.timeout(
        const Duration(minutes: 2),
        onTimeout: () async {
          await _killTree(process);
          return -1;
        },
      );
      await drains;
      if (code != 0) {
        throw StateError(
          'El audio descargado no se puede decodificar completamente.',
        );
      }
    } finally {
      _jobs.remove(jobId);
    }
  }

  Future<Duration?> _cachedAudioDuration(
    File file, {
    Duration expectedDuration = Duration.zero,
  }) async {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    if (await file.length() > _maxAudioFileBytes) return null;
    final duration = await _audioDuration(file);
    return duration != null && _durationMatches(duration, expectedDuration)
        ? duration
        : null;
  }

  Future<Directory> _audioCacheDirectory() async {
    final support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final supportPath = await support.resolveSymbolicLinks();
    final cache = Directory(p.join(supportPath, 'yt-dlp-audio'));
    await cache.create(recursive: true);
    final cachePath = await cache.resolveSymbolicLinks();
    if (!p.isWithin(supportPath, cachePath)) {
      throw StateError('La carpeta de audio en caché no es segura.');
    }
    return cache;
  }

  @override
  bool get supportsPlaybackCache => _desktop || _isAndroid;

  @override
  Future<({int bytes, int files})> playbackCacheInfo() async {
    if (!supportsPlaybackCache) return (bytes: 0, files: 0);
    final info = rust.audioCacheInfo(dir: (await _audioCacheDirectory()).path);
    return (bytes: info.bytes, files: info.files);
  }

  @override
  Future<int> clearPlaybackCache({String? protectedPath}) async {
    if (!supportsPlaybackCache) return 0;
    if (_clearingCache || _activeOperations > 0) {
      throw StateError('Espera a que terminen las operaciones de audio.');
    }
    _clearingCache = true;
    try {
      final cache = await _audioCacheDirectory();
      final effectivePath = protectedPath == _progressive?.uri.toString()
          ? _progressive?.file.path
          : protectedPath;
      return rust.clearAudioCache(dir: cache.path, protected: effectivePath);
    } finally {
      _clearingCache = false;
    }
  }

  Future<Duration?> _audioDuration(File file) async {
    final override = _audioDurationOverride;
    if (override != null) return override(file);
    if (_isAndroid) {
      try {
        final duration = int.tryParse(
          await _native('probeAudio', {'path': file.absolute.path}),
        );
        return duration == null || duration <= 0
            ? null
            : Duration(milliseconds: duration);
      } on StateError {
        return null;
      }
    }
    final directory = toolDirectory;
    if (directory == null) return null;
    final ffprobe = File(p.join(directory, _exe('ffprobe')));
    if (!await ffprobe.exists()) return null;
    final result = await Process.run(ffprobe.path, [
      '-v',
      'error',
      '-select_streams',
      'a:0',
      '-show_entries',
      'stream=codec_type:format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      file.path,
    ], runInShell: false);
    if (result.exitCode != 0) return null;
    final values = result.stdout.toString().trim().split(RegExp(r'\s+'));
    if (values.length < 2 || values.first != 'audio') return null;
    final seconds = double.tryParse(values.last);
    if (seconds == null || !seconds.isFinite || seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<void> _pruneAudioCache(
    Directory cache, {
    File? protect,
    int reserveBytes = 0,
  }) async {
    final report = rust.pruneAudioCache(
      dir: cache.path,
      maxBytes: _maxCachedAudioBytes,
      reserveBytes: reserveBytes,
      protected: [
        if (protect != null) protect.path,
        if (_progressive != null) _progressive!.file.path,
      ],
    );
    if (report.noSpace) {
      throw StateError('No hay espacio disponible en la cache de audio.');
    }
  }

  @override
  Future<void> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    final target = validateYouTube(track.pageUrl ?? '').toString();
    if (await destination.exists()) {
      throw StateError('El archivo de destino ya existe.');
    }
    await destination.parent.create(recursive: true);
    final temp = await Directory(
      destination.parent.path,
    ).createTemp('.aurora-');
    try {
      if (_cancelled.contains(jobId)) throw StateError('Descarga cancelada.');
      if (_isAndroid) {
        if (onProgress != null) _progress[jobId] = onProgress;
        final legacy = _updateDirectory == null
            ? null
            : File(
                p.join(
                  _updateDirectory!.path,
                  'yt-dlp-audio',
                  '${_videoId(track)}.audio',
                ),
              );
        if (legacy != null &&
            await _cachedAudioDuration(
                  legacy,
                  expectedDuration: track.duration,
                ) !=
                null) {
          await _operation(
            () => _invokeNative('exportCachedAudio', {
              'path': legacy.path,
              'directory': temp.path,
              'jobId': jobId,
            }),
          );
        } else {
          await _native('download', {
            'target': target,
            'directory': temp.path,
            'jobId': jobId,
          });
        }
      } else {
        await _run(
          [
            '--no-playlist',
            '-f',
            'bestaudio/best',
            '-x',
            '--audio-format',
            'mp3',
            '--audio-quality',
            '0',
            '--newline',
            '--progress-template',
            'download:AURORA_PROGRESS:%(progress._percent_str)s',
            '-o',
            p.join(temp.path, 'audio.%(ext)s'),
            '--',
            target,
          ],
          jobId: jobId,
          onProgress: onProgress,
        );
      }
      final file = File(p.join(temp.path, 'audio.mp3'));
      if (!await file.exists() || await file.length() == 0) {
        throw StateError('La descarga no produjo audio.');
      }
      if (await destination.exists()) throw StateError('El destino ya existe.');
      if (_cancelled.contains(jobId)) throw StateError('Descarga cancelada.');
      await file.rename(destination.path);
      onProgress?.call(1);
    } finally {
      _progress.remove(jobId);
      _cancelled.remove(jobId);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  /// Downloads a video container into [destination]'s parent directory. The
  /// destination basename is retained and the actual container extension is
  /// appended (for example, `abc.mp4` or `abc.webm`).
  @override
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    final target = validateVideoUrl(url.toString()).toString();
    await destination.parent.create(recursive: true);
    final parent = await destination.parent.resolveSymbolicLinks();
    final baseName = p.basenameWithoutExtension(destination.path);
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(baseName)) {
      throw ArgumentError('El nombre de destino no es válido.');
    }
    final temp = await Directory(parent).createTemp('.aurora-video-');
    try {
      if (_cancelled.contains(jobId)) throw StateError('Descarga cancelada.');
      if (_isAndroid) {
        if (onProgress != null) _progress[jobId] = onProgress;
        await _native('downloadVideo', {
          'target': target,
          'directory': temp.path,
          'jobId': jobId,
        });
      } else {
        await _run(
          [
            '--no-playlist',
            '-f',
            'best[ext=mp4][vcodec!=none][acodec!=none]/best[vcodec!=none][acodec!=none]',
            '--max-filesize',
            '512M',
            '--newline',
            '--progress-template',
            'download:AURORA_PROGRESS:%(progress._percent_str)s',
            '-o',
            p.join(temp.path, 'video.%(ext)s'),
            '--',
            target,
          ],
          jobId: jobId,
          onProgress: onProgress,
        );
      }
      final outputs = await temp
          .list(followLinks: false)
          .where(
            (entry) =>
                entry is File &&
                RegExp(
                  r'^video\.(mp4|webm|mkv|mov|m4v|avi|flv|3gp|ogv)$',
                  caseSensitive: false,
                ).hasMatch(p.basename(entry.path)),
          )
          .cast<File>()
          .toList();
      if (outputs.length != 1 ||
          await outputs.single.length() == 0 ||
          await outputs.single.length() > _maxAudioFileBytes) {
        throw StateError('La descarga no produjo un archivo de video válido.');
      }
      if (_cancelled.contains(jobId)) throw StateError('Descarga cancelada.');
      final finalFile = File(
        p.join(parent, '$baseName${p.extension(outputs.single.path)}'),
      );
      if (await FileSystemEntity.type(finalFile.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw StateError('El archivo de destino ya existe.');
      }
      await outputs.single.rename(finalFile.path);
      onProgress?.call(1);
    } finally {
      _progress.remove(jobId);
      _cancelled.remove(jobId);
      if (await temp.exists()) await temp.delete(recursive: true);
    }
  }

  @override
  Future<void> cancel(String jobId) async {
    if (jobId == 'resolve:$_progressiveVideoId') await _closeProgressive();
    if (_isAndroid) {
      if (jobId.startsWith('resolve:')) {
        _resolveCancellation++;
        final videoId = jobId.substring('resolve:'.length);
        final activeIds = (_resolveJobs[videoId] ?? const <String>{}).toList();
        _cancelled.addAll(activeIds);
        for (final activeId in activeIds) {
          await _channel.invokeMethod('cancel', {'jobId': activeId});
        }
      } else {
        _cancelled.add(jobId);
        await _channel.invokeMethod('cancel', {'jobId': jobId});
      }
      return;
    }
    if (jobId.startsWith('resolve:')) {
      final videoId = jobId.substring('resolve:'.length);
      for (final activeId in _resolveJobs[videoId] ?? const <String>{}) {
        if (_jobs[activeId] == null && !_startingJobs.contains(activeId)) {
          continue;
        }
        _cancelled.add(activeId);
        final process = _jobs[activeId];
        if (process != null) await _killTree(process);
      }
      return;
    }
    _cancelled.add(jobId);
    final process = _jobs[jobId];
    if (process != null) {
      await _killTree(process);
    }
  }

  @override
  Future<String> diagnose() async {
    if (_isAndroid) {
      return _native('diagnose', {});
    }
    final version = await _run(['--version']);
    return 'yt-dlp ${version.trim()} · ${toolDirectory ?? "Sin configurar"}';
  }

  @override
  void dispose() {
    _disposed = true;
    _firstUpdate?.cancel();
    _updateTimer?.cancel();
    unawaited(_closeProgressive().catchError((Object _) {}));
    if (_isAndroid) {
      for (final jobId in _startingJobs.toList()) {
        _cancelled.add(jobId);
        unawaited(
          _channel
              .invokeMethod<void>('cancel', {'jobId': jobId})
              .catchError((Object _) {}),
        );
      }
    }
    for (final process in _jobs.values) {
      unawaited(_killTree(process));
    }
    _jobs.clear();
    _resolveJobs.clear();
    _startingJobs.clear();
    _progress.clear();
    _channel.setMethodCallHandler(null);
  }
}
