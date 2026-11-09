import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Modelo de voz en español (Vosk, Apache 2.0). Se descarga una vez, al activar
/// los comandos de voz, y se verifica por tamaño y SHA-256 antes de usarlo.
abstract final class VoiceModel {
  static const name = 'vosk-model-small-es-0.42';
  static final url = Uri.parse('https://alphacephei.com/vosk/models/$name.zip');
  static const bytes = 39817833;
  static const sha256Hex =
      '09b239888f633ef2f0b4e09736e3d9936acfd810bc65d53fad45261762c6511f';

  static Directory directory(Directory supportDirectory) =>
      Directory(p.join(supportDirectory.path, 'voice', name));
}

class VoiceModelException implements Exception {
  const VoiceModelException(this.message);
  final String message;
  @override
  String toString() => message;
}

typedef VoiceDownloadProgress = void Function(double fraction);

/// Descarga [url] a [target] por HTTPS con certificados verificados, sin pasar
/// de [expectedBytes] y comprobando su SHA-256. Borra el archivo si algo falla.
Future<void> downloadVerified(
  Uri url,
  File target, {
  required int expectedBytes,
  required String expectedSha256,
  VoiceDownloadProgress? onProgress,
  HttpClient Function()? clientFactory,
}) async {
  if (url.scheme != 'https') {
    throw const VoiceModelException('La descarga debe ser por HTTPS.');
  }
  final client = (clientFactory?.call() ?? HttpClient())
    ..connectionTimeout = const Duration(seconds: 15);
  IOSink? sink;
  var complete = false;
  try {
    await target.parent.create(recursive: true);
    final request = await client.getUrl(url);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw VoiceModelException(
        'No se pudo descargar el modelo (HTTP ${response.statusCode}).',
      );
    }
    sink = target.openWrite();
    final digest = _DigestSink();
    final hash = sha256.startChunkedConversion(digest);
    var received = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      received += chunk.length;
      if (received > expectedBytes) {
        throw const VoiceModelException('El modelo pesa más de lo esperado.');
      }
      hash.add(chunk);
      sink.add(chunk);
      onProgress?.call(received / expectedBytes);
    }
    hash.close();
    await sink.close();
    sink = null;
    if (received != expectedBytes) {
      throw const VoiceModelException(
        'La descarga del modelo está incompleta.',
      );
    }
    if (digest.value.toString() != expectedSha256) {
      throw const VoiceModelException(
        'El modelo descargado no coincide con el esperado (SHA-256). No se usará.',
      );
    }
    complete = true;
  } on TimeoutException {
    throw const VoiceModelException(
      'La descarga del modelo se quedó sin respuesta.',
    );
  } on SocketException catch (e) {
    throw VoiceModelException(
      'Sin conexión para descargar el modelo: ${e.message}',
    );
  } on HandshakeException {
    throw const VoiceModelException(
      'No se pudo verificar el certificado del servidor.',
    );
  } finally {
    client.close(force: true);
    try {
      await sink?.close();
    } catch (_) {}
    if (!complete && await target.exists()) await target.delete();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
