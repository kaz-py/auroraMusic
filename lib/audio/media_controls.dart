import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_service_win/audio_service_win.dart';
import 'package:audio_session/audio_session.dart';

import '../core/audio_backend.dart';
import '../core/models.dart';

class MediaControls {
  MediaControls({
    required this.audio,
    required this.onPlay,
    required this.onPause,
    required this.onStop,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
  });
  final AudioBackend audio;
  final Future<void> Function() onPlay, onPause, onStop, onNext, onPrevious;
  final Future<void> Function(Duration) onSeek;
  _MediaHandler? _handler;
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  bool _resumeAfterInterruption = false;

  Future<void> initialize() async {
    if (Platform.isWindows) AudioServiceWin.registerWith();
    _handler = await AudioService.init<_MediaHandler>(
      builder: () => _MediaHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'aurora.music.playback',
        androidNotificationChannelName: 'Reproducción de música',
        androidNotificationOngoing: true,
      ),
    );
    audio.addListener(_publish);
    _publish();
    if (Platform.isAndroid || Platform.isIOS) {
      _session = await AudioSession.instance;
      await _session!.configure(const AudioSessionConfiguration.music());
      _interruptions = _session!.interruptionEventStream.listen((event) async {
        if (event.begin) {
          _resumeAfterInterruption = audio.isPlaying;
          await onPause();
        } else {
          if (_resumeAfterInterruption &&
              event.type != AudioInterruptionType.unknown) {
            await onPlay();
          }
          _resumeAfterInterruption = false;
        }
      });
      _noisy = _session!.becomingNoisyEventStream.listen((_) {
        _resumeAfterInterruption = false;
        unawaited(onPause());
      });
    }
  }

  Future<bool> activate() async => await _session?.setActive(true) ?? true;

  void updateTrack(Track? track) {
    _handler?.mediaItem.add(
      track == null
          ? null
          : MediaItem(
              id: track.id,
              title: track.title,
              artist: track.artist,
              album: track.album,
              duration: track.duration,
              artUri: _artUri(track.artworkUrl),
            ),
    );
    _publish();
  }

  // SMTC en Windows solo lee rutas locales como file:///; una ruta cruda falla.
  static Uri? _artUri(String? art) {
    if (art == null || art.isEmpty) return null;
    if (Platform.isWindows && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(art)) {
      return Uri.file(art);
    }
    return Uri.tryParse(art);
  }

  String? _sentKey;
  Duration _sentPosition = Duration.zero;
  final Stopwatch _sinceSent = Stopwatch();

  // `audio` avisa 5 veces por segundo (también en pausa) y cada envío cruza el
  // canal de plataforma: se publica solo si cambia el estado, si la posición
  // salta (búsqueda, pista nueva) o, sonando, como mucho una vez por segundo.
  void _publish() {
    final processing = audio.lastError != null
        ? AudioProcessingState.error
        : audio.isBuffering
        ? AudioProcessingState.buffering
        : _handler?.mediaItem.value == null
        ? AudioProcessingState.idle
        : AudioProcessingState.ready;
    final key = '${audio.isPlaying}|$processing|${audio.lastError}';
    final elapsed = _sinceSent.elapsed;
    final expected = _sentPosition + (audio.isPlaying ? elapsed : Duration.zero);
    final jumped = (audio.position - expected).abs() > const Duration(seconds: 2);
    final due = audio.isPlaying && elapsed >= const Duration(seconds: 1);
    if (key == _sentKey && !jumped && !due) return;
    _sentKey = key;
    _sentPosition = audio.position;
    _sinceSent
      ..reset()
      ..start();
    _handler?.playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          audio.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: audio.isPlaying,
        updatePosition: audio.position,
        errorCode: audio.lastError == null ? null : 1,
        errorMessage: audio.lastError,
      ),
    );
  }

  Future<void> dispose() async {
    audio.removeListener(_publish);
    await _handler?.seekForward(false);
    await _interruptions?.cancel();
    await _noisy?.cancel();
    await _session?.setActive(false);
    _handler?.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
  }
}

class _MediaHandler extends BaseAudioHandler with SeekHandler {
  _MediaHandler(this.controls);
  final MediaControls controls;
  @override
  Future<void> play() async {
    if (await controls.activate()) await controls.onPlay();
  }

  @override
  Future<void> pause() => controls.onPause();
  @override
  Future<void> stop() async {
    await seekForward(false);
    await controls.onStop();
  }

  @override
  Future<void> skipToNext() => controls.onNext();
  @override
  Future<void> skipToPrevious() => controls.onPrevious();
  @override
  Future<void> seek(Duration position) => controls.onSeek(position);
}
