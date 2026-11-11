import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../bridge/api/cache.dart' as rust;
import '../core/models.dart';
import 'lyrics_match.dart';

export 'lyrics_match.dart' show LyricsConfidence;

enum LyricsKind { synced, plain, instrumental, notFound }

class LyricLine {
  const LyricLine(this.at, this.text);
  final Duration at;
  final String text;
}

/// Corrección de tiempos de la letra de una pista.
class LyricsAdjust {
  const LyricsAdjust({
    required this.source,
    this.shiftMs,
    this.startsMs,
    this.tried = false,
  });

  /// `duration` (diferencia de duración) o `audio` (medido con Whisper).
  final String source;

  /// Desplazamiento constante (ms) que se suma a los tiempos de la letra.
  final int? shiftMs;

  /// Hora (ms) de cada línea; sustituye a los tiempos de la letra.
  final List<int>? startsMs;

  /// Ya se intentó medir en el audio sin un resultado fiable: no se repite.
  final bool tried;

  /// Medido en el audio: no hace falta volver a analizar.
  bool get settled => source == 'audio' || tried;

  factory LyricsAdjust.fromJson(Map<dynamic, dynamic> json) => LyricsAdjust(
    source: '${json['source']}',
    shiftMs: (json['shiftMs'] as num?)?.toInt(),
    startsMs: (json['startsMs'] as List?)
        ?.map((e) => (e as num).toInt())
        .toList(),
    tried: json['tried'] == true,
  );

  Map<String, Object?> toJson() => {
    'source': source,
    if (shiftMs != null) 'shiftMs': shiftMs,
    if (startsMs != null) 'startsMs': startsMs,
    if (tried) 'tried': true,
  };
}

class LyricsResult {
  const LyricsResult(
    this.kind, {
    this.lines = const [],
    this.text = '',
    this.source = '',
    this.confidence = LyricsConfidence.medium,
    this.fromCache = false,
  });
  final LyricsKind kind;
  final List<LyricLine> lines;
  final String text;

  /// Origen legible: «LRCLIB», «lyrics.ovh», «Archivo local».
  final String source;
  final LyricsConfidence confidence;

  /// Viene de la caché local (red lenta o sin conexión): se muestra como «guardada».
  final bool fromCache;

  LyricsResult asCached() => LyricsResult(
    kind,
    lines: lines,
    text: text,
    source: source,
    confidence: confidence,
    fromCache: true,
  );
}

/// Letra candidata de una búsqueda manual («Buscar otra letra»).
class LyricsCandidate {
  const LyricsCandidate({
    required this.title,
    required this.artist,
    required this.album,
    required this.seconds,
    required this.content,
    required this.synced,
    required this.score,
    this.source = 'LRCLIB',
  });
  final String title;
  final String artist;
  final String album;
  final int seconds;
  final String content;
  final bool synced;
  final double score;
  final String source;
}

typedef LyricsQuery = ({
  String artist,
  String title,
  String album,
  int seconds,
});

class LyricsService {
  LyricsService({
    HttpClient Function()? clientFactory,
    this.backoff = const Duration(milliseconds: 400),
    this.retries = 2,
    this.now = DateTime.now,
  }) : _clientFactory = clientFactory ?? HttpClient.new;
  static const maxBytes = 1024 * 1024;
  static const timeout = Duration(seconds: 3);
  static const negativeTtl = Duration(hours: 24);
  static const maxCacheFiles = 400;

  /// Una letra guardada más reciente que esto se usa sin consultar la red.
  static const freshTtl = Duration(days: 30);
  static const _maxMemory = 64;
  // shortcut: versión fija, no se lee de package_info; actualizar al subir de versión.
  static const userAgent =
      'Aurora/1.4.0 (https://github.com/kaz-py/auroraMusic)';
  final HttpClient Function() _clientFactory;
  final Duration backoff;
  final int retries;
  final DateTime Function() now;
  bool _disposed = false;
  int _generation = 0;
  final Set<HttpClient> _clients = {};

