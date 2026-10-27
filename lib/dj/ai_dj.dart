import 'dart:math' as math;
import 'dart:typed_data';

import '../core/models.dart';
import 'artist_graph.dart';
import 'coherence.dart';
import 'recommendations.dart';
import 'suggestions_api.dart' show djCoherenceWeight, djDecade;

/// Local taste model: feature-hashed track vectors, a time-decayed profile
/// built from observed signals, and an MMR ranker. Pure Dart, no network.
const djVectorDims = 256;
const djUpcomingTarget = 20;
const djRefillThreshold = 5;
const djMaxEvents = 500;
const djSearchesPerRefill = 2;

// Weights of the ranking score (documented in docs/dj.md).
const djTasteWeight = 0.55;
const djPriorWeight = 0.25;
const djContinuityWeight = 0.20;
const djRecentPenalty = 0.35;
const djSkippedArtistPenalty = 0.30;
const djMmrLambda = 0.7;

/// Ajustes del usuario: diversidad = 1 - lambda de MMR (0 = solo relevancia,
/// por defecto 0,3 = comportamiento histórico) y enfriamiento de artistas.
const djDefaultDiversity = 1 - djMmrLambda;
const djMaxDiversity = 0.8;

/// Afinidad 0-1 de una pista con el perfil: `relevancia / máximo posible`.
/// El máximo suma solo los términos presentes (gusto siempre; prior si se da
/// [prior]; continuidad si hay [current]), así que 1 = coincidencia perfecta.
/// Se recorta a [0, 1]; con perfil vacío devuelve null (no hay gustos).
double? djAffinity({
  required List<double> profile,
  required Track track,
  Track? current,
  double? prior,
  double bonus = 0,
}) {
  if (profile.every((v) => v == 0)) return null;
  final vector = embedDjTrack(track);
  var score = djTasteWeight * djCosine(profile, vector) + bonus;
  var max = djTasteWeight;
  if (prior != null) {
    score += djPriorWeight * prior;
    max += djPriorWeight;
  }
  if (current != null) {
    score += djContinuityWeight * djCosine(embedDjTrack(current), vector);
    max += djContinuityWeight;
  }
  return (score / max).clamp(0.0, 1.0);
}

const _noiseTokens = {
  'official',
  'oficial',
  'video',
  'videoclip',
  'audio',
  'lyrics',
  'lyric',
  'letra',
  'letras',
  'hd',
  'hq',
  '4k',
  'remastered',
  'remaster',
  'visualizer',
  'mv',
  'clip',
  'full',
  'version',
  'feat',
  'ft',
  'featuring',
  'prod',
  'the',
  'el',
  'la',
  'los',
  'las',
  'de',
  'del',
  'y',
  'and',
  'of',
  'en',
  'con',
  'with',
  'music',
  'topic',
};

/// Number of tracks the DJ should append: refill below [djRefillThreshold]
/// upcoming tracks (or when [force]d) up to [djUpcomingTarget].
int djRefillCount(int upcoming, {bool force = false}) =>
    force || upcoming < djRefillThreshold
    ? math.max(0, djUpcomingTarget - upcoming)
    : 0;

List<String> djArtists(String artist) => artist
    .toLowerCase()
    .split(
      RegExp(
        r'\s*(?:,|&|;|\s\+\s|\s/\s|\s+x\s+|\bfeat\.?|\bft\.?|\bfeaturing\b)\s*',
      ),
    )
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toSet()
    .toList();

String djPrimaryArtist(Track track) =>
    djArtists(track.artist).firstOrNull ?? '';

/// Weighted sparse features of a track before hashing.
Map<String, double> djTrackFeatures(Track track) {
  final features = <String, double>{};
  void add(String key, double weight) =>
      features.update(key, (value) => value + weight, ifAbsent: () => weight);
  final artists = djArtists(track.artist);
  for (var i = 0; i < artists.length; i++) {
    add('a:${artists[i]}', i == 0 ? 1.0 : 0.7);
  }
  final title = track.title.toLowerCase();
  for (final match in RegExp(
    r'[(\[](?:feat\.?|ft\.?|featuring)\s+([^)\]]+)[)\]]',
  ).allMatches(title)) {
    for (final artist in djArtists(match.group(1)!)) {
      if (!artists.contains(artist)) add('a:$artist', 0.7);
    }
  }
  final album = track.album?.trim().toLowerCase() ?? '';
  if (album.isNotEmpty && album != title) add('al:$album', 0.5);
  for (final genre in track.genres) {
    final value = genre.trim().toLowerCase();
    if (value.isNotEmpty) add('g:$value', 0.8);
  }
  final artistTokens = artists.expand((a) => a.split(RegExp(r'\s+'))).toSet();
  final tokens = title
      .replaceAll(RegExp(r'[(\[](?:feat|ft|featuring)[^)\]]*[)\]]'), ' ')
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where(
        (token) =>
            token.length >= 2 &&
            !_noiseTokens.contains(token) &&
            !artistTokens.contains(token),
      )
      .toSet();
  for (final token in tokens) {
    add('t:$token', 0.25);
  }
  return features;
}

