import 'dart:io';

import '../bridge/api/lyrics_align.dart' as rust;
import '../core/models.dart';
import 'lyrics_service.dart';

typedef LyricsAlignFn =
    Future<rust.LyricsAlignment> Function({
      required String modelPath,
      required String input,
      required List<rust.AlignHeader> headers,
      required List<rust.AlignLine> lines,
      required int scanSecs,
      String? language,
    });

/// Mide cuándo suena cada línea de la letra en el audio real (Whisper, local) y
/// guarda la corrección de la pista. Corre una vez por canción y en segundo
/// plano; si no hay un resultado fiable, la letra queda como estaba.
///
/// - Letra **sin tiempos**: pone hora a cada línea (saltándose la introducción
///   y los pasajes instrumentales) en vez de repartirlas a partes iguales.
/// - Letra **sincronizada**: corrige su desplazamiento (p. ej. un vídeo con una
///   introducción que la versión de estudio no tiene).
class LyricsAutoSync {
  LyricsAutoSync(
    this.service, {
    required this.available,
    required this.modelPath,
    LyricsAlignFn? align,
  }) : _align = align ?? rust.lyricsAlign;

  final LyricsService service;

  /// Función (no valor) porque cambia: modelo descargado, interruptor…
  final bool Function() available;
  final String Function() modelPath;
  final LyricsAlignFn _align;

  final _running = <String>{};

  /// Segundos de audio que se analizan: con tiempos basta el principio (se
  /// busca un desplazamiento); sin tiempos hace falta toda la canción.
  static const scanSyncedSecs = 90;
  static const scanPlainSecs = 300;

  /// Una desviación menor que esto es ruido de medida.
  static const minShiftMs = 400;

  /// `true` si se guardó una corrección nueva: hay que volver a pedir
  /// [LyricsService.adjusted] con la letra sin ajustar.
  Future<bool> run(
    Track track,
    LyricsResult raw,
    ResolvedAudio? audio,
    Directory root,
  ) async {
    final synced = raw.kind == LyricsKind.synced;
    if (!synced && raw.kind != LyricsKind.plain) return false;
    final lines = synced
        ? [
            for (final l in raw.lines)
              rust.AlignLine(text: l.text, atMs: l.at.inMilliseconds),
          ]
        : [
            for (final row in LyricsService.plainRows(raw.text))
              rust.AlignLine(text: row),
          ];
    if (lines.length < 3 || audio == null || !available()) return false;
    if (!_running.add(track.id)) return false;
    try {
      final known = await service.readAdjust(track, root);
      if (known != null && known.settled) return false;
      final result = await _align(
        modelPath: modelPath(),
        input: audio.input,
        headers: [
          for (final h in audio.headers.entries)
            rust.AlignHeader(name: h.key, value: h.value),
        ],
        lines: lines,
        scanSecs: synced ? scanSyncedSecs : scanPlainSecs,
      );
      if (!result.found) {
        // Se pudo medir y no hubo nada fiable: no se vuelve a intentar.
        await service.writeAdjust(
          track,
          root,
          LyricsAdjust(
            source: known?.source ?? 'tried',
            shiftMs: known?.shiftMs,
            tried: true,
          ),
        );
        return false;
      }
      final starts = [for (final s in result.startsMs) s.toInt()];
      final shift = result.shiftMs?.toInt();
      final negligible =
          synced &&
          shift != null &&
          shift.abs() < minShiftMs &&
          _flat(starts, raw);
      await service.writeAdjust(
        track,
        root,
        LyricsAdjust(
          source: 'audio',
          shiftMs: negligible ? 0 : shift,
          startsMs: negligible ? null : starts,
        ),
      );
      return !negligible || (known?.shiftMs ?? 0) != 0;
    } catch (_) {
      // Sin red, formato raro, modelo dañado…: la letra sigue como estaba y se
      // puede reintentar.
      return false;
    } finally {
      _running.remove(track.id);
    }
  }

  /// Los tiempos medidos no se apartan de los de la letra más que el ruido.
  static bool _flat(List<int> starts, LyricsResult raw) {
    if (starts.length != raw.lines.length) return false;
    for (var i = 0; i < starts.length; i++) {
      if ((starts[i] - raw.lines[i].at.inMilliseconds).abs() >= minShiftMs) {
        return false;
      }
    }
    return true;
  }
}
