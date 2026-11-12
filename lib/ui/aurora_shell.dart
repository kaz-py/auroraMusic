import '../../core/feature_flags.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'aurora_states.dart';
import '../theme/brasa_theme.dart';
import '../theme/slush_theme.dart';
import '../theme/slush_widgets.dart';
import 'slush/slush_player.dart';
import 'slush/slush_mobile.dart';
import '../theme/modern_theme.dart';
import '../theme/modern_widgets.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_controller.dart';
import '../core/audio_backend.dart';
import '../core/models.dart';
import '../core/source_backend.dart';
import '../core/desktop_shell.dart';
import '../core/duvet_presence.dart';
import '../core/window_controls.dart';
import '../discord/discord_presence.dart';
import 'brand/aurora_logo.dart';
import '../jam/jam_protocol.dart';
import '../account/account_settings.dart';
import '../profile/profile_settings.dart';
import 'desktop_settings_tiles.dart';
import 'profile_menu.dart';
import 'about_settings.dart';
import '../online/online_settings.dart';
import 'playlist_views/playlist_view_mode_tile.dart';
import 'lastfm_settings_panel.dart';
import '../jam/jam_controller.dart';
import '../remote/aurora_remote_actions.dart';
import '../remote/remote_control_service.dart';
import '../remote/remote_control_settings.dart';
import '../lyrics/lyrics_auto_sync.dart';
import '../lyrics/lyrics_service.dart';
import '../voice/voice_command_service.dart';
import '../voice/voice_settings.dart';
import 'slush/slush_eq_queue.dart';
import 'studio/equalizer_panel.dart';
import 'studio/studio_navigation.dart';
import 'slush/slush_bars.dart';
import 'slush/slush_pages.dart';
import 'slush/slush_decor.dart';
import 'mini_player/mini_player_host.dart';
import 'studio/session_aside.dart';
import 'studio/downloads_studio_page.dart';
import '../shortcuts/shortcut_host.dart';
import '../shortcuts/shortcut_service.dart';
import 'artist_mode.dart';
import 'mini_window.dart';
import 'shortcuts_settings_panel.dart';
import 'artwork.dart';
import 'dj_discovery_page.dart';
import 'home_music_page.dart';
import 'jam/jam_flows.dart';
import 'jam/jam_page.dart';
import 'jam/jam_widgets.dart';
import 'playlist_shelf.dart';
import 'playlist_views/playlist_cover.dart';
import 'playlist_views/playlist_photo_menu.dart';
import 'playlist_views/playlist_view_mode.dart';
import 'playlist_detail_tools.dart';
import 'profile_page.dart';
import '../dj/ai_dj.dart';
import '../import/spotify_import.dart';
import '../metadata/spotify/spotify_metadata_provider.dart';
import '../metadata/spotify_recs.dart';
import 'spotify_auto_add.dart';
import 'spotify_browser_panel.dart';
import '../metadata/youtube_match.dart';
import '../sources/innertube_source.dart';
import '../sources/stream/stream_orchestrator.dart' show AudioQuality;
export 'artwork.dart';
import 'lan_sync_panel.dart';
import 'spotify_import_dialog.dart';
import 'spotify_match_dialog.dart';
import 'vinyl_player.dart';
import 'queue_panel.dart';
import 'settings_layout.dart';
import 'offline_settings_panel.dart';
import 'video_downloads_page.dart';
import 'artists_page.dart';
import 'follow_widgets.dart';
import '../follow/follow_providers.dart';
import 'track_actions.dart';
import 'mini_player/song_card.dart';
import 'friends_page.dart';
import '../friends/friends_providers.dart';
import '../friends/friends_service.dart';
import '../notifications/system_notifier.dart';
import 'undo_snackbar.dart';
import '../updater/update_controller.dart';
import '../updater/update_ui.dart';

// Los ids de sección son estables: no se renumeran al quitar una.
const _sections = <int, String>{
  0: 'Inicio',
  1: 'Buscar',
  2: 'Biblioteca',
  3: 'Descargas locales',
  4: 'Modo Vinilo',
  5: 'Cola de reproducción',
  6: 'Letras',
  7: 'Ajustes',
  8: 'DJ',
  9: 'Jam',
  11: 'Descargar vídeos',
  12: 'Artistas',
  13: 'Ecualizador',
  14: 'Amigos',
};
const _icons = <int, IconData>{
  0: Icons.home_outlined,
  1: Icons.search,
  2: Icons.library_music_outlined,
  3: Icons.download_outlined,
  4: Icons.album_outlined,
  5: Icons.queue_music,
  6: Icons.lyrics_outlined,
  7: Icons.tune,
  8: Icons.explore_outlined,
  9: Icons.groups_outlined,
  11: Icons.video_file_outlined,
  12: Icons.mic_none_rounded,
  13: Icons.equalizer,
  14: Icons.people_outline,
};
const _primarySections = [0, 1, 8, 2, 3];
const _slushPrimarySections = [0, 1, 2, 8, 9];

class AuroraShell extends ConsumerStatefulWidget {
  const AuroraShell({super.key});
  @override
  ConsumerState<AuroraShell> createState() => _AuroraShellState();
}

