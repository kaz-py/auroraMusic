import 'dart:async';
import 'account/account_service.dart';
import 'account/sync_service.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'audio/equalizer_controller.dart';
import 'audio/media_controls.dart';
import 'audio/routed_music_audio.dart';
import 'core/audio_backend.dart';
import 'core/artwork_metadata.dart';
import 'core/models.dart';
import 'core/queue_policy.dart';
import 'core/source_backend.dart';
import 'import/spotify_import.dart';
import 'follow/follow_boost.dart';
import 'library/library_database.dart';
import 'jam/jam_models.dart' show jamCleanName;
import 'lyrics/lyrics_auto_sync.dart';
import 'lastfm/lastfm_service.dart';
import 'lastfm/lastfm_stats.dart';
import 'profile/avatar_image.dart';
import 'dj/ai_dj.dart';
import 'dj/artist_graph.dart';
import 'dj/coherence.dart';
import 'dj/dj_modes.dart';
import 'dj/recommendations.dart';
import 'dj/reco_memory.dart';
import 'dj/suggestions_api.dart';
import 'metadata/spotify/spotify_metadata_provider.dart';
import 'metadata/spotify_recs.dart';
import 'metadata/youtube_match.dart';
import 'discord/discord_presence.dart';
import 'sources/innertube_source.dart';
import 'sources/stream/stream_orchestrator.dart' show AudioQuality;
import 'sources/youtube_request_policy.dart';
import 'sources/web_music_source.dart';

final controllerProvider = ChangeNotifierProvider<AppController>((ref) {
  throw StateError('Override controllerProvider at application startup.');
});

class AppController extends ChangeNotifier {
  static const _maxStreamRecoveryAttempts = 1;
  AppController({
    required this.audio,
    required this.source,
    required this.database,
    required this.preferences,
    required this.supportDirectory,
    this.lastfm,
  });

  /// Cuenta y sincronización (lib/account); null hasta que main las conecta.
  AccountService? accounts;
  SyncService? sync;

  /// Vuelve a leer la biblioteca de la base (tras sincronizar con la cuenta).
  Future<void> reloadLibrary() async {
    tracks = await database.readTracks();
    favoriteIds = await database.readFavorites();
    playlists = await database.readPlaylists();
    _loadPlaylistPhotos();
    recentTracks = _lookup(await database.readHistory());
    _notify();
  }

  /// Scrobbling y recomendaciones opcionales de Last.fm (null = sin ellas).
  final LastfmService? lastfm;
  final AudioBackend audio;
  final SourceBackend source;
  final LibraryDatabase database;
  final SharedPreferences preferences;

  /// Alinea las letras con el audio; lo conecta la interfaz de escritorio.
  LyricsAutoSync? lyricsAutoSync;
  final Directory supportDirectory;

  /// Ecualizador local de este dispositivo (la Jam no lo sincroniza).
  late final EqualizerController eq = EqualizerController(
    audio: audio,
    preferences: preferences,
  );

  /// Artistas seguidos (lib/follow); lo conecta la interfaz al arrancar.
  Set<String> Function() followedArtistKeys = _noFollowedArtists;
  static Set<String> _noFollowedArtists() => const {};
  bool get usesOfficialYouTubeMusic => source.usesOfficialYouTubeMusic;
  bool get usesYouTubeWebAudio => source.usesYouTubeWebAudio;

  /// The current track plays in the official site, not a native backend.
  bool get webPlayback =>
      audio is RoutedMusicAudio && (audio as RoutedMusicAudio).usingWeb;

  /// The site is showing an ad; the player shows «Anuncio» meanwhile.
  bool get adPlaying => audio.adPlaying;
  Uri? youtubeMusicRequest;
  bool _youtubeMusicActive = false;
  bool get youtubeMusicActive => _youtubeMusicActive;

  /// A navigation request only. The official player owns its queue and session.
  void openYouTubeMusic([Uri? uri]) {
    if (!usesOfficialYouTubeMusic) return;
    try {
      final target = WebMusicSource.officialUri(uri);
      if (_loadedTrackId != null) _resumePosition = audio.position;
      ++_playGeneration;
      _cancelRecovery();
      _cancelPendingResolution();
      stopPersonalDj();
      _playIntent = false;
      busy = false;
      _loadedTrackId = null;
      _loadedAudioInput = null;
      _usingRemote = false;
      _recoverableRemoteTrackId = null;
      _youtubeMusicActive = true;
      youtubeMusicRequest = target;
      _controls?.updateTrack(null);
      if (audio.isPlaying || audio.isBuffering) {
        unawaited(audio.pause().catchError(_report));
      }
      _notify();
    } on ArgumentError catch (exception) {
      _report(exception);
    }
  }

  void clearYouTubeMusicRequest() {
    youtubeMusicRequest = null;
    _notify();
  }

  /// Called after the official player has closed; personal playback stays paused.
  void closeYouTubeMusic() {
    _youtubeMusicActive = false;
    youtubeMusicRequest = null;
    _playIntent = false;
    _notify();
  }

  bool requiresOfficialYouTubeMusic(Track track) =>
      usesOfficialYouTubeMusic &&
      !(track.isLocal && File(track.localPath!).existsSync()) &&
      (track.isPendingSpotifyMatch ||
          WebMusicSource.isOnlineYouTube(track.copyWith(clearLocalPath: true)));

  bool isNativePlayable(Track track) {
    if (usesYouTubeWebAudio) {
      if (track.isPendingSpotifyMatch) return false;
      if (track.isLocal && File(track.localPath!).existsSync()) return true;
      if (WebMusicSource.isOnlineYouTube(
        track.copyWith(clearLocalPath: true),
      )) {
        try {
          WebMusicSource.audioUriForTrack(track);
          return true;
        } on StateError {
          return false;
        }
      }
      final uri = Uri.tryParse(track.pageUrl ?? '');
      return uri?.scheme == 'https' &&
          uri!.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    }
    if (!usesOfficialYouTubeMusic) {
      return !track.isPendingSpotifyMatch &&
          (track.isLocal || track.pageUrl != null);
    }
    if (track.isLocal && File(track.localPath!).existsSync()) return true;
    final uri = Uri.tryParse(track.pageUrl ?? '');
    return !track.isPendingSpotifyMatch &&
        !requiresOfficialYouTubeMusic(track) &&
        uri?.scheme == 'https' &&
        uri!.host.isNotEmpty &&
        uri.userInfo.isEmpty;
  }

  bool _routeToYouTubeMusic(Track track) {
    if (!requiresOfficialYouTubeMusic(track)) return false;
    openYouTubeMusic(WebMusicSource.uriForTrack(track));
    return true;
  }

  List<Track> get _nativeLibrary =>
      usesOfficialYouTubeMusic || usesYouTubeWebAudio
      ? tracks.where(isNativePlayable).toList()
      : tracks;
  MediaControls? _controls;
  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<String>? _nativeActions;
  bool _disposed = false;
  bool ready = false;
  bool _audioInitialized = false;
  bool busy = false;
  bool searching = false;
  bool diagnosing = false;
  bool sessionBusy = false;
  bool configuringDownloadDirectory = false;
  bool clearingPlaybackCache = false;
  String? playbackCacheMessage;
  String get downloadsDirectoryPath =>
      preferences.getString('downloadsDirectory') ??
      p.join(supportDirectory.path, 'downloads');
  bool get canConfigureDownloadDirectory =>
      Platform.isWindows || Platform.isLinux;
  bool get hasYouTubeSession => source.cookieFile != null;
  String? error;
  String? diagnostics;
  List<Track> tracks = [];
  List<Track> searchResults = [];
  List<Track> discoveredRecommendations = [];
  bool discoveringRecommendations = false;
  String? recommendationDiscoveryError;
  String? personalDjError;
  DjFilters _djFilters = const DjFilters();
  DjFilters get djFilters => _djFilters;
  String _searchQuery = '';
  SearchKind searchKind = SearchKind.songs;
  List<SearchEntry> searchEntries = [];
  String? _searchContinuation;
  bool searchLoadingMore = false;
  String? searchError;
  SearchEntry? searchDetail;
  List<Track> searchDetailTracks = [];
  bool searchDetailLoading = false;
  String? searchDetailError;
  bool get hasMoreSearchResults => _searchContinuation != null;
  String get searchQuery => _searchQuery;
  List<String> get recentSearches =>
      preferences.getStringList('recentSearches') ?? const [];
  List<Track> recentTracks = [];
  List<MusicPlaylist> playlists = [];
  List<DownloadJob> downloads = [];
  Set<String> favoriteIds = {};
  List<Track> queue = [];
  int queueIndex = -1;
  bool shuffle = false;

  /// Autoplay: con la cola agotada se añaden sugerencias del motor local.
  bool autoRefill = true;

  /// Pistas que el autoplay añadió (marca «Sugerida» en la cola).
  final Set<String> autoAddedIds = {};

  /// Pistas que el usuario puso a mano («Añadir a la cola», «A continuación»).
  /// Al reproducir desde Spotify se conservan; el resto de lo que viene se
  /// reemplaza. shortcut: no se guarda entre sesiones, al reiniciar todo lo
  /// que viene cuenta como contexto reemplazable.
  final Set<String> manualQueuedIds = {};
  int _seedGeneration = 0;
  Future<void>? _refillFuture;
  SuggestionsApi? _suggestionsApi;

  /// Vecindario de artistas (YouTube Music, Last.fm y co-escucha en la radio)
  /// con etiquetas de género; lo usan el motor, la cola y el DJ.
  late final ArtistGraph artistGraph = ArtistGraph(
    preferences: preferences,
    youtubeRelated: switch (source) {
      final InnerTubeSource s => s.relatedArtists,
      _ => null,
    },
    lastfmSimilar: lastfm == null
        ? null
        : (a) async => lastfm!.active
              ? lastfm!.client.similarArtists(a)
              : throw StateError('Last.fm inactivo'),
    lastfmTags: lastfm == null
        ? null
        : (a) async => lastfm!.active
              ? lastfm!.client.artistTopTags(a)
              : throw StateError('Last.fm inactivo'),
  );

  /// Motor de recomendaciones compartido con la Jam; se crea una sola vez.
  SuggestionsApi get suggestionsApi {
    if (_suggestionsApi != null) return _suggestionsApi!;
    final matcher = YoutubeMatcher(
      search: (q, k) => source.searchPage(q, k).then((p) => p.tracks),
    );
    // Con Last.fm activo, sus recomendaciones lideran (DJ y Jam).
    final mix = {...defaultRecMix};
    void syncMix() => mix[RecBucket.lastfm] = lastfm?.active == true
        ? 0.40
        : defaultRecMix[RecBucket.lastfm]!;
    syncMix();
    lastfm?.addListener(syncMix);
    return _suggestionsApi = SuggestionsApi(
      graph: artistGraph,
      mix: mix,
      sources: source is InnerTubeSource
          ? [
              ...spotifyRecSources(
                catalog: ProviderSpotifyCatalog(SpotifyMetadataProvider()),
                matcher: matcher,
              ),
              if (lastfm != null) lastfm!.recSource(matcher),
            ]
          : const [],
    );
  }

  /// Perfil de gustos de ESTE dispositivo (nunca sale del equipo).
  ParticipantTaste get selfTaste => ParticipantTaste('self', _tasteProfile());

  bool get _canAutoRefill =>
      autoRefill &&
      !_disposed &&
      !_jamPlaybackActive &&
      !_youtubeMusicActive &&
      repeat != RepeatMode.one &&
      (_personalDjActive || repeat == RepeatMode.off) &&
      queue.isNotEmpty &&
      queueIndex >= 0;

  void setAutoRefill(bool value) {
    autoRefill = value;
    unawaited(preferences.setBool('autoRefill', value));
    _notify();
  }

  /// Red de seguridad: la cola no termina nunca. Mantiene hasta [target]
  /// pistas por delante añadiendo al final (nunca reordena ni quita lo que
  /// armó el usuario). Motor → biblioteca → favoritos → repetir lo sonado;
  /// sin repetir artista seguido. Actúa también con el DJ personal.
  Future<void> _refillQueue({int target = kQueueLookahead}) {
    if (!_canAutoRefill || _upcomingCount >= target) {
      return _refillFuture ?? Future.value();
    }
    return _refillFuture ??= _doRefill(
      target,
    ).whenComplete(() => _refillFuture = null);
  }

  /// Artistas de las señales del usuario: favoritos, saltados (30 últimos
  /// eventos) y escuchados enteros (10 últimos). Los eventos de pistas que no
  /// están en la biblioteca usan el artista guardado en el evento.
  ({Set<String> favorites, Set<String> skipped, Set<String> listened})
  _djArtistSignals() {
    final byId = {for (final t in tracks) t.id: t};
    String artistOf(DjEvent e) => switch (byId[e.trackId]) {
      final t? => djPrimaryArtist(t),
      null => e.artist,
    };
    final events = _djEvents.reversed.take(30).toList();
    return (
      favorites: {
        for (final id in favoriteIds)
          if (byId[id] case final t?) djPrimaryArtist(t),
      }..remove(''),
      skipped: {
        for (final e in events)
          if (e.signal == DjSignal.skip) artistOf(e),
      }..remove(''),
      listened: {
        for (final e
            in events.where((e) => e.signal == DjSignal.complete).take(10))
          artistOf(e),
      }..remove(''),
    );
  }

  /// Contexto de coherencia de la semilla actual (sin la cola: no deriva).
  CoherenceContext _seedCoherence(TasteProfile profile) {
    final signals = _djArtistSignals();
    return seedCoherence(
      features: profile.features,
      favoriteArtists: signals.favorites,
      listenedArtists: signals.listened,
      current: currentTrack,
      graph: artistGraph,
    );
  }

  CoherenceResult _coherenceOf(Track t, CoherenceContext ctx) => scoreCoherence(
    t,
    ctx,
    decade: djDecade(t),
    genres: artistGraph.tagsOf(djPrimaryArtist(t)),
  );

  /// Sugerencias del motor local (mismo filtro de coherencia para el DJ y el
  /// autoplay). Un fallo o un tiempo agotado no apagan nada: se anota un aviso
  /// discreto, se reintenta con espera creciente y quien llama cae a lo local.
  /// La radio de YouTube (related) entra como una fuente más del motor, que
  /// la mezcla por cubo (`mix`) y la filtra igual que el resto.
  Future<List<Suggestion>> _engineSuggestions({int limit = 12}) async {
    final current = currentTrack;
    final recent = recentTracks
        .take(20)
        .expand(recommendationTrackKeys)
        .toSet();
    final extra = <DjCandidate>[];
    final taste = selfTaste;
    final signals = _djArtistSignals();
    // Radio sola (motor caído o en espera): solo lo relacionado con la
    // semilla; si nada lo está, las 3 más coherentes. Nunca vacía si hay radio.
    List<Suggestion> radioOnly() {
      final coh = _seedCoherence(taste.profile);
      final scored = [
        for (final c in extra) (c: c, r: _coherenceOf(c.track, coh)),
      ];
      var keep = [
        for (final s in scored)
          if (coh.isEmpty || s.r.score >= djRelatedThreshold) s,
      ];
      if (keep.isEmpty) {
        keep = ([
          ...scored,
        ]..sort((a, b) => b.r.score.compareTo(a.r.score))).take(3).toList();
      }
      return [
        for (final s in keep)
          Suggestion(
            s.c.track,
            s.c.reason,
            '',
            bucket: RecBucket.radio,
            coherence: s.r.score,
            coherenceReason: s.r.reason,
          ),
      ];
    }

    try {
      final src = source;
      final id = current?.id.startsWith('yt:') == true
          ? current!.id.substring(3)
          : null;
      if (src is InnerTubeSource && id != null) {
        try {
          final related = await src
              .related(id)
              .timeout(const Duration(seconds: 4));
          for (var i = 0; i < related.length; i++) {
            extra.add(
              DjCandidate(
                related[i],
                'Radio de YouTube',
                prior: 0.5 / (1 + i / 5),
                bucket: RecBucket.radio,
              ),
            );
          }
          // Co-escucha: artistas que se repiten en la radio son vecinos.
          artistGraph.learnCoListened(
            djPrimaryArtist(current!),
            related.map(djPrimaryArtist),
          );
        } catch (_) {}
      }
      // Radio de YouTube como suplente si el motor local falla o está en espera.
      final retryAt = _engineRetryAt;
      if (retryAt != null && DateTime.now().isBefore(retryAt)) {
        return radioOnly();
      }
      final picks = await suggestionsApi
          .getSuggestions(
            SessionContext(
              participants: [taste],
              mode: _djMode,
              current: current,
              library: tracks,
              recentKeys: recent,
              queueTail: queue.skip(max(0, queue.length - 3)).toList(),
              favoriteArtists: signals.favorites,
              skippedArtists: signals.skipped,
              listenedArtists: signals.listened,
              filters: djFilters,
              extraCandidates: extra,
              limit: limit,
              heardShare: djHeardShare(_djMode),
            ),
          )
          .timeout(refillEngineTimeout);
      _engineFailures = 0;
      _engineRetryAt = null;
      if (_personalDjActive && personalDjError == _engineDownNotice) {
        personalDjError = null;
        _notify();
      }
      return picks;
    } catch (_) {
      _engineFailures++;
      _engineRetryAt = DateTime.now().add(
        Duration(seconds: min(120, 5 << min(_engineFailures - 1, 5))),
      );
      if (_personalDjActive && !_disposed) {
        personalDjError = _engineDownNotice;
        _notify();
      }
      return radioOnly();
    }
  }