// FNV-1a 32-bit: stable across runs, unlike String.hashCode.
int _fnv1a(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

Float32List djHashFeatures(Map<String, double> features) {
  final vector = Float32List(djVectorDims);
  for (final entry in features.entries) {
    final hash = _fnv1a(entry.key);
    final sign = hash & 0x80000000 == 0 ? 1.0 : -1.0;
    vector[hash % djVectorDims] += sign * entry.value;
  }
  return djNormalize(vector);
}

Float32List embedDjTrack(Track track) => djHashFeatures(djTrackFeatures(track));

Float32List djNormalize(Float32List vector) {
  var norm = 0.0;
  for (final value in vector) {
    norm += value * value;
  }
  if (norm == 0) return vector;
  norm = math.sqrt(norm);
  for (var i = 0; i < vector.length; i++) {
    vector[i] /= norm;
  }
  return vector;
}

double djCosine(List<double> a, List<double> b) {
  if (a.length != b.length) return 0;
  var dot = 0.0, na = 0.0, nb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return na == 0 || nb == 0 ? 0 : dot / math.sqrt(na * nb);
}

enum DjSignal { complete, skip }

/// One observed playback outcome. Stored compactly as
/// `kind|millis|trackId|artist` (old events have no artist).
class DjEvent {
  const DjEvent(this.signal, this.trackId, this.at, {this.artist = ''});
  final DjSignal signal;
  final String trackId;
  final DateTime at;

  /// Artista principal (para saltos de pistas que no están en la biblioteca).
  final String artist;

  String encode() =>
      '${signal == DjSignal.skip ? 's' : 'c'}|${at.millisecondsSinceEpoch}|$trackId|${artist.replaceAll('|', '')}';

  static DjEvent? decode(String value) {
    final parts = value.split('|');
    if (parts.length < 3 || (parts[0] != 's' && parts[0] != 'c')) return null;
    final millis = int.tryParse(parts[1]);
    // El artista (sin «|») va siempre al final; el id puede llevar «|».
    // Formato antiguo: exactamente 3 partes, sin artista.
    final legacy = parts.length == 3;
    final id = parts.sublist(2, legacy ? 3 : parts.length - 1).join('|');
    if (millis == null || id.isEmpty) return null;
    return DjEvent(
      parts[0] == 's' ? DjSignal.skip : DjSignal.complete,
      id,
      DateTime.fromMillisecondsSinceEpoch(millis),
      artist: legacy ? '' : parts.last,
    );
  }
}

/// Skip = advanced manually before 30 s or 30% of the track.
bool djIsSkip(Duration position, Duration duration) =>
    position < const Duration(seconds: 30) ||
    (duration > Duration.zero &&
        position.inMilliseconds < duration.inMilliseconds * 0.3);

class TasteProfile {
  const TasteProfile(this.vector, this.features);
  final Float32List vector;

  /// Unhashed feature weights, used to build discovery queries.
  final Map<String, double> features;
  bool get isEmpty => vector.every((value) => value == 0);
}

/// Time-decayed weighted sum of real signals. Favorites and playlists have
/// no timestamp, so they are not decayed; events decay with [halfLife].
TasteProfile buildTasteProfile({
  required List<Track> favorites,
  required List<Track> playlistTracks,
  required List<Track> history,
  required List<DjEvent> events,
  required Map<String, Track> known,
  required DateTime now,
  Duration halfLife = const Duration(days: 14),
}) {
  final vector = Float32List(djVectorDims);
  final features = <String, double>{};
  void add(Track track, double weight) {
    final embedding = embedDjTrack(track);
    for (var i = 0; i < djVectorDims; i++) {
      vector[i] += weight * embedding[i];
    }
    djTrackFeatures(track).forEach(
      (key, value) => features.update(
        key,
        (sum) => sum + weight * value,
        ifAbsent: () => weight * value,
      ),
    );
  }

  for (final track in favorites) {
    add(track, 3.0);
  }
  for (final track in playlistTracks) {
    add(track, 1.5);
  }
  for (var i = 0; i < history.length; i++) {
    add(history[i], 0.8 / (1 + i / 4));
  }
  for (final event in events) {
    final track = known[event.trackId];
    if (track == null) continue;
    final age = now.difference(event.at).inMinutes.clamp(0, 1 << 30);
    final decay = math.pow(0.5, age / halfLife.inMinutes).toDouble();
    add(track, (event.signal == DjSignal.skip ? -1.5 : 1.0) * decay);
  }
  return TasteProfile(djNormalize(vector), features);
}

typedef DjQuery = ({String query, String reason});

/// Discovery searches built from the strongest positive profile features,
/// interleaving artists, genres and albums; [used] keeps refills varied.
/// [neighbors] (artistas afines) van primero si no son ya del perfil ni de
/// [skippedArtists].
List<DjQuery> djDiscoveryQueries(
  TasteProfile profile, {
  Set<String> used = const {},
  int max = djSearchesPerRefill,
  Track? fallback,
  List<String> neighbors = const [],
  Set<String> skippedArtists = const {},
}) {
  List<String> top(String prefix, int count) {
    final entries =
        profile.features.entries
            .where((e) => e.key.startsWith(prefix) && e.value > 0)
            .toList()
          ..sort((a, b) {
            final order = b.value.compareTo(a.value);
            return order != 0 ? order : a.key.compareTo(b.key);
          });
    return entries
        .take(count)
        .map((e) => e.key.substring(prefix.length))
        .toList();
  }

  final artists = top('a:', 6), genres = top('g:', 3), albums = top('al:', 2);
  final options = <DjQuery>[];
  final known = {
    for (final k in profile.features.keys)
      if (k.startsWith('a:')) coherenceNorm(k.substring(2)),
    for (final a in skippedArtists) coherenceNorm(a),
  };
  for (final n in neighbors) {
    if (n.isEmpty || known.contains(coherenceNorm(n))) continue;
    options.add((query: '$n songs', reason: 'Artista afín a lo que escuchas'));
  }
  for (var i = 0; i < 6; i++) {
    if (i < artists.length) {
      options.add((
        query: '${artists[i]} songs',
        reason: 'Porque escuchas a ${artists[i]}',
      ));
    }
    if (i < genres.length) {
      options.add((
        query: '${genres[i]} music',
        reason: 'Por tu gusto por ${genres[i]}',
      ));
    }
    if (i < albums.length) {
      options.add((query: albums[i], reason: 'Parecido a tus favoritos'));
    }
  }
  if (options.isEmpty && fallback != null && fallback.artist.isNotEmpty) {
    options.add((
      query: '${fallback.artist} songs',
      reason: 'Porque escuchaste ${fallback.title}',
    ));
  }
  return options.where((o) => !used.contains(o.query)).take(max).toList();
}

/// De dónde sale un candidato; la mezcla de fuentes reparte cuota por cubo.
enum RecBucket { similar, adjacent, discovery, radio, lastfm }

class DjCandidate {
  const DjCandidate(
    this.track,
    this.reason, {
    this.prior = 0,
    this.bucket = RecBucket.similar,
  });
  final Track track;
  final String reason;
  final RecBucket bucket;

  /// Source rank prior in [0, 1]; earlier in its list is better.
  final double prior;
}

/// Reparto determinista de la cuota: true cuando el siguiente puesto debe ser
/// una pista ya oída (la tanda empieza por una nueva y alterna hasta [share]).
bool djWantHeard(int heardSoFar, int chosenSoFar, double share) =>
    heardSoFar < (share * (chosenSoFar + 1)).round();

/// Ranks candidates by taste, continuity and source prior, minus penalties,
/// then picks greedily with MMR (λ = [lambda]) under an artist cooldown:
/// never the same artist back-to-back and at most two per ten tracks.
/// Con [coherence], lo no relacionado con la semilla (bajo
/// [djRelatedThreshold]) solo entra si falta relacionado, y la coherencia
/// suma a la relevancia; [graph] aporta etiquetas de género por artista.
List<TrackRecommendation> rankDjCandidates({
  required List<DjCandidate> candidates,
  required List<double> profile,
  required int limit,
  Track? current,
  Set<String> blockedKeys = const {},
  Set<String> recentKeys = const {},
  Set<String> skippedArtists = const {},
  List<Track> queueTail = const [],
  DjFilters filters = const DjFilters(),
  double lambda = djMmrLambda,
  bool artistCooldown = true, // false: permite el mismo artista seguido
  double Function(Track track)? adjust, // sesgo de modo (dj_modes.dart)
  Set<String> heardKeys = const {}, // claves de lo ya oído (biblioteca)
  double? heardShare, // cuota de ya oídas por tanda; null = sin cuota
  CoherenceContext? coherence,
  ArtistGraph? graph,
}) {
  if (limit <= 0) return const [];
  final cohOf = <DjCandidate, CoherenceResult>{};
  final currentVector = current == null ? null : embedDjTrack(current);
  final pool =
      <({DjCandidate candidate, Float32List vector, double relevance})>[];
  final seen = <String>{...blockedKeys};
  final ordered = [...candidates]..sort((a, b) => b.prior.compareTo(a.prior));
  for (final candidate in ordered) {
    final track = candidate.track;
    final keys = recommendationTrackKeys(track);
    if (keys.any(seen.contains) ||
        !filters.permits(track) ||
        track.isPendingSpotifyMatch ||
        !(track.isLocal || track.pageUrl != null)) {
      continue;
    }
    seen.addAll(keys);
    final vector = embedDjTrack(track);
    final coh = coherence == null || coherence.isEmpty
        ? null
        : scoreCoherence(
            track,
            coherence,
            decade: djDecade(track),
            genres: graph?.tagsOf(djPrimaryArtist(track)) ?? const [],
          );
    final relevance =
        djTasteWeight * djCosine(profile, vector) +
        djPriorWeight * candidate.prior +
        (currentVector == null
            ? 0
            : djContinuityWeight * djCosine(currentVector, vector)) -
        -(adjust?.call(track) ?? 0) -
        (keys.any(recentKeys.contains) ? djRecentPenalty : 0) -
        (skippedArtists.contains(djPrimaryArtist(track))
            ? djSkippedArtistPenalty
            : 0) +
        (coh == null ? 0 : djCoherenceWeight * (coh.score - 0.5));
    pool.add((candidate: candidate, vector: vector, relevance: relevance));
    if (coh != null) cohOf[candidate] = coh;
  }
  if (cohOf.isNotEmpty && pool.isNotEmpty) {
    // Misma puerta que el motor: relacionado primero, lo demás para completar.
    final gate = coherenceGate(
      pool,
      result: (p) => cohOf[p.candidate]!,
      artist: (p) => djPrimaryArtist(p.candidate.track),
      limit: limit,
      // El enfriamiento admite dos por cada diez pistas.
      artistCap: artistCooldown ? math.max(1, (limit * 0.2).ceil()) : limit,
    );
    pool
      ..clear()
      ..addAll(gate.kept);
  }

  final artistsSoFar = [
    if (current != null && queueTail.isEmpty) djPrimaryArtist(current),
    ...queueTail.map(djPrimaryArtist),
  ];
  bool allowed(String artist) {
    if (artist.isEmpty || !artistCooldown) return true;
    if (artistsSoFar.isNotEmpty && artistsSoFar.last == artist) return false;
    final window = artistsSoFar.length > 9
        ? artistsSoFar.sublist(artistsSoFar.length - 9)
        : artistsSoFar;
    return window.where((a) => a == artist).length < 2;
  }

  bool heardOf(DjCandidate c) =>
      recommendationTrackKeys(c.track).any(heardKeys.contains);
  var heardPicked = 0;
  final picked =
      <({DjCandidate candidate, Float32List vector, double relevance})>[];
  while (picked.length < limit && pool.isNotEmpty) {
    // One relaxed pick per batch when every artist is cooling down, so
    // single-artist libraries still continue (slowly) instead of stopping.
    final relaxed =
        picked.isEmpty &&
        !pool.any((c) => allowed(djPrimaryArtist(c.candidate.track)));
    // Con cuota se busca primero en la clase que toca; si no hay, en cualquiera.
    final wantHeard = heardShare == null
        ? null
        : djWantHeard(heardPicked, picked.length, heardShare);
    var bestIndex = -1;
    for (final only in [?wantHeard, null]) {
      var bestScore = double.negativeInfinity;
      for (var i = 0; i < pool.length; i++) {
        if (!relaxed && !allowed(djPrimaryArtist(pool[i].candidate.track))) {
          continue;
        }
        if (only != null && heardOf(pool[i].candidate) != only) continue;
        var redundancy = 0.0;
        for (final chosen in picked) {
          redundancy = math.max(
            redundancy,
            djCosine(pool[i].vector, chosen.vector),
          );
        }
        final score = lambda * pool[i].relevance - (1 - lambda) * redundancy;
        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }
      if (bestIndex >= 0) break;
    }
    if (bestIndex < 0) break;
    final best = pool.removeAt(bestIndex);
    if (heardOf(best.candidate)) heardPicked++;
    picked.add((
      candidate: best.candidate,
      vector: best.vector,
      relevance: best.relevance,
    ));
    artistsSoFar.add(djPrimaryArtist(best.candidate.track));
  }
  return [
    for (final pick in picked)
      TrackRecommendation(
        track: pick.candidate.track,
        reason: pick.candidate.reason,
        // Relevancia (suma ponderada, máximo teórico 1) recortada a 0-1.
        affinity: pick.relevance.clamp(0.0, 1.0),
      ),
  ];
}
