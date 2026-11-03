import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../../core/models.dart';
import '../artwork_cache.dart';
import 'cover_tone.dart';

/// Ancho al que se decodifica la portada para el fondo. Se difumina una sola
/// vez a esta resolución y luego se escala: el coste por fotograma es el de
/// pintar una textura, no el de un desenfoque.
const int kCoverDecodeWidth = 96;

/// Sigma del desenfoque en píxeles de la textura de [kCoverDecodeWidth]; escala
/// a ~28 px lógicos en un mini reproductor de ~340 px de ancho.
const double kCoverBlurSigma = 8;

/// Lado de la rejilla de muestreo para el tono (8×8 = 64 muestras).
const int kCoverSampleGrid = 8;

/// Portada ya difuminada, lista para pintar, y colores muestreados de ella.
class CoverBackdropData {
  CoverBackdropData({required this.image, required this.samples})
    : adaptiveTone = CoverTone.adaptive(samples);

  /// Textura difuminada (la posee la caché; no se libera a mano, la recoge
  /// el GC cuando nadie la usa).
  final ui.Image image;

  /// Colores opacos de la textura difuminada (rejilla 8×8).
  final List<Color> samples;

  /// Velo y texto para el mini reproductor (claro u oscuro según la portada).
  final CoverTone adaptiveTone;
}

/// Origen de las portadas difuminadas. Separado del widget para que la E/S y
/// la decodificación queden fuera del árbol y los tests lo sustituyan.
abstract interface class CoverBackdropSource {
  /// Clave estable de la portada de [track] (`null` si no tiene).
  String? keyOf(Track track);

  /// Resultado ya cargado, sin esperar; `null` si no está en caché.
  CoverBackdropData? peek(Track track);

  /// Carga (o reutiliza) la portada. `null` si no hay portada o falló.
  Future<CoverBackdropData?> load(Track track);
}

typedef CoverLoader = Future<CoverBackdropData?> Function(Track track);

/// Caché LRU de portadas difuminadas: una carga por portada aunque la pidan
/// varios widgets a la vez, y los fallos no se guardan (se reintentan).
class CoverBackdropCache implements CoverBackdropSource {
  CoverBackdropCache({this.capacity = 16, CoverLoader? loader})
    : _loader = loader ?? loadBlurredCover;

  static final shared = CoverBackdropCache();

  final int capacity;
  final CoverLoader _loader;
  final _ready = <String, CoverBackdropData>{};
  final _inflight = <String, Future<CoverBackdropData?>>{};

  @override
  String? keyOf(Track track) {
    final url = track.artworkUrl?.trim();
    return url == null || url.isEmpty ? null : '${track.id}|$url';
  }

  @override
  CoverBackdropData? peek(Track track) {
    final key = keyOf(track);
    final hit = key == null ? null : _ready.remove(key);
    if (hit != null) _ready[key!] = hit;
    return hit;
  }

  @override
  Future<CoverBackdropData?> load(Track track) {
    final key = keyOf(track);
    if (key == null) return Future.value();
    final hit = peek(track);
    if (hit != null) return Future.value(hit);
    return _inflight[key] ??= _fetch(key, track);
  }

  Future<CoverBackdropData?> _fetch(String key, Track track) async {
    try {
      final data = await _loader(track);
      if (data != null) {
        _ready[key] = data;
        while (_ready.length > capacity) {
          _ready.remove(_ready.keys.first);
        }
      }
      return data;
    } catch (_) {
      return null;
    } finally {
      _inflight.remove(key);
    }
  }
}

/// Decodifica la portada pequeña, la difumina una vez y muestrea sus colores.
/// `null` si no hay portada, no carga o no decodifica.
Future<CoverBackdropData?> loadBlurredCover(Track track) async {
  final url = track.artworkUrl?.trim();
  if (url == null || url.isEmpty) return null;
  final ImageProvider base = url.startsWith('asset:')
      ? AssetImage(url.substring(6))
      : CachedArtworkImage(upgradeArtworkUrl(url, 226));
  final source = await _firstFrame(ResizeImage(base, width: kCoverDecodeWidth));
  if (source == null) return null;
  try {
    final blurred = await _blur(source);
    final bytes = await blurred.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bytes == null) return null;
    return CoverBackdropData(
      image: blurred,
      samples: gridSamples(
        bytes.buffer.asUint8List(),
        blurred.width,
        blurred.height,
      ),
    );
  } finally {
    source.dispose();
  }
}

Future<ui.Image?> _firstFrame(ImageProvider provider) {
  final done = Completer<ui.Image?>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!done.isCompleted) done.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (_, _) {
      if (!done.isCompleted) done.complete();
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return done.future.timeout(
    const Duration(seconds: 10),
    onTimeout: () {
      stream.removeListener(listener);
      return null;
    },
  );
}

Future<ui.Image> _blur(ui.Image source) {
  final recorder = ui.PictureRecorder();
  final w = source.width.toDouble(), h = source.height.toDouble();
  ui.Canvas(recorder).drawImage(
    source,
    ui.Offset.zero,
    ui.Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: kCoverBlurSigma,
        sigmaY: kCoverBlurSigma,
        tileMode: ui.TileMode.clamp,
      ),
  );
  final picture = recorder.endRecording();
  return picture.toImage(w.round(), h.round()).whenComplete(picture.dispose);
}

/// Media por celda de una rejilla [kCoverSampleGrid]² sobre píxeles RGBA.
List<Color> gridSamples(Uint8List rgba, int width, int height) {
  final cells = <Color>[];
  for (var gy = 0; gy < kCoverSampleGrid; gy++) {
    for (var gx = 0; gx < kCoverSampleGrid; gx++) {
      final x0 = gx * width ~/ kCoverSampleGrid;
      final x1 = ((gx + 1) * width ~/ kCoverSampleGrid).clamp(x0 + 1, width);
      final y0 = gy * height ~/ kCoverSampleGrid;
      final y1 = ((gy + 1) * height ~/ kCoverSampleGrid).clamp(y0 + 1, height);
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final i = (y * width + x) * 4;
          r += rgba[i];
          g += rgba[i + 1];
          b += rgba[i + 2];
          n++;
        }
      }
      if (n > 0) cells.add(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
    }
  }
  return cells;
}