class _AuroraShellState extends ConsumerState<AuroraShell>
    with WidgetsBindingObserver {
  int _section = 0;
  bool _jamVisited = false;
  bool _videosVisited = false;
  bool _navigationPending = false;
  JamController? _jam;

  /// Amigo con el chat abierto en Amigos (`null`: la lista). Lo comparten
  /// los avisos y «atrás».
  final _friendsChat = ValueNotifier<String?>(null);

  /// Modo mini (ventana compacta, solo Windows): `MiniWindowView` sustituye al
  /// shell mientras está activo.
  bool _miniWindow = false;

  Future<void> _setMiniWindow(bool on) async {
    if (_miniWindow == on) return;
    final done = await WindowControls.setMiniWindow(on);
    // Al salir se vuelve aunque falle la ventana nativa: no atrapa al usuario.
    if (!mounted || (on && !done)) return;
    setState(() => _miniWindow = on);
  }

  /// Un único controlador de Jam para chip, barra inferior, panel y página.
  JamController _ensureJam() {
    _jam ??= JamController(app: ref.read(controllerProvider))
      ..addListener(_jamChanged);
    return _jam!;
  }

  void _openJamPanel() => showJamPanel(context, _ensureJam());
  Future<void> _startJam({List<Track> seed = const []}) =>
      startJamFlow(context, _ensureJam(), seed: seed);
  bool _spotifySearch = false;
  SpotifyAutoAdder? _spotifyAdderCache;

  /// Spotify → YouTube automático; sin InnerTube cae al diálogo manual.
  SpotifyAutoAdder get _spotifyAdder => _spotifyAdderCache ??= () {
    AppController app() => ref.read(controllerProvider);
    final source = app().source;
    return SpotifyAutoAdder(
      matcher: source is InnerTubeSource
          ? YoutubeMatcher(
              search: (q, k) => source.searchPage(q, k).then((p) => p.tracks),
            )
          : null,
      save: (spotify, match, {next = false}) =>
          app().importSpotifyMetadataMatch(spotify, match, next: next),
      playSeed: (spotify, match, {context, extras}) => app().playSpotifySeed(
        spotify,
        match,
        context: context,
        extras: extras,
      ),
      moreFromArtist: source is InnerTubeSource
          ? (seed) => ProviderSpotifyCatalog(
              SpotifyMetadataProvider(),
            ).artistTopTracks(djPrimaryArtist(seed))
          : null,
      queueLength: () => app().queue.length,
      unqueue: (id) {
        final i = app().queue.lastIndexWhere((q) => q.id == id);
        if (i >= 0) app().removeFromQueue(i);
      },
      manual: (track, {replacing}) => _spotifyManual(track, replacing),
      messenger: () => mounted ? ScaffoldMessenger.maybeOf(context) : null,
      jam: () => _jam,
    );
  }();

  Future<void> _spotifyManual(Track track, Track? replacing) {
    final c = ref.read(controllerProvider);
    return SpotifyMatchDialog.show(
      context,
      track: track,
      saveLabel: 'Añadir a la cola',
      playLabel: 'Reproducir',
      onSearch: () => c.findSpotifyMatches(track),
      onSave: (match, {required play}) async {
        final ok = await c.importSpotifyMetadataMatch(track, match, play: play);
        if (ok && replacing != null && replacing.id != match.id) {
          _spotifyAdder.unqueue(replacing.id);
        }
        return ok;
      },
    );
  }

  MusicPlaylist? _playlist;
  bool _likesSelected = false;
  final List<int> _backStack = [];
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late final AudioBackend _audio;
  late final DesktopShell _desktop;
  late final DuvetPresence _duvet;
  late final RemoteControlService _remote;
  late final VoiceCommandService _voice;
  late final LyricsService _lyricsSyncService;
  late final AppController _syncOwner;
  // Hay un consumidor visible del espectro: Vinilo, EQ o la hoja del EQ.
  bool get _playerOpen =>
      _section == 4 || _section == 13 || equalizerSheetsOpen.value > 0;
  bool _foreground = true;
  bool _analysisEnabled = false;
  late final UpdateController _updates;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
    _audio = ref.read(controllerProvider).audio;
    _updates = UpdateController(ref.read(controllerProvider).preferences)
      ..start();
    WindowControls.install();
    _desktop = DesktopShell(ref.read(controllerProvider))..start();
    _duvet = DuvetPresence(ref.read(controllerProvider))..start();
    final app = ref.read(controllerProvider);
    final remoteActions = AuroraRemoteActions(
      app,
      currentJam: () => _jam,
      ensureJam: () => mounted ? _ensureJam() : null,
    );
    _voice = VoiceCommandService(
      app.preferences,
      remoteActions,
      supportDirectory: app.supportDirectory,
    )..start();
    _syncOwner = app;
    _lyricsSyncService = LyricsService();
    app.lyricsAutoSync = LyricsAutoSync(
      _lyricsSyncService,
      available: () => _voice.lyricsSyncEnabled && _voice.analysisReady,
      modelPath: () => _voice.modelPath,
    );
    _remote = RemoteControlService(
      app.preferences,
      remoteActions,
      discoveryFile: File(
        p.join(app.supportDirectory.path, 'remote_control.json'),
      ),
    )..start();
    _audio.setVisualizationEnabled(false);
    equalizerSheetsOpen.addListener(_eqSheetChanged);
    _listenForJamLinks();
    _startFollow();
    _startSpotifyMatching();
    _notifier.onTap = _openFriends;
    _friendsSub = ref
        .read(friendsServiceProvider)
        .notices
        .listen(_friendsNotice);
  }

  StreamSubscription<FriendsNotice>? _friendsSub;

  /// Solicitudes + canciones sin ver, para la insignia de «Amigos».
  int get _friendsBadge {
    final f = ref.watch(friendsServiceProvider);
    return f.unseenCount + f.incoming.length;
  }

  final _notifier = SystemNotifier();

  /// Empareja con YouTube las canciones de Spotify que sigan pendientes.
  AppController? _spotifyMatchController;

  void _startSpotifyMatching() {
    final c = ref.read(controllerProvider);
    _spotifyMatchController = c;
    c.onSpotifyMatchFinished = (matched, total) {
      if (!mounted) return;
      showUndoSnackBar(
        ScaffoldMessenger.maybeOf(context),
        Text(
          matched == total
              ? 'Spotify: $matched canciones emparejadas con YouTube'
              : 'Spotify: $matched de $total canciones emparejadas con '
                    'YouTube; elige a mano las demás',
        ),
      );
    };
    unawaited(c.autoMatchSpotify());
  }

  void _openFriends(String? peerId) {
    unawaited(WindowControls.invoke('showWindow'));
    _friendsChat.value = peerId == null || peerId.isEmpty ? null : peerId;
    _navigate(14);
  }

  Future<void> _friendsNotice(FriendsNotice n) async {
    if (!mounted) return;
    // Con la app a la vista basta la barra interna; si no, notificación del sistema.
    if (!_foreground && await _notifier.showFriend(n)) return;
    if (!mounted) return;
    showUndoSnackBar(
      ScaffoldMessenger.maybeOf(context),
      Text(friendsNoticeMessage(n)),
      label: 'Ver',
      onAction: () => _openFriends(n.peerId),
    );
  }

  /// Carga los artistas seguidos y busca novedades (como mucho cada ~12 h).
  void _startFollow() {
    final follow = ref.read(followServiceProvider);
    // Enganche del DJ: refuerzo suave a pistas de artistas seguidos.
    final controller = ref.read(controllerProvider);
    controller.followedArtistKeys = () => follow.followedArtistKeys;
    controller.artistNavigator = (name) async {
      await _navigate(1);
      if (mounted) await controller.openArtistProfile(name);
    };
    unawaited(
      follow
          .load()
          .then((_) => follow.refreshIfDue())
          .catchError((Object _) {}),
    );
  }

  Future<void> _openEntry(SearchEntry entry) async {
    await _navigate(1);
    if (mounted) ref.read(controllerProvider).openSearchEntry(entry);
  }

  // aurora://jam/CODIGO: argumentos de Windows (arranque o 2.ª instancia) o
  // intent de Android (canal aurora/link).
  void _listenForJamLinks() {
    void open(String raw) {
      final link = RegExp(r'aurora://[^\s"]+').firstMatch(raw)?.group(0);
      if (link != null && jamCodeFromLaunchArgument(link) != null) {
        unawaited(_joinJamLink(link));
      }
    }

    if (WindowControls.supported) {
      WindowControls.onArguments = open;
      WindowControls.launchArguments.forEach(open);
    } else if (Platform.isAndroid) {
      const channel = MethodChannel('aurora/link');
      channel.setMethodCallHandler((call) async {
        if (call.method == 'link') open(call.arguments as String);
      });
      channel.invokeMethod<String>('initial').then((v) {
        if (v != null) open(v);
      }, onError: (_) {});
    }
  }

  Future<void> _joinJamLink(String link) async {
    await _navigate(9);
    await _ensureJam().joinFromLink(link, 'Invitado');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncVisualization();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncVisualization();
  }

  void _eqSheetChanged() {
    if (mounted) _syncVisualization();
  }

  void _syncVisualization() {
    final c = ref.read(controllerProvider);
    final enabled =
        c.audio.supportsVisualization &&
        _playerOpen &&
        _foreground &&
        c.audio.isPlaying &&
        !c.reducedMotion &&
        !MediaQuery.disableAnimationsOf(context);
    if (enabled != _analysisEnabled) {
      _analysisEnabled = enabled;
      _audio.setVisualizationEnabled(enabled);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _spotifyMatchController?.onSpotifyMatchFinished = null;
    _friendsSub?.cancel();
    _desktop.dispose();
    _duvet.dispose();
    _remote.dispose();
    _voice.dispose();
    _syncOwner.lyricsAutoSync = null;
    _lyricsSyncService.dispose();
    WindowControls.onArguments = null;
    _jam?.removeListener(_jamChanged);
    _jam?.dispose();
    _friendsChat.dispose();
    _spotifyAdderCache?.dispose();
    equalizerSheetsOpen.removeListener(_eqSheetChanged);
    if (_analysisEnabled) _audio.setVisualizationEnabled(false);
    _updates.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _jamChanged() {
    if (mounted) setState(() {});
  }

  void _jamCreated(JamController controller) {
    if (identical(_jam, controller)) return;
    _jam?.removeListener(_jamChanged);
    _jam = controller;
    _jam?.addListener(_jamChanged);
    _jamChanged();
  }

  Future<void> _navigate(int value, {bool recordBack = true}) async {
    if (_navigationPending) return;
    _navigationPending = true;
    try {
      if (!mounted) return;
      if (value != 0 && value != 8) {
        ref.read(controllerProvider).cancelRecommendationDiscovery();
      }
      setState(() {
        if (value == 0) {
          _backStack.clear();
        } else if (value != _section && recordBack) {
          _backStack.add(_section);
          if (_backStack.length > 20) _backStack.removeAt(0);
        }
        _section = value;
        if (value == 9) _jamVisited = true;
        if (value == 11) _videosVisited = true;
        _playlist = null;
        _likesSelected = false;
      });
      _syncVisualization();
    } finally {
      _navigationPending = false;
    }
  }

  bool _handleBack(AppController c) {
    // «Atrás» en un chat abierto vuelve a la lista sin salir de Amigos.
    if (_section == 14 && _friendsChat.value != null) {
      _friendsChat.value = null;
      return true;
    }
    if (_section == 1 && c.searchDetail != null) {
      c.openSearchEntry(null);
      return true;
    }
    if (_playlist != null || _likesSelected) {
      setState(() {
        _playlist = null;
        _likesSelected = false;
      });
      return true;
    }
    if (_backStack.isNotEmpty) {
      _navigate(_backStack.removeLast(), recordBack: false);
      return true;
    }
    if (_section != 0) {
      _navigate(0);
      return true;
    }
    return false;
  }

  final _mute = MuteMemory();

  // Con Jam activa el controlador decide (host alterna, invitado con permiso
  // enruta al host); sin permiso muestra su mensaje en vez de silencio.
  Future<void> _togglePlay(AppController c) async {
    final jam = _jam;
    if (!c.jamPlaybackActive || jam == null) {
      c.togglePlayback();
      return;
    }
    await jam.togglePlayback();
    final message = jam.error;
    if (message != null && mounted) {
      showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(message));
    }
  }

  void _runShortcut(AppController c, ShortcutId id) {
    final seek = const Duration(seconds: 5);
    switch (id) {
      case ShortcutId.playPause:
        _togglePlay(c);
      case ShortcutId.next:
        c.next();
      case ShortcutId.previous:
        c.previous();
      case ShortcutId.shuffle:
        c.setShuffle(!c.shuffle);
      case ShortcutId.repeat:
        c.cycleRepeat();
      case ShortcutId.mute:
        _mute.toggle(c);
      case ShortcutId.volumeUp:
        c.setVolume(c.audio.volume + 0.05);
      case ShortcutId.volumeDown:
        c.setVolume(c.audio.volume - 0.05);
      case ShortcutId.seekForward:
      case ShortcutId.seekBack:
        final target =
            c.audio.position + (id == ShortcutId.seekForward ? seek : -seek);
        final max = c.audio.duration;
        c.seek(
          target < Duration.zero
              ? Duration.zero
              : (max > Duration.zero && target > max ? max : target),
        );
      case ShortcutId.favorite:
        final track = c.currentTrack;
        if (track != null) c.toggleFavorite(track);
      case ShortcutId.jam:
        _navigate(9);
      case ShortcutId.queue:
        _navigate(5);
      case ShortcutId.home:
        _navigate(0);
      case ShortcutId.search:
        _navigate(1);
      case ShortcutId.library:
        _navigate(2);
      case ShortcutId.downloads:
        _navigate(3);
      case ShortcutId.searchFocus:
        _navigate(1);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _searchFocus.requestFocus(),
        );
      case ShortcutId.vinyl:
        _navigate(4);
      case ShortcutId.lyrics:
        _navigate(6);
      case ShortcutId.equalizer:
        showEqualizerSheet(context, c);
      case ShortcutId.sleep:
        c.setSleepTimer(
          c.sleepRemaining == null ? const Duration(minutes: 30) : null,
        );
      case ShortcutId.addToQueue:
      case ShortcutId.addToJam:
        break; // las atiende la fila enfocada (TrackActionsRegion)
    }
  }

  Future<void> _openLibrary({
    MusicPlaylist? playlist,
    bool likes = false,
  }) async {
    await _navigate(2);
    if (!mounted || _section != 2) return;
    setState(() {
      _playlist = playlist;
      _likesSelected = likes;
    });
  }

  void _submitSearch(AppController c, String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    c.search(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(controllerProvider);
    ref.listen(
      controllerProvider.select((c) => (c.reducedMotion, c.audio.isPlaying)),
      (_, _) => _syncVisualization(),
    );
    final shell = TrackActionsScope(
      jam: _jam,
      ensureJam: _ensureJam,
      addToPlaylist: (track) => _addToPlaylist(c, track),
      child: ShortcutHost(
        service: ref.watch(shortcutServiceProvider),
        onAction: (id) => _runShortcut(c, id),
        extraBindings: {
          const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
              _togglePlay(c),
          const SingleActivator(LogicalKeyboardKey.mediaTrackNext): c.next,
          const SingleActivator(LogicalKeyboardKey.mediaTrackPrevious):
              c.previous,
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, size) {
              final wide = size.maxWidth >= 900;
              final desktop = size.maxWidth >= 1200;
              final rail = size.maxWidth >= 600;
              final brasa = isBrasa(context);
              final slushBar = isSlush(context) && rail;
              final jamOn =
                  _jam?.service.connected == true ||
                  _jam?.service.reconnecting == true;
              return Scaffold(
                body: SafeArea(
                  child: Column(
                    children: [
                      if (slushBar)
                        SlushTopBar(
                          selected: _section,
                          onNavigate: _navigate,
                          onProfile: (ctx) => _showProfileMenu(ctx, c),
                          avatar: c.profileAvatar,
                          sessionText: jamOn ? 'JAM ACTIVA' : 'INICIAR JAM',
                          onSession: jamOn ? _openJamPanel : _startJam,
                          onAdd: () => _createPlaylist(c),
                        )
                      else if (rail || WindowControls.supported)
                        StudioTitleBar(
                          onNavigate: _navigate,
                          onProfile: (ctx) => _showProfileMenu(ctx, c),
                          avatar: c.profileAvatar,
                          searchController: brasa && rail ? _search : null,
                          searchFocus: _searchFocus,
                          onSearch: (q) {
                            _spotifySearch = false;
                            _navigate(1);
                            _submitSearch(c, q);
                          },
                          onSearchChanged: (_) => setState(() {}),
                          sessionText: brasa
                              ? (jamOn
                                    ? 'Jam · ${_jam!.peopleCount} ${_jam!.peopleCount == 1 ? 'persona' : 'personas'}'
                                    : 'Iniciar una Jam')
                              : jamOn
                              ? 'JAM · ${_jam!.peopleCount} ${_jam!.peopleCount == 1 ? 'PERSONA' : 'PERSONAS'} · ${_jam!.roleLabel.toUpperCase()}'
                              : 'INICIAR UNA JAM',
                          activeSession:
                              (_jam?.service.connected == true ||
                              _jam?.service.reconnecting == true),
                          onSession:
                              (_jam?.service.connected == true ||
                                  _jam?.service.reconnecting == true)
                              ? _openJamPanel
                              : _startJam,
                        ),
                      Expanded(
                        child: Row(
                          children: [
                            if (rail && !slushBar) _sidebar(c, wide),
                            Expanded(
                              child: Column(
                                children: [
                                  if (!(brasa && rail) &&
                                      !(slushBar && _section == 0) &&
                                      (!wide || ![0, 3].contains(_section)))
                                    _header(c, rail),
                                  if (!c.ready || c.busy)
                                    const LinearProgressIndicator(minHeight: 2),
                                  if (c.error != null) _errorBanner(c),
                                  UpdateBanner(
                                    controller: _updates,
                                    isPlaying: () => c.audio.isPlaying,
                                  ),
                                  Expanded(
                                    child:
                                        isModern(context) && !isSlush(context)
                                        ? Align(
                                            alignment: Alignment.topCenter,
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    const [
                                                      4,
                                                      5,
                                                      9,
                                                      11,
                                                    ].contains(_section)
                                                    ? double.infinity
                                                    : 1600,
                                              ),
                                              child: _content(c),
                                            ),
                                          )
                                        : _content(c),
                                  ),
                                ],
                              ),
                            ),
                            if (desktop &&
                                !slushBar &&
                                !c.jamPlaybackActive &&
                                _section != 3 &&
                                _section != 4 &&
                                _section != 5 &&
                                _section != 6 &&
                                _section != 7 &&
                                _section != 13 &&
                                _section != 11)
                              StudioSessionAside(
                                controller: c,
                                jam: _jam,
                                onStartJam: _startJam,
                                onJam: () => _navigate(9),
                                onQueue: () => _navigate(
                                  (_jam?.service.connected == true ||
                                          _jam?.service.reconnecting == true)
                                      ? 9
                                      : 5,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _miniPlayer(c, rail, MiniPlayerPlacement.body),
                    ],
                  ),
                ),
                bottomNavigationBar: rail
                    ? null
                    : isSlush(context)
                    ? MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: SlushBottomBar(
                          icons: [
                            for (final s in _slushPrimarySections)
                              switch (s) {
                                2 => Icons.queue_music,
                                8 => Icons.auto_awesome,
                                9 => Icons.groups_outlined,
                                _ => _icons[s]!,
                              },
                          ],
                          labels: [
                            for (final s in _slushPrimarySections)
                              _sections[s]!,
                          ],
                          selected: _slushPrimarySections.indexOf(_section),
                          onSelect: (i) => _navigate(_slushPrimarySections[i]),
                          mini: _miniPlayer(
                            c,
                            rail,
                            MiniPlayerPlacement.bottomBar,
                          ),
                        ),
                      )
                    : NavigationBar(
                        height: 64,
                        selectedIndex: math.max(
                          0,
                          _primarySections.indexOf(_section),
                        ),
                        onDestinationSelected: (index) =>
                            _navigate(_primarySections[index]),
                        labelBehavior:
                            NavigationDestinationLabelBehavior.onlyShowSelected,
                        backgroundColor: brasa
                            ? Brasa.void_
                            : isSlush(context)
                            ? context.slush.ink
                            : isModern(context)
                            ? Theme.of(context).colorScheme.surfaceContainerLow
                            : null,
                        indicatorColor: brasa ? Brasa.cream : null,
                        elevation: isModern(context) || brasa ? 0 : null,
                        destinations: List.generate(
                          _primarySections.length,
                          (i) => NavigationDestination(
                            icon: Icon(_icons[_primarySections[i]]),
                            selectedIcon: brasa
                                ? SizedBox(
                                    width: 64,
                                    height: 32,
                                    child: DecoratedBox(
                                      decoration: const ShapeDecoration(
                                        color: Brasa.cream,
                                        shape: StadiumBorder(),
                                      ),
                                      child: Icon(
                                        _icons[_primarySections[i]],
                                        color: Brasa.void_,
                                      ),
                                    ),
                                  )
                                : null,
                            label: _primarySections[i] == 3
                                ? 'Descargas'
                                : _sections[_primarySections[i]]!,
                            tooltip: _sections[_primarySections[i]],
                          ),
                        ),
                      ),
              );
            },
          ),
        ),
      ),
    );
    final guarded = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_handleBack(c)) SystemNavigator.pop();
      },
      child: shell,
    );
    // Modo mini y Modo artista sustituyen a todo el shell (que conserva su
    // estado, incluida la sección) mientras están activos.
    return _miniWindow
        ? MiniWindowView(
            controller: c,
            jam: _jam,
            onTogglePlay: () => _togglePlay(c),
            onExit: () => unawaited(_setMiniWindow(false)),
          )
        : _section == 6
        ? Scaffold(
            body: ArtistModePage(
              controller: c,
              jam: _jam,
              onTogglePlay: () => _togglePlay(c),
              onClose: () {
                if (!_handleBack(c)) _navigate(0);
              },
            ),
          )
        : guarded;
  }

  Widget _sidebar(AppController c, bool wide) {
    if (wide) {
      return StudioSidebar(
        controller: c,
        selected: _section,
        onNavigate: _navigate,
        onPlaylist: (playlist) => _openLibrary(playlist: playlist),
        onCreatePlaylist: () => _createPlaylist(c),
        shortcuts: ref.watch(shortcutServiceProvider),
        friendsBadge: _friendsBadge,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final modern = isModern(context);
    return Container(
      width: wide ? 216 : 76,
      decoration: BoxDecoration(
        border: modern
            ? null
            : Border(
                right: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: .35),
                ),
              ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (modern)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Tracky.navy,
                      shape: BoxShape.circle,
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  )
                else
                  const AuroraLogo(size: 28),
                if (wide) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Aurora',
                    style: TextStyle(
                      fontSize: modern ? 18 : 20,
                      fontWeight: modern ? FontWeight.w600 : FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final i in _primarySections) _navItem(i, wide),
                  const Divider(indent: 20, endIndent: 20, height: 18),
                  for (final i in [12, 11, 9, 14, 4, 5, 6, 13])
                    _navItem(i, wide),
                  if (wide && c.playlists.isNotEmpty) ...[
                    const Divider(indent: 20, endIndent: 20, height: 18),
                    for (final playlist in c.playlists)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                        ),
                        leading: const Icon(Icons.queue_music, size: 18),
                        title: Text(
                          playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _openLibrary(playlist: playlist),
                      ),
                  ],
                ],
              ),
            ),
          ),
          _navItem(7, wide),
        ],
      ),
    );
  }

  Widget _navItem(int index, bool wide) {
    final colors = Theme.of(context).colorScheme;
    final active = _section == index;
    final modern = isModern(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Tooltip(
        message: _sections[index],
        child: Material(
          color: modern
              ? (active ? colors.primary : Colors.transparent)
              : active
              ? colors.primary.withValues(alpha: .12)
              : Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(modern ? 999 : 8),
          child: InkWell(
            onTap: () => _navigate(index),
            borderRadius: BorderRadius.circular(modern ? 999 : 8),
            child: SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: wide
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  const SizedBox(width: 12),
                  Badge(
                    isLabelVisible: index == 14 && _friendsBadge > 0,
                    label: Text('$_friendsBadge'),
                    child: Icon(
                      _icons[index],
                      size: 19,
                      color: modern
                          ? (active
                                ? colors.onPrimary
                                : colors.onSurfaceVariant)
                          : active
                          ? colors.primary
                          : colors.onSurfaceVariant,
                    ),
                  ),
                  if (wide) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _sections[index]!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: modern && active ? colors.onPrimary : null,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _modernTitle(String title) {
    final words = title.split(' ');
    final (before, emphasis) = _section == 0 && _playlist == null
        ? ('Tu ', 'música')
        : _playlist != null || words.length < 2
        ? (title, '')
        : ('${words.sublist(0, words.length - 1).join(' ')} ', words.last);
    return Align(
      alignment: Alignment.centerLeft,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: ModernHeadline(before: before, emphasis: emphasis, size: 28),
      ),
    );
  }

  /// Slush: estas secciones llevan su propio titular gigante (SlushPage).
  bool get _slushOwned =>
      isSlush(context) && const [1, 2, 3, 7, 11, 12, 14].contains(_section);

  Widget _header(AppController c, bool rail) {
    if (rail && _slushOwned) return const SizedBox.shrink();
    return !rail &&
            isSlush(context) &&
            ((_section == 0 && _playlist == null) || _slushOwned)
        ? SlushMobileTopBar(
            onSettings: () => _navigate(7),
            onProfile: (ctx) => _showProfileMenu(ctx, c),
            avatar: c.profileAvatar,
            onMore: _navigate,
            friendsBadge: _friendsBadge,
          )
        : _headerBar(c, rail);
  }

  /// Slush: cabecera gigante + píldoras + contenido en tarjeta blanca.
  Widget _slushPage(AppController c, Widget child) {
    if (!_slushOwned) return child;
    final s = _section;
    final libRoot = s == 2 && _playlist == null && !_likesSelected;
    final songs = '${c.tracks.length} canciones';
    final list = c.playlists.where((p) => p.id == _playlist?.id).firstOrNull;
    final found = c.searchEntries.isNotEmpty && c.searchResults.isEmpty
        ? c.searchEntries.length
        : c.searchResults.length;
    final (base, title, sticker, pills) = switch (s) {
      1 => (
        Slush.lilac,
        'BÚSQUEDA',
        '¡HEY!',
        [
          _spotifySearch ? 'Spotify' : 'YouTube',
          if (c.searching)
            'Buscando…'
          else if (found > 0)
            '$found resultados'
          else
            '${c.recentSearches.length} recientes',
        ],
      ),
      2 => (
        Slush.mint,
        _likesSelected
            ? 'ME GUSTA'
            : _playlist == null
            ? 'BIBLIOTECA'
            : (list?.name ?? 'LISTA').toUpperCase(),
        _likesSelected ? 'AMOR' : 'TUYA',
        libRoot
            ? [
                songs,
                '${c.playlists.length} listas',
                '${c.favoriteIds.length} me gusta',
              ]
            : [
                '${_likesSelected ? c.favoriteIds.length : (list?.trackIds.length ?? 0)} canciones',
              ],
      ),
      3 => (
        const Color(0xffa9d0ff),
        'DESCARGAS',
        'BAJA',
        [
          '${c.downloads.where((j) => j.status == DownloadStatus.completed).length} listas',
          '${c.downloads.where((j) => j.status == DownloadStatus.queued || j.status == DownloadStatus.downloading).length} en curso',
        ],
      ),
      11 => (const Color(0xffa9d0ff), 'VÍDEOS', 'MP4', ['yt-dlp']),
      14 => (Slush.mint, 'AMIGOS', 'HOLA', const <String>[]),
      12 => (
        Slush.yellow,
        'ARTISTAS',
        'FANS',
        ['${c.tracks.map((t) => t.artist).toSet().length} artistas', songs],
      ),
      _ => (
        const Color(0xffffb48a),
        'AJUSTES',
        'TUYO',
        ['Slush', _settingsTabs[_settingsTab]],
      ),
    };
    return SlushPage(
      color: slushTone(context, base),
      title: title,
      sticker: sticker,
      pills: pills,
      card: !libRoot && s != 7,
      child: child,
    );
  }

  Widget _headerBar(AppController c, bool rail) => Padding(
    padding: rail
        ? EdgeInsets.fromLTRB(
            32,
            isModern(context) ? 28 : 18,
            32,
            isModern(context) ? 20 : 12,
          )
        : const EdgeInsets.fromLTRB(16, 8, 8, 4),
    child: Row(
      children: [
        if (!rail) ...[const AuroraLogo(size: 28), const SizedBox(width: 10)],
        Expanded(
          child: !rail && isModern(context)
              ? const SizedBox.shrink()
              : isModern(context)
              ? _modernTitle(
                  (_playlist == null
                          ? null
                          : c.playlists
                                .where((p) => p.id == _playlist!.id)
                                .firstOrNull
                                ?.name) ??
                      _sections[_section]!,
                )
              : Text(
                  (_playlist == null
                          ? null
                          : c.playlists
                                .where((p) => p.id == _playlist!.id)
                                .firstOrNull
                                ?.name) ??
                      _sections[_section]!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        if (rail)
          IconButton(
            tooltip: 'Importar archivos de audio',
            onPressed: c.ready ? c.importFiles : null,
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        if (_section != 1)
          IconButton(
            tooltip: 'Buscar música',
            onPressed: () => _navigate(1),
            icon: const Icon(Icons.search),
          ),
        if (!rail)
          IconButton(
            tooltip: 'Ajustes',
            onPressed: () => _navigate(7),
            icon: const Icon(Icons.tune),
          ),
        if (!rail && _section == 4 && !isSlush(context) && c.nowTrack != null)
          Builder(
            builder: (b) => IconButton(
              tooltip: 'Más acciones',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () {
                final box = b.findRenderObject() as RenderBox;
                showSongCard(
                  context,
                  c,
                  c.nowTrack!,
                  box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                  openQueue: () => _navigate(5),
                );
              },
            ),
          ),
        if (!rail)
          PopupMenuButton<int>(
            tooltip: 'Más vistas',
            icon: Badge(
              isLabelVisible: _friendsBadge > 0,
              label: Text('$_friendsBadge'),
              child: const Icon(Icons.more_horiz),
            ),
            onSelected: (v) =>
                v == -1 ? (c.ready ? c.importFiles() : null) : _navigate(v),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: -1,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.create_new_folder_outlined),
                  title: Text('Importar archivos'),
                ),
              ),
              PopupMenuItem(
                value: 12,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.mic_none_rounded),
                  title: Text('Artistas'),
                ),
              ),
              PopupMenuItem(
                value: 11,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.video_file_outlined),
                  title: Text('Descargar vídeos'),
                ),
              ),
              PopupMenuItem(
                value: 9,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Jam'),
                ),
              ),
              if (supabaseServicesEnabled)
                PopupMenuItem(
                  value: 14,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Badge(
                      isLabelVisible: _friendsBadge > 0,
                      label: Text('$_friendsBadge'),
                      child: const Icon(Icons.people_outline),
                    ),
                    title: const Text('Amigos'),
                  ),
                ),
              PopupMenuItem(
                value: 4,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.album_outlined),
                  title: Text('Modo Vinilo'),
                ),
              ),
              PopupMenuItem(
                value: 5,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.queue_music),
                  title: Text('Cola de reproducción'),
                ),
              ),
              PopupMenuItem(
                value: 6,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.lyrics_outlined),
                  title: Text('Letras'),
                ),
              ),
              PopupMenuItem(
                value: 13,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.equalizer),
                  title: Text('Ecualizador'),
                ),
              ),
            ],
          ),
        if (rail)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: isModern(context)
                ? ModernBadge(
                    ref
                        .watch(shortcutServiceProvider)
                        .labelOf(ShortcutId.searchFocus),
                  )
                : Text(
                    ref
                        .watch(shortcutServiceProvider)
                        .labelOf(ShortcutId.searchFocus),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
      ],
    ),
  );

  Widget _errorBanner(AppController c) => isBrasa(context)
      ? Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Material(
            color: Brasa.graphite,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      c.error!,
                      style: const TextStyle(fontSize: 14, color: Brasa.cream),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar aviso',
                    onPressed: c.clearError,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        )
      : isModern(context)
      ? ModernBanner(message: c.error!, onClose: c.clearError)
      : Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    c.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar aviso',
                  onPressed: c.clearError,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        );

  Widget _content(AppController c) => Stack(
    fit: StackFit.expand,
    children: [
      Offstage(
        offstage: [9, 11].contains(_section),
        child: isSlush(context)
            ? _SlushSectionFade(section: _section, child: _page(c))
            : _page(c),
      ),
      if (_videosVisited)
        Offstage(
          offstage: _section != 11,
          child: _slushPage(
            c,
            VideoDownloadsPage(
              key: const ValueKey('video-downloads-page'),
              source: c.source,
              supportDirectory: c.supportDirectory,
            ),
          ),
        ),
      if (_jamVisited)
        Offstage(
          key: const ValueKey('jam-session'),
          offstage: _section != 9,
          child: TickerMode(
            enabled: _section == 9,
            child: JamPage(
              key: const ValueKey('persistent-jam-page'),
              controller: c,
              jam: _ensureJam(),
              onControllerReady: _jamCreated,
            ),
          ),
        ),
    ],
  );

  /// Slush: pestañas del reproductor (Vinilo/Letras/EQ/Cola) sobre la sección.
  Widget _slushTabs(AppController c, int section, Widget child) =>
      isSlush(context)
      ? Column(
          children: [
            SlushPlayerHeader(
              controller: c,
              current: section,
              onSection: _navigate,
            ),
            Expanded(child: child),
          ],
        )
      : child;

  Widget _page(AppController c) {
    switch (_section) {
      case 1:
        return _slushPage(c, _searchPage(c));
      case 2:
        return _slushPage(c, _library(c));
      case 3:
        return _slushPage(c, _downloads(c));
      case 4:
        return VinylPlayer(
          controller: c,
          follow: ref.read(followServiceProvider),
          onSection: _navigate,
          onBack: () => _handleBack(ref.read(controllerProvider)),
          jam: _jam,
        );
      case 5:
        if (isSlush(context)) {
          return SlushEqQueue(
            controller: c,
            onNavigate: _navigate,
            queueFirst: true,
          );
        }
        return _slushTabs(c, 5, QueuePanel(controller: c));
      case 7:
        return _slushPage(c, _settings(c));
      case 8:
        return DjDiscoveryPage(controller: c, onSearch: () => _navigate(1));
      case 13:
        if (isSlush(context)) {
          return SlushEqQueue(controller: c, onNavigate: _navigate);
        }
        return _slushTabs(
          c,
          13,
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: EqualizerPanel(controller: c, onClose: () => _navigate(0)),
          ),
        );
      case 12:
        return _slushPage(
          c,
          ArtistsPage(
            controller: c,
            follow: ref.read(followServiceProvider),
            tracks: c.tracks,
            onPlay: c.playTrack,
            onSearch: (query) {
              _search.text = query;
              _navigate(1);
              if (query.isNotEmpty) _submitSearch(c, query);
            },
          ),
        );
      case 14:
        return _slushPage(
          c,
          FriendsPage(
            controller: c,
            openChat: _friendsChat,
            jam: _jam,
            onSettings: () => _navigate(7),
            onJoinJam: (code) => _joinJamLink('aurora://jam/$code'),
          ),
        );
      case 9:
      case 11:
        return const SizedBox.shrink();
      default:
        return _home(c);
    }
  }

  Widget _home(AppController c) => HomeMusicPage(
    follow: ref.read(followServiceProvider),
    onSearchQuery: (query) {
      _search.text = query;
      _spotifySearch = false;
      _navigate(1);
      _submitSearch(c, query);
    },
    controller: c,
    onSearch: () => _navigate(1),
    onDownloads: () => _navigate(3),
    onVinyl: () => _navigate(4),
    onLikes: () => setState(() {
      _section = 2;
      _likesSelected = true;
      _playlist = null;
    }),
    onOpenPlaylist: (playlist) => setState(() {
      _section = 2;
      _playlist = playlist;
      _likesSelected = false;
    }),
  );

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: isModern(context)
            ? Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              )
            : Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    ],
  );

  /// Punto de color de un chip de acento (el color real) o, en «Automático»,
  /// una estrella: así cada opción se reconoce sin leer su nombre.
  Widget? _swatch(Color? color, bool auto, Color ring) {
    if (color == null && !auto) return null;
    if (auto) return Icon(Icons.auto_awesome, size: 16, color: ring);
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 1.5),
      ),
    );
  }

  /// ChoiceChip; en Modern: 8 px de radio, activo en azul marino. [swatch] /
  /// [auto]: chip de acento con su color a la vista.
  Widget _chip(
    String label,
    bool selected,
    VoidCallback onSelected, {
    Color? swatch,
    bool auto = false,
  }) {
    if (isBrasa(context)) {
      final dot = _swatch(swatch, auto, selected ? Brasa.void_ : Brasa.cloud);
      return ChoiceChip(
        avatar: dot,
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: Brasa.cream,
        backgroundColor: Brasa.graphite,
        // Contorno visible también sin seleccionar (si no, el chip se funde
        // con la tarjeta); seleccionado, grueso y del color del acento.
        side: BorderSide(
          color: selected ? (swatch ?? Brasa.accent) : Brasa.steel,
          width: selected ? 2.5 : 1,
        ),
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: selected ? Brasa.void_ : Brasa.cream,
        ),
        onSelected: (_) => onSelected(),
      );
    }
    // Slush: chip propio de 44; el tema base usa el chip del tema. Los de
    // acento van rellenos de su color.
    if (isSlush(context)) {
      return SlushChip(
        label,
        selected: selected,
        color: swatch ?? Slush.yellow,
        icon: auto ? Icons.auto_awesome : null,
        onTap: onSelected,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final dot = _swatch(
      swatch,
      auto,
      selected && isModern(context) ? colors.onPrimary : colors.onSurface,
    );
    if (!isModern(context)) {
      return ChoiceChip(
        avatar: dot,
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      );
    }
    return ChoiceChip(
      avatar: dot,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: colors.primary,
      backgroundColor: colors.surfaceContainerHighest,
      side: BorderSide(color: colors.outline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w500,
        color: selected ? colors.onPrimary : colors.onSurface,
      ),
      onSelected: (_) => onSelected(),
    );
  }

  /// Margen lateral de las páginas: el de Slush por ancho, 24 en el resto.
  double get _pagePad => isSlush(context)
      ? SlushSpacing.margin(MediaQuery.sizeOf(context).width)
      : 24;

  Widget _searchPage(AppController c) {
    final chips = [
      _chip(
        'Audio · YouTube',
        !_spotifySearch,
        () => setState(() => _spotifySearch = false),
      ),
      _chip(
        'Metadatos · Spotify',
        _spotifySearch,
        () => setState(() => _spotifySearch = true),
      ),
    ];
    final column = Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _pagePad, vertical: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            // Slush: una sola línea con scroll horizontal (no 3 líneas).
            child: isSlush(context)
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(spacing: 8, children: chips),
                  )
                : Wrap(spacing: 8, children: chips),
          ),
        ),
        Expanded(
          child: _spotifySearch
              ? SpotifyBrowserPanel(adder: _spotifyAdder)
              : _audioSearchPage(c),
        ),
      ],
    );
    return _scrollIfShort(column);
  }

  /// Con texto muy grande el cuerpo queda casi sin alto: la pantalla se
  /// desplaza en vez de desbordar.
  Widget _scrollIfShort(Widget column) {
    if (MediaQuery.textScalerOf(context).scale(14) <= 18) return column;
    return LayoutBuilder(
      builder: (_, box) => box.maxHeight >= 480
          ? column
          : SingleChildScrollView(child: SizedBox(height: 480, child: column)),
    );
  }

  Widget _audioSearchPage(AppController c) => Column(
    children: [
      // Brasa en pantalla ancha: la búsqueda vive en la barra superior.
      if (!(isBrasa(context) && MediaQuery.sizeOf(context).width >= 600))
        Padding(
          padding: EdgeInsets.fromLTRB(_pagePad, 8, _pagePad, 8),
          child: TextField(
            controller: _search,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: 'Canción, artista o enlace',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _submitSearch(c, _search.text),
              ),
              border: isBrasa(context)
                  ? OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9999),
                      borderSide: BorderSide.none,
                    )
                  : isModern(context)
                  ? null
                  : const OutlineInputBorder(),
            ),
            onSubmitted: (query) => _submitSearch(c, query),
            onChanged: (_) => setState(() {}),
          ),
        ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: _pagePad),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              for (final (kind, label) in const [
                (SearchKind.songs, 'Canciones'),
                (SearchKind.albums, 'Álbumes'),
                (SearchKind.artists, 'Artistas'),
                (SearchKind.videos, 'Vídeos'),
              ])
                _chip(label, c.searchKind == kind, () => c.setSearchKind(kind)),
            ],
          ),
        ),
      ),
      if (c.searching) const LinearProgressIndicator(minHeight: 2),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: _pagePad),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _importPlaylist(c),
            icon: const Icon(Icons.playlist_add),
            label: const Text('Importar una lista por enlace'),
          ),
        ),
      ),
      Expanded(
        // Las bandas de ListTile pintan en el Material más cercano: sin este
        // recorte la lista (Slush) se dibuja encima de pestañas y campo.
        child: Material(
          type: MaterialType.transparency,
          clipBehavior: Clip.hardEdge,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasSidebar = constraints.maxWidth >= 900;
              final results = c.searchDetail != null
                  ? _searchDetail(c, c.searchDetail!)
                  : _searchFocus.hasFocus && _search.text.trim().isEmpty
                  ? _recentSearchList(c)
                  : _searchResults(c);
              if (!hasSidebar) return results;
              return Row(
                children: [
                  SizedBox(width: 220, child: _recentSearchList(c)),
                  const VerticalDivider(width: 1),
                  Expanded(child: results),
                ],
              );
            },
          ),
        ),
      ),
    ],
  );

  Widget _recentSearchList(AppController c) {
    final recent = c.recentSearches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Búsquedas recientes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (recent.isNotEmpty)
              TextButton(
                onPressed: c.clearRecentSearches,
                child: const Text('Borrar'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          Text(
            'Tus búsquedas aparecerán aquí.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          for (final query in recent)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 18),
              title: Text(query, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Quitar de recientes',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => c.removeRecentSearch(query),
              ),
              onTap: () {
                _search.text = query;
                _searchFocus.unfocus();
                _submitSearch(c, query);
              },
            ),
      ],
    );
  }

  Widget _searchResults(AppController c) {
    final entries =
        c.searchKind == SearchKind.albums || c.searchKind == SearchKind.artists;
    final count = entries ? c.searchEntries.length : c.searchResults.length;
    if (count == 0) {
      if (c.searchError != null && !c.searching) {
        return Column(
          children: [
            Expanded(
              child: _empty(
                Icons.error_outline,
                'No se pudo buscar',
                c.searchError!,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: OutlinedButton.icon(
                onPressed: () => c.search(c.searchQuery),
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
            ),
          ],
        );
      }
      final done = c.searchQuery.isNotEmpty && !c.searching;
      return _empty(
        Icons.travel_explore,
        c.searching
            ? 'Buscando tu próxima canción…'
            : done
            ? 'Sin resultados'
            : 'Encuentra algo que te mueva',
        c.searching
            ? 'La búsqueda puede tardar unos segundos.'
            : done
            ? 'Prueba con otro título o artista, o pega un enlace directo.'
            : 'Escribe un título, artista o pega un enlace compatible.',
      );
    }
    final hasFooter = c.hasMoreSearchResults || c.searchError != null;
    // Al acercarse al final se pide la siguiente página (el botón queda de
    // respaldo y para reintentar tras un error).
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.axis == Axis.vertical &&
            n.metrics.extentAfter < 600 &&
            c.hasMoreSearchResults &&
            c.searchError == null) {
          // Fuera de la notificación: no se puede avisar a la interfaz en pleno layout.
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => c.loadMoreSearch(),
          );
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: count + (hasFooter ? 1 : 0),
        itemBuilder: (_, i) {
          if (i < count) {
            return entries
                ? _entryTile(c, c.searchEntries[i])
                : _trackTile(
                    c,
                    c.searchResults[i],
                    c.searchResults,
                    searchResult: true,
                  );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (c.searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'No se pudieron cargar más resultados: ${c.searchError}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (c.hasMoreSearchResults)
                  OutlinedButton.icon(
                    onPressed: c.searchLoadingMore ? null : c.loadMoreSearch,
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      c.searchLoadingMore ? 'Cargando…' : 'Cargar más',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _entryTile(AppController c, SearchEntry entry) => ListTile(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    leading: Artwork(
      track: Track(
        id: 'entry:${entry.browseId}',
        title: entry.title,
        artist: entry.subtitle,
        artworkUrl: entry.artworkUrl,
      ),
      artworkContext: ArtworkContext.thumbnail,
      radius: entry.kind == SearchKind.artists ? 28 : 8,
    ),
    title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      entry.subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: const Icon(Icons.chevron_right),
    onTap: () => c.openSearchEntry(entry),
  );

  Widget _searchDetail(AppController c, SearchEntry entry) {
    final tracks = c.searchDetailTracks;
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Volver a los resultados',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => c.openSearchEntry(null),
            ),
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        if (entry.kind == SearchKind.artists)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FollowButton(
              service: ref.read(followServiceProvider),
              name: entry.title,
              browseId: entry.browseId,
              imageUrl: entry.artworkUrl,
            ),
          ),
        if (c.searchDetailLoading) const LinearProgressIndicator(minHeight: 2),
        if (tracks.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.icon(
                onPressed: () => c.playTrack(tracks.first, context: tracks),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Reproducir todo'),
              ),
              TrackBatchButtons(controller: c, tracks: tracks),
            ],
          ),
      ],
    );
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: tracks.isEmpty ? 2 : tracks.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) return header;
        if (tracks.isNotEmpty) return _trackTile(c, tracks[i - 1], tracks);
        return SizedBox(
          height: 320,
          child: c.searchDetailLoading
              ? _empty(Icons.album_outlined, 'Cargando…', entry.title)
              : _empty(
                  c.searchDetailError != null
                      ? Icons.error_outline
                      : Icons.music_off_outlined,
                  c.searchDetailError != null
                      ? 'No se pudo cargar'
                      : 'Sin canciones',
                  c.searchDetailError ?? 'Este resultado no tiene canciones.',
                ),
        );
      },
    );
  }

  Widget _library(AppController c) {
    if (_playlist != null || _likesSelected) {
      final playlist = _likesSelected
          ? null
          : c.playlists.where((item) => item.id == _playlist!.id).firstOrNull;
      if (!_likesSelected && playlist == null) {
        return _empty(
          Icons.queue_music,
          'Esta lista ya no existe',
          'Selecciona otra lista de tu biblioteca.',
        );
      }
      final items = _likesSelected
          ? c.tracks.where((track) => c.favoriteIds.contains(track.id)).toList()
          : playlist!.trackIds
                .map(
                  (id) => c.tracks.where((track) => track.id == id).firstOrNull,
                )
                .whereType<Track>()
                .toList();
      final header = Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _playlist = null;
                _likesSelected = false;
              }),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Todas las listas'),
            ),
            if (_likesSelected)
              Text('Me gusta', style: Theme.of(context).textTheme.titleMedium),
            if (items.isNotEmpty)
              TrackBatchButtons(controller: c, tracks: items),
            if (playlist != null) ...[
              PlaylistPhotoMenu(
                controller: c,
                playlist: playlist,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: PlaylistCover(
                        playlist: playlist,
                        tracks: playlistCoverTracks(c, playlist),
                        size: 72,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Tooltip(
                        message: 'Cambiar foto',
                        child: GestureDetector(
                          key: const ValueKey('playlist-cover-camera'),
                          onTap: () =>
                              changePlaylistPhoto(context, c, playlist),
                          child: const CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.photo_camera,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('playlist-change-photo'),
                onPressed: () => changePlaylistPhoto(context, c, playlist),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Cambiar foto'),
              ),
              if (playlist.photoPath != null)
                TextButton(
                  key: const ValueKey('playlist-remove-photo'),
                  onPressed: () => c.setPlaylistPhoto(playlist, null),
                  child: const Text('Quitar foto'),
                ),
              PlaylistSendButton(controller: c, playlist: playlist),
              OutlinedButton(
                onPressed: () async {
                  final name = await _askText(
                    'Renombrar lista',
                    'Nombre',
                    initial: playlist.name,
                  );
                  if (name != null) c.renamePlaylist(playlist, name);
                },
                child: const Text('Renombrar'),
              ),
              TextButton(
                onPressed: () async {
                  if (await _confirm(
                    'Eliminar lista',
                    'Se eliminará «${playlist.name}». Tus archivos permanecerán en la biblioteca.',
                  )) {
                    c.deletePlaylist(playlist);
                    setState(() => _playlist = null);
                  }
                },
                child: const Text('Eliminar'),
              ),
            ],
          ],
        ),
      );
      if (items.isEmpty) {
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            header,
            SizedBox(
              height: 320,
              child: _empty(
                _likesSelected ? Icons.favorite_border : Icons.playlist_add,
                _likesSelected
                    ? 'Aún no hay canciones que te gusten'
                    : 'Esta lista está esperando música',
                _likesSelected
                    ? 'Marca una canción con Me gusta para verla aquí.'
                    : 'Añade canciones desde el menú de cualquier resultado o canción.',
              ),
            ),
          ],
        );
      }
      return PlaylistDetailTools(
        tracks: items,
        onPlay: (v) => c.playTrack(v.first, context: v),
        header: header,
        builder: (v, canReorder) => playlist == null || !canReorder
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: v.length + 1,
                itemBuilder: (_, i) => i == 0
                    ? header
                    : _trackTile(
                        c,
                        v[i - 1],
                        v,
                        key: ValueKey('${playlist?.id}-${v[i - 1].id}'),
                        playlist: playlist,
                      ),
              )
            : ReorderableListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                header: header,
                itemCount: v.length,
                onReorder: (oldIndex, newIndex) =>
                    c.reorderPlaylist(playlist, oldIndex, newIndex),
                itemBuilder: (_, i) => _trackTile(
                  c,
                  v[i],
                  v,
                  key: ValueKey('${playlist.id}-${v[i].id}'),
                  playlist: playlist,
                ),
              ),
      );
    }
    final column = Column(
      children: [
        if (!isSlush(context))
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tu biblioteca',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: isSlush(context)
                  ? SlushSpacing.margin(MediaQuery.sizeOf(context).width)
                  : 24,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: c.busy ? null : () => _importSpotify(c),
                      icon: const Icon(Icons.library_add_outlined),
                      label: const Text('Importar de Spotify'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _createPlaylist(c),
                      icon: const Icon(Icons.add),
                      label: const Text('Crear lista'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (isSlush(context)) ...[
                SlushLikesCard(
                  count: c.favoriteIds.length,
                  onTap: () => setState(() {
                    _likesSelected = true;
                    _playlist = null;
                  }),
                ),
                const SizedBox(height: 18),
              ] else
                ListTile(
                  leading: const Icon(Icons.favorite),
                  title: const Text('Me gusta'),
                  subtitle: Text('${c.favoriteIds.length} canciones'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => setState(() {
                    _likesSelected = true;
                    _playlist = null;
                  }),
                ),
              FollowedArtistsSection(
                showArtists: false,
                service: ref.read(followServiceProvider),
                onOpenArtist: (_) {},
                onOpenRelease: (release) => _openEntry(release.entry),
              ),
              if (c.playlists.isEmpty)
                _empty(
                  Icons.queue_music,
                  'Una lista para cada momento',
                  'Crea una lista y reúne tus canciones favoritas.',
                ),
              if (c.playlists.isNotEmpty)
                PlaylistShelf(
                  controller: c,
                  onOpen: (playlist) => setState(() {
                    _likesSelected = false;
                    _playlist = playlist;
                  }),
                ),
              FollowedArtistsSection(
                showNews: false,
                service: ref.read(followServiceProvider),
                onOpenArtist: (artist) => _openEntry(
                  SearchEntry(
                    kind: SearchKind.artists,
                    browseId: artist.browseId,
                    title: artist.name,
                    artworkUrl: artist.imageUrl,
                  ),
                ),
                onOpenRelease: (release) => _openEntry(release.entry),
              ),
            ],
          ),
        ),
      ],
    );
    return _scrollIfShort(column);
  }

  Widget _trackTile(
    AppController c,
    Track t,
    List<Track> items, {
    Key? key,
    MusicPlaylist? playlist,
    bool searchResult = false,
  }) {
    final active = c.currentTrack?.id == t.id;
    final playlistIndex = playlist?.trackIds.indexOf(t.id) ?? -1;
    final extras = <TrackMenuExtra>[
      if (t.isPendingSpotifyMatch)
        (
          label: 'Elegir coincidencia de YouTube',
          run: () => _matchSpotify(c, t),
        ),
      if (c.canDownloadTrack(t))
        (label: 'Descargar audio', run: () => c.downloadTrack(t)),
      if (playlist != null && playlistIndex > 0)
        (
          label: 'Subir en la lista',
          run: () =>
              c.reorderPlaylist(playlist, playlistIndex, playlistIndex - 1),
        ),
      if (playlist != null && playlistIndex < playlist.trackIds.length - 1)
        (
          label: 'Bajar en la lista',
          run: () =>
              c.reorderPlaylist(playlist, playlistIndex, playlistIndex + 2),
        ),
      if (playlist != null)
        (
          label: 'Quitar de esta lista',
          run: () => c.removeFromPlaylist(playlist, t),
        ),
    ];
    return TrackActionsRegion(
      key: key,
      controller: c,
      track: t,
      extras: extras,
      builder: (context, hot) {
        final tile = ListTile(
          shape: isSlush(context)
              ? RoundedRectangleBorder(
                  side: active
                      ? context.slush.border
                      : context.slush.borderSoft,
                  borderRadius: BorderRadius.circular(SlushRadius.r16),
                )
              : active
              ? auroraSelectedShape(context)
              : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          selectedTileColor: isSlush(context) ? Slush.mint : null,
          selectedColor: isSlush(context) ? Slush.ink : null,
          selected: active,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 4,
          ),
          leading: Artwork(
            track: t,
            artworkContext: ArtworkContext.thumbnail,
            radius: 8,
          ),
          title: Text(
            t.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Text(
            t.isPendingSpotifyMatch
                ? '${t.artist} · Elige una coincidencia de YouTube'
                : '${t.artist}${t.isLocal ? ' · Disponible sin conexión' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: t.isPendingSpotifyMatch
              ? () => _matchSpotify(c, t)
              : () =>
                    c.playTrack(t, context: items, replaceQueue: !searchResult),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (MediaQuery.sizeOf(context).width >= 700)
                isSlush(context)
                    ? SlushPill(_time(t.duration), color: Slush.lilac)
                    : Text(
                        _time(t.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
              IconButtonTheme(
                data: isSlush(context) && active
                    ? IconButtonThemeData(
                        style: IconButton.styleFrom(foregroundColor: Slush.ink),
                      )
                    : IconButtonTheme.of(context),
                child: TrackMenuButton(
                  controller: c,
                  track: t,
                  extras: extras,
                  quickAdd: true,
                  quickAddVisible: hot,
                ),
              ),
            ],
          ),
        );
        return isSlush(context)
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: tile,
              )
            : tile;
      },
    );
  }

  Widget _downloads(AppController c) => DownloadsStudioPage(controller: c);

  static const _settingsTabs = [
    'Apariencia',
    'Reproducción',
    'Biblioteca',
    'Cuenta y servicios',
    'Avanzado',
    'Acerca de',
  ];
  int _settingsTab = 0;

  /// Plegado/desplegado de cada sección de Ajustes por título; vive aquí para
  /// que se recuerde al salir y volver a Ajustes.
  final _settingsExpanded = <String, bool>{};
  int _settingsOpenSerial = 0;

  /// Abre Ajustes. [tab] null conserva la categoría en la que se quedó; con
  /// [section] esa sección llega desplegada.
  void _openSettings(int? tab, [String? section]) {
    if (tab != null) {
      setState(() {
        _settingsTab = tab;
        if (section != null) _settingsExpanded[section] = true;
        _settingsOpenSerial++;
      });
    }
    _navigate(7);
  }

  void _showProfileMenu(BuildContext anchor, AppController c) {
    final account = c.accounts?.profile;
    showProfileMenu(
      anchor,
      name:
          account?.username ??
          (c.profileName.isEmpty ? 'Invitado' : c.profileName),
      status: account != null ? 'Sesión iniciada' : 'Sin sesión',
      avatar: c.profileAvatar,
      onSelected: (e) => _openSettings(e.tab, e.section),
    );
  }

  // Palabras extra para el buscador de Ajustes, por título de sección.
  static const _settingsKeywords = <String, String>{
    'Perfil': 'foto avatar nombre estadísticas',
    'Cuenta': 'sesión correo sincronizar usuario',
    'Comandos de voz': 'micrófono voz habla aurora',
    'Identidad y tema': 'tema modo oscuro claro',
    'Color de acento': 'color',
    'Almacenamiento y biblioteca': 'carpeta descargas música caché',
    'Actualizaciones': 'versión actualizar release',
    'Atajos': 'teclado combinaciones',
    'Herramientas, sesión y diagnóstico':
        'youtube yt-dlp ffmpeg sesión cookies',
    'Control remoto (Stream Deck)': 'stream deck api',
    'Discord': 'presencia',
    'Ecualizador': 'eq bandas presets',
    'Sueño': 'temporizador dormir',
    'Reproducción': 'autoplay cola',
    'Música sin conexión': 'offline descargas',
    'Last.fm': 'scrobble historial',
    'Movimiento': 'animaciones reducir',
    'Acerca de': 'versión información licencia',
    'Servicios en línea': 'servicios en línea supabase jam modo local',
    'Transferir por QR':
        'qr red local lan pasar biblioteca dispositivo sincronizar',
  };

  // Por título; lo no listado (herramientas y diagnóstico) cae en Avanzado.
  int _settingsTabOf(String title) => switch (title) {
    'Identidad y tema' || 'Color de acento' || 'Movimiento' => 0,
    'Reproducción' ||
    'Reproducción experimental' ||
    'Ecualizador' ||
    'Sueño' => 1,
    'Almacenamiento y biblioteca' ||
    'Vista de playlists' ||
    'Música sin conexión' => 2,
    'Cuenta' ||
    'Servicios en línea' ||
    'Transferir por QR' ||
    'Perfil' ||
    'Actualizaciones' ||
    'Last.fm' => 3,
    'Acerca de' => 5,
    _ => 4,
  };

  Widget _settings(AppController c) {
    final allSections = <({String title, String subtitle, List<Widget> Function() children})>[
      (
        title: 'Perfil',
        subtitle: 'Tu foto y nombre en la Jam',
        children: () => [
          ProfileSettings(controller: c),
          ListTile(
            leading: const Icon(Icons.query_stats_rounded),
            title: const Text('Estadísticas de escucha'),
            subtitle: const Text('Canción, artista y género más escuchados'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Perfil')),
                  body: ProfilePage(controller: c),
                ),
              ),
            ),
          ),
        ],
      ),
      if (supabaseServicesEnabled)
        (
          title: 'Cuenta',
          subtitle: 'Sincroniza tu biblioteca entre dispositivos',
          children: () => [AccountSettings(controller: c)],
        ),
      (
        title: 'Servicios en línea',
        subtitle: 'Jam, cuentas y modo local',
        children: () => [OnlineSettings(status: c.online)],
      ),
      (
        title: 'Transferir por QR',
        subtitle: 'Pasa tu biblioteca a otro dispositivo de tu red',
        children: () => [LanSyncPanel(controller: c)],
      ),
      (
        title: 'Vista de playlists',
        subtitle: 'Cómo se muestran tus listas',
        children: () => [PlaylistViewModeTile(controller: c)],
      ),
      (
        title: 'Almacenamiento y biblioteca',
        subtitle: 'Tu música y descargas en este dispositivo',
        children: () => [
          const Text('Carpeta de descargas'),
          const SizedBox(height: 8),
          SelectableText(c.downloadsDirectoryPath),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    c.canConfigureDownloadDirectory &&
                        !c.configuringDownloadDirectory
                    ? c.chooseDownloadDirectory
                    : null,
                icon: const Icon(Icons.drive_file_move_outline),
                label: Text(
                  c.configuringDownloadDirectory
                      ? 'Abriendo selector…'
                      : 'Cambiar carpeta',
                ),
              ),
              OutlinedButton.icon(
                onPressed: c.openDownloadDirectory,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Abrir carpeta'),
              ),
              OutlinedButton.icon(
                onPressed: c.importFiles,
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Importar archivos'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('La carpeta se usa para las próximas descargas.'),
          if (c.source.supportsPlaybackCache) ...[
            const SizedBox(height: 20),
            Text(
              'Caché de reproducción',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              'Hasta 512 MB. Los archivos antiguos se limpian automáticamente. Tus descargas y la canción actual se conservan.',
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: c.busy || c.clearingPlaybackCache
                    ? null
                    : c.clearPlaybackCache,
                icon: const Icon(Icons.cleaning_services_outlined),
                label: Text(
                  c.clearingPlaybackCache ? 'Limpiando…' : 'Limpiar caché',
                ),
              ),
            ),
            if (c.playbackCacheMessage != null) ...[
              const SizedBox(height: 8),
              Text(c.playbackCacheMessage!),
            ],
          ],
        ],
      ),
      (
        title: 'Actualizaciones',
        subtitle: 'Nuevas versiones desde GitHub Releases',
        children: () => [UpdateSettings(controller: _updates)],
      ),
      if (c.lastfm != null)
        (
          title: 'Last.fm',
          subtitle: 'Opcional: historial y recomendaciones',
          children: () => [LastfmSettingsPanel(service: c.lastfm!)],
        ),
      (
        title: 'Música sin conexión',
        subtitle: 'Descargas explícitas y archivos locales',
        children: () => [
          OfflineSettingsPanel(
            controller: c,
            onManage: () => _navigate(3),
            onSearch: () => _navigate(1),
          ),
        ],
      ),
      if (c.source.supportsExperimentalProgressivePlayback)
        (
          title: 'Reproducción experimental',
          subtitle: 'Descarga mientras se reproduce',
          children: () => [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Descargar mientras se reproduce'),
              subtitle: Text(
                c.source.supportsExperimentalProgressivePlayback
                    ? 'Empieza antes; puede esperar en zonas aún no descargadas o fallar. La descarga completa sigue siendo la opción estable.'
                    : 'No disponible para esta fuente o plataforma.',
              ),
              value: c.experimentalProgressivePlayback,
              onChanged: c.source.supportsExperimentalProgressivePlayback
                  ? c.setExperimentalProgressivePlayback
                  : null,
            ),
          ],
        ),
      (
        title: 'Reproducción',
        subtitle: 'Cola y reproducción automática',
        children: () => [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Autoplay: rellenar la cola automáticamente'),
            subtitle: const Text(
              'Al acabarse la cola, Aurora añade canciones afines a tus gustos.',
            ),
            value: c.autoRefill,
            onChanged: c.setAutoRefill,
          ),
          const SizedBox(height: 8),
          Text(
            'Calidad de audio',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (q, label) in const [
                (AudioQuality.high, 'Alta'),
                (AudioQuality.normal, 'Normal'),
                (AudioQuality.saver, 'Ahorro de datos'),
              ])
                _chip(label, c.audioQuality == q, () => c.setAudioQuality(q)),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Alta: Opus ~160 kbps. Normal: AAC ~128 kbps. Ahorro de datos: ~50 kbps. Se aplica desde la siguiente canción que se cargue.',
          ),
        ],
      ),
      (
        title: 'Identidad y tema',
        subtitle: 'Tema y modo de Aurora',
        children: () => [
          Text('Temas', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          const Text(
            'Atelier es el clásico; Modern, limpio y luminoso; Brasa, oscuro y cálido en carriles; Slush, pegatinas y colores planos.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'atelier': 'Atelier',
                'modern': 'Modern',
                'brasa': 'Brasa',
                'slush': 'Slush',
              }.entries)
                _chip(
                  entry.value,
                  c.themeKind == entry.key,
                  () => c.setThemeKind(entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Modo', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (c.themeKind == 'brasa')
            const Text('Brasa es siempre oscuro.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in {
                  ThemeMode.system: 'Sistema',
                  ThemeMode.dark: 'Oscuro',
                  ThemeMode.light: 'Claro',
                }.entries)
                  _chip(
                    entry.value,
                    c.themeMode == entry.key,
                    () => c.setThemeMode(entry.key),
                  ),
              ],
            ),
        ],
      ),
      (
        title: 'Color de acento',
        subtitle: 'Automático toma el color de la portada actual',
        children: () => [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in const {
                'automatic': 'Automático',
                'terracotta': 'Terracota',
                'amber': 'Ámbar',
                'forest': 'Verde bosque',
                'purple': 'Morado',
              }.entries)
                _chip(
                  entry.value,
                  c.accentPalette == entry.key,
                  () => c.setAccentPalette(entry.key),
                  swatch: AppController.accentPaletteColors[entry.key],
                  auto: entry.key == 'automatic',
                ),
            ],
          ),
        ],
      ),
      if (discordAvailable)
        (
          title: 'Discord',
          subtitle: 'Presencia enriquecida',
          children: () => [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mostrar en Discord'),
              subtitle: const Text(
                'Muestra la canción que suena en tu perfil.',
              ),
              value: c.discordPresence,
              onChanged: c.setDiscordPresence,
            ),
          ],
        ),
      if (_voice.supported)
        (
          title: 'Comandos de voz',
          subtitle: 'Di «Aurora, pausa», «Aurora, siguiente»…',
          children: () => [VoiceSettings(service: _voice)],
        ),
      if (_remote.supported)
        (
          title: 'Control remoto (Stream Deck)',
          subtitle: 'API local para pausar, saltar e iniciar la Jam',
          children: () => [RemoteControlSettings(service: _remote)],
        ),
      (
        title: 'Movimiento',
        subtitle: 'Animaciones de la interfaz',
        children: () => [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reducir movimiento'),
            subtitle: const Text('Una experiencia visual más tranquila.'),
            value: c.reducedMotion,
            onChanged: c.setReducedMotion,
          ),
        ],
      ),
      if (WindowControls.supported)
        (
          title: 'Mini reproductor',
          subtitle: 'Ventana compacta siempre visible',
          children: () => [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mini reproductor'),
              subtitle: const Text(
                'Reduce la ventana a una tarjeta siempre visible con la portada, el progreso y los controles. Se sale con el botón de la tarjeta.',
              ),
              value: _miniWindow,
              onChanged: (on) => unawaited(_setMiniWindow(on)),
            ),
          ],
        ),
      if (WindowControls.supported || DuvetPresence.platformSupported)
        (
          title: WindowControls.supported ? 'Ventana y bandeja' : 'Duvet',
          subtitle: WindowControls.supported
              ? 'Cierre, bandeja del sistema e inicio'
              : 'Lo que escuchas, en tu perfil',
          children: () => [
            DesktopSettingsTiles(shell: _desktop, duvet: _duvet),
          ],
        ),
      (
        title: 'Ecualizador',
        subtitle: 'Bandas paramétricas, presets y comparación A/B',
        children: () => [EqualizerPanel(controller: c)],
      ),
      (
        title: 'Atajos',
        subtitle: 'Teclado y combinaciones',
        children: () => [
          ShortcutsSettingsPanel(service: ref.read(shortcutServiceProvider)),
        ],
      ),
      (
        title: 'Sueño',
        subtitle: c.sleepRemaining == null
            ? 'Temporizador desactivado'
            : '${c.sleepRemaining!.inMinutes + 1} minutos restantes',
        children: () => [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Temporizador de sueño'),
            subtitle: Text(
              c.sleepRemaining == null
                  ? 'Desactivado'
                  : '${c.sleepRemaining!.inMinutes + 1} minutos restantes',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _sleepTimer(c),
          ),
        ],
      ),
      (
        title: 'Herramientas, sesión y diagnóstico',
        subtitle: 'Fuentes locales y utilidades opcionales',
        children: () => [
          Text(
            defaultTargetPlatform == TargetPlatform.android
                ? 'Herramientas integradas en este dispositivo'
                : c.source.toolDirectory == null
                ? 'Configura la carpeta de herramientas para las descargas explícitas de vídeos.'
                : 'Herramientas: ${c.source.toolDirectory}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (defaultTargetPlatform != TargetPlatform.android)
                OutlinedButton.icon(
                  onPressed: c.configureTools,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Carpeta de herramientas'),
                ),
              OutlinedButton.icon(
                onPressed: c.diagnosing ? null : c.runDiagnostics,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: Text(
                  c.diagnosing ? 'Comprobando…' : 'Comprobar configuración',
                ),
              ),
              OutlinedButton.icon(
                onPressed:
                    c.source.updatingTools ||
                        c.busy ||
                        c.audio.isPlaying ||
                        c.audio.isBuffering
                    ? null
                    : c.source.checkForUpdates,
                icon: const Icon(Icons.system_update_alt),
                label: Text(
                  c.source.updatingTools
                      ? 'Comprobando nightly…'
                      : 'Comprobar yt-dlp nightly',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Nightly se comprueba automáticamente como máximo cada 24 horas, cuando no se reproduce música. Python, QuickJS y FFmpeg en Android se actualizan con la app.',
          ),
          if (c.source.toolUpdateMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(c.source.toolUpdateMessage!),
            ),
          if (c.diagnostics != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: SelectableText(c.diagnostics!),
            ),
          const SizedBox(height: 16),
          Text(
            c.hasYouTubeSession
                ? 'Sesión de YouTube configurada'
                : 'Sesión de YouTube opcional sin importar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Importa un archivo cookies.txt en formato Netscape exportado por ti de tu sesión de YouTube. Aurora guarda una copia local. Puedes reemplazarla o eliminarla desde aquí. Una sesión no garantiza resolver límites de YouTube ni errores 429.',
            style: TextStyle(height: 1.6),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: c.sessionBusy ? null : c.importYouTubeSession,
                icon: const Icon(Icons.person_outline),
                label: Text(
                  c.sessionBusy
                      ? 'Procesando sesión…'
                      : c.hasYouTubeSession
                      ? 'Reemplazar sesión'
                      : 'Importar sesión',
                ),
              ),
              if (c.hasYouTubeSession)
                TextButton.icon(
                  onPressed: c.sessionBusy ? null : c.clearYouTubeSession,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Eliminar sesión'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  if (await _confirm(
                    'Limpiar caché',
                    'Se eliminarán los archivos temporales. Tus descargas y listas se conservarán.',
                  )) {
                    c.clearCache();
                  }
                },
                icon: const Icon(Icons.cleaning_services_outlined),
                label: const Text('Limpiar caché temporal'),
              ),
            ],
          ),
        ],
      ),
      (
        title: 'Acerca de',
        subtitle: 'Versión y nota de uso',
        children: () => [const AboutSettings()],
      ),
    ];
    final modern = isModern(context);
    final brasa = isBrasa(context);
    return SettingsLayout(
      tabs: _settingsTabs,
      icons: const [
        Icons.palette_outlined,
        Icons.play_circle_outline,
        Icons.library_music_outlined,
        Icons.manage_accounts_outlined,
        Icons.tune_rounded,
        Icons.info_outline_rounded,
      ],
      descriptions: const [
        'Tema, modo, color de acento y movimiento.',
        'Ecualizador, sueño y autoplay.',
        'Carpetas, descargas y vista de playlists.',
        'Perfil, actualizaciones y Last.fm.',
        'Ventana, atajos, herramientas y diagnóstico.',
        'Versión de Aurora.',
      ],
      selected: _settingsTab,
      onSelect: (i) => setState(() => _settingsTab = i),
      sections: [
        for (final s in allSections)
          SettingsSection(
            title: s.title,
            subtitle: s.subtitle,
            tab: _settingsTabOf(s.title),
            keywords: _settingsKeywords[s.title] ?? '',
            builder: s.children,
          ),
      ],
      expanded: _settingsExpanded,
      openSerial: _settingsOpenSerial,
      sectionTitle: _sectionTitle,
      chip: _chip,
      card: (child, compact) => Padding(
        padding: EdgeInsets.only(bottom: brasa ? 16 : (modern ? 24 : 16)),
        child: brasa
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: Brasa.obsidian,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: Brasa.cardShadow,
                ),
                child: Material(type: MaterialType.transparency, child: child),
              )
            : modern
            ? ModernCard(
                padding: EdgeInsets.zero,
                child: Material(type: MaterialType.transparency, child: child),
              )
            : Material(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
      ),
    );
  }

  /// Mini reproductor / barra de transporte (ver `mini_player_host.dart`).
  Widget _miniPlayer(
    AppController c,
    bool rail,
    MiniPlayerPlacement placement,
  ) => MiniPlayerHost(
    controller: c,
    section: _section,
    rail: rail,
    placement: placement,
    jam: _jam,
    onOpenPlayer: () => _navigate(4),
    onTogglePlay: () => _togglePlay(c),
    onOpenQueue: () => _navigate(5),
    onOpenLyrics: () => _navigate(6),
    onOpenMini: WindowControls.supported
        ? () => unawaited(_setMiniWindow(true))
        : null,
    mute: _mute,
  );

  Future<void> _sleepTimer(AppController c) async {
    final value = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Temporizador de sueño',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            for (final minutes in [0, 15, 30, 45, 60])
              ListTile(
                leading: const Icon(Icons.bedtime_outlined),
                title: Text(minutes == 0 ? 'Desactivar' : '$minutes minutos'),
                onTap: () => Navigator.pop(context, minutes),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
    if (value != null) {
      c.setSleepTimer(value == 0 ? null : Duration(minutes: value));
    }
  }

  Future<void> _createPlaylist(AppController c) async {
    final name = await _askText('Crear lista', 'Nombre de la lista');
    if (name == null) return;
    await c.createPlaylist(name);
    final created = c.playlists.where((p) => p.name == name.trim()).lastOrNull;
    if (created == null || !mounted) return;
    // Paso opcional: ofrecer la foto justo al crear.
    showUndoSnackBar(
      ScaffoldMessenger.of(context),
      Text('Lista «${created.name}» creada'),
      label: 'Añadir foto',
      onAction: () => changePlaylistPhoto(context, c, created),
      duration: const Duration(seconds: 6),
    );
  }

  Future<void> _addToPlaylist(AppController c, Track t) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * .6, 420),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Añadir a una lista',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Crear una lista'),
              onTap: () => Navigator.pop(context, '__new__'),
            ),
            Expanded(
              child: ListView(
                children: c.playlists
                    .map(
                      (p) => ListTile(
                        leading: const Icon(Icons.queue_music),
                        title: Text(p.name),
                        onTap: () => Navigator.pop(context, p.id),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (id == '__new__') {
      final name = await _askText('Crear lista', 'Nombre de la lista');
      if (name != null) {
        await c.createPlaylist(name);
        final created = c.playlists.where((p) => p.name == name).lastOrNull;
        if (created != null) c.addToPlaylist(created, t);
      }
    } else if (id != null) {
      final p = c.playlists.where((p) => p.id == id).firstOrNull;
      if (p != null) c.addToPlaylist(p, t);
    }
  }

  Future<void> _importPlaylist(AppController c) async {
    final url = await _askText('Importar lista', 'Enlace de la lista');
    if (url != null) c.importPlaylist(url);
  }

  Future<void> _importSpotify(AppController c) async {
    c.clearError();
    final source = await SpotifyImportSourceDialog.show(context);
    if (source == null || !mounted) return;
    SpotifyImportResult? result;
    if (source.link != null) {
      final fetched = await c.fetchSpotifyLink(source.link!);
      if (!mounted) return;
      if (fetched != null) {
        result = SpotifyImportResult(playlists: [fetched.playlist], skipped: 0);
        if (fetched.truncated) {
          showUndoSnackBar(
            ScaffoldMessenger.maybeOf(context),
            const Text(
              'Spotify solo dejó leer las primeras 100 canciones sin iniciar sesión.',
            ),
          );
        }
      }
    } else {
      result = await c.pickSpotifyImport();
    }
    if (!mounted) return;
    if (result == null) {
      if (c.error != null) {
        showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(c.error!));
        c.clearError();
      }
      return;
    }
    await SpotifyImportDialog.show(
      context,
      result: result,
      onImport: c.importSpotifyPlaylists,
    );
    if (!mounted || c.error == null) return;
    showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(c.error!));
    c.clearError();
  }

  Future<void> _matchSpotify(AppController c, Track track) =>
      SpotifyMatchDialog.show(
        context,
        track: track,
        onSearch: () => c.findSpotifyMatches(track),
        onSave: (match, {required play}) =>
            c.matchSpotifyTrack(track.id, match, play: play),
      );

  Future<String?> _askText(
    String title,
    String label, {
    String initial = '',
  }) async {
    final input = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          maxLength: label.contains('Enlace') ? 2048 : 120,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    // Dialog exit animation can still reference its controller.
    Future<void>.delayed(const Duration(milliseconds: 300), input.dispose);
    return result;
  }

  Future<bool> _confirm(
    String title,
    String message, {
    String confirmLabel = 'Confirmar',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;

  Widget _empty(IconData icon, String title, String message) => isSlush(context)
      ? SlushEmpty(icon: icon, title: title, message: message)
      : _plainEmpty(icon, title, message);

  Widget _plainEmpty(IconData icon, String title, String message) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class SpectrumView extends StatelessWidget {
  const SpectrumView({
    super.key,
    required this.values,
    required this.color,
    required this.enabled,
  });
  final ValueListenable<List<double>> values;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: enabled
            ? ValueListenableBuilder<List<double>>(
                valueListenable: values,
                builder: (_, bins, _) =>
                    CustomPaint(painter: _SpectrumPainter(bins, color)),
              )
            : CustomPaint(
                painter: _SpectrumPainter(
                  const [],
                  color.withValues(alpha: .3),
                ),
              ),
      ),
    ),
  );
}

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter(this.bins, this.color);
  final List<double> bins;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 32;
    final width = size.width / count;
    final paint = Paint()..color = color;
    for (int i = 0; i < count; i++) {
      final amplitude = bins.isEmpty
          ? 0.0
          : bins[(i * bins.length / count).floor().clamp(0, bins.length - 1)];
      final height = math.max(
        2.0,
        amplitude.isFinite ? amplitude.clamp(0.0, 1.0) * size.height : 2.0,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            i * width + 2,
            (size.height - height) / 2,
            math.max(1, width - 4),
            height,
          ),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter oldDelegate) =>
      oldDelegate.bins != bins || oldDelegate.color != color;
}

String _time(Duration value) {
  final seconds = math.max(0, value.inSeconds);
  final minutes = seconds ~/ 60;
  return '${minutes.toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// Slush: entrada de sección (opacidad + 8 px, 220 ms `easeOut`) al cambiar de
/// pestaña. El hijo conserva su estado; con movimiento reducido es un corte.
class _SlushSectionFade extends StatefulWidget {
  const _SlushSectionFade({required this.section, required this.child});
  final int section;
  final Widget child;

  @override
  State<_SlushSectionFade> createState() => _SlushSectionFadeState();
}

class _SlushSectionFadeState extends State<_SlushSectionFade>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: SlushMotion.sectionIn,
    value: 1,
  );

  @override
  void didUpdateWidget(_SlushSectionFade old) {
    super.didUpdateWidget(old);
    if (old.section != widget.section && !SlushMotion.reduce(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlushMotion.fadeSlide(_c, widget.child);
}
