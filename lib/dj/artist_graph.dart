// Vecindario de artistas («organizational similarity»): artistas afines de la
// página de YouTube Music, `artist.getSimilar` de Last.fm y artistas que
// coinciden en la radio de YouTube, más etiquetas de género de Last.fm. Las
// lecturas son síncronas y solo de caché; `warm` rellena la caché con tiempo
// acotado. Persistido en SharedPreferences como JSON.
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'coherence.dart';

class _Entry {
  _Entry(this.t, this.ok, this.n, this.g, {this.fetched = true});
  int t; // epoch ms de la última actualización
  bool ok; // false = todas las fuentes fallaron
  Set<String> n; // vecinos normalizados
  List<String> g; // etiquetas de género
  bool fetched; // false = solo co-escucha: `warm` aún debe pedir las fuentes

  Map<String, Object> toJson() => {
    't': t,
    'ok': ok,
    'n': n.toList(),
    'g': g,
    if (!fetched) 'f': false,
  };
}

class ArtistGraph {
  ArtistGraph({
    required SharedPreferences preferences,
    Future<List<String>> Function(String artist)? youtubeRelated,
    Future<List<String>> Function(String artist)? lastfmSimilar,
    Future<List<String>> Function(String artist)? lastfmTags,
    DateTime Function()? now,
  }) : _prefs = preferences,
       _youtubeRelated = youtubeRelated,
       _lastfmSimilar = lastfmSimilar,
       _lastfmTags = lastfmTags,
       _now = now ?? DateTime.now {
    _load();
  }

  static const prefsKey = 'artistGraph';
  static const ttl = Duration(days: 14);
  static const failureTtl = Duration(hours: 1);
  static const maxEntries = 400;

  final SharedPreferences _prefs;
  final Future<List<String>> Function(String artist)? _youtubeRelated;
  final Future<List<String>> Function(String artist)? _lastfmSimilar;
  final Future<List<String>> Function(String artist)? _lastfmTags;
  final DateTime Function() _now;
  final _entries = <String, _Entry>{};
  final _inflight = <String>{};

  void _load() {
    final raw = _prefs.getString(prefsKey);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return;
      for (final e in map.entries) {
        final v = e.value;
        if (e.key is! String || v is! Map) continue;
        _entries[e.key as String] = _Entry(
          v['t'] is int ? v['t'] as int : 0,
          v['ok'] == true,
          {
            for (final s in (v['n'] as List? ?? const []))
              if (!isGenericArtistName('$s')) '$s',
          },
          [for (final s in (v['g'] as List? ?? const [])) '$s'],
          fetched: v['f'] != false,
        );
      }
    } catch (_) {
      _entries.clear(); // caché corrupta: se reconstruye
    }
  }

  void _save() {
    if (_entries.length > maxEntries) {
      final oldest = _entries.entries.toList()
        ..sort((a, b) => a.value.t.compareTo(b.value.t));
      for (final e in oldest.take(_entries.length - maxEntries)) {
        _entries.remove(e.key);
      }
    }
    unawaited(
      _prefs
          .setString(
            prefsKey,
            jsonEncode({
              for (final e in _entries.entries) e.key: e.value.toJson(),
            }),
          )
          .then((_) {}, onError: (Object _) {}),
    );
  }

  /// Vecinos (normalizados con [coherenceNorm]) de [artist]; solo caché.
  Set<String> neighborsOf(String artist) =>
      _entries[coherenceNorm(artist)]?.n ?? const {};

  /// Etiquetas de género de [artist]; solo caché.
  List<String> tagsOf(String artist) =>
      _entries[coherenceNorm(artist)]?.g ?? const [];

  bool _fresh(_Entry? e, int nowMs) =>
      e != null &&
      e.fetched &&
      nowMs - e.t < (e.ok ? ttl : failureTtl).inMilliseconds;

  /// Pide en paralelo lo que falta o caducó; corta a los [budget] (lo que
  /// llegue después se guarda igualmente).
  Future<void> warm(
    Iterable<String> artists, {
    Duration budget = const Duration(seconds: 3),
  }) async {
    final fetchers = [?_youtubeRelated, ?_lastfmSimilar];
    final tagFetcher = _lastfmTags;
    if (fetchers.isEmpty && tagFetcher == null) return;
    final nowMs = _now().millisecondsSinceEpoch;
    final todo = <String, String>{};
    for (final a in artists) {
      final k = coherenceNorm(a);
      if (k.isEmpty || _inflight.contains(k) || todo.containsKey(k)) continue;
      if (!_fresh(_entries[k], nowMs)) todo[k] = a;
    }
    if (todo.isEmpty) return;
    var done = false;
    Future<List<String>?> safe(Future<List<String>> Function() call) async {
      try {
        return await call();
      } catch (_) {
        return null;
      }
    }

    Future<void> fetch(String key, String artist) async {
      _inflight.add(key);
      try {
        final results = await Future.wait([
          for (final f in fetchers) safe(() => f(artist)),
          if (tagFetcher != null) safe(() => tagFetcher(artist)),
        ]);
        final neighbors = results.take(fetchers.length);
        final tags = tagFetcher == null ? null : results.last;
        final ok = results.any((l) => l != null);
        final old = _entries[key];
        _entries[key] = _Entry(
          _now().millisecondsSinceEpoch,
          ok,
          {
            ...?old?.n, // lo aprendido por co-escucha no se pierde
            for (final l in neighbors)
              for (final a in l ?? const <String>[])
                if (coherenceNorm(a).isNotEmpty &&
                    coherenceNorm(a) != key &&
                    !isGenericArtistName(a))
                  coherenceNorm(a),
          },
          [for (final g in tags ?? old?.g ?? const <String>[]) g.toLowerCase()],
        );
        if (done) _save();
      } finally {
        _inflight.remove(key);
      }
    }

    try {
      await Future.wait([
        for (final e in todo.entries) fetch(e.key, e.value),
      ]).timeout(budget);
    } on TimeoutException {
      // Sin esperar más: lo que llegue tarde se guarda al llegar.
    }
    done = true;
    _save();
  }

  /// Artistas que salen al menos dos veces en la radio de [seed] pasan a ser
  /// sus vecinos. Nunca quita vecinos.
  void learnCoListened(String seed, Iterable<String> artists) {
    final key = coherenceNorm(seed);
    if (key.isEmpty) return;
    final counts = <String, int>{};
    for (final a in artists) {
      final n = coherenceNorm(a);
      if (n.isNotEmpty && n != key && !isGenericArtistName(n)) {
        counts.update(n, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final learned = {
      for (final e in counts.entries)
        if (e.value >= 2) e.key,
    };
    if (learned.isEmpty) return;
    final entry = _entries[key];
    if (entry != null) {
      if (entry.n.containsAll(learned)) return;
      entry.n = {...entry.n, ...learned};
    } else {
      _entries[key] = _Entry(
        _now().millisecondsSinceEpoch,
        false,
        learned,
        const [],
        fetched: false,
      );
    }
    _save();
  }
}
