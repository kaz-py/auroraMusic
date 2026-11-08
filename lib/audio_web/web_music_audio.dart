import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/audio_backend.dart';
import '../audio/eq_model.dart';
import '../core/models.dart';
import '../youtube_music/youtube_music_ad_blocker.dart';
import 'web_music_bridge.dart';

export 'web_music_bridge.dart' show WebMusicBridge, NativeWebMusicBridge;

/// Plays YouTube tracks through the official music.youtube.com player in an
/// invisible WebView. Aurora's Track supplies metadata; the page's media
/// element supplies state, progress and completion.
class WebMusicAudio extends AudioBackend {
  WebMusicAudio({
    WebMusicBridge? bridge,
    this.pollInterval = const Duration(milliseconds: 500),
    this.mediaWaitTimeout = const Duration(seconds: 30),
    this.playTimeout = const Duration(seconds: 20),
  }) : _bridge = bridge ?? NativeWebMusicBridge();

  final WebMusicBridge _bridge;
  final Duration pollInterval;
  final Duration mediaWaitTimeout;

  /// How long the page waits for `playing`/`timeupdate` after play().
  final Duration playTimeout;
  final _spectrum = ValueNotifier<List<double>>(const []);
  final _completed = StreamController<void>.broadcast();
  Timer? _timer;
  Widget? _view;
  Uri? _target;
  DateTime? _waitingSince;
  int _generation = 0;
  bool _disposed = false, _released = false, _sampling = false;
  bool _ended = false, _failed = false;
  bool _playIntent = false, _playing = false, _buffering = false;

  /// The site needs the user (consent, sign-in, verification, gesture).
  bool needsWebsiteAccess = false;

  /// Shown on demand so the user can resolve [needsWebsiteAccess].
  bool showingWebsite = false;
  @override
  bool adPlaying = false;
  Duration _position = Duration.zero, _duration = Duration.zero;
  Duration _pendingSeek = Duration.zero;
  double _volume = 0.8;
  Future<void> _operations = Future.value();
  Future<void>? _initialization;

  @override
  bool get supportsEqualizer => false;
  @override
  bool get supportsVisualization => false;
  @override
  String? lastError;
  @override
  bool get isPlaying => _playing;
  @override
  bool get isBuffering => _buffering;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  double get volume => _volume;
  @override
  ValueListenable<List<double>> get spectrum => _spectrum;
  @override
  Stream<void> get completed => _completed.stream;

  YouTubeMusicAdBlocker? get adBlocker => _bridge.adBlocker;

