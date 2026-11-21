import 'dart:io';

import 'package:path/path.dart' as p;

/// Errores sin capturar de Dart en `logs/dart-AAAA-MM-DD.log` (hora UTC).
/// Escribe en síncrono: el proceso puede cerrarse justo después del error.
class CrashLog {
  CrashLog(this.directory, {this.version = '', DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Directory directory;
  final String version;
  final DateTime Function() _now;
  // Un error que se repite en cada fotograma se anota una sola vez.
  final _seen = <String>{};

  void record(String kind, Object error, [StackTrace? stack]) {
    if (!_seen.add('$kind $error')) return;
    final at = _now().toUtc();
    final stamp = at.toIso8601String();
    try {
      directory.createSync(recursive: true);
      File(
        p.join(directory.path, 'dart-${stamp.substring(0, 10)}.log'),
      ).writeAsStringSync(
        '[$stamp] $kind (Aurora $version)\n$error\n${stack ?? ''}\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } on FileSystemException {
      // Sin disco no hay registro; el registro nunca debe tumbar la app.
    }
  }
}
