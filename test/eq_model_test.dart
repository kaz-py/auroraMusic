import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurora_music/audio/eq_model.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List sine(double hz, double amp, int frames) {
  final out = Float32List(frames * 2);
  for (var n = 0; n < frames; n++) {
    final v = amp * math.sin(2 * math.pi * hz * n / 48000);
    out[2 * n] = v;
    out[2 * n + 1] = v;
  }
  return out;
}

double rms(Float32List pcm, {int from = 0, int? to}) {
  final end = to ?? pcm.length;
  var sum = 0.0;
  for (var i = from; i < end; i += 2) {
    sum += pcm[i] * pcm[i];
  }
  return math.sqrt(sum / ((end - from) / 2));
}

double maxStep(Float32List pcm) {
  var m = 0.0;
  for (var i = 2; i < pcm.length; i += 2) {
    m = math.max(m, (pcm[i] - pcm[i - 2]).abs());
  }
  return m;
}

List<EqBand> bandsWith(Map<int, EqBand> overrides) => [
  for (var i = 0; i < eqBandCount; i++)
    overrides[i] ?? EqBand(eqDefaultFrequencies[i]),
];

void main() {
  group('RBJ peaking biquad', () {
    test('0 dB is the identity', () {
      final c = peakingCoefficients(48000, 1000, 0, 1);
      expect(c[0], closeTo(1, 1e-12));
      expect(c[1], closeTo(c[3], 1e-12));
      expect(c[2], closeTo(c[4], 1e-12));
    });

    test('matches the RBJ cookbook values for +6 dB, 1 kHz, Q 1 at 48 kHz', () {
      final c = peakingCoefficients(48000, 1000, 6, 1);
      // Cookbook: A = 10^(6/40), w0 = 2*pi*1000/48000, alpha = sin(w0)/2.
      final a = math.pow(10, 6 / 40);
      final w0 = 2 * math.pi * 1000 / 48000;
      final alpha = math.sin(w0) / 2;
      final a0 = 1 + alpha / a;
      expect(c[0], closeTo((1 + alpha * a) / a0, 1e-12));
      expect(c[1], closeTo(-2 * math.cos(w0) / a0, 1e-12));
      expect(c[2], closeTo((1 - alpha * a) / a0, 1e-12));
      expect(c[4], closeTo((1 - alpha / a) / a0, 1e-12));
      // Numeric values pinned so a formula slip is caught.
      expect(c[0], closeTo(1.0440, 1e-3));
      expect(c[1], closeTo(-1.8954, 1e-3));
    });

    test('peak gain equals the band gain and cuts mirror boosts', () {
      for (final g in [-12.0, -3.5, 0.1, 6.0, 12.0]) {
        final c = peakingCoefficients(48000, 1000, g, 1.4);
        expect(biquadResponseDb(c, 1000, 48000), closeTo(g, 0.01));
        final mirror = peakingCoefficients(48000, 1000, -g, 1.4);
        for (final f in [40.0, 400.0, 2500.0, 9000.0]) {
          expect(
            biquadResponseDb(c, f, 48000) + biquadResponseDb(mirror, f, 48000),
            closeTo(0, 1e-6),
          );
        }
        expect(biquadResponseDb(c, 20, 48000).abs(), lessThan(g.abs()));
      }
    });

    test('higher Q is narrower', () {
      double at2k(double q) =>
          biquadResponseDb(peakingCoefficients(48000, 1000, 9, q), 2000, 48000);
      expect(at2k(8), lessThan(at2k(1)));
    });

    test(
      'poles stay inside the unit circle over the whole parameter range',
      () {
        for (final f in [20.0, 100.0, 1000.0, 10000.0, 20000.0]) {
          for (final g in [-12.0, 12.0]) {
            for (final q in [eqMinQ, 1.0, eqMaxQ]) {
              final c = peakingCoefficients(48000, f, g, q);
              expect(c.every((v) => v.isFinite), isTrue);
              expect(c[4].abs(), lessThan(1));
              expect(c[3].abs(), lessThan(1 + c[4]));
            }
          }
        }
      },
    );
  });

  group('EqBand and presets', () {
    test('bands are clamped and never NaN', () {
      final b = EqBand(5, 99, -3);
      expect(b.frequency, eqMinHz);
      expect(b.gainDb, eqMaxDb);
      expect(b.q, eqMinQ);
      final nan = EqBand(double.nan, double.infinity, double.nan);
      expect(nan.frequency.isFinite && nan.gainDb.isFinite, isTrue);
      expect(nan.q, 1);
    });

    test('auto preamp compensates the peak and is 1 for cuts', () {
      expect(eqAutoPreamp(eqFlatBands()), closeTo(1, 1e-9));
      expect(
        eqAutoPreamp(bandsWith({0: EqBand(60, -6), 4: EqBand(1000, -3)})),
        1,
      );
      final boosted = eqAutoPreamp(bandsWith({4: EqBand(1000, 6, 1)}));
      expect(boosted, closeTo(math.pow(10, -6 / 20), 0.01));
    });

    test('export and import round-trip, invalid JSON is rejected', () {
      final presets = [
        EqPreset('Mío', bandsWith({1: EqBand(200, 4.5, 2.2)})),
      ];
      final back = eqPresetsFromJson(eqPresetsToJson(presets));
      expect(back.single.name, 'Mío');
      expect(back.single.bands[1], EqBand(200, 4.5, 2.2));
      expect(back.single.bands.length, eqBandCount);
      expect(() => eqPresetsFromJson('no json'), throwsFormatException);
      expect(
        () => eqPresetsFromJson('{"presets":[{"name":""}]}'),
        throwsFormatException,
      );
      // Out-of-range imported values are clamped, never trusted.
      final wild = eqPresetsFromJson(
        '{"name":"x","bands":[{"frequency":1e9,"gainDb":-500,"q":0}]}',
      );
      expect(wild.single.bands[0].frequency, eqMaxHz);
      expect(wild.single.bands[0].gainDb, eqMinDb);
      expect(wild.single.bands[0].q, eqMinQ);
    });
  });
}