  static Uri validateInput(String input) {
    final uri = Uri.tryParse(input);
    final id = uri?.queryParameters['v'];
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'music.youtube.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.path != '/watch' ||
        uri.fragment.isNotEmpty ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['v']?.length != 1 ||
        id == null ||
        !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      throw ArgumentError('Se requiere un enlace oficial de canción válido.');
    }
    return Uri.https('music.youtube.com', '/watch', {'v': id});
  }

  /// Mount exactly once, persistently, in the app shell. Hidden it is a 1×1
  /// covered host (still rendering, so media keeps playing) without pointer,
  /// focus or semantics. Visible only while [showingWebsite]. Never reparent.
  Widget buildEngineView() {
    if (_released) return const SizedBox.shrink();
    final visible = showingWebsite;
    return SizedBox(
      width: visible ? double.infinity : 1,
      height: visible ? double.infinity : 1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeFocus(
            excluding: !visible,
            child: ExcludeSemantics(
              excluding: !visible,
              child: IgnorePointer(
                ignoring: !visible,
                child: _view ??= _bridge.buildView(),
              ),
            ),
          ),
          if (!visible)
            const Positioned.fill(child: ColoredBox(color: Color(0xff000000))),
        ],
      ),
    );
  }

  void setWebsiteVisible(bool visible) {
    if (_disposed || showingWebsite == visible) return;
    showingWebsite = visible;
    notifyListeners();
  }

  @override
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _bridge.onFailure = (message, siteAction) =>
        _failure(message, siteAction: siteAction);
    _bridge.onNavigation = (uri) {
      if (uri != null && uri.host != 'music.youtube.com' && _target != null) {
        _accessRequired();
      }
    };
    await _bridge.initialize();
    if (_disposed) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  void _accessRequired() => _failure(
    'YouTube Music necesita una confirmación (consentimiento, inicio de '
    'sesión o verificación). Pulsa «Revisar sitio» para resolverla.',
    siteAction: true,
  );

  void _failure(String message, {bool siteAction = false}) {
    if (_disposed) return;
    lastError = message;
    _failed = true;
    needsWebsiteAccess = needsWebsiteAccess || siteAction;
    _playIntent = false;
    _playing = _buffering = false;
    notifyListeners();
  }

  @override
  Future<void> load(
    ResolvedAudio source, {
    Duration start = Duration.zero,
  }) async {
    final target = validateInput(source.input);
    if (source.headers.isNotEmpty) {
      throw ArgumentError('La sesión permanece dentro del sitio oficial.');
    }
    ++_generation;
    _target = target;
    _playIntent = _playing = _ended = _failed = adPlaying = false;
    _buffering = true;
    needsWebsiteAccess = false;
    lastError = null;
    _position = start;
    _duration = source.duration;
    _pendingSeek = start;
    _waitingSince = DateTime.now();
    notifyListeners();
    final generation = _generation;
    try {
      await _bridge.navigate(target);
    } catch (_) {
      if (generation == _generation) {
        _failure('No se pudo abrir la canción en YouTube Music.');
      }
      rethrow;
    }
  }

  /// Serialized; results of an older generation (track) are discarded.
  Future<void> _command(String action, [double? value]) {
    final generation = _generation;
    final target = _target;
    final result = _operations.then((_) async {
      if (_disposed || target == null || generation != _generation) return;
      try {
        final snapshot = await _bridge
            .command(
              action,
              videoId: target.queryParameters['v']!,
              generation: generation,
              value: value,
              timeout: playTimeout,
            )
            .timeout(playTimeout + const Duration(seconds: 5));
        if (!_disposed && generation == _generation) _receive(snapshot);
      } catch (_) {
        if (!_disposed && generation == _generation) {
          _failure(
            'YouTube Music no respondió. Pulsa reproducir para reintentar.',
          );
        }
      }
    });
    _operations = result.catchError((Object _) {});
    return result;
  }

  /// Samples actual page media state; also a deterministic fake-bridge test seam.
  Future<void> refresh() async {
    if (_disposed || _target == null || _sampling) return;
    _sampling = true;
    try {
      await _command('snapshot');
    } finally {
      _sampling = false;
    }
  }

  void _receive(Map<String, dynamic>? data) {
    if (data == null || data['status'] == 'waiting') {
      if (_waitingSince != null &&
          DateTime.now().difference(_waitingSince!) > mediaWaitTimeout) {
        _failure(
          'YouTube Music no presentó audio a tiempo. Pulsa reproducir para '
          'reintentar.',
        );
      }
      return;
    }
    final name = data['errorName'];
    final detail = name is String && RegExp(r'^[A-Za-z]{1,40}$').hasMatch(name)
        ? ' (${data['action']}: $name)'
        : '';
    switch (data['status']) {
      case 'website':
        _accessRequired();
        return;
      case 'differentTrack':
        // During initial navigation the previous document may still be active.
        if (_waitingSince != null || _failed) return;
        _failure(
          'YouTube Music cambió de canción. Elige una canción en Aurora.',
        );
        unawaited(_command('pause'));
        return;
      case 'playBlocked':
        _failure(
          'YouTube Music pidió una interacción para reproducir$detail. '
          'Pulsa «Revisar sitio».',
          siteAction: true,
        );
        return;
      case 'playTimeout':
        _failure(
          'YouTube Music no empezó a reproducir a tiempo$detail. Pulsa '
          'reproducir para reintentar.',
        );
        return;
      case 'seekUnavailable':
        lastError = 'No se puede adelantar durante un anuncio.';
        notifyListeners();
        return;
      case 'commandFailed':
        _failure('El sitio no pudo aplicar ese control$detail.');
        return;
    }
    if (data['generation'] != _generation ||
        data['videoId'] != _target?.queryParameters['v']) {
      return;
    }
    _waitingSince = null;
    if (data['mediaError'] is num && data['mediaError'] != 0) {
      _failure(
        'YouTube Music no pudo reproducir esta canción '
        '(error ${data['mediaError']}).',
      );
      return;
    }
    adPlaying = data['adPlaying'] == true;
    _playing = data['playing'] == true;
    _buffering = data['buffering'] == true;
    if (_playing && !_failed && lastError != null) lastError = null;
    if (_playing && !_playIntent && !adPlaying && !_failed) {
      // The site autoplays on navigation; Aurora's controls own play intent.
      unawaited(_command('pause'));
    }
    if (!adPlaying) {
      _position = _seconds(data['position']);
      final duration = _seconds(data['duration']);
      if (duration > Duration.zero) _duration = duration;
      if (data['ended'] == true && !_ended) {
        _ended = true;
        // The ended snapshot carries a stale position.
        if (_duration > Duration.zero) _position = _duration;
        _playIntent = _playing = _buffering = false;
        _completed.add(null);
      }
    }
    notifyListeners();
  }

  static Duration _seconds(Object? value) => value is num && value.isFinite
      ? Duration(milliseconds: (value.clamp(0, 864000) * 1000).round())
      : Duration.zero;

  bool _stale(int generation) =>
      generation != _generation || _disposed || !_playIntent || _failed;

  @override
  Future<void> play() async {
    if (_target == null || _disposed) {
      throw StateError('Selecciona una canción.');
    }
    final generation = _generation;
    _playIntent = true;
    _ended = _failed = false;
    needsWebsiteAccess = false;
    lastError = null;
    final deadline = DateTime.now().add(mediaWaitTimeout);
    while (_waitingSince != null &&
        !_stale(generation) &&
        DateTime.now().isBefore(deadline)) {
      await _command('snapshot');
      if (_waitingSince != null && !_stale(generation)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
    if (_waitingSince != null && !_stale(generation)) {
      _failure(
        'YouTube Music no presentó audio a tiempo. Pulsa reproducir para '
        'reintentar.',
      );
    }
    if (!_stale(generation)) await _command('volume', _volume);
    if (!_stale(generation) && _pendingSeek > Duration.zero) {
      final pending = _pendingSeek;
      _pendingSeek = Duration.zero;
      await seek(pending);
    }
    if (!_stale(generation)) await _command('play');
    if (generation == _generation && !_disposed && _failed) {
      throw StateError(lastError ?? 'YouTube Music no pudo reproducir.');
    }
  }

  @override
  Future<void> pause() {
    _playIntent = false;
    return _command('pause');
  }

  /// Pauses and forgets the track; the page stays loaded for the next one.
  @override
  Future<void> stop() async {
    final generation = _generation;
    _playIntent = false;
    await _command('pause');
    if (generation != _generation || _disposed) return;
    ++_generation;
    _target = null;
    _playing = _buffering = adPlaying = false;
    _position = _duration = Duration.zero;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) =>
      _command('seek', position.inMilliseconds.clamp(0, 864000000) / 1000);

  @override
  void setVolume(double volume) {
    if (!volume.isFinite) return;
    _volume = volume.clamp(0, 1);
    unawaited(_command('volume', _volume));
    if (!_disposed) notifyListeners();
  }

  @override
  void setEqualizer(
    bool enabled,
    List<EqBand> bands, {
    bool autoPreamp = true,
  }) {}
  @override
  void setVisualizationEnabled(bool enabled) {}

  /// Unmounts the WebView, then releases its native environment (Windows exit).
  Future<void> shutdown() async {
    if (_released || _disposed) return;
    _timer?.cancel();
    _released = true;
    notifyListeners();
    await WidgetsBinding.instance.endOfFrame;
    _bridge.dispose();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _timer?.cancel();
    final target = _target;
    if (target != null && !_released) {
      unawaited(
        _bridge
            .command(
              'pause',
              videoId: target.queryParameters['v']!,
              generation: _generation,
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
    }
    _disposed = true;
    ++_generation;
    if (!_released) _bridge.dispose();
    _spectrum.dispose();
    unawaited(_completed.close());
    super.dispose();
  }
}
