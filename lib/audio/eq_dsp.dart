import 'dart:typed_data';

import '../bridge/api/audio.dart' as rust;
import 'eq_model.dart';

/// Ecualizador paramétrico estéreo de 8 bandas peaking (RBJ) sobre PCM float32
/// entrelazado. El filtrado y las rampas viven en `rust/crates/aurora_audio`;
/// aquí quedan la API y el cálculo del preamp (que usa la curva de `eq_model`).
///
/// Todo cambio (ganancia, frecuencia, Q, activación, preamp) se acerca al
/// objetivo con una rampa exponencial de ~[timeConstantMs] ms, para que mover
/// un deslizador no produzca clics ni saltos de volumen. Con el EQ apagado y la
/// rampa terminada, [process] no toca el audio.
class ParametricEqualizer {
  ParametricEqualizer({
    this.sampleRate = eqSampleRate,
    this.channels = 2,
    double timeConstantMs = 12,
  }) : _engine = rust.Equalizer.create(
         sampleRate: sampleRate,
         channels: channels,
         timeConstantMs: timeConstantMs,
       );

  final double sampleRate;
  final int channels;
  final rust.Equalizer _engine;

  /// El EQ no modifica el audio y no hay rampa pendiente.
  bool get isIdle => _engine.isIdle();

  void configure({
    required bool enabled,
    required List<EqBand> bands,
    bool autoPreamp = true,
  }) {
    final active = [
      for (var i = 0; i < eqBandCount; i++)
        if (i < bands.length) bands[i],
    ];
    _engine.configure(
      enabled: enabled,
      bands: [
        for (final b in bands.take(eqBandCount))
          rust.EqBandParams(frequency: b.frequency, gainDb: b.gainDb, q: b.q),
      ],
      targetPreamp: enabled && autoPreamp ? eqAutoPreamp(active) : 1,
    );
  }

  /// Procesa [pcm] en el sitio. Muestras no finitas se tratan como silencio.
  void process(Float32List pcm) {
    if (isIdle) return;
    pcm.setAll(0, _engine.process(pcm: pcm));
  }
}
