// API estable de sugerencias de Aurora (consumida por la JAM y por el DJ).
//
//   final api = SuggestionsApi(sources: [...]);          // todo opcional
//   Future<List<Suggestion>> api.getSuggestions(SessionContext ctx)
//
// SessionContext:
//   participants   List<ParticipantTaste>  perfiles (1 = personal, N = Jam);
//                                          el perfil NUNCA sale del dispositivo
//   mode / current / queueTail / recentKeys / skippedArtists / favoriteArtists
//   listenedArtists  artistas escuchados hace poco (semilla de coherencia)
//   library        candidatos locales (relleno y respaldo sin red)
//   extraCandidates  candidatos ya traídos por el llamador (p. ej. radio de
//                  YouTube de la pista actual); entran en la mezcla
//   seed           semilla de exploración (null = distinta en cada sesión)
//   remember       false = vista previa que no consume la memoria
//   filters, limit (se admiten lotes grandes, p. ej. 30), now
//
// Candidatos: `sources` (por cubo: similar 50 %, adjacent 30 %, discovery 5 %,
// configurables en `mix`) + `fetchCandidates` (compat.) +
// `extraCandidates`. Si todo falla se usa la última lista de la misma sesión y
// después `library`; nunca se devuelve vacío mientras quede algo que ofrecer.
//
// Coherencia: vecindario de artistas (ArtistGraph) y géneros de la semilla;
// lo no relacionado solo entra si no hay bastante relacionado.
// Ranking: relevancia con el perfil + novedad (memoria anti-repetición de 300
// pistas / 7 días persistida) + diversidad (MMR, tope por artista, género y
// década) + exploración (ε-greedy con muestreo ponderado). Si el pool se agota
// la ventana de repetición se relaja por tramos en vez de quedarse vacío.
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:typed_data';

import '../core/models.dart';
import 'ai_dj.dart';
import 'artist_graph.dart';
import 'coherence.dart';
import 'dj_modes.dart';
import 'recommendations.dart';
import 'reco_memory.dart';

/// Peso de la coherencia de artista en la relevancia.
const djCoherenceWeight = 1.2;

class ParticipantTaste {
  const ParticipantTaste(this.id, this.profile, {this.weight = 1});
  final String id;
  final TasteProfile profile;
  final double weight;
}

class SessionContext {
  const SessionContext({
    required this.participants,
    this.mode = DjMode.discover,
    this.current,
    this.queueTail = const [],
    this.recentKeys = const {},
    this.skippedArtists = const {},
    this.favoriteArtists = const {},
    this.listenedArtists = const {},
    this.library = const [],
    this.extraCandidates = const [],
    this.filters = const DjFilters(),
    this.limit = 10,
    this.now,
    this.seed,
    this.remember = true,
    this.heardShare,
  });
  final List<ParticipantTaste> participants;
  final DjMode mode;
  final Track? current;
  final List<Track> queueTail;
  final Set<String> recentKeys, skippedArtists, favoriteArtists;

  /// Artistas escuchados hace poco (entran en la semilla de coherencia).
  final Set<String> listenedArtists;
  final List<Track> library;
  final List<DjCandidate> extraCandidates;
  final DjFilters filters;
  final int limit;
  final DateTime? now;
  final int? seed;
  final bool remember;

  /// Cuota (0..1) de pistas ya oídas por tanda; `library` define qué cuenta
  /// como oído. null = sin cuota (comportamiento de la Jam).
  final double? heardShare;
}

class Suggestion {
  const Suggestion(
    this.track,
    this.reason,
    this.comment, {
    this.forParticipant,
    this.bucket = RecBucket.similar,
    this.coherence = 0.5,
    this.coherenceReason = '',
  });
  final Track track;

  /// Coherencia de artista con la semilla/gustos (0..1, 0,5 = sin datos).
  final double coherence;
  final String coherenceReason;

  /// Razón legible en español («Porque escuchas X», «Descubrimiento»…).
  final String reason;

  /// Frase breve de transición (plantillas locales).
  final String comment;

  /// Participante al que va dirigida (turno round-robin en una Jam).
  final String? forParticipant;
  final RecBucket bucket;
}

