import '../bridge/api/audio.dart' as rust;

String redactAudioError(Object error) => '$error'
    .replaceAll(RegExp(r'https?://[^\s<>"\x27]+'), '[recurso remoto]')
    .replaceAll(
      RegExp(r'(authorization|cookie):[^\r\n]+', caseSensitive: false),
      '[cabecera privada]',
    );

bool isCompleteAudioStream({
  required bool isPlaying,
  required bool isBuffering,
  required bool cleanEof,
  required Duration decoded,
  required Duration consumed,
  required Duration expected,
}) => rust.audioIsCompleteStream(
  isPlaying: isPlaying,
  isBuffering: isBuffering,
  cleanEof: cleanEof,
  decodedUs: decoded.inMicroseconds,
  consumedUs: consumed.inMicroseconds,
  expectedUs: expected.inMicroseconds,
);

bool shouldResumeAfterSeek({
  required int request,
  required int latestRequest,
  required bool playIntent,
}) => request == latestRequest && playIntent;

/// Log-frequency display bars from the native mixer's first 256 FFT bins.
List<double> spectrumBars(List<double> fft) => rust.audioSpectrumBars(fft: fft);