  static const _engineDownNotice = 'el motor de sugerencias no responde';
  int _engineFailures = 0;
  DateTime? _engineRetryAt;

  /// Tiempo máximo que se espera al motor antes de seguir con lo local. Por
  /// encima de `SuggestionsApi.budget` (9 s): el motor corta sus fuentes a
  /// tiempo y devuelve lo reunido; esto solo salta si se cuelga del todo.
  Duration refillEngineTimeout = const Duration(seconds: 12);

  /// Sustituye el motor de sugerencias (pruebas).
  set suggestionsApi(SuggestionsApi api) => _suggestionsApi = api;

  Future<void> _doRefill(int target) =>
      _fillQueue(target: target, allowed: () => _canAutoRefill);

  /// Rellena hasta [target] pistas por delante. [priority] (p. ej. más
  /// canciones del artista de Spotify) entra antes que el motor; [fallbacks]
  /// false = solo motor y prioritarias (sin biblioteca ni repetir). Inserta en
  /// [insertAt] (por defecto al final) y descarta lo que ya esté en la cola.
  Future<void> _fillQueue({
    required int target,
    required bool Function() allowed,
    Future<List<Track>> Function()? priority,
    bool fallbacks = true,
    int Function()? insertAt,
  }) async {
    final current = currentTrack;
    final before = {for (final t in queue) t.id};
    final recent = recentTracks
        .take(20)
        .expand(recommendationTrackKeys)
        .toSet();
    final picked = <Track>[];
    bool native(Track t) =>
        !(usesOfficialYouTubeMusic || usesYouTubeWebAudio) ||
        isNativePlayable(t);
    int need() => target - (queue.length - queueIndex - 1) - picked.length;
    // Tope por artista en lo que viene (~30 %): una semilla de un solo artista
    // no puede llenar la cola; se mezcla con otros del perfil y nuevos.
    final perArtist = <String, int>{};
    for (final t in queue.skip(max(0, queueIndex + 1))) {
      perArtist.update(djPrimaryArtist(t), (n) => n + 1, ifAbsent: () => 1);
    }
    final artistCap = max(2, (target * 0.3).ceil());
    void takeOnce(
      Iterable<Track> pool,
      bool relaxed, {
      bool allowRecent = false,
      bool reuse = false,
    }) {
      final seen = {
        for (final t in [if (!reuse) ...queue, ...picked])
          ...recommendationTrackKeys(t),
      };
      {
        for (final t in pool) {
          if (need() <= 0) return;
          final keys = recommendationTrackKeys(t);
          if (t.isPendingSpotifyMatch ||
              !native(t) ||
              keys.any(seen.contains) ||
              (!allowRecent && keys.any(recent.contains))) {
            continue;
          }
          final at = insertAt?.call() ?? queue.length;
          final previous = picked.isNotEmpty
              ? picked.last
              : (at > 0 && at <= queue.length ? queue[at - 1] : null);
          final artist = djPrimaryArtist(t);
          if (!relaxed &&
              ((previous != null && djPrimaryArtist(previous) == artist) ||
                  (artist.isNotEmpty &&
                      (perArtist[artist] ?? 0) >= artistCap))) {
            continue;
          }
          perArtist.update(artist, (n) => n + 1, ifAbsent: () => 1);
          picked.add(t);
          seen.addAll(keys);
        }
      }
    }

    // Un grupo de orígenes: todos con la regla de artista estricta y solo
    // después, si falta, relajada (si no, el primer origen repetía artista
    // antes de que la biblioteca aportara variedad).
    void take(
      List<Iterable<Track>> pools, {
      bool allowRecent = false,
      bool reuse = false,
    }) {
      for (final relaxed in [false, true]) {
        for (final pool in pools) {
          takeOnce(pool, relaxed, allowRecent: allowRecent, reuse: reuse);
        }
      }
    }

    final lead = priority == null
        ? const <Track>[]
        : await priority().catchError((Object _) => const <Track>[]);
    final engine = await _engineSuggestions(
      limit: min(30, max(12, 2 * need())),
    );
    // Intercala: prioritarias y motor, para no encadenar el mismo origen.
    final mixed = <Track>[];
    final picks = [for (final s in engine) s.track];
    for (var i = 0; i < max(lead.length, picks.length); i++) {
      if (i < picks.length) mixed.add(picks[i]);
      if (i < lead.length) mixed.add(lead[i]);
    }
    if (!fallbacks) {
      take([mixed]);
      await _commitFill(picked, before, allowed, insertAt);
      return;
    }
    // Biblioteca de respaldo: primero lo coherente con la semilla (orden
    // estable: `sort` de Dart no lo es, así que se desempata por posición).
    final coh = _seedCoherence(_tasteProfile());
    final scores = [for (final t in tracks) _coherenceOf(t, coh).score];
    final order = List.generate(tracks.length, (i) => i)
      ..sort((a, b) {
        final c = scores[b].compareTo(scores[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    take([
      mixed,
      [for (final i in order) tracks[i]],
    ]);
    final favorites = [
      for (final t in tracks)
        if (favoriteIds.contains(t.id)) t,
    ];
    take([favorites, tracks], allowRecent: true);
    // Último recurso: repetir lo ya sonado antes que quedarse en silencio.
    if (need() > 0 && current != null) {
      take(
        [
          [...queue.take(queueIndex), current],
        ],
        allowRecent: true,
        reuse: true,
      );
    }
    await _commitFill(picked, before, allowed, insertAt);
  }

  Future<void> _commitFill(
    List<Track> picked,
    Set<String> before,
    bool Function() allowed,
    int Function()? insertAt,
  ) async {
    if (picked.isEmpty || !allowed()) return;
    // Otro relleno pudo adelantarse durante las esperas: sin duplicados.
    final fresh = [
      for (final t in picked)
        if (before.contains(t.id) ||
            !queue.any((q) => recommendationTracksMatch(q, t)))
          t,
    ];
    if (fresh.isEmpty) return;
    queue.insertAll(
      (insertAt?.call() ?? queue.length).clamp(0, queue.length),
      fresh,
    );
    autoAddedIds.addAll(fresh.map((t) => t.id));
    await _saveQueue();
    _notify();
  }

  RepeatMode repeat = RepeatMode.off;
  bool experimentalProgressivePlayback = false;
  bool adaptiveColors = true;
  String accentPalette = 'automatic';
  static const Map<String, Color> accentPaletteColors = {
    'terracotta': Color(0xffc45c2b),
    'amber': Color(0xffa66b00),
    'forest': Color(0xff28734a),
    'purple': Color(0xff7047a3),
  };
  bool reducedMotion = false;

  ThemeMode themeMode = ThemeMode.dark;

  /// 'atelier' (por defecto), 'modern', 'brasa' o 'slush'.
  String themeKind = 'modern';
  AudioQuality audioQuality = AudioQuality.high;
  final DiscordPresence discord = DiscordPresence();
  bool get discordPresence => discord.enabled;
  void setDiscordPresence(bool value) {
    discord.enabled = value;
    unawaited(preferences.setBool('discordPresence', value));
    _audioChanged();
  }

  /// Perfil local del usuario (lo usa la Jam). Vacío = sin nombre elegido.
  String profileName = '';

  /// Miniatura cuadrada del avatar (JPEG/PNG de 128 px, <= 24 KB) o null.
  Uint8List? profileAvatar;
  Color accentColor = const Color(0xffe86927);
  Timer? _sleepTimer;
  DateTime? _sleepEnd;
  bool _sleepAtTrackEnd = false;
  int _playGeneration = 0;
  int _recoveryGeneration = 0;
  int _searchGeneration = 0;
  int _searchDetailGeneration = 0;
  int _recommendationDiscoveryGeneration = 0;
  int _personalDjGeneration = 0;
  bool _personalDjActive = false;
  bool _personalDjIncludeDiscovery = true;
  Set<String> _personalDjSeenKeys = {};
  Future<void>? _personalDjRefillTask;
  List<DjEvent> _djEvents = [];
  final Set<String> _djUsedQueries = {};
  final Set<String> _djEmbeddedIds = {};

  /// Short Spanish reason for each track the DJ queued in this session.
  final Map<String, String> personalDjReasons = {};

  /// Observed skip/complete events, newest last (bounded to [djMaxEvents]).
  List<DjEvent> get djEvents => List.unmodifiable(_djEvents);
  bool _processingDownloads = false;
  Future<void>? _downloadWorker;
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;
  String? _loadedTrackId;
  String? _loadedAudioInput;
  String? _pendingResolveVideoId;
  String? _prefetchKey;
  bool _prefetching = false;
  Duration _resumePosition = Duration.zero;
  final Random _random = Random();
  final List<int> _shuffleHistory = [];
  final Set<int> _shufflePlayed = {};
  DateTime _lastSnapshot = DateTime.fromMillisecondsSinceEpoch(0);
  bool _recovering = false;
  bool _playIntent = false;
  bool _jamPlaybackActive = false;

  /// Jam owns the audio backend temporarily, without persisting its queue.
  bool get jamPlaybackActive => _jamPlaybackActive;
  bool _usingRemote = false;
  String? _recoveryTrackId;
  String? _recoverableRemoteTrackId;
  int _expiryRetries = 0;
  Duration _recoveryProgressPosition = Duration.zero;

  Track? _jamNowPlaying;

  /// Pista que suena en la Jam (null hasta que cargue la primera).
  Track? get jamNowPlaying => _jamNowPlaying;
  int _jamPartySize = 0;
  String? _jamSessionId;

  /// Oyentes y sesión de la Jam, solo para la presencia de Discord.
  void setJamParty(String? sessionId, int size) {
    _jamSessionId = sessionId;
    _jamPartySize = size;
    _updateDiscord();
  }

  void _updateDiscord() {
    if (!discordAvailable) return;
    final loaded = currentTrack;
    final jam = _jamPlaybackActive;
    discord.update(
      jam
          ? _jamNowPlaying
          : loaded != null && _loadedTrackId == loaded.id
          ? loaded
          : null,
      playing: audio.isPlaying,
      position: audio.position,
      jam: jam,
      partySize: jam ? _jamPartySize : 0,
      partyId: _jamSessionId,
    );
  }

  void setJamNowPlaying(Track? track) {
    if (_jamNowPlaying?.id == track?.id) return;
    _jamNowPlaying = track;
    _updateDiscord();
    _notify();
  }

  /// Lo que realmente suena: la pista de la Jam o la de la cola personal.
  Track? get nowTrack => _jamPlaybackActive ? _jamNowPlaying : currentTrack;

  /// Historial/perfil para lo que suena en Jam; sin tocar la cola personal.
  Future<void> noteJamPlay(Track track) async {
    await _remember(track);
    await database.recordPlay(track.id);
    recentTracks = [
      track,
      ...recentTracks.where((item) => item.id != track.id),
    ].take(100).toList();
    await RecsMemory.shared.record([track], DateTime.now());
    _notify();
  }

  Track? get currentTrack =>
      queueIndex >= 0 && queueIndex < queue.length ? queue[queueIndex] : null;
  List<TrackRecommendation> get recommendations => recommendTracks(
    library: _nativeLibrary,
    favoriteIds: favoriteIds,
    playlists: playlists,
    history: recentTracks,
    currentTrackId: currentTrack?.id,
    filters: djFilters,
  );
  bool get canDiscoverRecommendations =>
      !usesOfficialYouTubeMusic &&
      (!usesYouTubeWebAudio || source.supportsOnlineMetadataSearch) &&
      (strongestTasteArtist(
                library: tracks,
                favoriteIds: favoriteIds,
                playlists: playlists,
                history: recentTracks,
              ) !=
              null ||
          recommendations.isNotEmpty);
  bool get personalDjActive => _personalDjActive;
  bool get personalDjIncludeDiscovery => _personalDjIncludeDiscovery;
  bool get canStartPersonalDj {
    final queuedKeys = queue.expand(recommendationTrackKeys).toSet();
    final hasUnqueuedRecommendation = [
      ...recommendations.map((item) => item.track),
      if (_personalDjIncludeDiscovery) ...discoveredRecommendations,
    ].any((track) => !recommendationTrackKeys(track).any(queuedKeys.contains));
    return hasUnqueuedRecommendation || _hasPlayableUpcomingQueue;
  }

  bool get _hasPlayableUpcomingQueue {
    if (currentTrack == null ||
        !(_playIntent || busy || audio.isPlaying || _loadedTrackId != null)) {
      return false;
    }
    bool playable(Track track) => isNativePlayable(track);
    if (shuffle) {
      return queue.asMap().entries.any(
        (entry) =>
            entry.key != queueIndex &&
            (repeat == RepeatMode.all || !_shufflePlayed.contains(entry.key)) &&
            playable(entry.value),
      );
    }
    if (queueIndex + 1 < queue.length) {
      return queue.skip(queueIndex + 1).any(playable);
    }
    return repeat == RepeatMode.all &&
        queue.asMap().entries.any(
          (entry) => entry.key != queueIndex && playable(entry.value),
        );
  }

  String _recommendationTasteKey() {
    final sortedFavorites = favoriteIds.toList()..sort();
    return [
      jsonEncode(djFilters.toJson()),
      ...sortedFavorites,
      ...playlists.map(
        (playlist) => '${playlist.id}:${playlist.trackIds.join(',')}',
      ),
      ...recentTracks.map((track) => track.id),
    ].join('|');
  }

  DjMode _djMode = DjMode.discover;
  DjMode get djMode => _djMode;

  double _djDiversity = djDefaultDiversity;
  double get djDiversity => _djDiversity;
  bool _djArtistCooldown = true;
  bool get djArtistCooldown => _djArtistCooldown;

  Future<void> setDjDiversity(double value) async {
    value = value.clamp(0.0, djMaxDiversity);
    if (value == _djDiversity) return;
    _djDiversity = value;
    ++_personalDjGeneration;
    _notify();
    await preferences.setDouble('djDiversity', value);
  }

  Future<void> setDjArtistCooldown(bool value) async {
    if (value == _djArtistCooldown) return;
    _djArtistCooldown = value;
    ++_personalDjGeneration;
    _notify();
    await preferences.setBool('djArtistCooldown', value);
  }

  /// Afinidad 0-1 de [track] con tu perfil local (null si aún no hay gustos).
  double? djTrackAffinity(Track track) => djAffinity(
    profile: _tasteProfile().vector,
    track: track,
    current: currentTrack,
  );

  Future<void> setDjMode(DjMode mode) async {
    if (mode == _djMode) return;
    _djMode = mode;
    ++_personalDjGeneration;
    _notify();
    await preferences.setString('djMode', mode.name);
    if (_personalDjActive && _playIntent) unawaited(_refillPersonalDjQueue());
  }

  /// Reordena candidatos de la Jam con SOLO el perfil de este dispositivo
  /// (un único participante); el perfil nunca sale del equipo.
  Future<List<Track>> rankForJam(List<Track> candidates, Track? current) async {
    final api = SuggestionsApi(
      fetchCandidates: (_) async => [
        for (var i = 0; i < candidates.length; i++)
          DjCandidate(candidates[i], '', prior: 0.5 / (1 + i / 5)),
      ],
    );
    final picks = await api.getSuggestions(
      SessionContext(
        participants: [ParticipantTaste('self', _tasteProfile())],
        mode: _djMode,
        current: current,
        recentKeys: recentTracks
            .take(20)
            .expand(recommendationTrackKeys)
            .toSet(),
        limit: candidates.length,
      ),
    );
    return [for (final s in picks) s.track];
  }

  Future<void> setDjFilters(DjFilters filters) async {
    // Copy lists so external mutations cannot bypass invalidation.
    _djFilters = DjFilters.fromJson(filters.toJson());
    ++_recommendationDiscoveryGeneration;
    ++_personalDjGeneration;
    discoveringRecommendations = false;
    discoveredRecommendations = [];
    recommendationDiscoveryError = null;
    personalDjError = null;
    _notify();
    await preferences.setString('djFilters', jsonEncode(djFilters.toJson()));
    if (_personalDjActive && _playIntent) unawaited(_refillPersonalDjQueue());
  }

  Future<void> refreshRecommendations() async {
    ++_recommendationDiscoveryGeneration;
    discoveringRecommendations = false;
    discoveredRecommendations = [];
    recommendationDiscoveryError = null;
    _notify();
    if (canDiscoverRecommendations) await discoverRecommendations();
  }

  Future<void> discoverRecommendations() async {
    if (usesOfficialYouTubeMusic ||
        (usesYouTubeWebAudio && !source.supportsOnlineMetadataSearch)) {
      return;
    }
    if (discoveringRecommendations || _disposed) return;
    final seed =
        strongestTasteArtist(
          library: tracks,
          favoriteIds: favoriteIds,
          playlists: playlists,
          history: recentTracks,
        ) ??
        recommendations.firstOrNull?.track.artist;
    if (seed == null) return;
    final generation = ++_recommendationDiscoveryGeneration;
    final tasteKey = _recommendationTasteKey();
    discoveringRecommendations = true;
    recommendationDiscoveryError = null;
    _notify();
    try {
      final results = await source.search('$seed songs', limit: 12);
      if (generation != _recommendationDiscoveryGeneration ||
          _disposed ||
          tasteKey != _recommendationTasteKey()) {
        return;
      }
      final seenIds = {...tracks.expand(recommendationTrackKeys)};
      final fresh = <Track>[];
      for (final track in results) {
        final keys = recommendationTrackKeys(track);
        if (!djFilters.permits(track) ||
            keys.any(seenIds.contains) ||
            track.isPendingSpotifyMatch ||
            track.pageUrl == null) {
          continue;
        }
        seenIds.addAll(keys);
        fresh.add(track);
      }
      discoveredRecommendations = fresh.take(6).toList();
      unawaited(_embedDjTracks(results));
    } catch (exception) {
      if (generation == _recommendationDiscoveryGeneration &&
          !_disposed &&
          tasteKey == _recommendationTasteKey()) {
        recommendationDiscoveryError = exception.toString();
      }
    } finally {
      if (generation == _recommendationDiscoveryGeneration && !_disposed) {
        discoveringRecommendations = false;
        _notify();
      }
    }
  }

  void cancelRecommendationDiscovery() {
    if (!discoveringRecommendations) return;
    ++_recommendationDiscoveryGeneration;
    discoveringRecommendations = false;
    _notify();
  }

  /// «Iniciar DJ»: fija el modo y arranca con lo local (o la pista actual); si
  /// no hay semilla local pide una tanda al motor (radio de YouTube/Spotify).
  /// false = no pudo empezar (Jam activa, sin música ni red). El relleno
  /// continuo es el de [startPersonalDj]; no se reimplementa nada.
  Future<bool> startDjSession({
    DjMode? mode,
    bool includeDiscovery = false,
  }) async {
    if (_jamPlaybackActive) return false;
    if (mode != null) await setDjMode(mode);
    if (_personalDjActive) return true;
    await startPersonalDj(includeDiscovery: includeDiscovery);
    if (!_personalDjActive && !_disposed) {
      final picks = await _engineSuggestions(limit: 12);
      await startPersonalDj(
        includeDiscovery: includeDiscovery,
        seeds: [for (final pick in picks) pick.track],
      );
    }
    return _personalDjActive;
  }

  Future<void> startPersonalDj({
    bool includeDiscovery = false,
    List<Track> seeds = const [],
  }) async {
    if (_jamPlaybackActive) return;
    if (personalDjActive) return;
    includeDiscovery =
        includeDiscovery &&
        !usesOfficialYouTubeMusic &&
        (!usesYouTubeWebAudio || source.supportsOnlineMetadataSearch);
    final preserveCurrent =
        currentTrack != null &&
        (_playIntent || busy || audio.isPlaying || _loadedTrackId != null);
    final existingKeys = preserveCurrent
        ? queue.expand(recommendationTrackKeys).toSet()
        : <String>{};
    final seedTracks = <Track>[];
    final seenKeys = <String>{...existingKeys};
    for (final track in [
      ...recommendations.map((item) => item.track),
      if (includeDiscovery) ...discoveredRecommendations,
      ...seeds,
    ]) {
      if (preserveCurrent && queue.length + seedTracks.length >= 24) break;
      final keys = recommendationTrackKeys(track);
      if (!isNativePlayable(track) ||
          !djFilters.permits(track) ||
          keys.any(seenKeys.contains)) {
        continue;
      }
      seenKeys.addAll(keys);
      seedTracks.add(track);
      if (seedTracks.length == 6) break;
    }
    if (seedTracks.isEmpty && !(preserveCurrent && _hasPlayableUpcomingQueue)) {
      return;
    }
    ++_personalDjGeneration;
    _personalDjActive = true;
    _personalDjIncludeDiscovery = includeDiscovery;
    _djUsedQueries.clear();
    personalDjError = null;
    _personalDjSeenKeys = seenKeys;
    _notify();
    if (preserveCurrent) {
      final insertAt = queueIndex + 1;
      for (var i = 0; i < _shuffleHistory.length; i++) {
        if (_shuffleHistory[i] >= insertAt) {
          _shuffleHistory[i] += seedTracks.length;
        }
      }
      final shiftedPlayed = _shufflePlayed
          .map((index) => index >= insertAt ? index + seedTracks.length : index)
          .toSet();
      _shufflePlayed
        ..clear()
        ..addAll(shiftedPlayed);
      queue.insertAll(insertAt, seedTracks);
      await _saveQueue();
      _notify();
      if (audio.isPlaying) unawaited(_refillPersonalDjQueue(force: true));
      return;
    }
    queue = seedTracks;
    queueIndex = 0;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    _resumePosition = Duration.zero;
    _playIntent = true;
    await _playCurrent();
    if (_personalDjActive && audio.isPlaying) {
      unawaited(_refillPersonalDjQueue(force: true));
    }
  }

  void stopPersonalDj() {
    if (!_personalDjActive) return;
    ++_personalDjGeneration;
    _personalDjActive = false;
    personalDjError = null;
    _notify();
  }

  void setPersonalDjIncludeDiscovery(bool value) {
    value =
        value &&
        !usesOfficialYouTubeMusic &&
        (!usesYouTubeWebAudio || source.supportsOnlineMetadataSearch);
    if (_personalDjIncludeDiscovery == value) return;
    _personalDjIncludeDiscovery = value;
    _notify();
  }

  int get _upcomingCount => shuffle
      ? queue.length - _shufflePlayed.length
      : queue.length - queueIndex - 1;

  /// Keeps about [djUpcomingTarget] DJ tracks ahead; refills below
  /// [djRefillThreshold] unless [force]d. Only appends after user choices.
  Future<void> _refillPersonalDjQueue({bool force = false}) async {
    if (!_personalDjActive || !_playIntent || _disposed) return;
    final pending = _personalDjRefillTask;
    if (pending != null) {
      await pending;
      if (_personalDjActive && _playIntent && !_disposed) {
        await _refillPersonalDjQueue(force: force);
      }
      return;
    }
    if (queue.isEmpty || queueIndex < 0) return;
    if (djRefillCount(_upcomingCount, force: force) == 0) return;
    final generation = _personalDjGeneration;
    final task = _performPersonalDjRefill(generation).catchError((
      Object exception,
    ) {
      // Un fallo nunca apaga el DJ: aviso discreto y la red de seguridad sigue.
      if (_disposed) return;
      personalDjError = _plain(exception);
      _notify();
    });
    _personalDjRefillTask = task;
    try {
      await task;
    } finally {
      if (identical(_personalDjRefillTask, task)) {
        _personalDjRefillTask = null;
      }
    }
  }

  /// Embeds tracks into the local vector store once per session.
  Future<void> _embedDjTracks(Iterable<Track> items) async {
    final fresh = [
      for (final track in items)
        if (_djEmbeddedIds.add(track.id))
          (track: track, vector: embedDjTrack(track)),
    ];
    if (fresh.isEmpty || _disposed) return;
    try {
      await database.upsertTrackVectors(fresh);
    } catch (_) {
      // The store is an optimisation; the DJ keeps working without it.
      for (final entry in fresh) {
        _djEmbeddedIds.remove(entry.track.id);
      }
    }
  }

  int? _djSignalGeneration;

  void _recordDjSignal(DjSignal signal) {
    final track = currentTrack;
    if (track == null || _loadedTrackId != track.id) return;
    // One signal per playback: duplicate completion events must not skew taste.
    if (_djSignalGeneration == _playGeneration) return;
    _djSignalGeneration = _playGeneration;
    _djEvents = [
      ..._djEvents,
      DjEvent(signal, track.id, DateTime.now(), artist: djPrimaryArtist(track)),
    ];
    if (_djEvents.length > djMaxEvents) {
      _djEvents = _djEvents.sublist(_djEvents.length - djMaxEvents);
    }
    unawaited(
      preferences
          .setStringList('djEvents', [for (final e in _djEvents) e.encode()])
          .then((_) {}, onError: (Object _) {}),
    );
    unawaited(_embedDjTracks([track]));
  }

  TasteProfile _tasteProfile() {
    final byId = {for (final track in tracks) track.id: track};
    return buildTasteProfile(
      favorites: [for (final id in favoriteIds) ?byId[id]],
      playlistTracks: [
        for (final id in playlists.expand((p) => p.trackIds).toSet()) ?byId[id],
      ],
      history: recentTracks,
      events: _djEvents,
      known: byId,
      now: DateTime.now(),
    );
  }

  Future<void> _performPersonalDjRefill(int generation) async {
    bool stale() =>
        generation != _personalDjGeneration || !_personalDjActive || _disposed;
    final discovery = _personalDjIncludeDiscovery && !usesOfficialYouTubeMusic;
    final current = currentTrack;
    final profile = _tasteProfile();
    final byId = {for (final track in _nativeLibrary) track.id: track};
    final candidates = <DjCandidate>[];
    final local = recommendTracks(
      library: _nativeLibrary,
      favoriteIds: favoriteIds,
      playlists: playlists,
      history: recentTracks,
      currentTrackId: current?.id,
      limit: 24,
      filters: djFilters,
    );
    for (var i = 0; i < local.length; i++) {
      candidates.add(
        DjCandidate(local[i].track, local[i].reason, prior: 0.6 / (1 + i / 5)),
      );
    }

    // Vector store: nearest neighbours of the profile and the current track.
    try {
      await _embedDjTracks(tracks);
      if (stale()) return;
      await database.saveTasteProfile(profile.vector);
      final neighbours = [
        if (!profile.isEmpty)
          for (final n in await database.nearestTracks(profile.vector, k: 40))
            (track: n.track, continuity: false),
        if (current != null)
          for (final n in await database.nearestTracks(
            embedDjTrack(current),
            k: 20,
            exclude: {current.id},
          ))
            (track: n.track, continuity: true),
      ];
      if (stale()) return;
      for (var i = 0; i < neighbours.length; i++) {
        // Without discovery the DJ only uses tracks from the library.
        final track =
            byId[neighbours[i].track.id] ??
            (discovery ? neighbours[i].track : null);
        if (track == null) continue;
        candidates.add(
          DjCandidate(
            track,
            favoriteIds.contains(track.id)
                ? 'De tus favoritos'
                : neighbours[i].continuity
                ? 'Porque escuchaste ${current!.title}'
                : 'Parecido a tus favoritos',
            prior: 0.3 / (1 + i / 10),
          ),
        );
      }
    } catch (_) {
      if (stale()) return;
    }

    // Discovery: queries built from the taste profile, results embedded.
    if (discovery) {
      final signals = _djArtistSignals();
      final top = tasteTop(profile, 'a:', 1).firstOrNull ?? '';
      final libraryArtists = {
        for (final t in tracks) coherenceNorm(djPrimaryArtist(t)),
      };
      final queries = djDiscoveryQueries(
        profile,
        used: _djUsedQueries,
        fallback: current,
        neighbors: [
          for (final n in artistGraph.neighborsOf(top))
            if (!libraryArtists.contains(n)) n,
        ],
        skippedArtists: signals.skipped,
      );
      for (final query in queries) {
        if (stale()) return;
        _djUsedQueries.add(query.query);
        try {
          final results = await source.search(query.query, limit: 12);
          if (stale() || !_personalDjIncludeDiscovery) return;
          await _embedDjTracks(results);
          if (stale()) return;
          for (var i = 0; i < results.length; i++) {
            candidates.add(
              DjCandidate(results[i], query.reason, prior: 0.5 / (1 + i / 5)),
            );
          }
        } catch (exception) {
          if (stale()) return;
          personalDjError = exception.toString();
          _notify();
        }
      }
    }
    if (stale()) return;

    // Mismo motor (Spotify, radio de YouTube y filtro de coherencia) que el autoplay.
    final engine = await _engineSuggestions();
    if (stale()) return;
    for (var i = 0; i < engine.length; i++) {
      candidates.add(
        DjCandidate(
          engine[i].track,
          engine[i].reason,
          prior: 0.5 / (1 + i / 5),
          bucket: engine[i].bucket,
        ),
      );
    }

    // Recompute after the awaits: the user may have queued tracks meanwhile.
    final limit = djUpcomingTarget - _upcomingCount;
    if (limit <= 0) return;
    _personalDjSeenKeys.addAll(queue.expand(recommendationTrackKeys));
    final signals = _djArtistSignals();
    final picks = rankDjCandidates(
      candidates: [
        for (final candidate in candidates)
          if (isNativePlayable(candidate.track)) candidate,
      ],
      profile: profile.vector,
      limit: limit,
      current: current,
      blockedKeys: _personalDjSeenKeys,
      recentKeys: recentTracks.take(20).expand(recommendationTrackKeys).toSet(),
      skippedArtists: signals.skipped,
      queueTail: queue.skip(max(0, queueIndex)).toList(),
      filters: djFilters,
      lambda: 1 - _djDiversity,
      artistCooldown: _djArtistCooldown,
      heardKeys: {for (final t in tracks) ...recommendationTrackKeys(t)},
      heardShare: djHeardShare(_djMode),
      coherence: seedCoherence(
        features: profile.features,
        favoriteArtists: signals.favorites,
        listenedArtists: signals.listened,
        current: current,
        graph: artistGraph,
      ),
      graph: artistGraph,
      adjust: (t) =>
          djModeBonus(
            _djMode,
            t,
            now: DateTime.now(),
            knownArtists: {
              for (final r in recentTracks.take(30)) djPrimaryArtist(r),
            },
          ) +
          followedArtistBonus(t, followedArtistKeys()),
    );
    for (final pick in picks) {
      queue.add(pick.track);
      _personalDjSeenKeys.addAll(recommendationTrackKeys(pick.track));
      personalDjReasons[pick.track.id] = pick.reason;
    }
    if (picks.isNotEmpty) {
      await _saveQueue();
      _notify();
    }
  }

  /// Reason of the next DJ-picked track, for the DJ panel.
  String? get personalDjNextReason {
    if (!_personalDjActive || shuffle) return null;
    for (final track in queue.skip(queueIndex + 1)) {
      final reason = personalDjReasons[track.id];
      if (reason != null) return '${track.title} · $reason';
    }
    return null;
  }

  Duration? get sleepRemaining {
    if (_sleepAtTrackEnd) {
      final left = audio.duration - audio.position;
      return left.isNegative ? Duration.zero : left;
    }
    final end = _sleepEnd;
    if (end == null) return null;
    final remaining = end.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Future<void> initialize({bool mediaControls = true}) async {
    ready = false;
    error = null;
    try {
      tracks = await database.readTracks();
      favoriteIds = await database.readFavorites();
      playlists = await database.readPlaylists();
      _loadPlaylistPhotos();
      downloads = await database.readDownloads();
      final legacyRoot = Directory(p.join(supportDirectory.path, 'downloads'));
      await legacyRoot.create(recursive: true);
      for (final job in downloads) {
        job.destinationRoot ??= await _canonicalDownloadRoot(
          p.join(supportDirectory.path, 'downloads'),
        );
        await database.saveDownload(job);
      }
      recentTracks = _lookup(await database.readHistory());
      _djMode =
          DjMode.values.asNameMap()[preferences.getString('djMode')] ??
          DjMode.discover;
      _djDiversity =
          (preferences.getDouble('djDiversity') ?? djDefaultDiversity).clamp(
            0.0,
            djMaxDiversity,
          );
      _djArtistCooldown = preferences.getBool('djArtistCooldown') ?? true;
      final savedFilters = preferences.getString('djFilters');
      if (savedFilters != null) {
        try {
          _djFilters = DjFilters.fromJson(
            jsonDecode(savedFilters) as Map<String, dynamic>,
          );
        } on FormatException {
          _djFilters = const DjFilters();
        } on TypeError {
          _djFilters = const DjFilters();
        }
      }
      _djEvents = (preferences.getStringList('djEvents') ?? const [])
          .map(DjEvent.decode)
          .whereType<DjEvent>()
          .toList();
      final savedPalette = preferences.getString('accentPalette');
      accentPalette =
          savedPalette == 'automatic' ||
              accentPaletteColors.containsKey(savedPalette)
          ? savedPalette!
          : (preferences.getBool('adaptiveColors') == false
                ? 'terracotta'
                : 'automatic');
      adaptiveColors = accentPalette == 'automatic';
      accentColor = accentPaletteColors[accentPalette] ?? accentColor;
      reducedMotion = preferences.getBool('reducedMotion') ?? false;
      experimentalProgressivePlayback =
          source.supportsExperimentalProgressivePlayback &&
          (preferences.getBool('experimentalProgressivePlayback') ?? false);
      if (source.supportsExperimentalProgressivePlayback) {
        source.setExperimentalProgressivePlayback(
          experimentalProgressivePlayback,
        );
      }
      themeKind =
          const {
            'atelier',
            'modern',
            'brasa',
            'slush',
          }.contains(preferences.getString('themeKind'))
          ? preferences.getString('themeKind')!
          : 'modern';
      audioQuality =
          AudioQuality.values.asNameMap()[preferences.getString(
            'audioQuality',
          )] ??
          AudioQuality.high;
      _applyAudioQuality();
      discord.enabled = preferences.getBool('discordPresence') ?? true;
      themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == preferences.getString('themeMode'),
        orElse: () => ThemeMode.dark,
      );
      profileName = jamCleanName(
        preferences.getString('profileName') ?? '',
        fallback: '',
      );
      try {
        final file = File(p.join(supportDirectory.path, 'profile_avatar.bin'));
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty && bytes.length <= avatarMaxOutputBytes) {
            profileAvatar = bytes;
          }
        }
      } catch (_) {}
      eq.load();
      queue = _lookup(preferences.getStringList('queue') ?? []);
      queueIndex = queue.isEmpty
          ? -1
          : (preferences.getInt('queueIndex') ?? 0).clamp(0, queue.length - 1);
      _resumePosition = Duration(
        milliseconds: preferences.getInt('position') ?? 0,
      );
      repeat = RepeatMode.values.firstWhere(
        (mode) => mode.name == preferences.getString('repeat'),
        orElse: () => RepeatMode.off,
      );
      shuffle = preferences.getBool('shuffle') ?? false;
      autoRefill = preferences.getBool('autoRefill') ?? true;
      final directory = preferences.getString('toolDirectory');
      if (directory != null && canConfigureDownloadDirectory) {
        try {
          await source.configureToolDirectory(directory);
        } catch (_) {
          error =
              'La carpeta de herramientas cambió. Configúrala en Ajustes para usar YouTube.';
        }
      }
    } catch (exception) {
      _report(exception);
    }
    // Library restoration must not prevent native playback initialization.
    try {
      if (!_audioInitialized) {
        await audio.initialize();
        _audioInitialized = true;
      }
      audio.setVolume(preferences.getDouble('volume') ?? 0.75);
      eq.apply();
      if (_completedSubscription == null) {
        audio.addListener(_audioChanged);
        _completedSubscription = audio.completed.listen(
          (_) => unawaited(_onCompleted()),
        );
      }
      if (Platform.isAndroid) {
        _nativeActions ??= audio.mediaActions.listen((action) {
          if (_jamPlaybackActive) return;
          final seekTo = action.startsWith('seek:')
              ? int.tryParse(action.substring(5))
              : null;
          final task = switch (action) {
            _ when seekTo != null => seek(Duration(milliseconds: seekTo)),
            'next' => next(),
            'previous' => previous(),
            'play' => resumePlayback(),
            'pause' => pausePlayback(),
            'stop' => stopPlayback(),
            _ => Future<void>.value(),
          };
          unawaited(task.catchError(_report));
        });
      } else if (mediaControls && !Platform.isLinux && _controls == null) {
        // (audio_service no tiene implementación para Linux.)
        try {
          _controls = MediaControls(
            audio: audio,
            onPlay: resumePlayback,
            onPause: pausePlayback,
            onStop: stopPlayback,
            onNext: next,
            onPrevious: previous,
            onSeek: seek,
          );
          await _controls!.initialize();
          _controls!.updateTrack(currentTrack);
        } catch (_) {
          error =
              'No se pudieron iniciar los controles multimedia del sistema. Puedes usar los controles de la app.';
        }
      }
      if (currentTrack != null) unawaited(_updateAccent(currentTrack!));
      await source.initializeUpdates(
        isPlaybackActive: () =>
            audio.isPlaying ||
            audio.isBuffering ||
            busy ||
            _jamPlaybackActive ||
            _youtubeMusicActive,
        onStatusChanged: _notify,
      );
    } catch (exception) {
      _report(exception);
    } finally {
      ready = _audioInitialized;
      _notify();
    }
  }

  List<Track> _lookup(List<String> ids) {
    final byId = {for (final track in tracks) track.id: track};
    return ids.map((id) => byId[id]).whereType<Track>().toList();
  }

  void _audioChanged() {
    _updateDiscord();
    // Scrobble: nunca en Jam compartido (track null reinicia la sesión).
    final loaded = currentTrack;
    lastfm?.observe(
      !_jamPlaybackActive && loaded != null && _loadedTrackId == loaded.id
          ? loaded
          : null,
      playing: audio.isPlaying,
      position: audio.position,
      duration: audio.duration,
    );
    if (_jamPlaybackActive) {
      _notify();
      return;
    }
    _adoptWebTrackMetadata();
    final audioError = audio.lastError;
    final failure = YouTubeRequestPolicy.classify(audioError ?? '');
    if (audioError != null && audioError != error) error = audioError;
    if (_playIntent &&
        !_recovering &&
        audio.isPlaying &&
        audio.position - _recoveryProgressPosition >=
            const Duration(seconds: 60)) {
      _expiryRetries = 0;
      _recoveryProgressPosition = audio.position;
    }
    if (audio.isPlaying && audio.position >= _openFailureWindow) {
      _openFailureSkips = 0;
    }
    if (_pendingPlay != null &&
        _pendingPlay!.id == currentTrack?.id &&
        _pendingPlayGeneration == _playGeneration &&
        audioError == null &&
        audio.isPlaying &&
        audio.position >= _openFailureWindow) {
      unawaited(_confirmPlay());
    }
    // The web engine reports its own actionable errors; no stream to renew.
    final streamPlayback = _usingRemote && !webPlayback;
    if (audioError != null &&
        streamPlayback &&
        _recoverableRemoteTrackId == currentTrack?.id &&
        _playIntent &&
        !_recovering &&
        !busy &&
        _expiryRetries < _maxStreamRecoveryAttempts &&
        _isRecoverableStreamError(audioError)) {
      unawaited(_recoverExpiredStream());
    } else if (audioError != null &&
        streamPlayback &&
        _recoverableRemoteTrackId == currentTrack?.id &&
        _playIntent &&
        !_recovering &&
        !busy &&
        audio.position < _openFailureWindow &&
        _isRecoverableStreamError(audioError)) {
      // Retries spent and the stream never really started: next track.
      _skipUnopenableStream();
    } else if (audioError != null &&
        streamPlayback &&
        (failure == YouTubeFailure.blocked ||
            (failure == YouTubeFailure.accessDenied &&
                !(currentTrack != null &&
                    source.isExpiredStream(currentTrack!))))) {
      source.reportPlaybackFailure(audioError);
    }
    _maybePrefetchNext();
    if (audio.isPlaying &&
        DateTime.now().difference(_lastSnapshot).inSeconds >= 5) {
      _lastSnapshot = DateTime.now();
      unawaited(_saveQueue().catchError((Object _) {}));
    }
    // Solo cambió la posición: los widgets de progreso escuchan a `audio`,
    // el resto del árbol no necesita reconstruirse 5 veces por segundo.
    final sig = Object.hash(
      currentTrack?.id,
      audio.isPlaying,
      audio.isBuffering,
      audio.lastError,
      busy,
      _usingRemote,
    );
    final now = DateTime.now();
    if (sig == _audioSig &&
        now.difference(_lastAudioNotify) < const Duration(seconds: 1)) {
      return;
    }
    _audioSig = sig;
    _lastAudioNotify = now;
    _notify();
  }

  int _failedSkips = 0;

  Track? _pendingPlay;
  int _pendingPlayGeneration = -1;

  /// Escribe historial y memoria de la pista cargada cuando suena de verdad.
  Future<void> _confirmPlay() async {
    final track = _pendingPlay;
    final generation = _pendingPlayGeneration;
    if (track == null) return;
    _pendingPlay = null;
    try {
      await database.recordPlay(track.id);
      if (generation != _playGeneration || _disposed) return;
      recentTracks = [
        track,
        ...recentTracks.where((item) => item.id != track.id),
      ].take(100).toList();
      // La memoria anti-repetición del motor cuenta lo que SUENA.
      unawaited(
        RecsMemory.shared
            .record([track], DateTime.now())
            .then((_) {}, onError: (Object _) {}),
      );
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  /// A stream that errors before this much playback "never opened".
  static const _openFailureWindow = Duration(seconds: 5);
  static const _maxOpenFailureSkips = 3;
  int _openFailureSkips = 0;

  /// Moves on when a stream that never started failed past its retries, so a
  /// dead URL does not park the queue. Bounded to avoid a loop of failures.
  void _skipUnopenableStream() {
    if (!_playIntent ||
        _openFailureSkips >= _maxOpenFailureSkips ||
        !_hasNextToAdvance) {
      return;
    }
    _openFailureSkips++;
    unawaited(next(fromCompletion: true));
  }

  bool get _hasNextToAdvance => shuffle
      ? queue.length - _shufflePlayed.length > 0
      : repeat == RepeatMode.all || queueIndex < queue.length - 1;

  /// true solo cuando `next(fromCompletion)` lleva a la pista que va a sonar.
  bool _autoAdvance = false;
  int? _audioSig;
  DateTime _lastAudioNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// Warms the next queue item's URL once; shuffle and repeat-one skip it.
  void _maybePrefetchNext() {
    final track = currentTrack;
    if (_prefetching ||
        track == null ||
        !_usingRemote ||
        !_playIntent ||
        _recovering ||
        !audio.isPlaying ||
        _loadedTrackId != track.id ||
        shuffle ||
        repeat == RepeatMode.one) {
      return;
    }
    final duration = audio.duration;
    if (audio.position < const Duration(seconds: 10) &&
        !(duration > Duration.zero && audio.position * 2 >= duration)) {
      return;
    }
    final nextIndex = queueIndex + 1 < queue.length
        ? queueIndex + 1
        : repeat == RepeatMode.all && queue.length > 1
        ? 0
        : -1;
    if (nextIndex < 0) return;
    final upcoming = queue[nextIndex];
    final key = '$_playGeneration:${upcoming.id}';
    if (_prefetchKey == key ||
        upcoming.id == track.id ||
        upcoming.isLocal ||
        upcoming.isPendingSpotifyMatch) {
      return;
    }
    _prefetchKey = key;
    _prefetching = true;
    final generation = _playGeneration;
    unawaited(
      source.prefetch(upcoming).catchError((Object _) {}).whenComplete(() {
        // A queue change meanwhile only wastes the cached URL; allow a new one.
        _prefetching = false;
        if (generation != _playGeneration) _prefetchKey = null;
      }),
    );
  }

  void _adoptWebTrackMetadata() {
    final track = currentTrack;
    final metadata = audio.currentTrackMetadata;
    if (!usesYouTubeWebAudio ||
        busy ||
        track == null ||
        _loadedTrackId != track.id ||
        !_usingRemote ||
        metadata == null ||
        metadata.title.trim().isEmpty ||
        metadata.title == 'YouTube Music') {
      return;
    }
    final placeholder = track.title == 'YouTube Music';
    final missingCover =
        track.artworkUrl == null || track.artworkUrl!.trim().isEmpty;
    final improveCover =
        track.spotifyUri == null &&
        metadata.title.trim() == track.title.trim() &&
        metadata.artworkUrl != null &&
        metadata.artworkUrl != track.artworkUrl &&
        (missingCover ||
            artworkWidthHint(metadata.artworkUrl) >
                artworkWidthHint(track.artworkUrl)) &&
        (missingCover || _isWebArtwork(track.artworkUrl!)) &&
        _isWebArtwork(metadata.artworkUrl!);
    if (!placeholder && !improveCover) return;
    try {
      final video = WebMusicSource.audioUriForTrack(track).queryParameters['v'];
      if (metadata.id != 'yt:$video') return;
    } on StateError {
      return;
    }
    final updated = Track(
      id: track.id,
      title: placeholder ? metadata.title.trim() : track.title,
      artist: !placeholder || metadata.artist.trim().isEmpty
          ? track.artist
          : metadata.artist.trim(),
      duration: track.duration,
      artworkUrl: improveCover
          ? metadata.artworkUrl
          : missingCover
          ? metadata.artworkUrl
          : track.artworkUrl,
      pageUrl: track.pageUrl,
      localPath: track.localPath,
      album: track.album,
      genres: track.genres,
      spotifyUri: track.spotifyUri,
      spotifyMatchPending: track.spotifyMatchPending,
    );
    queue[queueIndex] = updated;
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].id == updated.id) tracks[i] = updated;
    }
    for (var i = 0; i < recentTracks.length; i++) {
      if (recentTracks[i].id == updated.id) recentTracks[i] = updated;
    }
    _controls?.updateTrack(updated);
    unawaited(audio.updateTrackMetadata(updated).catchError(_report));
    unawaited(database.saveTrack(updated).catchError(_report));
  }

  bool _isWebArtwork(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        const [
          'ytimg.com',
          'ggpht.com',
          'googleusercontent.com',
        ].any((domain) => uri.host == domain || uri.host.endsWith('.$domain'));
  }

  bool _isRecoverableStreamError(String message) {
    final failure = YouTubeRequestPolicy.classify(message);
    if (failure == YouTubeFailure.blocked ||
        RegExp(r'\bblocked\b', caseSensitive: false).hasMatch(message)) {
      return false;
    }
    if (failure == YouTubeFailure.accessDenied) {
      return currentTrack != null && source.isExpiredStream(currentTrack!);
    }
    return RegExp(
      r'410|4xx\s+client\s+error|expired|termin[oó] antes de completar|premature\s+(?:eof|end)|timed?\s*out|timeout|socketexception|httpexception|connection\s+(?:reset|closed|aborted)|network_connection_(?:failed|timeout)|broken\s+pipe|unexpected\s+eof',
      caseSensitive: false,
    ).hasMatch(message);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _report(Object exception) {
    error = exception.toString().replaceFirst(
      RegExp(r'^(Exception|StateError|Bad state):\s*'),
      '',
    );
    _notify();
  }

  void clearError() {
    error = null;
    _notify();
  }

  Future<void> _remember(Track track) async {
    final index = tracks.indexWhere((item) => item.id == track.id);
    if (index >= 0 &&
        track.localPath == null &&
        tracks[index].localPath != null) {
      track = track.copyWith(localPath: tracks[index].localPath);
    }
    if (index < 0) {
      tracks.insert(0, track);
    } else {
      tracks[index] = track;
    }
    await database.saveTrack(track);
  }

  /// Searches [query]; a new query discards any response still in flight.
  Future<void> search(String query, {SearchKind? kind}) async {
    final generation = ++_searchGeneration;
    _searchQuery = query.trim();
    if (kind != null) searchKind = kind;
    searchDetail = null;
    searchError = null;
    searchLoadingMore = false;
    _searchContinuation = null;
    searchResults = [];
    searchEntries = [];
    if (_searchQuery.isEmpty) {
      searching = false;
      _notify();
      return;
    }
    searching = true;
    error = null;
    unawaited(_rememberSearch(_searchQuery));
    _notify();
    try {
      if (usesOfficialYouTubeMusic || usesYouTubeWebAudio) {
        final needle = _searchQuery.toLowerCase();
        final local = _nativeLibrary.where(
          (track) => [
            track.title,
            track.artist,
            track.album ?? '',
            ...track.genres,
          ].any((text) => text.toLowerCase().contains(needle)),
        );
        final result = local.toList();
        if (generation == _searchGeneration) searchResults = result;
        if (usesYouTubeWebAudio) {
          try {
            final linked = await source.search(_searchQuery);
            final seen = result.map((track) => track.id).toSet();
            result.addAll(linked.where((track) => seen.add(track.id)));
          } catch (exception) {
            if (generation == _searchGeneration) _report(exception);
          }
          if (generation == _searchGeneration) searchResults = result;
        }
      } else {
        final page = await source.searchPage(_searchQuery, searchKind);
        if (generation != _searchGeneration) return;
        searchResults = page.tracks;
        searchEntries = page.entries;
        _searchContinuation = page.continuation;
      }
      // Search results feed the DJ vector store.
      if (generation == _searchGeneration) {
        unawaited(_embedDjTracks(searchResults));
      }
    } catch (exception) {
      if (generation == _searchGeneration) searchError = _plain(exception);
    } finally {
      if (generation == _searchGeneration) {
        searching = false;
        _notify();
      }
    }
  }

  Future<void> setSearchKind(SearchKind kind) =>
      kind == searchKind && _searchQuery.isEmpty
      ? Future.value()
      : search(_searchQuery, kind: kind);

  Future<void> loadMoreSearch() async {
    final token = _searchContinuation;
    if (token == null || searching || searchLoadingMore) return;
    final generation = _searchGeneration;
    searchLoadingMore = true;
    searchError = null;
    _notify();
    try {
      final page = await source.searchPage(
        _searchQuery,
        searchKind,
        continuation: token,
      );
      if (generation != _searchGeneration) return;
      final tracks = {for (final t in searchResults) t.id};
      final entries = {for (final e in searchEntries) e.browseId};
      searchResults = [
        ...searchResults,
        ...page.tracks.where((t) => tracks.add(t.id)),
      ];
      searchEntries = [
        ...searchEntries,
        ...page.entries.where((e) => entries.add(e.browseId)),
      ];
      _searchContinuation = page.continuation;
    } catch (exception) {
      if (generation == _searchGeneration) searchError = _plain(exception);
    } finally {
      if (generation == _searchGeneration) {
        searchLoadingMore = false;
        _notify();
      }
    }
  }

  /// Lo fija el shell: cambia a Buscar y abre el perfil.
  Future<void> Function(String name)? artistNavigator;

  void openArtist(String name) {
    final n = name.split(RegExp(r'\s*(?:,|&| x | feat\.?| ft\.?)\s*')).first;
    if (n.trim().isNotEmpty) unawaited(artistNavigator?.call(n.trim()));
  }

  /// Busca al artista por nombre y abre su perfil con todas sus canciones.
  Future<void> openArtistProfile(String name) async {
    try {
      final page = await source.searchPage(name, SearchKind.artists);
      final entry = page.entries.firstOrNull;
      if (entry == null) {
        error = 'No encontré el perfil de $name.';
        _notify();
        return;
      }
      await openSearchEntry(entry);
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> openSearchEntry(SearchEntry? entry) async {
    final generation = ++_searchDetailGeneration;
    searchDetail = entry;
    searchDetailTracks = [];
    searchDetailError = null;
    searchDetailLoading = entry != null;
    _notify();
    if (entry == null) return;
    try {
      final loaded = await source.browseTracks(entry);
      if (generation == _searchDetailGeneration) searchDetailTracks = loaded;
    } catch (exception) {
      if (generation == _searchDetailGeneration) {
        searchDetailError = _plain(exception);
      }
    } finally {
      if (generation == _searchDetailGeneration) {
        searchDetailLoading = false;
        _notify();
      }
    }
  }

  Future<void> _rememberSearch(String query) => preferences.setStringList(
    'recentSearches',
    [query, ...recentSearches.where((item) => item != query)].take(10).toList(),
  );

  Future<void> removeRecentSearch(String query) async {
    await preferences.setStringList(
      'recentSearches',
      recentSearches.where((item) => item != query).toList(),
    );
    _notify();
  }

  Future<void> clearRecentSearches() async {
    await preferences.remove('recentSearches');
    _notify();
  }

  String _plain(Object exception) => exception.toString().replaceFirst(
    RegExp(r'^(Exception|StateError|Bad state):\s*'),
    '',
  );

  /// [replaceQueue] false (resultados de búsqueda/descubrimiento): suena solo
  /// [track] y la cola de por delante se conserva; [context] se ignora.
  Future<void> playTrack(
    Track track, {
    List<Track>? context,
    bool replaceQueue = true,
  }) async {
    if (_jamPlaybackActive) return;
    final selected =
        tracks.where((item) => item.id == track.id).firstOrNull ?? track;
    if (_routeToYouTubeMusic(selected)) return;
    // Elegir a mano una pista suelta (replaceQueue false) no apaga el DJ ni
    // reemplaza su cola; solo reemplazar la cola lo detiene.
    if (_personalDjActive && replaceQueue) stopPersonalDj();
    await _playTrack(track, context: context, replaceQueue: replaceQueue);
  }

  Future<void> _playTrack(
    Track track, {
    List<Track>? context,
    bool replaceQueue = true,
  }) async {
    _playIntent = true;
    _expiryRetries = 0;
    if (replaceQueue) _sleepAtTrackEnd = false;
    final remembered = {for (final item in tracks) item.id: item};
    final selected = remembered[track.id] ?? track;
    if (_routeToYouTubeMusic(selected)) return;
    final seen = <String>{};
    if (!replaceQueue) {
      // Lo sonado se queda; de lo que viene solo sigue lo puesto a mano (o la
      // cola del DJ): el resto de la playlist/radio anterior se descarta para
      // no volver a ella. El relleno de _playCurrent completa si faltan.
      final head = queueIndex >= 0 && queueIndex < queue.length
          ? queueIndex + 1
          : 0;
      final ahead = [
        for (final t in queue.skip(head))
          if (t.id != selected.id &&
              !recommendationTracksMatch(t, selected) &&
              (_personalDjActive || manualQueuedIds.contains(t.id)))
            t,
      ];
      queue = [...queue.take(head), selected, ...ahead];
      queueIndex = head;
      autoAddedIds.remove(selected.id);
      manualQueuedIds.remove(selected.id);
      _shuffleHistory.clear();
      _shufflePlayed
        ..clear()
        ..add(queueIndex);
      _resumePosition = Duration.zero;
      await _playCurrent();
      return;
    }
    queue = [];
    autoAddedIds.clear();
    manualQueuedIds.clear();
    for (final candidate in context?.isNotEmpty == true ? context! : [track]) {
      final item = remembered[candidate.id] ?? candidate;
      if ((usesOfficialYouTubeMusic || usesYouTubeWebAudio) &&
          !isNativePlayable(item)) {
        continue;
      }
      if (item.id != selected.id && recommendationTracksMatch(item, selected)) {
        continue;
      }
      final keys = recommendationTrackKeys(item);
      if (keys.any(seen.contains)) continue;
      seen.addAll(keys);
      queue.add(item);
    }
    queueIndex = queue.indexWhere((item) => item.id == selected.id);
    if (queueIndex < 0) {
      queue.insert(0, selected);
      queueIndex = 0;
    }
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> playQueueAt(int index) async {
    if (_jamPlaybackActive) return;
    if (index < 0 || index >= queue.length) return;
    if (_routeToYouTubeMusic(queue[index])) return;
    _playIntent = true;
    _expiryRetries = 0;
    queueIndex = index;
    _resumePosition = Duration.zero;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(index);
    await _playCurrent();
  }

  Future<void> _playCurrent({bool fromRecovery = false}) async {
    final autoAdvance = _autoAdvance;
    _autoAdvance = false;
    if (_jamPlaybackActive) return;
    if (!_audioInitialized) {
      _playIntent = false;
      _report(
        StateError('El audio no está preparado. Reintenta iniciar Aurora.'),
      );
      return;
    }
    if (!fromRecovery) _cancelRecovery();
    final track = currentTrack;
    if (track == null) return;
    if (_routeToYouTubeMusic(track)) return;
    _youtubeMusicActive = false;
    youtubeMusicRequest = null;
    final generation = ++_playGeneration;
    if (!fromRecovery) _cancelPendingResolution();
    if (track.isPendingSpotifyMatch) {
      _playIntent = false;
      _recoverableRemoteTrackId = null;
      busy = true;
      _notify();
      try {
        try {
          await audio.stop();
        } catch (_) {}
        if (generation != _playGeneration || _disposed) return;
        _loadedTrackId = null;
        _loadedAudioInput = null;
        _usingRemote = false;
        _report(
          StateError(
            'Esta canción de Spotify aún no tiene una coincidencia. '
            'Abre la biblioteca y elige su video de YouTube.',
          ),
        );
      } finally {
        if (generation == _playGeneration) {
          busy = false;
          _notify();
        }
      }
      return;
    }
    if (_recoveryTrackId != track.id) {
      _recoveryTrackId = track.id;
      _expiryRetries = 0;
    }
    busy = true;
    error = null;
    _loadedTrackId = null;
    _notify();
    try {
      await audio.stop();
      if (generation != _playGeneration || _disposed) return;
      _loadedAudioInput = null;
      for (final item in List<Track>.of(queue)) {
        await _remember(item);
        if (generation != _playGeneration || _disposed) return;
      }
      if (generation != _playGeneration || _disposed) return;
      final remembered = tracks
          .where((item) => item.id == track.id)
          .firstOrNull;
      final local = track.localPath ?? remembered?.localPath;
      final availableLocally = local != null && await File(local).exists();
      if (generation != _playGeneration || _disposed) return;
      if (!availableLocally &&
          _routeToYouTubeMusic(track.copyWith(clearLocalPath: true))) {
        return;
      }
      _usingRemote = !availableLocally;
      if (!availableLocally &&
          track.pageUrl == null &&
          !(usesYouTubeWebAudio && WebMusicSource.isOnlineYouTube(track))) {
        throw StateError(
          'El archivo ya no está disponible. Vuelve a importarlo.',
        );
      }
      if (!availableLocally && source.supportsPlaybackCache) {
        final page = Uri.tryParse(track.pageUrl ?? '');
        final videoId = page?.host == 'youtu.be'
            ? page?.pathSegments.firstOrNull
            : page?.queryParameters['v'];
        if (videoId != null &&
            RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId)) {
          _pendingResolveVideoId = videoId;
        }
      }
      var resolved = availableLocally
          ? ResolvedAudio(input: local, duration: track.duration)
          : await source.resolve(track);
      if (generation != _playGeneration || _disposed) return;
      _pendingResolveVideoId = null;
      _loadedAudioInput = resolved.input;
      // Before load so the system session never shows the previous track.
      _publishMetadata(track);
      try {
        await audio.load(resolved, start: _resumePosition);
      } catch (loadError) {
        // The CDN can refuse one URL (410 from the loopback proxy, expiry):
        // a fresh resolve usually lands on another URL, so retry once.
        if (availableLocally ||
            fromRecovery ||
            generation != _playGeneration ||
            _disposed ||
            !_isRecoverableStreamError('$loadError')) {
          rethrow;
        }
        source.invalidateResolvedAudio(track);
        resolved = await source.resolve(track);
        if (generation != _playGeneration || _disposed) return;
        _loadedAudioInput = resolved.input;
        await audio.load(resolved, start: _resumePosition);
      }
      if (_youtubeMusicActive) {
        await audio.pause();
        return;
      }
      if (generation != _playGeneration || _disposed) return;
      _resumePosition = Duration.zero;
      _loadedTrackId = track.id;
      if (_controls != null && !await _controls!.activate()) {
        throw StateError(
          'Otra aplicación está usando el audio. Intenta reproducir de nuevo.',
        );
      }
      if (generation != _playGeneration || _disposed) return;
      await audio.play();
      if (_youtubeMusicActive) {
        await audio.pause();
        return;
      }
      if (generation != _playGeneration || _disposed) return;
      _recoverableRemoteTrackId = _usingRemote ? track.id : null;
      final readyTrack = audio.duration > Duration.zero
          ? track.copyWith(duration: audio.duration, localPath: local)
          : track;
      if (generation == _playGeneration &&
          queueIndex >= 0 &&
          queueIndex < queue.length) {
        queue[queueIndex] = readyTrack;
      }
      await _remember(readyTrack);
      if (generation != _playGeneration || _disposed) return;
      _publishMetadata(readyTrack);
      // Historial y memoria esperan a que suene de verdad (_confirmPlay):
      // una pista que falla al abrir no cuenta como escuchada.
      _pendingPlay = readyTrack;
      _pendingPlayGeneration = generation;
      await _saveQueue();
      _failedSkips = 0;
      unawaited(_updateAccent(track));
    } catch (exception) {
      if (generation == _playGeneration) {
        _report(exception);
        // Una pista que no resuelve no debe dejar la cola parada (a menudo
        // viene del DJ); salta a la siguiente, con tope para no hacer bucle.
        if (_playIntent &&
            autoAdvance &&
            !fromRecovery &&
            _failedSkips < 3 &&
            _hasNextToAdvance) {
          _failedSkips++;
          unawaited(next(fromCompletion: true));
        }
      }
    } finally {
      if (generation == _playGeneration) {
        _pendingResolveVideoId = null;
        busy = _recovering && fromRecovery;
        _adoptWebTrackMetadata();
        _notify();
        // Con menos de $kQueueLookahead por delante se deja lista la continuación (DJ y red).
        // _playIntent, no audio.isPlaying: en Android/web ese estado llega
        // después por evento y el relleno se saltaba hasta el final.
        if (_loadedTrackId == track.id && _playIntent) {
          unawaited(_topUpQueue());
        }
      }
    }
  }

  /// El DJ propone primero; la red de seguridad cubre lo que falte.
  Future<void> _topUpQueue() async {
    await _refillPersonalDjQueue();
    await _refillQueue();
  }

  /// Suspend personal playback before Jam starts using [audio].
  Future<void> beginJamPlayback() async {
    if (_jamPlaybackActive) return;
    if (_loadedTrackId != null) _resumePosition = audio.position;
    _jamPlaybackActive = true;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    ++_playGeneration;
    busy = false;
    stopPersonalDj();
    await audio.pause();
    _controls?.updateTrack(null);
    _notify();
  }

  /// Release Jam audio. The Jam bridge restores its captured personal session.
  Future<void> endJamPlayback() async {
    if (!_jamPlaybackActive) return;
    try {
      await audio.stop();
    } finally {
      _loadedTrackId = null;
      _loadedAudioInput = null;
      _recoverableRemoteTrackId = null;
      _usingRemote = false;
      _playIntent = false;
      _jamPlaybackActive = false;
      _jamNowPlaying = null;
      _controls?.updateTrack(currentTrack);
      _notify();
    }
  }

  Future<void> resumePlayback() async {
    if (_jamPlaybackActive) return;
    if (_youtubeMusicActive) return;
    if (currentTrack == null) return;
    _playIntent = true;
    if (_loadedTrackId != currentTrack!.id || audio.lastError != null) {
      if (audio.lastError != null) {
        _resumePosition = audio.position > Duration.zero
            ? audio.position
            : _resumePosition;
        _expiryRetries = 0;
      }
      await _playCurrent();
      return;
    }
    try {
      final generation = _playGeneration;
      if (_controls != null && !await _controls!.activate()) return;
      if (generation != _playGeneration || _disposed) return;
      await audio.play();
      if (_youtubeMusicActive) {
        await audio.pause();
        return;
      }
      if (_personalDjActive) unawaited(_refillPersonalDjQueue());
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> _recoverExpiredStream() async {
    final trackId = currentTrack?.id;
    final occurrence = queueIndex;
    final recoveryGeneration = ++_recoveryGeneration;
    final failedError = audio.lastError;
    final resumePosition = audio.position > Duration.zero
        ? audio.position
        : _resumePosition;
    if (trackId == null || _playGeneration == 0) return;
    _recovering = true;
    busy = true;
    _notify();
    _resumePosition = resumePosition;
    var exhausted = false;
    try {
      while (_expiryRetries < _maxStreamRecoveryAttempts) {
        _expiryRetries++;
        await Future<void>.delayed(Duration(seconds: 2 * _expiryRetries));
        if (recoveryGeneration != _recoveryGeneration ||
            occurrence != queueIndex ||
            currentTrack?.id != trackId ||
            !_playIntent ||
            _disposed) {
          return;
        }
        _resumePosition = resumePosition;
        source.invalidateResolvedAudio(currentTrack!);
        await _playCurrent(fromRecovery: true);
        if (recoveryGeneration != _recoveryGeneration ||
            occurrence != queueIndex ||
            currentTrack?.id != trackId ||
            !_playIntent ||
            _disposed) {
          return;
        }
        if (_loadedTrackId == trackId &&
            audio.isPlaying &&
            audio.lastError == null) {
          _recoveryProgressPosition = audio.position;
          if (error == failedError) error = null;
          _notify();
          return;
        }
        if (error != null &&
            const {
              YouTubeFailure.blocked,
              YouTubeFailure.accessDenied,
            }.contains(YouTubeRequestPolicy.classify(error!))) {
          return;
        }
      }
      exhausted = true;
    } finally {
      if (recoveryGeneration == _recoveryGeneration) {
        _recovering = false;
        busy = false;
        _notify();
      }
    }
    if (exhausted &&
        resumePosition < _openFailureWindow &&
        recoveryGeneration == _recoveryGeneration &&
        occurrence == queueIndex &&
        currentTrack?.id == trackId &&
        !_disposed) {
      _skipUnopenableStream();
    }
  }

  void _cancelRecovery() {
    ++_recoveryGeneration;
    _recovering = false;
  }

  void _cancelPendingResolution() {
    final videoId = _pendingResolveVideoId;
    _pendingResolveVideoId = null;
    if (videoId != null) {
      unawaited(source.cancel('resolve:$videoId').catchError((Object _) {}));
    }
  }

  Future<void> togglePlayback() async {
    if (_jamPlaybackActive) return;
    if (_playIntent && (audio.isPlaying || busy || _recovering)) {
      await pausePlayback();
      await _saveQueue();
    } else {
      await resumePlayback();
    }
  }

  Future<void> pausePlayback() async {
    if (_jamPlaybackActive) return;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    ++_playGeneration;
    busy = false;
    await audio.pause();
    _notify();
  }

  /// Fin real de la cola (sin pistas que sumar): se avisa y el DJ sigue activo.
  Future<void> _endOfQueue() async {
    if (tracks.isEmpty && autoRefill) {
      error = 'No hay más canciones: añade música a tu biblioteca.';
    }
    await stopPlayback(keepDj: true);
  }

  Future<void> stopPlayback({bool keepDj = false}) async {
    if (_jamPlaybackActive) return;
    if (!keepDj) stopPersonalDj();
    ++_playGeneration;
    _sleepAtTrackEnd = false;
    _pendingPlay = null;
    _playIntent = false;
    _cancelRecovery();
    _cancelPendingResolution();
    busy = false;
    _recoverableRemoteTrackId = null;
    await audio.stop();
    _loadedAudioInput = null;
    _controls?.updateTrack(null);
    _loadedTrackId = null;
    _resumePosition = Duration.zero;
    await _saveQueue();
    _notify();
  }

  Future<void> seek(Duration position) async {
    if (_jamPlaybackActive) return;
    if (_loadedTrackId == null) return;
    try {
      await audio.seek(position);
      await _saveQueue();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> _onCompleted() async {
    if (_jamPlaybackActive) return;
    if (_youtubeMusicActive) return;
    if (!_playIntent || _disposed) return;
    final duration = audio.duration;
    if (duration > Duration.zero &&
        audio.position + const Duration(seconds: 2) < duration) {
      return;
    }
    _recordDjSignal(DjSignal.complete);
    if (_pendingPlayGeneration == _playGeneration) await _confirmPlay();
    if (_sleepAtTrackEnd) {
      _sleepAtTrackEnd = false;
      _notify();
      await pausePlayback();
      return;
    }
    if (repeat == RepeatMode.one) {
      _resumePosition = Duration.zero;
      await _playCurrent();
      return;
    }
    final generation = _playGeneration;
    final occurrence = queueIndex;
    final hasNoUpcoming = shuffle
        ? queue.length - _shufflePlayed.length <= 0
        : queueIndex == queue.length - 1;
    if (hasNoUpcoming && (_personalDjActive || _canAutoRefill)) {
      await _topUpQueue();
      if (!_playIntent ||
          _disposed ||
          generation != _playGeneration ||
          occurrence != queueIndex) {
        return;
      }
    }
    await next(fromCompletion: true);
  }

  Future<void> next({bool fromCompletion = false}) async {
    _autoAdvance = fromCompletion;
    if (_jamPlaybackActive) return;
    if (_youtubeMusicActive) return;
    if (queue.isEmpty) return;
    final heard = _loadedTrackId == currentTrack?.id;
    final skipped =
        !fromCompletion && (!heard || djIsSkip(audio.position, audio.duration));
    if (skipped && heard) _recordDjSignal(DjSignal.skip);
    _playIntent = true;
    final pendingNext =
        _playNextCount > 0 && _playNextAnchorId == currentTrack?.id
        ? queueIndex + 1
        : null;
    if (shuffle && queue.length > 1) {
      // Aleatorio: saltar (Siguiente antes de djIsSkip: <30 s o <30 % de la
      // pista, o sin haber cargado) no cuenta como oída; sigue en la cola y
      // puede volver a salir en esta vuelta, pero nunca justo a continuación.
      if (skipped) _shufflePlayed.remove(queueIndex);
      List<int> unplayed() => List.generate(queue.length, (i) => i)
          .where(
            (i) =>
                i != queueIndex &&
                !_shufflePlayed.contains(i) &&
                (!(usesOfficialYouTubeMusic || usesYouTubeWebAudio) ||
                    isNativePlayable(queue[i])),
          )
          .toList();
      var candidates = unplayed();
      if (candidates.isEmpty &&
          repeat != RepeatMode.all &&
          (_personalDjActive || _canAutoRefill)) {
        // Autoplay: the DJ continues when the queue runs out.
        final generation = _playGeneration;
        await _refillPersonalDjQueue(force: true);
        await _refillQueue();
        if (generation != _playGeneration || _disposed || !_playIntent) return;
        candidates = unplayed();
      }
      if (candidates.isEmpty) {
        if (repeat != RepeatMode.all) {
          await _endOfQueue();
          return;
        }
        _shufflePlayed
          ..clear()
          ..add(queueIndex);
        candidates = List.generate(queue.length, (i) => i)
            .where(
              (i) =>
                  i != queueIndex &&
                  (!(usesOfficialYouTubeMusic || usesYouTubeWebAudio) ||
                      isNativePlayable(queue[i])),
            )
            .toList();
      }
      if (candidates.isEmpty) {
        await _endOfQueue();
        return;
      }
      _shuffleHistory.add(queueIndex);
      // «Reproducir a continuación» wins over the random pick.
      queueIndex = candidates.contains(pendingNext)
          ? pendingNext!
          : candidates[_random.nextInt(candidates.length)];
      _shufflePlayed.add(queueIndex);
    } else {
      int? nextIndex() =>
          [
                for (var i = queueIndex + 1; i < queue.length; i++) i,
                if (repeat == RepeatMode.all)
                  for (var i = 0; i <= queueIndex && i < queue.length; i++) i,
              ]
              .where(
                (i) =>
                    !(usesOfficialYouTubeMusic || usesYouTubeWebAudio) ||
                    isNativePlayable(queue[i]),
              )
              .firstOrNull;
      var target = nextIndex();
      if (target == null && _personalDjActive) {
        // Autoplay: the DJ continues when the queue runs out.
        final generation = _playGeneration;
        await _refillPersonalDjQueue(force: true);
        if (generation != _playGeneration || _disposed || !_playIntent) return;
        target = nextIndex();
      }
      if (target == null && _canAutoRefill) {
        final generation = _playGeneration;
        await _refillQueue();
        if (generation != _playGeneration || _disposed || !_playIntent) return;
        target = nextIndex();
      }
      if (target == null) {
        await _endOfQueue();
        return;
      }
      queueIndex = target;
    }
    if (queueIndex == pendingNext) {
      // Keep the remaining play-next items queued FIFO behind the new track.
      _playNextAnchorId = queue[queueIndex].id;
      _playNextCount--;
    }
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (_jamPlaybackActive) return;
    if (_youtubeMusicActive) return;
    if (audio.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (queue.isEmpty) return;
    _playIntent = true;
    if (shuffle && _shuffleHistory.isNotEmpty) {
      queueIndex = _shuffleHistory.removeLast();
      _shufflePlayed.add(queueIndex);
    } else {
      final previous = [for (var i = queueIndex - 1; i >= 0; i--) i]
          .where(
            (i) =>
                !(usesOfficialYouTubeMusic || usesYouTubeWebAudio) ||
                isNativePlayable(queue[i]),
          )
          .firstOrNull;
      if (previous == null &&
          (usesOfficialYouTubeMusic || usesYouTubeWebAudio)) {
        return;
      }
      queueIndex = previous ?? 0;
    }
    _resumePosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> _saveQueue() async {
    if (_jamPlaybackActive) return;
    await preferences.setStringList('queue', queue.map((t) => t.id).toList());
    await preferences.setInt('queueIndex', queueIndex);
    await preferences.setInt(
      'position',
      (_loadedTrackId == null ? _resumePosition : audio.position)
          .inMilliseconds,
    );
  }

  Future<void> persistSession() => _saveQueue();
  Future<void> addToQueue(Track track) async {
    final selected =
        tracks.where((item) => item.id == track.id).firstOrNull ?? track;
    if (_routeToYouTubeMusic(selected)) return;
    if (queue.any((queued) => recommendationTracksMatch(queued, track))) return;
    await _remember(track);
    // Recheck after persistence: concurrent enqueue calls may finish together.
    if (queue.any((queued) => recommendationTracksMatch(queued, track))) return;
    queue.add(track);
    manualQueuedIds.add(track.id);
    if (_personalDjActive) {
      _personalDjSeenKeys.addAll(recommendationTrackKeys(track));
    }
    if (queueIndex < 0) queueIndex = 0;
    await _saveQueue();
    _notify();
  }

  String? _playNextAnchorId;
  int _playNextCount = 0;

  /// Inserts [track] right after the current one, FIFO among play-next calls.
  Future<void> playNext(Track track) async {
    if (queue.isEmpty || queueIndex < 0 || queueIndex >= queue.length) {
      return addToQueue(track);
    }
    bool matches(Track queued) => recommendationTracksMatch(queued, track);
    if (queue.indexWhere(matches) == queueIndex) return;
    if (!queue.any(matches)) await _remember(track);
    // Recheck after persistence: the queue may have changed meanwhile.
    if (queueIndex < 0 || queueIndex >= queue.length) return addToQueue(track);
    final currentId = queue[queueIndex].id;
    if (_playNextAnchorId != currentId) {
      _playNextAnchorId = currentId;
      _playNextCount = 0;
    }
    var moved = track;
    final from = queue.indexWhere(matches);
    if (from == queueIndex) return;
    if (from >= 0) {
      moved = queue.removeAt(from);
      if (from < queueIndex) {
        queueIndex--;
      } else if (from <= queueIndex + _playNextCount) {
        _playNextCount--;
      }
      _shuffleHistory.clear();
      _shufflePlayed
        ..clear()
        ..add(queueIndex);
    } else {
      final insertAt = queueIndex + 1 + _playNextCount;
      for (var i = 0; i < _shuffleHistory.length; i++) {
        if (_shuffleHistory[i] >= insertAt) _shuffleHistory[i]++;
      }
      final shifted = _shufflePlayed
          .map((i) => i >= insertAt ? i + 1 : i)
          .toList();
      _shufflePlayed
        ..clear()
        ..addAll(shifted);
    }
    queue.insert(queueIndex + 1 + _playNextCount, moved);
    manualQueuedIds.add(moved.id);
    _playNextCount++;
    if (_personalDjActive) {
      _personalDjSeenKeys.addAll(recommendationTrackKeys(moved));
    }
    await _saveQueue();
    _notify();
  }

  Future<void> removeFromQueue(int index) async {
    if (index < 0 || index >= queue.length) return;
    final currentRemoved = index == queueIndex;
    queue.removeAt(index);
    if (index < queueIndex || queueIndex >= queue.length) queueIndex--;
    _shuffleHistory.clear();
    _shufflePlayed.clear();
    if (currentRemoved) {
      _resumePosition = Duration.zero;
      if (queue.isEmpty) {
        queueIndex = -1;
        await stopPlayback();
      } else if (!_youtubeMusicActive) {
        queueIndex = index.clamp(0, queue.length - 1);
        await _playCurrent();
      } else {
        queueIndex = index.clamp(0, queue.length - 1);
      }
    }
    await _saveQueue();
    _notify();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= queue.length ||
        newIndex < 0 ||
        newIndex > queue.length) {
      return;
    }
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    final item = queue.removeAt(oldIndex);
    queue.insert(target, item);
    if (queueIndex == oldIndex) {
      queueIndex = target;
    } else if (oldIndex < queueIndex && target >= queueIndex) {
      queueIndex--;
    } else if (oldIndex > queueIndex && target <= queueIndex) {
      queueIndex++;
    }
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    await _saveQueue();
    _notify();
  }

  void setShuffle(bool value) {
    shuffle = value;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    unawaited(preferences.setBool('shuffle', value));
    _notify();
  }

  void cycleRepeat() {
    repeat = RepeatMode.values[(repeat.index + 1) % RepeatMode.values.length];
    unawaited(preferences.setString('repeat', repeat.name));
    _notify();
  }

  Future<void> toggleFavorite(Track track) async {
    try {
      await _remember(track);
      final selected = !favoriteIds.contains(track.id);
      await database.setFavorite(track.id, selected);
      if (selected) {
        favoriteIds.add(track.id);
      } else {
        favoriteIds.remove(track.id);
      }
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> createPlaylist(String name) async {
    if (name.trim().isEmpty) return;
    final playlist = MusicPlaylist(
      id: 'list_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim(),
    );
    await database.savePlaylist(playlist);
    playlists.add(playlist);
    _notify();
  }

  /// Copia local de una playlist recibida de un amigo.
  Future<void> savePlaylistCopy(String name, List<Track> shared) async {
    final id = 'list_${DateTime.now().microsecondsSinceEpoch}';
    for (final t in shared) {
      if (!tracks.any((x) => x.id == t.id)) await _remember(t);
    }
    final playlist = MusicPlaylist(
      id: id,
      name: name.trim().isEmpty ? 'Playlist de un amigo' : name.trim(),
      trackIds: [for (final t in shared) t.id],
    );
    await database.savePlaylist(playlist);
    playlists.add(playlist);
    _notify();
  }

  Future<void> renamePlaylist(MusicPlaylist playlist, String name) async {
    if (name.trim().isEmpty) return;
    playlist = _latestPlaylist(playlist);
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: name.trim(),
        trackIds: playlist.trackIds,
      ),
    );
  }

  Future<void> deletePlaylist(MusicPlaylist playlist) async {
    await database.deletePlaylist(playlist.id);
    playlists.removeWhere((item) => item.id == playlist.id);
    await _setPlaylistPhotoPath(playlist.id, null);
    _notify();
  }

  // Fotos de playlist: mapa id→ruta en preferencias (sin migrar la tabla, y
  // renombrar/reordenar no la tocan porque _replacePlaylist la reinyecta).
  Map<String, String> _playlistPhotos = {};

  void _loadPlaylistPhotos() {
    try {
      final raw = preferences.getString('playlistPhotos');
      _playlistPhotos = raw == null
          ? {}
          : (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      _playlistPhotos = {};
    }
    final ids = playlists.map((item) => item.id).toSet();
    _playlistPhotos.removeWhere(
      (id, path) => !ids.contains(id) || !File(path).existsSync(),
    );
    playlists = [
      for (final item in playlists) item.withPhoto(_playlistPhotos[item.id]),
    ];
  }

  Future<void> _setPlaylistPhotoPath(String id, String? path) async {
    final old = _playlistPhotos[id];
    if (path == null) {
      _playlistPhotos.remove(id);
    } else {
      _playlistPhotos[id] = path;
    }
    if (old != null && old != path) {
      try {
        await File(old).delete();
      } catch (_) {}
    }
    try {
      await preferences.setString(
        'playlistPhotos',
        jsonEncode(_playlistPhotos),
      );
    } catch (_) {}
    final index = playlists.indexWhere((item) => item.id == id);
    if (index >= 0) playlists[index] = playlists[index].withPhoto(path);
  }

  Future<void> setPlaylistPhoto(
    MusicPlaylist playlist,
    Uint8List? bytes,
  ) async {
    String? path;
    if (bytes != null) {
      final dir = Directory(p.join(supportDirectory.path, 'playlist_covers'));
      await dir.create(recursive: true);
      // Nombre nuevo cada vez: así FileImage no sirve la foto anterior de caché.
      path = p.join(
        dir.path,
        '${playlist.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(path).writeAsBytes(bytes, flush: true);
    }
    await _setPlaylistPhotoPath(playlist.id, path);
    _notify();
  }

  /// Igual que [pickProfileAvatar] pero con miniatura mayor; error legible o null.
  Future<String?> pickPlaylistPhoto(MusicPlaylist playlist) async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final path = result.isEmpty ? null : result.first.path;
      if (path == null) return null;
      final file = File(path);
      if (await file.length() > avatarMaxInputBytes) {
        return 'La imagen pesa más de 8 MB.';
      }
      final bytes = await makeAvatarThumbnail(
        await file.readAsBytes(),
        sizes: const [512, 384, 256],
        maxBytes: 400 * 1024,
      );
      await setPlaylistPhoto(playlist, bytes);
      return null;
    } on AvatarException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo abrir la imagen.';
    }
  }

  Future<void> _replacePlaylist(MusicPlaylist playlist) async {
    final index = playlists.indexWhere((item) => item.id == playlist.id);
    if (index < 0) return;
    playlists[index] = playlist.withPhoto(_playlistPhotos[playlist.id]);
    await database.savePlaylist(playlist);
    _notify();
  }

  MusicPlaylist _latestPlaylist(MusicPlaylist playlist) => playlists.firstWhere(
    (item) => item.id == playlist.id,
    orElse: () => playlist,
  );
  Future<void> addToPlaylist(MusicPlaylist playlist, Track track) async {
    await _remember(track);
    playlist = _latestPlaylist(playlist);
    if (playlist.trackIds.contains(track.id)) return;
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        trackIds: [...playlist.trackIds, track.id],
      ),
    );
  }

  Future<void> removeFromPlaylist(MusicPlaylist playlist, Track track) async {
    playlist = _latestPlaylist(playlist);
    await _replacePlaylist(
      MusicPlaylist(
        id: playlist.id,
        name: playlist.name,
        trackIds: playlist.trackIds.where((id) => id != track.id).toList(),
      ),
    );
  }

  Future<void> reorderPlaylist(
    MusicPlaylist playlist,
    int oldIndex,
    int newIndex,
  ) async {
    playlist = _latestPlaylist(playlist);
    final ids = List.of(playlist.trackIds);
    if (oldIndex < 0 ||
        oldIndex >= ids.length ||
        newIndex < 0 ||
        newIndex > ids.length) {
      return;
    }
    ids.insert(
      newIndex > oldIndex ? newIndex - 1 : newIndex,
      ids.removeAt(oldIndex),
    );
    await _replacePlaylist(
      MusicPlaylist(id: playlist.id, name: playlist.name, trackIds: ids),
    );
  }

  Future<void> clearPlaybackCache() async {
    if (busy || clearingPlaybackCache) return;
    clearingPlaybackCache = true;
    playbackCacheMessage = null;
    _notify();
    try {
      final removed = await source.clearPlaybackCache(
        protectedPath: _loadedAudioInput,
      );
      playbackCacheMessage = removed == 0
          ? 'No hay archivos temporales que limpiar. La canción actual se conserva.'
          : 'Caché limpiada: ${(removed / (1024 * 1024)).toStringAsFixed(1)} MB liberados. La canción actual se conserva.';
    } catch (exception) {
      _report(exception);
    } finally {
      clearingPlaybackCache = false;
      _notify();
    }
  }

  Future<void> importFiles() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3', 'wav', 'flac', 'ogg', 'opus', 'm4a', 'aac'],
      );
      if (selection.isEmpty) return;
      final directory = Directory(p.join(supportDirectory.path, 'imports'));
      await directory.create(recursive: true);
      for (final file in selection) {
        final path = file.path;
        if (path == null) continue;
        final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
        final destination = p.join(
          directory.path,
          '$id${p.extension(path).toLowerCase()}',
        );
        await File(path).copy(destination);
        await _remember(
          Track(
            id: id,
            title: p.basenameWithoutExtension(file.name),
            artist: 'Archivo local',
            localPath: destination,
          ),
        );
      }
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<SpotifyImportResult?> pickSpotifyImport() async {
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'csv'],
      );
      if (selection.isEmpty) return null;
      final file = selection.first;
      final path = file.path;
      if (path == null) {
        throw const FormatException(
          'No se pudo abrir el archivo seleccionado.',
        );
      }
      if (await File(path).length() > maxSpotifyImportBytes) {
        throw const FormatException('El archivo supera el límite de 20 MB.');
      }
      return SpotifyImportParser.parse(
        await File(path).readAsString(),
        extension: p.extension(file.name).replaceFirst('.', ''),
        fallbackPlaylistName: p.basenameWithoutExtension(file.name),
      );
    } catch (exception) {
      _report(exception);
      return null;
    }
  }

  Future<bool> importSpotifyPlaylists(
    List<SpotifyImportPlaylist> imported,
  ) async {
    if (imported.isEmpty) return false;
    busy = true;
    _notify();
    try {
      final stamp =
          '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32)}';
      var trackNumber = 0;
      final newTracks = <Track>[];
      final newPlaylists = <MusicPlaylist>[];
      for (
        var playlistNumber = 0;
        playlistNumber < imported.length;
        playlistNumber++
      ) {
        final playlist = imported[playlistNumber];
        final trackIds = <String>[];
        for (final importedTrack in playlist.tracks) {
          final track = Track(
            id: 'spotify_${stamp}_${trackNumber++}',
            title: importedTrack.title,
            artist: importedTrack.artist,
            album: importedTrack.album,
            spotifyUri: importedTrack.uri,
            spotifyMatchPending: true,
          );
          newTracks.add(track);
          trackIds.add(track.id);
        }
        newPlaylists.add(
          MusicPlaylist(
            id: 'spotify_list_${stamp}_$playlistNumber',
            name: playlist.name,
            trackIds: trackIds,
          ),
        );
      }
      await database.saveTracksAndPlaylists(newTracks, newPlaylists);
      tracks.insertAll(0, newTracks);
      playlists.addAll(newPlaylists);
      error = null;
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<List<Track>> findSpotifyMatches(Track track) async {
    if (usesOfficialYouTubeMusic) return [];
    if (usesYouTubeWebAudio) {
      final matches = _nativeLibrary
          .where(
            (item) =>
                recommendationTracksMatch(item, track) ||
                (item.title.trim().toLowerCase() ==
                        track.title.trim().toLowerCase() &&
                    item.artist.trim().toLowerCase() ==
                        track.artist.trim().toLowerCase()),
          )
          .take(3)
          .toList();
      if (matches.length < 3 && source.supportsOnlineMetadataSearch) {
        final remote = await source.search(
          '${track.title} ${track.artist}',
          limit: 3 - matches.length,
        );
        matches.addAll(
          remote.where(
            (item) =>
                !matches.any((saved) => recommendationTracksMatch(saved, item)),
          ),
        );
      }
      return matches;
    }
    return source.search('${track.title} ${track.artist}', limit: 3);
  }

  /// Spotify supplies descriptions only; the selected match supplies audio.
  /// Devuelve la pista a guardar, o null (y avisa) si el audio no es válido.
  Track? _spotifyPlayable(Track metadata, Track match) {
    final uri = Uri.tryParse(match.pageUrl ?? '');
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    final hasAudioPage =
        uri?.scheme == 'https' &&
        const {'youtube.com', 'music.youtube.com', 'youtu.be'}.contains(host);
    if (match.isPendingSpotifyMatch || (!match.isLocal && !hasAudioPage)) {
      _report(StateError('Selecciona una coincidencia de audio válida.'));
      return null;
    }
    return Track(
      id: match.id,
      title: metadata.title,
      artist: metadata.artist,
      duration: metadata.duration == Duration.zero
          ? match.duration
          : metadata.duration,
      artworkUrl: metadata.artworkUrl ?? match.artworkUrl,
      album: metadata.album ?? match.album,
      genres: metadata.genres.isEmpty ? match.genres : metadata.genres,
      spotifyUri: metadata.spotifyUri,
      pageUrl: match.pageUrl,
      localPath: match.localPath,
    );
  }

  /// [play] reproduce y rehace lo que viene a partir de esta pista
  /// ([playSpotifySeed]); si no, se añade al final o ([next]) a continuación.
  Future<bool> importSpotifyMetadataMatch(
    Track metadata,
    Track match, {
    bool play = false,
    bool next = false,
  }) async {
    if (play) return playSpotifySeed(metadata, match);
    final track = _spotifyPlayable(metadata, match);
    if (track == null) return false;
    try {
      next ? await playNext(track) : await addToQueue(track);
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    }
  }

  /// Toque en una canción de Spotify, como la radio de Spotify: suena ya y lo
  /// que viene se reconstruye desde esta pista. Se conserva el historial (y la
  /// pista que sonaba) y lo puesto a mano; se reemplaza lo sugerido y el resto
  /// del contexto anterior. [context] aporta, en orden, lo que sigue del
  /// álbum/playlist ya emparejado por tandas; [extras] más canciones del
  /// artista. Cuando se agota el contexto entra la radio (motor local +
  /// radio de YouTube + [extras]) hasta [kQueueLookahead] por delante.
  Future<bool> playSpotifySeed(
    Track metadata,
    Track match, {
    Stream<List<(Track, Track)>>? context,
    Future<List<Track>> Function()? extras,
  }) async {
    if (_jamPlaybackActive) return false;
    final playable = _spotifyPlayable(metadata, match);
    if (playable == null) return false;
    try {
      await _remember(playable);
    } catch (exception) {
      _report(exception);
      return false;
    }
    final selected =
        tracks.where((item) => item.id == playable.id).firstOrNull ?? playable;
    if (_routeToYouTubeMusic(selected)) return true;
    final generation = ++_seedGeneration;
    final head = queueIndex >= 0 && queueIndex < queue.length
        ? queueIndex + 1
        : 0;
    final history = queue.take(head).toList();
    final ahead = queue.skip(head).toList();
    final keep = repeat == RepeatMode.one
        ? ahead
        : [
            for (final t in ahead)
              if (manualQueuedIds.contains(t.id)) t,
          ];
    keep.removeWhere((t) => recommendationTracksMatch(t, playable));
    _playIntent = true;
    _expiryRetries = 0;
    queue = [...history, selected, ...keep];
    queueIndex = history.length;
    autoAddedIds.removeWhere((id) => !keep.any((t) => t.id == id));
    _playNextAnchorId = null;
    _playNextCount = 0;
    _shuffleHistory.clear();
    _shufflePlayed
      ..clear()
      ..add(queueIndex);
    _resumePosition = Duration.zero;
    final protectedIds = <String>{for (final t in keep) t.id};
    bool stale() => generation != _seedGeneration || _disposed;
    if (repeat != RepeatMode.one) {
      // Se lanza antes de esperar al audio; _refillQueue comparte este futuro.
      _refillFuture = _rebuildAfterSeed(
        stale,
        protectedIds,
        context,
        extras,
      ).whenComplete(() => _refillFuture = null);
    }
    await _saveQueue();
    _notify();
    await _playCurrent();
    return true;
  }

  Future<void> _rebuildAfterSeed(
    bool Function() stale,
    Set<String> protectedIds,
    Stream<List<(Track, Track)>>? context,
    Future<List<Track>> Function()? extras,
  ) async {
    // Primer índice tras lo protegido (puesto a mano + contexto ya añadido).
    int tailStart() {
      var i = queueIndex + 1;
      while (i < queue.length && protectedIds.contains(queue[i].id)) {
        i++;
      }
      return i;
    }

    try {
      if (context != null) {
        await for (final chunk in context) {
          if (stale()) return;
          final fresh = <Track>[];
          for (final (spotify, yt) in chunk) {
            final t = _spotifyPlayable(spotify, yt);
            if (t != null &&
                !queue.any((q) => recommendationTracksMatch(q, t)) &&
                !fresh.any((q) => recommendationTracksMatch(q, t))) {
              fresh.add(t);
            }
          }
          if (fresh.isEmpty) continue;
          for (final t in fresh) {
            await _remember(t);
          }
          if (stale()) return;
          queue.insertAll(tailStart(), fresh);
          protectedIds.addAll(fresh.map((t) => t.id));
          await _saveQueue();
          _notify();
        }
      }
      if (stale()) return;
      if (queue.length - queueIndex - 1 >= kQueueLookahead) return;
      await _fillQueue(
        target: kQueueLookahead,
        allowed: () => !stale() && !_jamPlaybackActive,
        priority: extras == null
            ? null
            : () => extras().timeout(const Duration(seconds: 8)),
        // Con «Rellenar la cola» apagado solo entra lo que ofrece la semilla.
        fallbacks: _canAutoRefill,
        insertAt: tailStart,
      );
    } catch (_) {
      // La red de seguridad (_refillQueue) cubre lo que falte.
    }
  }

  void _publishMetadata(Track track) {
    _controls?.updateTrack(track);
    unawaited(audio.updateTrackMetadata(track).catchError((Object _) {}));
  }

  Future<bool> matchSpotifyTrack(
    String trackId,
    Track match, {
    bool play = false,
  }) async {
    final index = tracks.indexWhere((track) => track.id == trackId);
    if (index < 0 || !tracks[index].isPendingSpotifyMatch) return false;
    final localMatch = match.isLocal && File(match.localPath!).existsSync();
    if (!localMatch && (match.pageUrl == null || match.pageUrl!.isEmpty)) {
      _report(
        StateError('El resultado no incluye un enlace de YouTube válido.'),
      );
      return false;
    }
    final original = tracks[index];
    final updated = original.copyWith(
      pageUrl: match.pageUrl,
      artworkUrl: match.artworkUrl,
      duration: match.duration,
      spotifyMatchPending: false,
      localPath: localMatch ? match.localPath : null,
    );
    try {
      await database.saveTrack(updated);
      tracks[index] = updated;
      for (var i = 0; i < queue.length; i++) {
        if (queue[i].id == trackId) queue[i] = updated;
      }
      error = null;
      _notify();
      if (play) {
        final queuePosition = queue.indexWhere((track) => track.id == trackId);
        if (queuePosition >= 0) {
          await playQueueAt(queuePosition);
        } else {
          await playTrack(updated);
        }
      }
      return true;
    } catch (exception) {
      _report(exception);
      return false;
    }
  }

  Future<void> importPlaylist(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (usesOfficialYouTubeMusic &&
        uri != null &&
        WebMusicSource.isYouTubeUri(uri)) {
      openYouTubeMusic(uri);
      return;
    }
    busy = true;
    _notify();
    try {
      final imported = await source.importPlaylist(Uri.parse(url.trim()));
      for (final track in imported) {
        await _remember(track);
      }
      final playlist = MusicPlaylist(
        id: 'list_${DateTime.now().microsecondsSinceEpoch}',
        name: 'Lista importada',
        trackIds: imported.map((item) => item.id).toList(),
      );
      await database.savePlaylist(playlist);
      playlists.add(playlist);
    } catch (exception) {
      _report(exception);
    } finally {
      busy = false;
      _notify();
    }
  }

  bool canDownloadTrack(Track track) {
    if (track.isPendingSpotifyMatch ||
        (track.isLocal && File(track.localPath!).existsSync())) {
      return false;
    }
    if (usesOfficialYouTubeMusic || usesYouTubeWebAudio) {
      if (WebMusicSource.isOnlineYouTube(
        track.copyWith(clearLocalPath: true),
      )) {
        return false;
      }
      final uri = Uri.tryParse(track.pageUrl ?? '');
      return uri?.scheme == 'https' &&
          uri!.host.isNotEmpty &&
          uri.userInfo.isEmpty;
    }
    return !track.isLocal && track.pageUrl != null;
  }

  Future<void> downloadTrack(Track track) async {
    if (track.isLocal && File(track.localPath!).existsSync()) return;
    if (requiresOfficialYouTubeMusic(track) ||
        (usesYouTubeWebAudio &&
            WebMusicSource.isOnlineYouTube(
              track.copyWith(clearLocalPath: true),
            ))) {
      _report(
        StateError(
          'YouTube Music se reproduce en el reproductor oficial. Las descargas de yt-dlp son solo de video.',
        ),
      );
      return;
    }
    if (!canDownloadTrack(track)) {
      _report(StateError('Esta canción no tiene una fuente descargable.'));
      return;
    }
    if (downloads.any(
      (job) =>
          job.track.id == track.id &&
          (job.status == DownloadStatus.queued ||
              job.status == DownloadStatus.downloading ||
              job.status == DownloadStatus.completed),
    )) {
      return;
    }
    late final String destinationRoot;
    try {
      final directory = Directory(downloadsDirectoryPath);
      if (downloadsDirectoryPath ==
          p.join(supportDirectory.path, 'downloads')) {
        await directory.create(recursive: true);
      }
      destinationRoot = await _canonicalDownloadRoot(downloadsDirectoryPath);
      await _remember(track);
    } catch (exception) {
      _report(exception);
      return;
    }
    final job = DownloadJob(
      id: 'job_${DateTime.now().microsecondsSinceEpoch}',
      track: track,
      destinationRoot: destinationRoot,
    );
    downloads.insert(0, job);
    await database.saveDownload(job);
    _notify();
    if (!_processingDownloads) {
      _downloadWorker = _processDownloads();
      unawaited(_downloadWorker);
    }
  }

  Future<void> _processDownloads() async {
    if (_processingDownloads || _disposed) return;
    _processingDownloads = true;
    try {
      while (!_disposed) {
        final waiting = downloads.where(
          (job) => job.status == DownloadStatus.queued,
        );
        if (waiting.isEmpty) break;
        final job = waiting.last;
        job.status = DownloadStatus.downloading;
        await database.saveDownload(job);
        if (_disposed) return;
        if (job.status == DownloadStatus.cancelled) continue;
        _notify();
        try {
          final directory = Directory(job.destinationRoot!);
          await directory.create(recursive: true);
          if (_disposed) return;
          final safeId = _safeDownloadId(job.track.id);
          // La fuente elige la extensión (Opus/M4A sin recodificar en escritorio,
          // MP3 en Android); `.mp3` es solo la sugerencia.
          final destination = File(p.join(directory.path, '$safeId.mp3'));
          for (final extension in _downloadExtensions) {
            final existing = File(p.join(directory.path, '$safeId$extension'));
            if (await existing.exists()) {
              throw FileSystemException(
                'El archivo de destino ya existe.',
                existing.path,
              );
            }
          }
          final saved = await source.download(
            job.track,
            destination,
            jobId: job.id,
            onProgress: (progress) {
              if (job.status != DownloadStatus.downloading) return;
              job.progress = progress.clamp(0, 1);
              _notify();
            },
          );
          if (_disposed) return;
          if (job.status != DownloadStatus.cancelled) {
            job.status = DownloadStatus.completed;
            job.progress = 1;
            job.localPath = saved.path;
            final downloaded = job.track.copyWith(localPath: saved.path);
            await _remember(downloaded);
            queue = queue
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
            searchResults = searchResults
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
            recentTracks = recentTracks
                .map((item) => item.id == downloaded.id ? downloaded : item)
                .toList();
          } else if (await saved.exists()) {
            final root = await directory.resolveSymbolicLinks();
            final target = await saved.resolveSymbolicLinks();
            if (p.dirname(target) == root &&
                _isDownloadName(p.basename(target), job.track.id)) {
              await File(target).delete();
            }
          }
        } catch (exception) {
          if (_disposed) return;
          if (job.status != DownloadStatus.cancelled) {
            job.status = DownloadStatus.failed;
            job.error = exception.toString();
          }
        }
        if (_disposed) return;
        await database.saveDownload(job);
        _notify();
      }
    } finally {
      _processingDownloads = false;
    }
  }

  Future<void> cancelDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.queued &&
        job.status != DownloadStatus.downloading) {
      return;
    }
    job.status = DownloadStatus.cancelled;
    await source.cancel(job.id);
    await database.saveDownload(job);
    _notify();
  }

  Future<void> retryDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.failed &&
        job.status != DownloadStatus.cancelled) {
      return;
    }
    await downloadTrack(job.track);
  }

