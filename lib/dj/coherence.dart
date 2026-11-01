// Coherencia de un candidato con los gustos/semilla: compara el ARTISTA, nunca
// el título. Mismo artista > colaboración > artista afín (vecindario) > mismo
// género > sin relación. El rechazo duro solo es para el caso inequívoco
// (artista distinto, sin género ni vecindario en común, y el nombre del
// artista semilla aparece únicamente en el título) y el llamador jamás vacía
// el pool con él.

import '../core/models.dart';
import 'ai_dj.dart';

/// Por debajo de esto un candidato no se considera relacionado con la semilla
/// (mismo artista, colaboración, artista afín o mismo género sí lo están).
const djRelatedThreshold = 0.55;

const _accents = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Nombre normalizado: minúsculas, sin acentos ni puntuación, sin « - Topic».
String coherenceNorm(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    b.write(_accents[c] ?? c);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'\s*-\s*topic$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

/// Artistas de la pista (principal + colaboradores + «feat.» del título).
Set<String> coherenceArtists(Track t) {
  final out = <String>{};
  void add(String raw) {
    for (final a in djArtists(raw)) {
      final n = coherenceNorm(a);
      if (n.isNotEmpty) out.add(n);
    }
  }

  add(t.artist);
  for (final m in RegExp(
    r'[(\[](?:feat\.?|ft\.?|featuring)\s+([^)\]]+)[)\]]',
    caseSensitive: false,
  ).allMatches(t.title)) {
    add(m.group(1)!);
  }
  return out;
}

class CoherenceContext {
  CoherenceContext({
    Iterable<String> artists = const [],
    Iterable<String> genres = const [],
    Iterable<String> neighbors = const [],
    Map<String, Iterable<String>> aliases = const {},
    this.decade,
  }) : artists = {
         for (final a in artists)
           if (coherenceNorm(a).isNotEmpty) coherenceNorm(a),
       },
       genres = {for (final g in genres) g.trim().toLowerCase()},
       neighbors = {
         for (final a in neighbors)
           if (coherenceNorm(a).isNotEmpty) coherenceNorm(a),
       },
       aliases = {
         for (final e in aliases.entries)
           coherenceNorm(e.key): {for (final a in e.value) coherenceNorm(a)},
       };

  /// Artistas de la semilla/gustos (normalizados).
  final Set<String> artists;
  final Set<String> genres;

  /// Artistas afines a la semilla (vecindario, normalizados).
  final Set<String> neighbors;

  /// Alias conocidos: nombre → otros nombres del mismo artista (opcional).
  final Map<String, Set<String>> aliases;
  final int? decade;
  bool get isEmpty => artists.isEmpty && genres.isEmpty && neighbors.isEmpty;

  bool knows(String artist) =>
      artists.contains(artist) ||
      (aliases[artist]?.any(artists.contains) ?? false) ||
      aliases.entries.any(
        (e) => artists.contains(e.key) && e.value.contains(artist),
      );
}

class CoherenceResult {
  const CoherenceResult(this.score, this.reason, {this.hardReject = false});

  /// 0..1 (0,5 = neutro, sin información).
  final double score;
  final String reason;
  final bool hardReject;
}

CoherenceResult scoreCoherence(
  Track t,
  CoherenceContext ctx, {
  int? decade,
  List<String> genres = const [],
}) {
  if (ctx.isEmpty) return const CoherenceResult(0.5, 'Sin referencia');
  final artists = coherenceArtists(t);
  final primary = artists.isEmpty
      ? ''
      : coherenceNorm(djArtists(t.artist).firstOrNull ?? '');
  final isTopic = t.artist.toLowerCase().contains('- topic');
  final topic = isTopic ? 0.03 : 0.0;
  if (primary.isNotEmpty && ctx.knows(primary)) {
    return CoherenceResult(0.95 + topic, 'Mismo artista');
  }
  if (artists.any(ctx.knows)) {
    return CoherenceResult(0.85 + topic, 'Colaboración con un artista tuyo');
  }
  final cg = {
    for (final g in [...t.genres, ...genres]) g.trim().toLowerCase(),
  };
  final sharedGenre = cg.any(ctx.genres.contains);
  final neighbor = artists.any(ctx.neighbors.contains);
  var score = neighbor
      ? 0.75
      : sharedGenre
      ? 0.60
      : 0.25;
  if (decade != null && ctx.decade != null) {
    score += (decade - ctx.decade!).abs() <= 10 ? 0.05 : -0.05;
  }
  // Coincidencia solo en el título: el nombre de un artista de la semilla
  // aparece como palabras del título, pero el artista es otro.
  final title = ' ${coherenceNorm(t.title)} ';
  final named = ctx.artists.any((a) => a.length >= 2 && title.contains(' $a '));
  final related = sharedGenre || neighbor;
  if (named) {
    return CoherenceResult(
      related ? score - 0.2 : 0.05,
      'Solo el título coincide con un artista tuyo',
      hardReject: !related,
    );
  }
  return CoherenceResult(
    score.clamp(0.0, 1.0),
    neighbor
        ? 'Artista afín'
        : sharedGenre
        ? 'Mismo género'
        : 'Artista sin relación conocida',
  );
}

/// Puerta de coherencia común al motor y al DJ. Lo relacionado (puntuación
/// >= [djRelatedThreshold]) entra siempre; lo demás, sin rechazos duros, solo
/// para completar [limit] puestos. Cada artista cuenta como mucho [artistCap]
/// puestos (la diversidad posterior no admite más); en el corte entran
/// exactamente los necesarios (empates por posición original). Nunca devuelve vacío si [items] no lo estaba.
({List<T> kept, bool relaxed}) coherenceGate<T>(
  List<T> items, {
  required CoherenceResult Function(T item) result,
  required String Function(T item) artist,
  required int limit,
  required int artistCap,
  Map<String, int> used = const {}, // apariciones previas por artista
}) {
  final related = <T>[], rest = <T>[];
  for (final i in items) {
    final r = result(i);
    if (r.score >= djRelatedThreshold) {
      related.add(i);
    } else if (!r.hardReject) {
      rest.add(i);
    }
  }
  final perArtist = <String, int>{...used};
  var capacity = 0;
  for (final i in related) {
    final a = artist(i);
    final n = perArtist.update(a, (n) => n + 1, ifAbsent: () => 1);
    if (a.isEmpty || n <= artistCap) capacity++;
  }
  final need = limit - capacity;
  var extra = <T>[];
  if (need > 0 && rest.isNotEmpty) {
    final idx = List.generate(rest.length, (k) => k)
      ..sort((a, b) {
        final c = result(rest[b]).score.compareTo(result(rest[a]).score);
        return c != 0 ? c : a.compareTo(b);
      });
    extra = [for (final k in idx.take(need)) rest[k]];
  }
  final keep = {...related, ...extra};
  if (keep.isEmpty) return (kept: [...items], relaxed: items.isNotEmpty);
  return (
    kept: [
      for (final i in items)
        if (keep.contains(i)) i,
    ],
    relaxed: extra.isNotEmpty,
  );
}

/// Reutilizable por cola, DJ y Jam. Ordena (estable) de más a menos coherente
/// SIN descartar nada salvo rechazos duros y solo si quedan al menos [keep]
/// candidatos; nunca devuelve vacío si la entrada no lo estaba.
class CoherenceFilter {
  static List<({DjCandidate candidate, CoherenceResult result})> rank(
    List<DjCandidate> candidates,
    CoherenceContext ctx, {
    int keep = 1,
  }) {
    final scored = [
      for (final c in candidates)
        (candidate: c, result: scoreCoherence(c.track, ctx)),
    ];
    final kept = [
      for (final s in scored)
        if (!s.result.hardReject) s,
    ];
    final out = kept.length >= keep ? kept : scored;
    return [...out]..sort((a, b) => b.result.score.compareTo(a.result.score));
  }
}
