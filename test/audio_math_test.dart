import 'package:aurora_music/audio/audio_math.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decoder errors retain HTTP status without signed URL or cookies', () {
    final error = redactAudioError(
      'HTTP 403 https://host/audio?sig=private Authorization: token\nCookie: private',
    );
    expect(error, contains('403'));
    expect(error, isNot(contains('sig=')));
    expect(error, isNot(contains('private')));
    expect(error, isNot(contains('token')));
  });
  test('FFT bars preserve silence and a measured frequency peak', () {
    expect(spectrumBars(List.filled(256, 0)), everyElement(0));
    final fft = List.filled(256, 0.0)..[128] = 1;
    final bars = spectrumBars(fft);
    expect(bars.length, 48);
    expect(bars.where((value) => value > 0).length, 1);
    expect(bars.reduce((a, b) => a > b ? a : b), 1);
    fft[128] = double.nan;
    expect(spectrumBars(fft), everyElement(0));
  });
}
