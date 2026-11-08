import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurora_music/audio/eq_dsp.dart';
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

  group('ParametricEqualizer', () {
    test('disabled EQ leaves the audio bit-identical', () {
      final eq = ParametricEqualizer();
      eq.configure(enabled: false, bands: bandsWith({4: EqBand(1000, 12)}));
      final pcm = sine(440, 0.99, 4800);
      final copy = Float32List.fromList(pcm);
      eq.process(pcm);
      expect(pcm, copy);
    });

    test('a boost raises the level by its gain once the ramp has settled', () {
      final eq = ParametricEqualizer();
      eq.configure(
        enabled: true,
        bands: bandsWith({4: EqBand(1000, 6, 1)}),
        autoPreamp: false,
      );
      final pcm = sine(1000, 0.2, 48000);
      eq.process(pcm);
      final settled = rms(pcm, from: 48000, to: 96000);
      final dry = rms(sine(1000, 0.2, 24000));
      expect(settled / dry, closeTo(math.pow(10, 6 / 20), 0.06));
    });

    test('auto preamp keeps a peak boost from raising the peak level', () {
      final eq = ParametricEqualizer();
      eq.configure(enabled: true, bands: bandsWith({4: EqBand(1000, 9, 1)}));
      final pcm = sine(1000, 0.5, 48000);
      eq.process(pcm);
      expect(
        rms(pcm, from: 48000) / rms(sine(1000, 0.5, 1000)),
        closeTo(1, 0.05),
      );
    });

    test('gain changes ramp: no instant jump and no discontinuity', () {
      final eq = ParametricEqualizer();
      eq.configure(enabled: true, bands: eqFlatBands(), autoPreamp: false);
      eq.process(sine(1000, 0.2, 4800));
      eq.configure(
        enabled: true,
        bands: bandsWith({4: EqBand(1000, 12, 1)}),
        autoPreamp: false,
      );
      final pcm = sine(1000, 0.2, 24000);
      final input = Float32List.fromList(pcm);
      eq.process(pcm);
      // First 0.7 ms barely moved, then it reaches +12 dB (x3.98).
      final first = rms(pcm, to: 128) / rms(input, to: 128);
      final last =
          rms(pcm, from: 24000, to: 48000) / rms(input, from: 24000, to: 48000);
      expect(first, lessThan(1.3));
      expect(last, closeTo(3.98, 0.25));
      // A hard switch would add a step; the ramp stays within the sine slope.
      expect(maxStep(pcm), lessThan(maxStep(input) * 4.3));
    });

    test('enabling and bypassing crossfade instead of clicking', () {
      final eq = ParametricEqualizer();
      final bands = bandsWith({4: EqBand(1000, 12, 1)});
      eq.configure(enabled: false, bands: bands, autoPreamp: false);
      eq.configure(enabled: true, bands: bands, autoPreamp: false);
      final pcm = sine(1000, 0.2, 24000);
      final input = Float32List.fromList(pcm);
      eq.process(pcm);
      expect(rms(pcm, to: 128) / rms(input, to: 128), lessThan(1.3));
      expect(maxStep(pcm), lessThan(maxStep(input) * 4.3));
      // Bypass back: converges to the dry signal and then goes idle.
      eq.configure(enabled: false, bands: bands, autoPreamp: false);
      final again = sine(1000, 0.2, 48000);
      eq.process(again);
      expect(eq.isIdle, isTrue);
      final tail = Float32List.fromList(again.sublist(80000));
      expect(rms(tail), closeTo(rms(sine(1000, 0.2, 4000)), 1e-3));
    });

    test('NaN, Infinity and absurd samples never reach the output', () {
      final eq = ParametricEqualizer();
      eq.configure(
        enabled: true,
        bands: bandsWith({3: EqBand(600, 12, 10)}),
        autoPreamp: false,
      );
      final pcm = sine(600, 0.5, 4800);
      pcm[10] = double.nan;
      pcm[11] = double.infinity;
      pcm[12] = double.negativeInfinity;
      pcm[100] = 1e30;
      pcm[101] = -1e30;
      eq.process(pcm);
      expect(pcm.every((v) => v.isFinite && v.abs() <= 1), isTrue);
    });

    test(
      'extreme settings changed at random stay finite and below full scale',
      () {
        final eq = ParametricEqualizer();
        final random = math.Random(7);
        final noise = Float32List(2 * 480);
        for (var round = 0; round < 200; round++) {
          eq.configure(
            enabled: random.nextBool() || round > 150,
            autoPreamp: random.nextBool(),
            bands: [
              for (var i = 0; i < eqBandCount; i++)
                EqBand(
                  20 + random.nextDouble() * 19980,
                  random.nextBool() ? eqMaxDb : eqMinDb * random.nextDouble(),
                  random.nextBool() ? eqMaxQ : eqMinQ,
                ),
            ],
          );
          for (var i = 0; i < noise.length; i++) {
            noise[i] = (random.nextDouble() * 2 - 1);
          }
          eq.process(noise);
          expect(noise.every((v) => v.isFinite && v.abs() <= 1), isTrue);
        }
      },
    );

    test('a hot signal with a full boost never exceeds full scale', () {
      final eq = ParametricEqualizer();
      eq.configure(
        enabled: true,
        bands: bandsWith({4: EqBand(1000, 12, 1)}),
        autoPreamp: false,
      );
      final pcm = sine(1000, 0.99, 48000);
      eq.process(pcm);
      final tail = pcm.sublist(48000);
      final peak = tail.map((v) => v.abs()).reduce(math.max);
      expect(peak, lessThanOrEqualTo(1));
      expect(peak, greaterThan(0.95));
    });
  });
}