  // Caché en memoria (LRU): reabrir la pista en la sesión no toca el disco.
  final Map<String, _Cached> _memory = {};

  void _remember(String key, _Cached? c) {
    _memory.remove(key);
    if (c == null) return;
    _memory[key] = c;
    if (_memory.length > _maxMemory) _memory.remove(_memory.keys.first);
  }

  // ---- LRC ------------------------------------------------------------

  static final _tag = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
  static final _offsetTag = RegExp(
    r'\[offset:\s*([+-]?\d+)\s*\]',
    caseSensitive: false,
  );

  static List<LyricLine> parseLrc(String input) {
    final out = <LyricLine>[];
    final rows = input.split(RegExp(r'\r?\n'));
    var offset = 0;
    for (final row in rows) {
      final off = _offsetTag.firstMatch(row);
      if (off != null) offset = int.tryParse(off.group(1)!) ?? 0;
    }
    for (final row in rows) {
      if (_offsetTag.hasMatch(row)) continue;
      final tags = _tag
          .allMatches(row)
          .where((t) => (int.tryParse(t.group(2)!) ?? 60) < 60)
          .toList();
      if (tags.isEmpty) continue;
      final lyric = row
          .replaceAll(_tag, '')
          .replaceAll(
            RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'),
            '',
          ) // LRC mejorado
          .trim();
      if (lyric.isEmpty) continue;
      for (final tag in tags) {
        final fraction = (tag.group(3) ?? '0').padRight(3, '0').substring(0, 3);
        final millis =
            (int.tryParse(tag.group(1)!) ?? 0) * 60000 +
            (int.tryParse(tag.group(2)!) ?? 0) * 1000 +
            (int.tryParse(fraction) ?? 0) +
            offset;
        out.add(
          LyricLine(Duration(milliseconds: millis.clamp(0, 1 << 40)), lyric),
        );
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  static LyricsResult _result(
    String content,
    String source,
    LyricsConfidence confidence, {
    bool allowSync = true,
  }) {
    final lines = allowSync ? parseLrc(content) : const <LyricLine>[];
    if (lines.isNotEmpty) {
      return LyricsResult(
        LyricsKind.synced,
        lines: lines,
        source: source,
        confidence: confidence,
      );
    }
    // Sin sincronía fiable: texto plano sin marcas de tiempo.
    final text = content
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(_tag, '').trim())
        .where(
          (l) => !RegExp(r'^\[[a-z]+:.*\]$', caseSensitive: false).hasMatch(l),
        )
        .join('\n')
        .trim();
    return text.isEmpty
        ? const LyricsResult(LyricsKind.notFound)
        : LyricsResult(
            LyricsKind.plain,
            text: text,
            source: source,
            confidence: confidence,
          );
  }

  // ---- consulta ---------------------------------------------------------

  static LyricsQuery queryFor(Track track) {
    final artist = cleanArtist(track.artist);
    return (
      artist: artist,
      title: cleanTitle(track.title, artist: track.artist),
      album: (track.album ?? '').trim(),
      seconds: track.duration.inSeconds,
    );
  }

  /// Caché primero: una letra guardada hace menos de [freshTtl] (o elegida/
  /// importada a mano, sin caducidad) se entrega al instante, sin red. Una
  /// negativa reciente ([negativeTtl]) devuelve «sin letra» sin red. Si la
  /// guardada caducó, o con [force], va la cascada LRCLIB get → LRCLIB search →
  /// lyrics.ovh; la caducada respalda (red caída, o respuesta lenta mediante
  /// [onInterim]) y se corrige con cada respuesta nueva. Una letra manual no se
  /// pisa salvo con [force]. Lanza si todo falló por red y no hay caché.
  Future<LyricsResult> load(
    Track track,
    Directory root, {
    bool force = false,
    void Function(LyricsResult cached)? onInterim,
    Duration slowAfter = const Duration(seconds: 3),
  }) async {
    final generation = _begin();
    bool stale() => _disposed || generation != _generation;
    const none = LyricsResult(LyricsKind.notFound);
    final cached = await _readCache(track, root);
    if (stale()) return none;
    if (cached != null && !force) {
      if (cached.negative && now().difference(cached.at) < negativeTtl) {
        return none; // LRCLIB ya confirmó que no existe hace menos de 24 h
      }
      if (cached.manual && !cached.negative) return cached.result.asCached();
      if (!cached.negative && now().difference(cached.at) < freshTtl) {
        return cached.result.asCached();
      }
    }
    final backup = cached == null || cached.negative
        ? null
        : cached.result.asCached();
    Timer? slow;
    if (backup != null && onInterim != null) {
      slow = Timer(slowAfter, () {
        if (!stale()) onInterim(backup);
      });
    }
    final q = queryFor(track);
    HttpClient? client;
    Object? lastError;
    try {
      client = _clientFactory()..connectionTimeout = timeout;
      _clients.add(client);
      final http = client;
      LyricsResult? found;
      Future<void> step(Future<LyricsResult?> Function() run) async {
        if (found != null || stale()) return;
        try {
          found = await run();
        } catch (e) {
          lastError = e;
        }
      }

      await step(() => _lrclibGet(http, q));
      await step(() async => (await _lrclibSearch(http, q, best: true))?.$1);
      await step(() => _ovh(http, q));
      if (stale()) return none;
      final hit = found;
      if (hit != null) {
        await _writeCache(track, root, hit); // corrige la caché anterior
        return hit;
      }
      if (backup != null) return backup;
      if (lastError != null) throw lastError!;
      await _writeNegative(track, root);
      return none;
    } catch (_) {
      if (stale()) return none; // petición abortada por cambio de pista
      if (backup != null) return backup;
      rethrow;
    } finally {
      slow?.cancel();
      if (client != null) {
        _clients.remove(client);
        client.close(force: true);
      }
    }
  }

  int _begin() {
    // Una carga nueva aborta las peticiones de la anterior.
    for (final c in _clients) {
      c.close(force: true);
    }
    _clients.clear();
    return ++_generation;
  }

  Future<LyricsResult?> _lrclibGet(HttpClient client, LyricsQuery q) async {
    final data = await _getJson(
      client,
      Uri.https('lrclib.net', '/api/get', {
        'artist_name': q.artist,
        'track_name': q.title,
        if (q.album.isNotEmpty) 'album_name': q.album,
        if (q.seconds > 0) 'duration': '${q.seconds}',
      }),
    );
    if (data is! Map<String, dynamic>) return null;
    return _fromLrclib(data, q);
  }

  LyricsResult? _fromLrclib(Map<String, dynamic> d, LyricsQuery q) {
    final m = _score(d, q);
    if (!m.acceptable) return null;
    if (d['instrumental'] == true) {
      return const LyricsResult(LyricsKind.instrumental, source: 'LRCLIB');
    }
    final synced = d['syncedLyrics'], plain = d['plainLyrics'];
    final useSynced = synced is String && synced.trim().isNotEmpty && m.syncOk;
    final content = useSynced ? synced : (plain is String ? plain : '');
    if (content.trim().isEmpty) return null;
    return _result(content, 'LRCLIB', m.confidence, allowSync: useSynced);
  }

  LyricsMatch _score(Map<String, dynamic> d, LyricsQuery q) =>
      scoreLyricsCandidate(
        wantedArtist: q.artist,
        wantedTitle: q.title,
        wantedSeconds: q.seconds,
        artist: '${d['artistName'] ?? ''}',
        title: '${d['trackName'] ?? d['name'] ?? ''}',
        seconds: d['duration'] is num ? d['duration'] as num : null,
      );

  /// Mejor candidato aceptable (sincronizada preferida) y la lista puntuada.
  Future<(LyricsResult, List<LyricsCandidate>)?> _lrclibSearch(
    HttpClient client,
    LyricsQuery q, {
    required bool best,
  }) async {
    var data = await _getJson(
      client,
      Uri.https('lrclib.net', '/api/search', {
        'track_name': q.title,
        'artist_name': q.artist,
      }),
    );
    if (data is! List || data.isEmpty) {
      data = await _getJson(
        client,
        Uri.https('lrclib.net', '/api/search', {'q': '${q.artist} ${q.title}'}),
      );
    }
    if (data is! List) return null;
    final scored = <(Map<String, dynamic>, LyricsMatch)>[];
    for (final e in data.take(40)) {
      if (e is Map<String, dynamic>) scored.add((e, _score(e, q)));
    }
    double rank((Map<String, dynamic>, LyricsMatch) c) {
      final s = c.$1['syncedLyrics'];
      return c.$2.score +
          (s is String && s.trim().isNotEmpty && c.$2.syncOk ? .08 : 0);
    }

    scored.sort((a, b) => rank(b).compareTo(rank(a)));
    final good = scored.where((c) => c.$2.acceptable).toList();
    if (best) {
      for (final c in good) {
        final r = _fromLrclib(c.$1, q);
        if (r != null) return (r, const <LyricsCandidate>[]);
      }
      return null;
    }
    return (
      const LyricsResult(LyricsKind.notFound),
      [
        for (final c in scored)
          if (_content(c.$1).isNotEmpty)
            LyricsCandidate(
              title: '${c.$1['trackName'] ?? c.$1['name'] ?? ''}',
              artist: '${c.$1['artistName'] ?? ''}',
              album: '${c.$1['albumName'] ?? ''}',
              seconds: (c.$1['duration'] as num?)?.round() ?? 0,
              content: _content(c.$1),
              synced: _syncedOf(c.$1).isNotEmpty,
              score: c.$2.score,
            ),
      ],
    );
  }

  static String _syncedOf(Map<String, dynamic> d) {
    final s = d['syncedLyrics'];
    return s is String ? s.trim() : '';
  }

  static String _content(Map<String, dynamic> d) {
    final s = _syncedOf(d);
    if (s.isNotEmpty) return s;
    final pl = d['plainLyrics'];
    return pl is String ? pl.trim() : '';
  }

  Future<LyricsResult?> _ovh(HttpClient client, LyricsQuery q) async {
    if (q.artist.isEmpty || q.title.isEmpty) return null;
    final data = await _getJson(
      client,
      Uri.https(
        'api.lyrics.ovh',
        '/v1/${Uri.encodeComponent(q.artist)}/${Uri.encodeComponent(q.title)}',
      ),
    );
    final text = data is Map ? data['lyrics'] : null;
    if (text is! String || text.trim().isEmpty) return null;
    // lyrics.ovh no ofrece duración: confianza media-baja, nunca sincronizada.
    return _result(text, 'lyrics.ovh', LyricsConfidence.low, allowSync: false);
  }

  /// GET JSON con reintentos (red, 429, 5xx) y backoff exponencial. 404 → null.
  Future<Object?> _getJson(HttpClient client, Uri uri) async {
    Object? error;
    for (var attempt = 0; attempt <= retries; attempt++) {
      if (_disposed) throw const HttpException('cancelado');
      try {
        final request = await client.getUrl(uri).timeout(timeout);
        request.headers.set(HttpHeaders.userAgentHeader, userAgent);
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(timeout);
        if (response.statusCode == 404) {
          await response.drain<void>();
          return null;
        }
        if (response.statusCode == 429 || response.statusCode >= 500) {
          await response.drain<void>();
          throw HttpException('${uri.host} respondió ${response.statusCode}.');
        }
        if (response.statusCode != 200) {
          await response.drain<void>();
          return null; // 4xx distinto de 429: petición no válida, sin reintento
        }
        final bytes = await _readBounded(response).timeout(timeout);
        try {
          return jsonDecode(utf8.decode(bytes));
        } on FormatException {
          return null; // respuesta rara: se trata como «sin datos»
        }
      } on FormatException {
        rethrow; // tamaño excedido: no reintentar
      } catch (e) {
        error = e;
        if (attempt < retries) {
          await Future<void>.delayed(backoff * (1 << attempt));
        }
      }
    }
    throw error!;
  }

  static Future<List<int>> _readBounded(HttpClientResponse response) async {
    if (response.contentLength > maxBytes) {
      throw const FormatException('Lyrics exceed 1 MiB.');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('Lyrics exceed 1 MiB.');
      }
    }
    return builder.takeBytes();
  }

  /// Candidatos de LRCLIB para elegir a mano (más probables primero).
  Future<List<LyricsCandidate>> candidates(Track track) async {
    final generation = _begin();
    final client = _clientFactory()..connectionTimeout = timeout;
    _clients.add(client);
    try {
      final r = await _lrclibSearch(client, queryFor(track), best: false);
      return _disposed || generation != _generation
          ? const []
          : (r?.$2 ?? const []);
    } finally {
      _clients.remove(client);
      client.close(force: true);
    }
  }

  Future<LyricsResult> choose(
    Track track,
    Directory root,
    LyricsCandidate c,
  ) async {
    final result = _result(c.content, c.source, LyricsConfidence.medium);
    await _writeCache(track, root, result, raw: c.content, manual: true);
    return result;
  }

  // ---- caché en disco ---------------------------------------------------

  static String _hash(String id) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(id)) {
      hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // En disco no se guarda ni el id crudo (puede ser una ruta): hash + título/artista normalizados.
  static String _key(Track t) =>
      '${_hash(t.id)}:${normalizeLyricsKey('${t.artist}${t.title}')}';

  File _file(Track track, Directory root) =>
      File(p.join(root.path, 'lyrics', '${_hash(track.id)}.json'));

  Future<_Cached?> _readCache(Track track, Directory root) async {
    final mem = _memoryKey(track, root);
    final hot = _memory[mem];
    if (hot != null) {
      _remember(mem, hot); // refresca el orden LRU
      return hot;
    }
    final read = await _readDisk(track, root);
    _remember(mem, read);
    return read;
  }

  String _memoryKey(Track track, Directory root) =>
      '${root.path}|${_key(track)}';

  Future<_Cached?> _readDisk(Track track, Directory root) async {
    try {
      final file = _file(track, root);
      if (await file.exists() && await file.length() <= maxBytes * 2) {
        final j = jsonDecode(await file.readAsString());
        if (j is Map && j['k'] == _key(track)) {
          unawaited(file.setLastModified(now()).catchError((_) {})); // LRU
          final at = DateTime.fromMillisecondsSinceEpoch(
            (j['at'] as num?)?.toInt() ?? 0,
          );
          final manual = j['manual'] == true;
          if (j['none'] == true) {
            return _Cached(
              const LyricsResult(LyricsKind.notFound),
              at,
              negative: true,
            );
          }
          final source = '${j['source'] ?? ''}';
          if (j['instrumental'] == true) {
            return _Cached(
              LyricsResult(LyricsKind.instrumental, source: source),
              at,
              manual: manual,
            );
          }
          final conf =
              LyricsConfidence.values.asNameMap()['${j['confidence']}'] ??
              LyricsConfidence.medium;
          final r = _result(
            '${j['content'] ?? ''}',
            source,
            conf,
            allowSync: j['synced'] != false,
          );
          if (r.kind != LyricsKind.notFound) {
            return _Cached(r, at, manual: manual);
          }
        }
      }
    } catch (_) {
      // caché ilegible: se ignora y se vuelve a pedir
    }
    return null;
  }

  Future<void> _writeCache(
    Track track,
    Directory root,
    LyricsResult r, {
    String? raw,
    bool manual = false,
  }) {
    final at = now();
    _remember(
      _memoryKey(track, root),
      r.kind == LyricsKind.notFound ? null : _Cached(r, at, manual: manual),
    );
    return _write(track, root, {
      if (manual) 'manual': true,
      'k': _key(track),
      'at': at.millisecondsSinceEpoch,
      'source': r.source,
      'confidence': r.confidence.name,
      if (r.kind == LyricsKind.instrumental) 'instrumental': true,
      'synced': r.kind == LyricsKind.synced,
      'content': raw ?? _serialize(r),
    });
  }

  Future<void> _writeNegative(Track track, Directory root) {
    final at = now();
    _remember(
      _memoryKey(track, root),
      _Cached(const LyricsResult(LyricsKind.notFound), at, negative: true),
    );
    return _write(track, root, {
      'k': _key(track),
      'at': at.millisecondsSinceEpoch,
      'none': true,
    });
  }

  static String _serialize(LyricsResult r) {
    if (r.kind == LyricsKind.synced) {
      String ts(Duration d) {
        final ms = d.inMilliseconds;
        return '[${(ms ~/ 60000).toString().padLeft(2, '0')}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${((ms % 1000) ~/ 10).toString().padLeft(2, '0')}]';
      }

      return r.lines.map((l) => '${ts(l.at)}${l.text}').join('\n');
    }
    return r.text;
  }

  Future<void> _write(
    Track track,
    Directory root,
    Map<String, Object?> data,
  ) async {
    if (_disposed) return;
    try {
      final dir = Directory(p.join(root.path, 'lyrics'))
        ..createSync(recursive: true);
      final bytes = utf8.encode(jsonEncode(data));
      if (bytes.length > maxBytes * 2) return;
      await _file(track, root).writeAsBytes(bytes, flush: true);
      rust.pruneDirectory(
        dir: dir.path,
        maxFiles: maxCacheFiles,
        nameSuffix: '.json',
        excludeNames: const ['adjust.json'],
      );
    } catch (_) {
      // la caché es opcional
    }
  }

  // ---- sincronía compartida (modo artista y tarjeta de Vinilo) -----------

  /// Reparte las líneas de una letra sin tiempos a lo largo de la pista (sin el
  /// 6 % inicial ni el 6 % final). Sin duración no hay nada que repartir.
  static List<LyricLine> spreadLines(String text, Duration total) {
    final rows = [
      for (final r in text.split(RegExp(r'\r?\n')))
        if (r.trim().isNotEmpty) r.trim(),
    ];
    if (rows.isEmpty || total <= Duration.zero) return const [];
    final ms = total.inMilliseconds;
    return [
      for (var i = 0; i < rows.length; i++)
        LyricLine(
          Duration(
            milliseconds: (ms * .06 + ms * .88 * i / rows.length).round(),
          ),
          rows[i],
        ),
    ];
  }

  /// La letra llegó sin sincronizar: LRCLIB suele tenerla sincronizada pero la
  /// descarta si la duración difiere más de 3 s (vídeos con intro). Se busca
  /// entre los candidatos una sincronizada que case con título, artista y una
  /// duración razonable (±20 s) y se guarda como elegida a mano. `null` si no
  /// hay ninguna. Los errores se propagan: quien llama decide.
  Future<LyricsResult?> upgradeToSynced(Track track, Directory root) async {
    final found = await candidates(track);
    final total = track.duration.inSeconds;
    final fits =
        found
            .where(
              (c) =>
                  c.synced &&
                  c.score >= .65 &&
                  (total == 0 || (c.seconds - total).abs() <= 20),
            )
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    if (fits.isEmpty) return null;
    final result = await choose(track, root, fits.first);
    if (result.kind != LyricsKind.synced) return null;
    // La letra es de otra versión más corta (el vídeo suele traer una intro):
    // sus tiempos van adelantados por esa diferencia. Se parte de ese desfase
    // hasta que el análisis del audio lo mida de verdad.
    // shortcut: supone que la diferencia es intro y no final.
    final gap = total - fits.first.seconds;
    if (gap > syncToleranceSeconds && await readAdjust(track, root) == null) {
      await writeAdjust(
        track,
        root,
        LyricsAdjust(source: 'duration', shiftMs: gap * 1000),
      );
    }
    return result;
  }

  // ---- ajuste de tiempos por pista ---------------------------------------

  File _adjustFile(Directory root) =>
      File(p.join(root.path, 'lyrics', 'adjust.json'));

  /// Ajuste guardado para [track] (por duración o medido en el audio).
  Future<LyricsAdjust?> readAdjust(Track track, Directory root) async {
    try {
      // Síncrono: el archivo es pequeño y así no depende de E/S asíncrona.
      final j = jsonDecode(_adjustFile(root).readAsStringSync());
      final e = j is Map ? j[_hash(track.id)] : null;
      return e is Map ? LyricsAdjust.fromJson(e) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeAdjust(
    Track track,
    Directory root,
    LyricsAdjust adjust,
  ) async {
    final file = _adjustFile(root);
    Map<String, dynamic> all = {};
    try {
      final j = jsonDecode(await file.readAsString());
      if (j is Map<String, dynamic>) all = j;
    } catch (_) {}
    all[_hash(track.id)] = adjust.toJson();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(all), flush: true);
    await temporary.rename(file.path);
  }

  /// [raw] (tal como llegó de la red o de la caché) con el ajuste de la pista
  /// aplicado. Idempotente: siempre se parte de la letra sin ajustar.
  Future<LyricsResult> adjusted(
    Track track,
    Directory root,
    LyricsResult raw,
  ) async {
    if (raw.kind != LyricsKind.synced && raw.kind != LyricsKind.plain) {
      return raw;
    }
    final adjust = await readAdjust(track, root);
    return adjust == null ? raw : applyAdjust(raw, adjust);
  }

  /// Líneas no vacías de una letra sin tiempos (las mismas que se alinean).
  static List<String> plainRows(String text) => [
    for (final row in text.split(RegExp(r'\r?\n')))
      if (row.trim().isNotEmpty) row.trim(),
  ];

  static LyricsResult applyAdjust(LyricsResult raw, LyricsAdjust adjust) {
    final starts = adjust.startsMs;
    LyricsResult build(List<LyricLine> lines) => LyricsResult(
      LyricsKind.synced,
      lines: lines,
      text: raw.text,
      source: raw.source,
      confidence: raw.confidence,
      fromCache: raw.fromCache,
    );
    if (raw.kind == LyricsKind.plain) {
      final rows = plainRows(raw.text);
      if (starts == null || starts.length != rows.length) return raw;
      return build([
        for (var i = 0; i < rows.length; i++)
          LyricLine(Duration(milliseconds: starts[i]), rows[i]),
      ]);
    }
    if (starts != null && starts.length == raw.lines.length) {
      return build([
        for (var i = 0; i < starts.length; i++)
          LyricLine(Duration(milliseconds: starts[i]), raw.lines[i].text),
      ]);
    }
    final shift = adjust.shiftMs ?? 0;
    if (shift == 0) return raw;
    return build([
      for (final line in raw.lines)
        LyricLine(
          Duration(
            milliseconds: (line.at.inMilliseconds + shift).clamp(0, 1 << 30),
          ),
          line.text,
        ),
    ]);
  }

  // ---- importación manual -------------------------------------------------

  Future<LyricsResult?> importFile(Track track, Directory root) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    if (files.isEmpty || files.first.path == null || _disposed) return null;
    final source = File(files.first.path!);
    final input = source.openRead(0, maxBytes + 1);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in input) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw const FormatException('Choose a lyrics file up to 1 MiB.');
      }
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Choose a lyrics file up to 1 MiB.');
    }
    final content = utf8.decode(bytes, allowMalformed: false);
    final result = _result(content, 'Archivo local', LyricsConfidence.high);
    await _writeCache(track, root, result, raw: content, manual: true);
    return result;
  }

  void dispose() {
    _disposed = true;
    _generation++;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

class _Cached {
  const _Cached(
    this.result,
    this.at, {
    this.negative = false,
    this.manual = false,
  });
  final LyricsResult result;
  final DateTime at;
  final bool negative;

  /// Elegida o importada por el usuario: la red no la pisa.
  final bool manual;
}
