import 'dart:math' as math;
import 'dart:typed_data';

import '../bridge/api/dj.dart' as rust;
import '../core/models.dart';
import 'artist_graph.dart';
import 'coherence.dart';
import 'recommendations.dart';
import 'suggestions_api.dart' show djCoherenceWeight, djDecade;

rust.DjTrack _rustTrack(Track track) => rust.DjTrack(
  artist: track.artist,
  title: track.title,
  album: track.album,
  genres: track.genres,
);

/// Local taste model: feature-hashed track vectors, a time-decayed profile
/// built from observed signals, and an MMR ranker. El cálculo vive en
/// `rust/crates/aurora_ai_dj`; aquí quedan los envoltorios y las constantes.
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

/// Number of tracks the DJ should append: refill below [djRefillThreshold]
/// upcoming tracks (or when [force]d) up to [djUpcomingTarget].
int djRefillCount(int upcoming, {bool force = false}) =>
    force || upcoming < djRefillThreshold
    ? math.max(0, djUpcomingTarget - upcoming)
    : 0;

List<String> djArtists(String artist) => rust.djArtists(artist: artist);

String djPrimaryArtist(Track track) =>
    djArtists(track.artist).firstOrNull ?? '';

/// Weighted sparse features of a track before hashing (insertion order kept).
Map<String, double> djTrackFeatures(Track track) => {
  for (final feature in rust.djTrackFeatures(track: _rustTrack(track)))
    feature.key: feature.weight,
};

Float32List djHashFeatures(Map<String, double> features) => rust.djHashFeatures(
  features: [
    for (final entry in features.entries)
      rust.DjFeature(key: entry.key, weight: entry.value),
  ],
);

Float32List embedDjTrack(Track track) =>
    rust.djEmbedTrack(track: _rustTrack(track));

// shortcut: copia Dart; una llamada FFI por par cuesta más que el bucle y suggestions_api la usa en bucles calientes, mover con aurora_core en la fase 7

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
  final resolved = <rust.DjEventInput>[];
  for (final event in events) {
    final track = known[event.trackId];
    if (track == null) continue;
    resolved.add(
      rust.DjEventInput(
        track: _rustTrack(track),
        skip: event.signal == DjSignal.skip,
        atMs: event.at.millisecondsSinceEpoch,
      ),
    );
  }
  final profile = rust.djBuildTasteProfile(
    favorites: [for (final track in favorites) _rustTrack(track)],
    playlistTracks: [for (final track in playlistTracks) _rustTrack(track)],
    history: [for (final track in history) _rustTrack(track)],
    events: resolved,
    nowMs: now.millisecondsSinceEpoch,
    halfLifeMinutes: halfLife.inMinutes,
  );
  return TasteProfile(profile.vector, {
    for (final feature in profile.features) feature.key: feature.weight,
  });
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
    if (n.isEmpty ||
        isGenericArtistName(n) ||
        known.contains(coherenceNorm(n))) {
      continue;
    }
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
  // Dart conserva los filtros que dependen de la app y la puerta de coherencia
  // (coherence.dart, fase 7); Rust deduplica por clave, puntúa y elige (MMR).
  final permitted = <DjCandidate>[
    for (final candidate in candidates)
      if (filters.permits(candidate.track) &&
          !candidate.track.isPendingSpotifyMatch &&
          (candidate.track.isLocal || candidate.track.pageUrl != null))
        candidate,
  ];
  final keysOf = {
    for (final candidate in permitted)
      candidate: recommendationTrackKeys(candidate.track),
  };
  var chosen = permitted;
  final bonus = <DjCandidate, double>{};
  if (coherence != null && !coherence.isEmpty && permitted.isNotEmpty) {
    // Misma deduplicación previa que hace Rust: prior descendente y claves ya vistas.
    final order = List.generate(permitted.length, (i) => i)
      ..sort((a, b) {
        final byPrior = permitted[b].prior.compareTo(permitted[a].prior);
        return byPrior != 0 ? byPrior : a.compareTo(b);
      });
    final seen = <String>{...blockedKeys};
    final pool = <DjCandidate>[];
    final cohOf = <DjCandidate, CoherenceResult>{};
    for (final index in order) {
      final candidate = permitted[index];
      final keys = keysOf[candidate]!;
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      pool.add(candidate);
      cohOf[candidate] = scoreCoherence(
        candidate.track,
        coherence,
        decade: djDecade(candidate.track),
        genres: graph?.tagsOf(djPrimaryArtist(candidate.track)) ?? const [],
      );
    }
    final artistsSoFar = [
      if (current != null && queueTail.isEmpty) djPrimaryArtist(current),
      ...queueTail.map(djPrimaryArtist),
    ];
    final window = artistsSoFar.length > 9
        ? artistsSoFar.sublist(artistsSoFar.length - 9)
        : artistsSoFar;
    // Misma puerta que el motor: relacionado primero, lo demás para completar.
    final gate = coherenceGate(
      pool,
      result: (candidate) => cohOf[candidate]!,
      artist: (candidate) => djPrimaryArtist(candidate.track),
      limit: limit,
      lastResort: (candidate) => candidate.bucket == RecBucket.discovery,
      // El enfriamiento admite dos por cada diez pistas.
      artistCap: artistCooldown ? math.max(1, (limit * 0.2).ceil()) : limit,
      // Mismas apariciones que bloquea allowed(): ventana de las últimas 9.
      used: artistCooldown
          ? {
              for (final a in window.toSet())
                a: window.where((x) => x == a).length,
            }
          : const {},
    );
    chosen = gate.kept;
    for (final candidate in chosen) {
      bonus[candidate] = djCoherenceWeight * (cohOf[candidate]!.score - 0.5);
    }
  }
  final picks = rust.djRankCandidates(
    request: rust.DjRankRequest(
      candidates: [
        for (final candidate in chosen)
          rust.DjRankCandidate(
            track: _rustTrack(candidate.track),
            prior: candidate.prior,
            keys: keysOf[candidate]!.toList(),
            adjust: adjust?.call(candidate.track) ?? 0.0,
            coherenceBonus: bonus[candidate] ?? 0.0,
          ),
      ],
      profile: profile is Float64List ? profile : Float64List.fromList(profile),
      limit: limit,
      current: current == null ? null : _rustTrack(current),
      blockedKeys: blockedKeys.toList(),
      recentKeys: recentKeys.toList(),
      skippedArtists: skippedArtists.toList(),
      queueTailArtists: [for (final track in queueTail) track.artist],
      lambda: lambda,
      artistCooldown: artistCooldown,
      heardKeys: heardKeys.toList(),
      heardShare: heardShare,
    ),
  );
  return [
    for (final pick in picks)
      TrackRecommendation(
        track: chosen[pick.index].track,
        reason: chosen[pick.index].reason,
        // Relevancia (suma ponderada, máximo teórico 1) recortada a 0-1.
        affinity: pick.affinity,
      ),
  ];
}