/// Fuente de candidatos de un cubo. Debe ser tolerante a fallos: si lanza o
/// tarda más de [SuggestionsApi.sourceTimeout] (o de lo que queda de
/// [SuggestionsApi.budget]) se ignora.
class RecSource {
  const RecSource(this.bucket, this.fetch);
  final RecBucket bucket;
  final Future<List<DjCandidate>> Function(SessionContext ctx, int want) fetch;
}

const defaultRecMix = <RecBucket, double>{
  RecBucket.similar: 0.50,
  RecBucket.adjacent: 0.30,
  RecBucket.discovery: 0.05, // fuera de perfil a propósito: cuota mínima
  RecBucket.lastfm: 0.08, // cuota pequeña: el perfil local manda
  RecBucket.radio:
      0.20, // radio de YouTube del llamador: sin cuota se penalizaba
};

/// Media ponderada de perfiles (cada vector ya está normalizado, así que nadie
/// domina por tener más historial); ignora perfiles vacíos o de peso <= 0.
TasteProfile combineTasteProfiles(List<ParticipantTaste> parts) {
  final vector = Float32List(djVectorDims);
  final features = <String, double>{};
  for (final p in parts) {
    if (p.weight <= 0 || p.profile.isEmpty) continue;
    for (var i = 0; i < djVectorDims; i++) {
      vector[i] += p.weight * p.profile.vector[i];
    }
    final total = p.profile.features.values.fold<double>(
      0,
      (s, v) => s + v.abs(),
    );
    if (total == 0) continue;
    p.profile.features.forEach(
      (k, v) => features.update(
        k,
        (s) => s + p.weight * v / total,
        ifAbsent: () => p.weight * v / total,
      ),
    );
  }
  return TasteProfile(djNormalize(vector), features);
}

/// Claves de característica más fuertes del perfil con el prefijo dado
/// (`a:` artistas, `g:` géneros), de mayor a menor peso.
List<String> tasteTop(TasteProfile profile, String prefix, int count) =>
    _featureTop(profile.features, prefix, count);

List<String> _featureTop(
  Map<String, double> features,
  String prefix,
  int count,
) {
  final entries =
      features.entries
          .where((e) => e.key.startsWith(prefix) && e.value > 0)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in entries.take(count)) e.key.substring(prefix.length)];
}

/// Artistas de la semilla de mayor a menor peso: la pista actual, el perfil,
/// lo escuchado hace poco y los favoritos. La cola NO entra (evita la deriva).
List<String> _seedArtists(
  Map<String, double> features,
  Set<String> favoriteArtists,
  Set<String> listenedArtists,
  Track? current,
) => {
  if (current != null) ...coherenceArtists(current),
  ..._featureTop(features, 'a:', 12),
  ...listenedArtists,
  ...favoriteArtists,
}.toList();

/// Artistas a precalentar en el grafo antes de rankear (actual + 8 primeros).
List<String> seedGraphArtists({
  required Map<String, double> features,
  Set<String> favoriteArtists = const {},
  Set<String> listenedArtists = const {},
  Track? current,
}) => {
  if (current != null) djPrimaryArtist(current),
  ..._seedArtists(features, favoriteArtists, listenedArtists, current).take(8),
}.where((a) => a.isNotEmpty).toList();

/// Vecinos de primer salto más los artistas que aparecen en las listas de al
/// menos dos de ellos (segundo salto). Solo caché: sin red.
Set<String> _withSecondHop(ArtistGraph graph, Set<String> first) {
  final counts = <String, int>{};
  for (final n in first) {
    for (final m in graph.neighborsOf(n)) {
      counts.update(m, (c) => c + 1, ifAbsent: () => 1);
    }
  }
  return {
    ...first,
    for (final e in counts.entries)
      if (e.value >= 2) e.key,
  };
}

/// Contexto de coherencia común a cola, motor y DJ: artistas del perfil, la
/// pista actual, favoritos y lo escuchado; vecinos y etiquetas del [graph].
CoherenceContext seedCoherence({
  required Map<String, double> features,
  Set<String> favoriteArtists = const {},
  Set<String> listenedArtists = const {},
  Track? current,
  ArtistGraph? graph,
}) {
  final artists = _seedArtists(
    features,
    favoriteArtists,
    listenedArtists,
    current,
  );
  final currentArtist = current == null ? null : djPrimaryArtist(current);
  return CoherenceContext(
    artists: artists,
    neighbors: graph == null
        ? const []
        : _withSecondHop(graph, {
            for (final a in seedGraphArtists(
              features: features,
              favoriteArtists: favoriteArtists,
              listenedArtists: listenedArtists,
              current: current,
            ))
              ...graph.neighborsOf(a),
          }),
    genres: {
      ..._featureTop(features, 'g:', 6),
      ...?current?.genres,
      if (graph != null) ...[
        if (currentArtist != null) ...graph.tagsOf(currentArtist),
        for (final a in _featureTop(features, 'a:', 3)) ...graph.tagsOf(a),
      ],
    },
    decade: current == null ? null : djDecade(current),
  );
}