  Future<void> removeDownload(DownloadJob job) async {
    if (job.status != DownloadStatus.completed) return;
    try {
      final localPath = job.localPath;
      if (localPath != null && await File(localPath).exists()) {
        final root = await _canonicalDownloadRoot(
          job.destinationRoot ?? p.join(supportDirectory.path, 'downloads'),
        );
        final file = File(localPath);
        final absolutePath = p.normalize(p.absolute(file.path));
        final canonicalParent = await Directory(
          p.dirname(absolutePath),
        ).resolveSymbolicLinks();
        final target = await file.resolveSymbolicLinks();
        if (!p.equals(canonicalParent, root) ||
            !_isDownloadName(p.basename(absolutePath), job.track.id) ||
            !p.equals(p.dirname(target), root) ||
            !_isDownloadName(p.basename(target), job.track.id)) {
          throw StateError('La descarga está fuera de la carpeta de Aurora.');
        }
        if (currentTrack?.id == job.track.id && !_usingRemote) {
          _resumePosition = audio.position;
          ++_playGeneration;
          await audio.stop();
          _loadedTrackId = null;
          _controls?.updateTrack(null);
        }
        await File(target).delete();
      }
      final remembered = tracks
          .where((track) => track.id == job.track.id)
          .firstOrNull;
      if (remembered != null) {
        final updated = remembered.copyWith(clearLocalPath: true);
        tracks = tracks
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        queue = queue
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        searchResults = searchResults
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        recentTracks = recentTracks
            .map((track) => track.id == updated.id ? updated : track)
            .toList();
        await database.saveTrack(updated);
      }
      await database.deleteDownload(job.id);
      downloads.removeWhere((item) => item.id == job.id);
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<String> _canonicalDownloadRoot(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) throw ArgumentError('La carpeta no existe.');
    final root = await directory.resolveSymbolicLinks();
    final probe = File(
      p.join(root, '.aurora-write-${DateTime.now().microsecondsSinceEpoch}'),
    );
    try {
      await probe.writeAsBytes(const []);
    } finally {
      if (await probe.exists()) await probe.delete();
    }
    return p.normalize(root);
  }

  // Formatos que puede dejar una descarga: Opus y M4A tal como los sirve la
  // fuente, y MP3 (Android y descargas anteriores).
  static const _downloadExtensions = ['.opus', '.m4a', '.mp3'];

  bool _isDownloadName(String name, String trackId) =>
      _downloadExtensions.contains(p.extension(name).toLowerCase()) &&
      p.basenameWithoutExtension(name) == _safeDownloadId(trackId);

  String _safeDownloadId(String id) =>
      id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');

  Future<void> configureDownloadDirectory(String? path) async {
    if (!canConfigureDownloadDirectory) {
      error = 'La carpeta de descargas no se puede configurar en Android.';
      _notify();
      return;
    }
    if (downloads.any(
      (job) =>
          job.status == DownloadStatus.queued ||
          job.status == DownloadStatus.downloading,
    )) {
      _report(
        StateError(
          'Espera a que terminen las descargas antes de cambiar la carpeta.',
        ),
      );
      return;
    }
    try {
      final selected = path ?? p.join(supportDirectory.path, 'downloads');
      if (path == null) await Directory(selected).create(recursive: true);
      final root = await _canonicalDownloadRoot(selected);
      await preferences.setString('downloadsDirectory', root);
      error = null;
    } catch (exception) {
      _report(exception);
    }
    _notify();
  }

  Future<void> chooseDownloadDirectory() async {
    if (!canConfigureDownloadDirectory) return configureDownloadDirectory('');
    if (configuringDownloadDirectory) return;
    configuringDownloadDirectory = true;
    _notify();
    try {
      final selected = await FilePicker.getDirectoryPath();
      if (selected != null) await configureDownloadDirectory(selected);
    } catch (exception) {
      _report(exception);
    } finally {
      configuringDownloadDirectory = false;
      _notify();
    }
  }

  Future<void> openDownloadDirectory() async {
    if (!canConfigureDownloadDirectory) {
      _report(
        UnsupportedError(
          'Abrir la carpeta de descargas no está disponible en Android.',
        ),
      );
      return;
    }
    try {
      final root = p.normalize(p.absolute(downloadsDirectoryPath));
      await Directory(root).create(recursive: true);
      await Process.start(
        Platform.isWindows ? 'explorer.exe' : 'xdg-open',
        [root],
        mode: ProcessStartMode.detached,
      );
    } catch (exception) {
      _report(exception);
    }
  }

  void setVolume(double value) {
    audio.setVolume(value.clamp(0, 1));
    unawaited(preferences.setDouble('volume', value.clamp(0, 1)));
    _notify();
  }

  void setExperimentalProgressivePlayback(bool value) {
    if (!source.supportsExperimentalProgressivePlayback ||
        experimentalProgressivePlayback == value) {
      return;
    }
    experimentalProgressivePlayback = value;
    source.setExperimentalProgressivePlayback(value);
    unawaited(preferences.setBool('experimentalProgressivePlayback', value));
    _notify();
  }

  Future<void> setProfileName(String value) async {
    var clean = jamCleanName(value, fallback: '');
    if (clean.length > 24) clean = clean.substring(0, 24).trim();
    if (clean == profileName) return;
    profileName = clean;
    _notify();
    try {
      await preferences.setString('profileName', clean);
    } catch (_) {}
  }

  Future<void> setProfileAvatar(Uint8List? bytes) async {
    profileAvatar = bytes;
    _notify();
    try {
      final file = File(p.join(supportDirectory.path, 'profile_avatar.bin'));
      if (bytes == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.writeAsBytes(bytes, flush: true);
      }
    } catch (_) {}
  }

  /// Abre el selector de imágenes; devuelve un error legible o null si fue bien.
  Future<String?> pickProfileAvatar() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.image);
      final path = result.isEmpty ? null : result.first.path;
      if (path == null) return null;
      final file = File(path);
      if (await file.length() > avatarMaxInputBytes) {
        return 'La imagen pesa más de 8 MB.';
      }
      final bytes = await file.readAsBytes();
      await setProfileAvatar(await makeAvatarThumbnail(bytes));
      return null;
    } on AvatarException catch (e) {
      return e.message;
    } catch (_) {
      return 'No se pudo abrir la imagen.';
    }
  }

  void setThemeKind(String value) {
    themeKind = const {'modern', 'brasa', 'slush'}.contains(value)
        ? value
        : 'atelier';
    unawaited(preferences.setString('themeKind', themeKind));
    _notify();
  }

  void setAudioQuality(AudioQuality q) {
    audioQuality = q;
    unawaited(preferences.setString('audioQuality', q.name));
    _applyAudioQuality();
    _notify();
  }

  void _applyAudioQuality() {
    final s = source;
    if (s is InnerTubeSource) s.audioQuality = audioQuality;
  }

  void setThemeMode(ThemeMode value) {
    themeMode = value;
    unawaited(preferences.setString('themeMode', value.name));
    _notify();
  }

  void setAdaptiveColors(bool value) {
    setAccentPalette(value ? 'automatic' : 'terracotta');
  }

  void setAccentPalette(String value) {
    if (value != 'automatic' && !accentPaletteColors.containsKey(value)) return;
    accentPalette = value;
    adaptiveColors = value == 'automatic';
    unawaited(preferences.setString('accentPalette', value));
    unawaited(preferences.setBool('adaptiveColors', adaptiveColors));
    if (adaptiveColors && currentTrack != null) {
      unawaited(_updateAccent(currentTrack!));
    } else {
      accentColor = accentPaletteColors[value] ?? const Color(0xffe86927);
      _notify();
    }
  }

  void setReducedMotion(bool value) {
    reducedMotion = value;
    unawaited(preferences.setBool('reducedMotion', value));
    _notify();
  }

  /// Para al terminar la pista que suena; si se salta a otra, vale la nueva.
  void setSleepAtTrackEnd() {
    setSleepTimer(null);
    _sleepAtTrackEnd = true;
    _notify();
  }

  void setSleepTimer(Duration? duration) {
    _sleepAtTrackEnd = false;
    _sleepTimer?.cancel();
    _sleepEnd = duration == null ? null : DateTime.now().add(duration);
    if (duration != null) {
      _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (sleepRemaining == Duration.zero) {
          timer.cancel();
          _sleepEnd = null;
          unawaited(pausePlayback());
        }
        _notify();
      });
    }
    _notify();
  }

  Future<void> _updateAccent(Track track) async {
    const fallback = Color(0xffe86927);
    if (!adaptiveColors) {
      accentColor = accentPaletteColors[accentPalette] ?? fallback;
      _notify();
      return;
    }
    if (track.artworkUrl == null) {
      accentColor = fallback;
      _notify();
      return;
    }
    final key = 'palette_${track.id}';
    final cached = preferences.getInt(key);
    if (cached != null) {
      accentColor = Color(cached);
      _notify();
      return;
    }
    ui.Codec? codec;
    ui.Image? image;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse(track.artworkUrl!);
      if (uri.scheme != 'https') return;
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200 ||
          response.contentLength > 2 * 1024 * 1024) {
        return;
      }
      final builder = BytesBuilder(copy: false);
      await for (final bytes in response.timeout(const Duration(seconds: 5))) {
        builder.add(bytes);
        if (builder.length > 2 * 1024 * 1024) return;
      }
      codec = await ui.instantiateImageCodec(
        builder.takeBytes(),
        targetWidth: 32,
        targetHeight: 32,
      );
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return;
      final buckets = <int, int>{};
      final bytes = pixels.buffer.asUint8List();
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final color = HSLColor.fromColor(
          Color.fromARGB(255, bytes[i], bytes[i + 1], bytes[i + 2]),
        );
        if (color.saturation < 0.25 ||
            color.lightness < 0.12 ||
            color.lightness > 0.9) {
          continue;
        }
        final bucket = (color.hue / 15).floor();
        buckets[bucket] = (buckets[bucket] ?? 0) + 1;
      }
      var selected = fallback;
      if (buckets.isNotEmpty) {
        final best = buckets.entries
            .reduce((a, b) => a.value >= b.value ? a : b)
            .key;
        selected = HSLColor.fromAHSL(
          1,
          best * 15.0 + 7.5,
          0.65,
          0.65,
        ).toColor();
      }
      if (currentTrack?.id != track.id || !adaptiveColors || _disposed) {
        return;
      }
      await preferences.setInt(key, selected.toARGB32());
      if (currentTrack?.id == track.id && adaptiveColors && !_disposed) {
        accentColor = selected;
        _notify();
      }
    } catch (_) {
      if (currentTrack?.id == track.id && adaptiveColors && !_disposed) {
        accentColor = fallback;
        _notify();
      }
    } finally {
      image?.dispose();
      codec?.dispose();
      client.close(force: true);
    }
  }

  Future<void> importYouTubeSession() async {
    if (sessionBusy) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        dialogTitle: 'Importar cookies.txt de tu sesión de YouTube',
      );
      if (files.isEmpty || files.first.path == null || _disposed) return;
      await configureYouTubeSession(File(files.first.path!));
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> configureYouTubeSession(File selected) async {
    if (sessionBusy || _disposed) return;
    sessionBusy = true;
    _notify();
    File? copy;
    try {
      if (await selected.length() > 1024 * 1024) {
        throw ArgumentError(
          'El archivo de sesión debe ocupar como máximo 1 MiB.',
        );
      }
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty || bytes.length > 1024 * 1024) {
        throw ArgumentError(
          'El archivo de sesión debe ocupar como máximo 1 MiB.',
        );
      }
      final directory = Directory(p.join(supportDirectory.path, 'session'));
      await directory.create(recursive: true);
      final root = await supportDirectory.resolveSymbolicLinks();
      final target = await directory.resolveSymbolicLinks();
      if (!p.isWithin(root, target)) {
        throw StateError('La carpeta de sesión está fuera de Aurora.');
      }
      copy = File(
        p.join(
          target,
          'youtube-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x100000000)}.txt',
        ),
      );
      await copy.writeAsBytes(bytes, flush: true);
      final previous = source.cookieFile;
      await source.configureCookieFile(copy.path);
      copy = null;
      if (previous != selected.absolute.path) {
        await _deleteSessionFile(previous);
      }
      error = null;
      diagnostics =
          'Sesión de YouTube importada. Puedes volver a intentar la búsqueda.';
    } catch (exception) {
      if (copy != null && await copy.exists()) await copy.delete();
      _report(exception);
    } finally {
      sessionBusy = false;
      _notify();
    }
  }

  Future<void> clearYouTubeSession() async {
    if (sessionBusy || _disposed) return;
    sessionBusy = true;
    _notify();
    try {
      final previous = source.cookieFile;
      await source.configureCookieFile(null);
      await _deleteSessionFile(previous);
      diagnostics = 'Sesión de YouTube eliminada de Aurora.';
      _notify();
    } catch (exception) {
      _report(exception);
    } finally {
      sessionBusy = false;
      _notify();
    }
  }

  Future<void> _deleteSessionFile(String? path) async {
    if (path == null) return;
    final file = File(path);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final root = await supportDirectory.resolveSymbolicLinks();
    final directory = p.join(root, 'session');
    final target = await file.resolveSymbolicLinks();
    if (p.isWithin(directory, target)) await File(target).delete();
  }

  Future<void> configureTools() async {
    if (!canConfigureDownloadDirectory) {
      await runDiagnostics();
      return;
    }
    try {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: Platform.isWindows
            ? 'Carpeta con yt-dlp.exe y deno.exe'
            : 'Carpeta con yt-dlp',
      );
      if (directory == null) return;
      await source.configureToolDirectory(directory);
      await preferences.setString('toolDirectory', directory);
      await runDiagnostics();
    } catch (exception) {
      _report(exception);
    }
  }

  Future<void> runDiagnostics() async {
    diagnosing = true;
    _notify();
    try {
      diagnostics = await source.diagnose();
    } catch (exception) {
      diagnostics = exception.toString();
    } finally {
      diagnosing = false;
      _notify();
    }
  }

  Future<void> clearCache() async {
    try {
      if (_processingDownloads) {
        throw StateError(
          'Espera a que terminen las descargas antes de limpiar la caché.',
        );
      }
      final directory = Directory(p.join(supportDirectory.path, 'cache'));
      if (await directory.exists()) {
        final root = await supportDirectory.resolveSymbolicLinks();
        final target = await directory.resolveSymbolicLinks();
        if (!p.isWithin(root, target)) {
          throw StateError('La caché está fuera de la carpeta de Aurora.');
        }
        await Directory(target).delete(recursive: true);
      }
      final downloadsDirectory = Directory(
        p.join(supportDirectory.path, 'downloads'),
      );
      if (await downloadsDirectory.exists()) {
        final root = await downloadsDirectory.resolveSymbolicLinks();
        await for (final entry in downloadsDirectory.list(followLinks: false)) {
          if (entry is! Directory ||
              !p.basename(entry.path).startsWith('.aurora-')) {
            continue;
          }
          final target = await entry.resolveSymbolicLinks();
          if (p.isWithin(root, target)) {
            await Directory(target).delete(recursive: true);
          }
        }
      }
      for (final key
          in preferences
              .getKeys()
              .where((key) => key.startsWith('palette_'))
              .toList()) {
        await preferences.remove(key);
      }
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      diagnostics =
          'Caché temporal eliminada. Tu biblioteca y descargas se conservaron.';
      _notify();
    } catch (exception) {
      _report(exception);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_nativeActions?.cancel());
    ++_playGeneration;
    ++_searchGeneration;
    _sleepTimer?.cancel();
    unawaited(_completedSubscription?.cancel());
    audio.removeListener(_audioChanged);
    eq.dispose();
    lastfm?.dispose();
    discord.dispose();
    unawaited(_saveQueue());
    if (_controls != null) unawaited(_controls!.dispose());
    audio.dispose();
    source.dispose();
    unawaited(_closeDatabase());
    super.dispose();
  }

  Future<void> _closeDatabase() async {
    try {
      await _downloadWorker;
    } finally {
      try {
        await database.close();
      } finally {
        _closed.complete();
      }
    }
  }
}
