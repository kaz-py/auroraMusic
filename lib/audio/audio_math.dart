import 'dart:math' as math;

import '../bridge/api/audio.dart' as rust;

double equalizerGain(double db) =>
    math.pow(10, db.clamp(-12, 12) / 20).toDouble();

double equalizerPreamp(List<double> gainsDb) {
  final boost = gainsDb.take(8).fold(0.0, (peak, gain) => math.max(peak, gain));
  return boost > 0 ? 0.9 / equalizerGain(boost) : 1;
}

/// Input-scoped network options; Schannel checks the Windows certificate store.
/// Loopback http (AudioProxy) gets the timeout/reconnect options without TLS.
List<String> ffmpegHttpsOptions(String input) {
  final uri = Uri.tryParse(input);
  final https = uri?.scheme == 'https';
  if (!https && !(uri?.scheme == 'http' && uri?.host == '127.0.0.1')) {
    return const [];
  }
  return [
    if (https) ...['-tls_verify', '1'],
    '-rw_timeout',
    '15000000',
    // Survive dropped connections while streaming instead of ending early.
    '-reconnect',
    '1',
    '-reconnect_streamed',
    '1',
    '-reconnect_delay_max',
    '5',
  ];
}

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
