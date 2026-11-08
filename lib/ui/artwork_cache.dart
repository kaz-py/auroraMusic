import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import '../bridge/api/cache.dart' as rust;

/// Sube la resolución de miniaturas de Google/YouTube (`=w60-h60`, `=s120`,
/// `/hqdefault.jpg`) al cubo [px] más cercano por encima. Otras URLs intactas.
/// Los cubos fijos evitan una entrada de caché por cada tamaño de widget.
String upgradeArtworkUrl(String url, double px) {
  final bucket = const [
    120,
    226,
    544,
    1200,
  ].firstWhere((b) => b >= px, orElse: () => 1200);
  final size = RegExp(r'=w\d+-h\d+(-[a-z0-9-]*)?$');
  if (size.hasMatch(url)) {
    return url.replaceFirstMapped(
      size,
      (m) => '=w$bucket-h$bucket${m.group(1) ?? ''}',
    );
  }
  if (RegExp(r'=s\d+(-[a-z0-9-]*)?$').hasMatch(url) &&
      url.contains('googleusercontent')) {
    return url.replaceFirstMapped(
      RegExp(r'=s\d+(-[a-z0-9-]*)?$'),
      (m) => '=s$bucket${m.group(1) ?? ''}',
    );
  }
  return url;
}

/// Caché de portadas en disco con límite de tamaño y expulsión LRU
/// (se usa la fecha de modificación, que se refresca en cada acierto).
class ArtworkDiskCache {
  ArtworkDiskCache(
    this.directory, {
    this.maxBytes = 150 * 1024 * 1024,
    this.useDisk = true,
    Future<Uint8List> Function(String url)? fetch,
  }) : _fetch = fetch ?? _httpFetch;

  /// Instancia compartida; si no hay carpeta de caché (tests) funciona sin disco.
  static final shared = ArtworkDiskCache(
    null,
    // En flutter test no hay path_provider: ir directo a red, sin esperas.
    useDisk: !Platform.environment.containsKey('FLUTTER_TEST'),
  );

  final Directory? directory;
  final int maxBytes;
  final bool useDisk;
  final Future<Uint8List> Function(String url) _fetch;
  Future<Directory?>? _dir;
  final _inflight = <String, Future<Uint8List>>{};

  Future<Directory?> _resolve() => _dir ??= () async {
    try {
      final d =
          directory ??
          Directory(
            '${(await getApplicationCacheDirectory()).path}/artwork_cache',
          );
      await d.create(recursive: true);
      return d;
    } catch (_) {
      return null; // sin disco: solo red
    }
  }();

  static String keyFor(String url) => sha1.convert(url.codeUnits).toString();

  Future<Uint8List> load(String url) =>
      _inflight[url] ??= _load(url).whenComplete(() {
        _inflight.remove(url);
      });

  Future<Uint8List> _load(String url) async {
    if (!useDisk) return _fetch(url);
    final dir = await _resolve();
    final file = dir == null ? null : File('${dir.path}/${keyFor(url)}');
    if (file != null) {
      try {
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            await file.setLastModified(DateTime.now());
            return bytes;
          }
        }
      } catch (_) {}
    }
    final bytes = await _fetch(url);
    if (file != null && bytes.isNotEmpty) {
      try {
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(file.path);
        unawaited(prune());
      } catch (_) {}
    }
    return bytes;
  }

  /// Borra lo menos usado hasta quedar por debajo de [maxBytes].
  Future<void> prune() => _pruning = (_pruning ?? Future.value()).then(
    (_) => _prune(),
  ); // en serie: dos podas a la vez borrarían de más

  Future<void>? _pruning;

  Future<void> _prune() async {
    final dir = await _resolve();
    if (dir == null) return;
    rust.pruneDirectory(
      dir: dir.path,
      maxBytes: maxBytes,
      excludeNames: const [],
    );
  }

  static Future<Uint8List> _httpFetch(String url) async {
    // Respeta el cliente de pruebas de Flutter (mismo gancho que NetworkImage).
    final client =
        (debugNetworkImageHttpClientProvider?.call()) ?? HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }
}

/// Proveedor de imagen que pasa por [ArtworkDiskCache].
@immutable
class CachedArtworkImage extends ImageProvider<CachedArtworkImage> {
  const CachedArtworkImage(this.url, {this.cache});
  final String url;
  final ArtworkDiskCache? cache;

  @override
  Future<CachedArtworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    CachedArtworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: (cache ?? ArtworkDiskCache.shared).load(url).then((bytes) async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return decode(buffer);
    }),
    scale: 1,
    debugLabel: url,
  );

  @override
  bool operator ==(Object other) =>
      other is CachedArtworkImage && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