String _title(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
    .join(' ');

/// Década de la pista si se puede deducir (género «80s», año en álbum/título).
int? djDecade(Track t) {
  final text = '${t.genres.join(' ')} ${t.album ?? ''} ${t.title}'
      .toLowerCase();
  final year = RegExp(r'\b(19[5-9]\d|20[0-2]\d)\b').firstMatch(text);
  if (year != null) return int.parse(year.group(1)!) ~/ 10 * 10;
  final short = RegExp(r'\b(?:19|20)?([5-9]0|[0-2]0)s\b').firstMatch(text);
  if (short == null) return null;
  final d = int.parse(short.group(1)!);
  return d >= 50 ? 1900 + d : 2000 + d;
}

String? _genre(Track t) {
  for (final g in t.genres) {
    final v = g.trim().toLowerCase();
    if (v.isNotEmpty && !RegExp(r'^(19|20)?\d0s$').hasMatch(v)) return v;
  }
  return null;
}

class _Item {
  _Item(this.candidate, this.vector)
    : artist = djPrimaryArtist(candidate.track),
      genre = _genre(candidate.track),
      decade = djDecade(candidate.track);
  final DjCandidate candidate;
  final Float32List vector;
  final String artist;
  final String? genre;
  final int? decade;
  List<double> rel = const [];
  double mean = 0;
  double group = 0;
  Track get track => candidate.track;
}

/// Cuántos candidatos sobreviven a cada etapa del último `getSuggestions`.
/// `ladder` anota los escalones de relajación usados (vacío = no hizo falta).
class SuggestionsDiagnostics {
  int gathered = 0, afterFilters = 0, afterCoherence = 0, afterMemory = 0;
  int picked = 0;
  double memoryTier = 1; // 1 = ventana completa, 0 = sin filtro de memoria
  bool coherenceRelaxed = false;
  Map<RecBucket, int> gatheredByBucket = {};
  Map<RecBucket, int> pickedByBucket = {};
  final ladder = <String>[];

  @override
  String toString() =>
      'recs gathered=$gathered(${gatheredByBucket.entries.map((e) => '${e.key.name}:${e.value}').join(',')}) '
      'filters=$afterFilters coherence=$afterCoherence'
      '${coherenceRelaxed ? '(relajada)' : ''} memory=$afterMemory@$memoryTier '
      'picked=$picked ladder=$ladder';
}

class SuggestionsApi {
  SuggestionsApi({
    this.fetchCandidates,
    this.sources = const [],
    this.mix = defaultRecMix,
    RecsMemory? memory,
    this.exploration = 0.2,
    this.sourceTimeout = const Duration(seconds: 6),
    this.budget = const Duration(seconds: 9),
    math.Random? random,
    this.graph,
  }) : memory = memory ?? RecsMemory.shared,
       _random = random ?? math.Random();

  /// Vecindario de artistas y etiquetas de género (opcional).
  final ArtistGraph? graph;

  /// Compatibilidad: una sola fuente que cuenta como cubo `similar`.
  final Future<List<DjCandidate>> Function(SessionContext ctx)? fetchCandidates;
  final List<RecSource> sources;
  final Map<RecBucket, double> mix;
  final RecsMemory memory;

  /// Probabilidad ε de elegir por muestreo ponderado en vez de la mejor.
  final double exploration;
  final Duration sourceTimeout;

  /// Tiempo total de `getSuggestions` para pedir a las fuentes: la escalera
  /// («fuentes x3») solo usa lo que sobre y, si no queda, se devuelve lo ya
  /// reunido. Quien llama debe esperar algo más que esto (ranking, memoria).
  final Duration budget;
  final math.Random _random;
  final _cache = <String, List<DjCandidate>>{};

  /// Contadores del último `getSuggestions` (para depurar «se queda sin recos»).
  SuggestionsDiagnostics lastDiagnostics = SuggestionsDiagnostics();

  static String _key(SessionContext c) =>
      '${c.mode.name}|${(c.participants.map((p) => p.id).toList()..sort()).join(',')}';

  Future<List<DjCandidate>> _gather(
    SessionContext ctx, {
    int boost = 1,
    Duration? timeout,
  }) async {
    final want = math.max(ctx.limit, 10) * boost;
    Future<List<DjCandidate>> run(
      RecBucket bucket,
      Future<List<DjCandidate>> Function() call,
    ) async {
      try {
        final out = await call().timeout(timeout ?? sourceTimeout);
        return [
          for (final c in out)
            DjCandidate(c.track, c.reason, prior: c.prior, bucket: bucket),
        ];
      } catch (_) {
        return const []; // sin red o fuente caída: las demás siguen
      }
    }

    final lists = await Future.wait([
      for (final s in sources)
        run(
          s.bucket,
          () => s.fetch(
            ctx,
            math.max(4, ((mix[s.bucket] ?? 0.2) * want * 2).ceil()),
          ),
        ),
      if (fetchCandidates != null)
        run(RecBucket.similar, () => fetchCandidates!(ctx)),
    ]);
    return [...ctx.extraCandidates, for (final l in lists) ...l];
  }

  Future<List<Suggestion>> getSuggestions(SessionContext ctx) async {
    final key = _key(ctx);
    final now = ctx.now ?? DateTime.now();
    final rnd = math.Random(ctx.seed ?? _random.nextInt(1 << 30));
    final clock = Stopwatch()..start();
    await memory.ensureLoaded();
    final combined = combineTasteProfiles(ctx.participants);
    // Vecindario de la semilla, en paralelo con las fuentes y dentro del
    // presupuesto total; tiene que estar antes de rankear.
    final warming = graph?.warm(
      seedGraphArtists(
        features: combined.features,
        favoriteArtists: ctx.favoriteArtists,
        listenedArtists: ctx.listenedArtists,
        current: ctx.current,
      ),
      budget: _shorter(const Duration(seconds: 3), budget),
    );
    var candidates = await _gather(
      ctx,
      timeout: _shorter(sourceTimeout, budget - clock.elapsed),
    );
    await warming;
    if (candidates.isNotEmpty) {
      if (_cache.length >= 16) _cache.remove(_cache.keys.first);
      _cache[key] = candidates;
    } else {
      candidates = _cache[key] ?? const [];
    }
    final heardOn = (ctx.heardShare ?? 0) > 0;
    // Biblioteca como relleno: `all` la mete completa (último recurso); si no,
    // solo con poca oferta o cuota de oídas (entonces una muestra).
    List<DjCandidate> withLibrary(List<DjCandidate> base, {bool all = false}) {
      final lowSupply = base.length < ctx.limit * 2;
      if (!all && !lowSupply && !heardOn) return base;
      final inKnown = {for (final c in base) c.track.id};
      var fromLibrary = [
        for (final t in ctx.library)
          if (!inKnown.contains(t.id)) t,
      ];
      if (!all && !lowSupply) {
        fromLibrary = (fromLibrary..shuffle(rnd))
            .take(math.max(30, ctx.limit * 3))
            .toList();
      }
      return [
        ...base,
        for (final t in fromLibrary)
          DjCandidate(
            t,
            'De tu biblioteca',
            prior: 0.3,
            bucket: ctx.favoriteArtists.contains(djPrimaryArtist(t))
                ? RecBucket.similar
                : RecBucket.adjacent,
          ),
      ];
    }

    // Escalera: memoria y coherencia ya se relajan dentro de _rank; si aun así
    // faltan pistas se amplían las fuentes (x3) y luego entra toda la biblioteca.
    final diag = SuggestionsDiagnostics();
    candidates = withLibrary(candidates);
    var picks = _rank(ctx, candidates, now, rnd, diag);
    final left = budget - clock.elapsed;
    if (picks.length < ctx.limit && left > Duration.zero) {
      diag.ladder.add('fuentes x3');
      // Sin tiempo de sobra no se pierde lo ya rankeado: se sigue con ello.
      final more = await _gather(
        ctx,
        boost: 3,
        timeout: _shorter(sourceTimeout, left),
      );
      if (more.isNotEmpty) {
        _cache[key] = more;
        candidates = [...candidates, ...more];
        picks = _rank(ctx, candidates, now, rnd, diag);
      }
    }
    if (picks.length < ctx.limit) {
      diag.ladder.add('biblioteca completa');
      candidates = withLibrary(candidates, all: true);
      picks = _rank(ctx, candidates, now, rnd, diag);
    }
    lastDiagnostics = diag;
    assert(() {
      developer.log('$diag', name: 'aurora.recs');
      return true;
    }());
    if (ctx.remember) unawaited(memory.record(picks.map((p) => p.track), now));
    Track? prev = ctx.queueTail.isNotEmpty ? ctx.queueTail.last : ctx.current;
    return [
      for (var i = 0; i < picks.length; i++)
        () {
          final s = Suggestion(
            picks[i].track,
            picks[i].reason,
            djTransitionComment(
              prev,
              picks[i].track,
              ctx.mode,
              seed: i,
              now: now,
            ),
            forParticipant: picks[i].forParticipant,
            bucket: picks[i].bucket,
            coherence: picks[i].coherence,
            coherenceReason: picks[i].coherenceReason,
          );
          prev = picks[i].track;
          return s;
        }(),
    ];
  }

  static Duration _shorter(Duration a, Duration b) => a < b ? a : b;

  List<
    ({
      Track track,
      String reason,
      String? forParticipant,
      RecBucket bucket,
      double coherence,
      String coherenceReason,
    })
  >
  _rank(
    SessionContext ctx,
    List<DjCandidate> candidates,
    DateTime now,
    math.Random rnd,
    SuggestionsDiagnostics diag,
  ) {
    diag
      ..gathered = candidates.length
      ..gatheredByBucket = {}
      ..coherenceRelaxed = false
      ..memoryTier = 1;
    for (final c in candidates) {
      diag.gatheredByBucket.update(c.bucket, (n) => n + 1, ifAbsent: () => 1);
    }
    if (ctx.limit <= 0) return const [];
    final parts = [
      for (final p in ctx.participants)
        if (p.weight > 0 && !p.profile.isEmpty) p,
    ];
    final vecs = parts.isEmpty
        ? [Float32List(djVectorDims)]
        : [for (final p in parts) p.profile.vector];
    final combined = combineTasteProfiles(ctx.participants);
    final topArtist = tasteTop(combined, 'a:', 1).firstOrNull;
    final currentVector = ctx.current == null
        ? null
        : embedDjTrack(ctx.current!);

    // Lo que ya está en la cola o suena no se vuelve a ofrecer.
    final inQueue = <String>{
      for (final t in [?ctx.current, ...ctx.queueTail])
        ...recommendationTrackKeys(t),
    };
    final inQueueNames = {
      for (final t in [?ctx.current, ...ctx.queueTail]) recsTrackKey(t),
    };
    final seen = <String>{...inQueue};
    final seenNames = <String>{...inQueueNames};
    final items = <_Item>[];
    final ordered = [...candidates]..sort((a, b) => b.prior.compareTo(a.prior));
    for (final c in ordered) {
      final t = c.track;
      final keys = recommendationTrackKeys(t);
      final name = recsTrackKey(t);
      if (keys.any(seen.contains) ||
          seenNames.contains(name) ||
          !ctx.filters.permits(t) ||
          t.isPendingSpotifyMatch ||
          !(t.isLocal || t.pageUrl != null)) {
        continue;
      }
      seen.addAll(keys);
      seenNames.add(name);
      items.add(_Item(c, embedDjTrack(t)));
    }

    diag.afterFilters = items.length;

    // Coherencia de ARTISTA con la semilla (nunca por título). Puerta dura: lo
    // no relacionado (bajo djRelatedThreshold) solo entra si falta relacionado.
    final coh = seedCoherence(
      features: combined.features,
      favoriteArtists: ctx.favoriteArtists,
      listenedArtists: ctx.listenedArtists,
      current: ctx.current,
      graph: graph,
    );
    final cohOf = <_Item, CoherenceResult>{
      for (final i in items)
        i: scoreCoherence(
          i.track,
          coh,
          decade: i.decade,
          genres: graph?.tagsOf(i.artist) ?? const [],
        ),
    };
    if (!coh.isEmpty && items.isNotEmpty) {
      final gate = coherenceGate(
        items,
        result: (i) => cohOf[i]!,
        artist: (i) => i.artist,
        limit: ctx.limit,
        artistCap: math.max(1, (ctx.limit / 5).ceil()),
        lastResort: (i) => i.candidate.bucket == RecBucket.discovery,
      );
      diag.coherenceRelaxed = gate.relaxed;
      items
        ..clear()
        ..addAll(gate.kept);
    }
    diag.afterCoherence = items.length;

    // Con cuota, lo que ya está en la biblioteca cuenta como «ya oído» y se
    // enfría con una ventana corta (djHeardCooldown) en vez de la de 7 días.
    final share = ctx.heardShare ?? 0;
    final heardKeys = share > 0
        ? {for (final t in ctx.library) ...recommendationTrackKeys(t)}
        : const <String>{};
    bool heardOf(_Item i) =>
        recommendationTrackKeys(i.track).any(heardKeys.contains);
    Duration windowOf(_Item i) => heardOf(i) ? djHeardCooldown : memory.window;

    // Tramos de relajación del filtro de repetición: ventana completa,
    // mitad, cuarto y sin filtro (entonces solo pesa la penalización).
    List<_Item> eligible(double tier) => [
      for (final i in items)
        if (() {
          final age = memory.ageOf(i.track, now);
          if (age != null && age < windowOf(i) * tier) return false;
          return !(tier >= 0.5 &&
              recommendationTrackKeys(i.track).any(ctx.recentKeys.contains));
        }())
          i,
    ];
    var pool = const <_Item>[];
    for (final tier in const [1.0, 0.5, 0.25, 0.0]) {
      pool = eligible(tier);
      diag.memoryTier = tier;
      if (pool.length >= ctx.limit) break;
    }
    diag.afterMemory = pool.length;

    for (final i in pool) {
      final age = memory.ageOf(i.track, now);
      final novelty = age == null
          ? 0.0
          : 0.4 * math.exp(-age.inMinutes / windowOf(i).inMinutes);
      final bonus =
          djModeBonus(
            ctx.mode,
            i.track,
            now: now,
            knownArtists: ctx.favoriteArtists,
          ) -
          novelty -
          (recommendationTrackKeys(i.track).any(ctx.recentKeys.contains)
              ? djRecentPenalty
              : 0) -
          (ctx.skippedArtists.contains(i.artist) ? djSkippedArtistPenalty : 0) +
          djCoherenceWeight * (cohOf[i]!.score - 0.5) +
          djPriorWeight * i.candidate.prior +
          (currentVector == null
              ? 0
              : djContinuityWeight * djCosine(currentVector, i.vector));
      final cos = [for (final v in vecs) djCosine(v, i.vector)];
      i.rel = [for (final c in cos) djTasteWeight * c + bonus];
      i.mean = i.rel.reduce((a, b) => a + b) / i.rel.length;
      // Afinidad de grupo: gusta a al menos dos personas.
      i.group = cos.where((c) => c > 0.15).length >= 2 ? 0.08 : 0;
    }

    final limit = ctx.limit;
    final artistCap = math.max(1, (limit / 5).ceil());
    final genreCap = math.max(2, (limit * 0.4).ceil());
    final decadeCap = math.max(2, (limit * 0.5).ceil());
    final artistsSoFar = [
      if (ctx.current != null && ctx.queueTail.isEmpty)
        djPrimaryArtist(ctx.current!),
      ...ctx.queueTail.map(djPrimaryArtist),
    ];
    final tailWindow = artistsSoFar.length > 9
        ? artistsSoFar.sublist(artistsSoFar.length - 9)
        : [...artistsSoFar];
    final chosen = <_Item>[];
    final turns = <String?>[];
    final byArtist = <String, int>{}, byGenre = <String, int>{};
    final byDecade = <int, int>{};
    final byBucket = <RecBucket, int>{};
    var heardPicked = 0;

    bool cooled(_Item i) =>
        i.artist.isEmpty ||
        ((artistsSoFar.isEmpty || artistsSoFar.last != i.artist) &&
            tailWindow.where((a) => a == i.artist).length < 2);
    bool capped(_Item i) =>
        (byArtist[i.artist] ?? 0) >= artistCap && i.artist.isNotEmpty ||
        (i.genre != null && (byGenre[i.genre] ?? 0) >= genreCap) ||
        (i.decade != null && (byDecade[i.decade] ?? 0) >= decadeCap);

    final remaining = [...pool];
    while (chosen.length < limit && remaining.isNotEmpty) {
      final turn = chosen.length % vecs.length;
      var options = [
        for (final i in remaining)
          if (cooled(i) && !capped(i)) i,
      ];
      if (options.isEmpty) {
        options = [
          for (final i in remaining)
            if (cooled(i)) i,
        ];
      }
      if (options.isEmpty) options = remaining; // nunca vacío
      if (share > 0) {
        // Cuota de ya oídas / nuevas; si no queda de la clase, cualquiera.
        final wantHeard = djWantHeard(heardPicked, chosen.length, share);
        final preferred = [
          for (final i in options)
            if (heardOf(i) == wantHeard) i,
        ];
        if (preferred.isNotEmpty) options = preferred;
      }
      final scores = <double>[];
      for (final i in options) {
        var redundancy = 0.0;
        for (final c in chosen) {
          redundancy = math.max(redundancy, djCosine(i.vector, c.vector));
        }
        final target = mix[i.candidate.bucket] ?? 0;
        final share = chosen.isEmpty
            ? 0.0
            : (byBucket[i.candidate.bucket] ?? 0) / chosen.length;
        final relevance = vecs.length > 1
            ? 0.6 * i.rel[turn] + 0.4 * i.mean + i.group
            : i.mean;
        scores.add(
          djMmrLambda * relevance -
              (1 - djMmrLambda) * redundancy +
              0.25 * (target - share) +
              0.03 * rnd.nextDouble(),
        );
      }
      var best = 0;
      if (options.length > 1 && rnd.nextDouble() < exploration) {
        // Muestreo ponderado (softmax): puede salir cualquiera de las buenas.
        final top = scores.reduce(math.max);
        final w = [for (final s in scores) math.exp((s - top) / 0.12)];
        var r = rnd.nextDouble() * w.reduce((a, b) => a + b);
        for (var k = 0; k < w.length; k++) {
          r -= w[k];
          if (r <= 0) {
            best = k;
            break;
          }
        }
      } else {
        for (var k = 1; k < scores.length; k++) {
          if (scores[k] > scores[best]) best = k;
        }
      }
      final pick = options[best];
      if (share > 0 && heardOf(pick)) heardPicked++;
      remaining.remove(pick);
      chosen.add(pick);
      turns.add(parts.isEmpty ? null : parts[turn].id);
      artistsSoFar.add(pick.artist);
      tailWindow.add(pick.artist);
      if (tailWindow.length > 9) tailWindow.removeAt(0);
      byArtist.update(pick.artist, (n) => n + 1, ifAbsent: () => 1);
      if (pick.genre != null) {
        byGenre.update(pick.genre!, (n) => n + 1, ifAbsent: () => 1);
      }
      if (pick.decade != null) {
        byDecade.update(pick.decade!, (n) => n + 1, ifAbsent: () => 1);
      }
      byBucket.update(pick.candidate.bucket, (n) => n + 1, ifAbsent: () => 1);
    }

    String reasonOf(_Item i) {
      if (i.candidate.reason.isNotEmpty) return i.candidate.reason;
      return switch (i.candidate.bucket) {
        RecBucket.similar =>
          topArtist == null
              ? 'Más de lo que te gusta'
              : 'Porque escuchas ${_title(topArtist)}',
        RecBucket.adjacent =>
          topArtist == null
              ? 'Artistas parecidos a tus gustos'
              : 'Artistas parecidos a ${_title(topArtist)}',
        RecBucket.discovery => 'Descubrimiento',
        RecBucket.radio => 'Radio de YouTube',
        RecBucket.lastfm => 'Recomendado por Last.fm',
      };
    }

    diag
      ..picked = chosen.length
      ..pickedByBucket = byBucket;
    return [
      for (var k = 0; k < chosen.length; k++)
        (
          track: chosen[k].track,
          reason: reasonOf(chosen[k]),
          forParticipant: turns[k],
          bucket: chosen[k].candidate.bucket,
          coherence: cohOf[chosen[k]]!.score,
          coherenceReason: cohOf[chosen[k]]!.reason,
        ),
    ];
  }
}
