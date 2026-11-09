import 'dart:io';

import '../bridge/api/lyrics_align.dart' as rust;
import '../core/models.dart';
import 'lyrics_service.dart';

/// Mide cuánto se desvía la letra respecto al audio real y fija el desfase de
/// la pista. Corre una vez por canción y en segundo plano; nunca pisa un ajuste
/// hecho a mano y, si no hay un resultado fiable, la letra queda como estaba.
class LyricsAutoSync {
  LyricsAutoSync(
    this.service, {
    required this.available,
    required this.libraryPath,
    required this.modelPath,
    Future<rust.LyricsAlignment> Function({
      required String libPath,
      required String modelDir,
      required String input,
      required List<rust.AlignHeader> headers,
      required List<rust.AlignLine> lines,
    })?
    align,
  }) : _align = align ?? rust.lyricsAlign;

  final LyricsService service;

  /// Función (no valor) porque cambia: modelo descargado, interruptor…
  final bool Function() available;
  final String? Function() libraryPath;
  final String Function() modelPath;
  final Future<rust.LyricsAlignment> Function({
    required String libPath,
    required String modelDir,
    required String input,
    required List<rust.AlignHeader> headers,
    required List<rust.AlignLine> lines,
  })
  _align;

  final _running = <String>{};

  /// Líneas que se usan como anclas.
  static const maxLines = 12;

  /// Una desviación menor que esto es ruido de medida.
  static const minShiftMs = 400;

  /// Devuelve el desfase efectivo nuevo (ms) si cambió; `null` si no hubo nada
  /// que hacer o no se pudo medir.
  Future<int?> run(
    Track track,
    LyricsResult result,
    ResolvedAudio? audio,
    Directory root,
  ) async {
    if (result.kind != LyricsKind.synced || result.lines.length < 2) {
      return null;
    }
    if (audio == null || audio.engine != AudioEngine.native) return null;
    if (!available()) return null;
    final library = libraryPath();
    if (library == null) return null;
    if (!_running.add(track.id)) return null;
    try {
      if (await service.hasUserOffset(track, root)) return null;
      final known = await service.readAutoOffset(track, root);
      if (known != null &&
          (known.source == 'audio' || known.source == 'tried')) {
        return null;
      }
      final alignment = await _align(
        libPath: library,
        modelDir: modelPath(),
        input: audio.input,
        headers: [
          for (final h in audio.headers.entries)
            rust.AlignHeader(name: h.key, value: h.value),
        ],
        lines: [
          for (final line in result.lines.take(maxLines))
            rust.AlignLine(text: line.text, atMs: line.at.inMilliseconds),
        ],
      );
      // Se pudo medir (con o sin resultado): no se vuelve a intentar con esta pista.
      if (!alignment.found) {
        await service.writeAutoOffset(track, root, known?.ms ?? 0, 'tried');
        return null;
      }
      final shift = alignment.shiftMs.toInt();
      // El audio va `shift` por detrás de la letra: la letra debe salir más tarde.
      final offset = shift.abs() < minShiftMs ? 0 : -shift;
      // Si el usuario ajustó mientras se medía, manda lo suyo.
      if (await service.hasUserOffset(track, root)) return null;
      await service.writeAutoOffset(track, root, offset, 'audio');
      return offset == (known?.ms ?? 0) ? null : offset;
    } catch (_) {
      // Sin red, formato raro, modelo dañado…: la letra sigue como estaba.
      return null;
    } finally {
      _running.remove(track.id);
    }
  }
}
