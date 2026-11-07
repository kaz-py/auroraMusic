import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../friends/friends_providers.dart';
import '../friends/friends_service.dart';
import '../jam/jam_controller.dart';
import '../shortcuts/shortcut_service.dart';
import 'friends_page.dart';
import 'jam/jam_flows.dart';
import 'undo_snackbar.dart';

/// Lo que el shell ofrece a cualquier fila de canciones: la Jam (si existe)
/// y el selector de listas. Sin scope las filas solo ofrecen acciones de cola.
class TrackActionsScope extends InheritedWidget {
  const TrackActionsScope({
    super.key,
    required this.jam,
    required this.ensureJam,
    this.addToPlaylist,
    required super.child,
  });
  final JamController? jam;
  final JamController Function() ensureJam;
  final Future<void> Function(Track track)? addToPlaylist;

  static TrackActionsScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TrackActionsScope>();

  @override
  bool updateShouldNotify(TrackActionsScope old) => true;
}

/// Texto para compartir: «Título — Artista» y, si no es local, el enlace de YouTube Music.
String shareText(Track t) {
  final base = '${t.title} — ${t.artist}';
  if (t.isLocal || t.id.isEmpty) return base;
  return '$base\nhttps://music.youtube.com/watch?v=${Uri.encodeQueryComponent(t.id)}';
}

/// Entrada extra del menú (p. ej. «Quitar de esta lista» en una playlist).
typedef TrackMenuExtra = ({String label, VoidCallback run});

/// Acción de la canción como dato: etiqueta, icono, qué hace y, si no se
/// puede, el motivo.
typedef TrackMenuItem = ({
  String label,
  IconData icon,
  VoidCallback run,
  String? disabledReason,
});

/// Lógica única de «cola / Jam» para menú ⋯, clic derecho, pulsación larga,
/// botón «+» y atajos. No duplica nada: delega en AppController y JamController.
class TrackActions {
  TrackActions(this.context, this.app)
    : _messenger = ScaffoldMessenger.maybeOf(context),
      _scope = TrackActionsScope.maybeOf(context);

  final BuildContext context;
  final AppController app;
  final ScaffoldMessengerState? _messenger;
  final TrackActionsScope? _scope;

  JamController? get activeJam {
    final jam = _scope?.jam;
    return jam != null && jam.active ? jam : null;
  }

  /// Motivo por el que no se puede añadir a la Jam (null si se puede).
  String? get jamBlockedReason {
    final jam = activeJam;
    if (jam == null || jam.canAdd) return null;
    return 'El anfitrión no permite añadir canciones.';
  }

  void _say(String text, {String? undoLabel, VoidCallback? undo}) {
    showUndoSnackBar(
      _messenger,
      Text(text),
      label: undo == null ? null : (undoLabel ?? 'Deshacer'),
      onAction: undo,
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> addToQueue(Track track) async {
    final before = app.queue.length;
    await app.addToQueue(track);
    final added = app.queue.length > before;
    _say(
      added ? 'Añadida a la cola' : 'Ya estaba en la cola',
      undo: added
          ? () {
              final i = app.queue.lastIndexWhere((q) => q.id == track.id);
              if (i >= 0) app.removeFromQueue(i);
            }
          : null,
    );
  }

  Future<void> addAllToQueue(List<Track> tracks) async {
    final before = app.queue.length;
    for (final track in tracks) {
      await app.addToQueue(track);
    }
    final n = app.queue.length - before;
    _say(
      n == 0
          ? 'Ya estaban en la cola'
          : n == 1
          ? 'Añadida 1 canción a la cola'
          : 'Añadidas $n canciones a la cola',
    );
  }

  // shortcut: sin plugin de compartir nativo; portapapeles + aviso.
  Future<void> share(Track track) async {
    await Clipboard.setData(ClipboardData(text: shareText(track)));
    _say('Copiado para compartir');
  }

  Future<void> playNext(Track track) async {
    await app.playNext(track);
    _say('Sonará a continuación');
  }

  /// Añade a la Jam activa (lotes y límites los gestiona JamController).
  void addToJam(List<Track> tracks) {
    final jam = activeJam;
    if (jam == null || tracks.isEmpty) return;
    final ok = jam.addTracks(tracks);
    _say(
      !ok
          ? (jam.error ?? 'No se pudo añadir a la Jam.')
          : tracks.length == 1
          ? 'Añadida a la Jam'
          : 'Añadiendo ${tracks.length} canciones a la Jam…',
    );
  }

  Future<void> startJam(List<Track> tracks) {
    final scope = _scope;
    if (scope == null) return Future.value();
    return startJamFlow(context, scope.ensureJam(), seed: tracks);
  }

  /// Atajo de teclado «añadir a la Jam» sobre la fila enfocada.
  void jamShortcut(Track track) {
    if (activeJam == null) {
      _say('Inicia una Jam para añadir canciones.');
    } else {
      addToJam([track]);
    }
  }

  /// Amigos solo si hay ProviderScope y una sesión iniciada.
  FriendsService? get _friends {
    try {
      final f = ProviderScope.containerOf(
        context,
        listen: false,
      ).read(friendsServiceProvider);
      return f.signedIn ? f : null;
    } catch (_) {
      return null;
    }
  }

  /// Acciones de la canción como datos (el menú ⋯ y la tarjeta del mini las
  /// pintan a su manera). [TrackMenuItem.disabledReason] no nulo: desactivada.
  List<TrackMenuItem> menuItems(Track track) {
    final jam = activeJam;
    final blocked = jamBlockedReason;
    final liked = app.favoriteIds.contains(track.id);
    return [
      (
        label: 'Reproducir a continuación',
        icon: Icons.playlist_play,
        run: () => playNext(track),
        disabledReason: null,
      ),
      (
        label: 'Añadir a la cola',
        icon: Icons.queue_music,
        run: () => addToQueue(track),
        disabledReason: null,
      ),
      if (jam != null)
        (
          label: 'Añadir a la Jam',
          icon: Icons.groups_outlined,
          run: () => addToJam([track]),
          disabledReason: blocked,
        )
      else if (_scope != null)
        (
          label: 'Iniciar una Jam con esto',
          icon: Icons.groups_outlined,
          run: () => startJam([track]),
          disabledReason: null,
        ),
      (
        label: liked ? 'Quitar de favoritos' : 'Añadir a favoritos',
        icon: liked ? Icons.favorite : Icons.favorite_border,
        run: () => app.toggleFavorite(track),
        disabledReason: null,
      ),
      (
        label: 'Compartir',
        icon: Icons.share_outlined,
        run: () => share(track),
        disabledReason: null,
      ),
      if (_friends case final f? when !track.isLocal)
        (
          label: 'Enviar a un amigo',
          icon: Icons.send_outlined,
          run: () => showSendToFriendSheet(context, f, track),
          disabledReason: null,
        ),
      if (_scope?.addToPlaylist != null)
        (
          label: 'Añadir a una lista',
          icon: Icons.playlist_add,
          run: () => _scope!.addToPlaylist!(track),
          disabledReason: null,
        ),
    ];
  }

  List<PopupMenuEntry<VoidCallback>> entries(
    Track track, {
    List<TrackMenuExtra> extras = const [],
  }) => [
    for (final i in menuItems(track))
      PopupMenuItem<VoidCallback>(
        value: i.run,
        enabled: i.disabledReason == null,
        child: () {
          final row = Row(
            children: [
              Icon(i.icon, size: 18),
              const SizedBox(width: 12),
              Flexible(child: Text(i.label)),
            ],
          );
          return i.disabledReason == null
              ? row
              : Tooltip(message: i.disabledReason!, child: row);
        }(),
      ),
    for (final extra in extras)
      PopupMenuItem<VoidCallback>(value: extra.run, child: Text(extra.label)),
  ];

  Future<void> showAt(
    Offset position,
    Track track, {
    List<TrackMenuExtra> extras = const [],
  }) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final run = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: entries(track, extras: extras),
    );
    run?.call();
  }
}

/// Botones «+» (cola) y ⋯ (menú completo) de la fila de una canción.
class TrackMenuButton extends StatelessWidget {
  const TrackMenuButton({
    super.key,
    required this.controller,
    required this.track,
    this.extras = const [],
    this.quickAdd = false,
    this.quickAddVisible = true,
  });
  final AppController controller;
  final Track track;
  final List<TrackMenuExtra> extras;

  /// Muestra el «+» rápido (añadir a la cola) junto al ⋯.
  final bool quickAdd;

  /// Si es false el «+» se oculta (escritorio sin cursor/foco sobre la fila).
  final bool quickAddVisible;

  @override
  Widget build(BuildContext context) {
    final actions = TrackActions(context, controller);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (quickAdd)
          ExcludeFocus(
            excluding: !quickAddVisible,
            child: IgnorePointer(
              ignoring: !quickAddVisible,
              child: Opacity(
                opacity: quickAddVisible ? 1 : 0,
                child: IconButton(
                  tooltip: 'Añadir a la cola',
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  onPressed: () => actions.addToQueue(track),
                  icon: const Icon(Icons.add),
                ),
              ),
            ),
          ),
        PopupMenuButton<VoidCallback>(
          tooltip: 'Opciones de ${track.title}',
          onSelected: (run) => run(),
          itemBuilder: (_) => actions.entries(track, extras: extras),
        ),
      ],
    );
  }
}

/// Envuelve una fila: clic derecho (escritorio), pulsación larga (móvil),
/// atajos «añadir a la cola/Jam» con la fila enfocada y acciones de accesibilidad.
/// [builder] recibe `active` (cursor o foco sobre la fila, o pantalla táctil).
class TrackActionsRegion extends StatefulWidget {
  const TrackActionsRegion({
    super.key,
    required this.controller,
    required this.track,
    required this.builder,
    this.extras = const [],
  });
  final AppController controller;
  final Track track;
  final List<TrackMenuExtra> extras;
  final Widget Function(BuildContext context, bool active) builder;

  @override
  State<TrackActionsRegion> createState() => _TrackActionsRegionState();
}

class _TrackActionsRegionState extends State<TrackActionsRegion> {
  bool _hover = false;
  bool _focus = false;

  static bool get _touch => const {
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.fuchsia,
  }.contains(defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    final actions = TrackActions(context, widget.controller);
    final track = widget.track;
    return Actions(
      actions: {
        ShortcutIntent: _RowAction(
          onQueue: () => actions.addToQueue(track),
          onJam: () => actions.jamShortcut(track),
        ),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (value) => setState(() => _focus = value),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            onSecondaryTapUp: (d) =>
                actions.showAt(d.globalPosition, track, extras: widget.extras),
            onLongPressStart: (d) =>
                actions.showAt(d.globalPosition, track, extras: widget.extras),
            child: Semantics(
              customSemanticsActions: {
                const CustomSemanticsAction(label: 'Añadir a la cola'): () =>
                    actions.addToQueue(track),
                const CustomSemanticsAction(
                  label: 'Reproducir a continuación',
                ): () =>
                    actions.playNext(track),
              },
              child: widget.builder(context, _hover || _focus || _touch),
            ),
          ),
        ),
      ),
    );
  }
}

/// Atiende solo «añadir a la cola/Jam»; el resto de atajos sube al shell.
class _RowAction extends Action<ShortcutIntent> {
  _RowAction({required this.onQueue, required this.onJam});
  final VoidCallback onQueue;
  final VoidCallback onJam;

  @override
  bool isEnabled(ShortcutIntent intent) =>
      intent.id == ShortcutId.addToQueue || intent.id == ShortcutId.addToJam;

  @override
  Object? invoke(ShortcutIntent intent) {
    if (intent.id == ShortcutId.addToQueue) {
      onQueue();
    } else {
      onJam();
    }
    return null;
  }
}

/// «Añadir todo a la cola» / «Añadir todo a la Jam» para álbumes, playlists
/// y canciones top de un artista.
class TrackBatchButtons extends StatelessWidget {
  const TrackBatchButtons({
    super.key,
    required this.controller,
    required this.tracks,
  });
  final AppController controller;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final actions = TrackActions(context, controller);
    final jam = actions.activeJam;
    final blocked = actions.jamBlockedReason;
    final hasScope = TrackActionsScope.maybeOf(context) != null;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        OutlinedButton.icon(
          onPressed: tracks.isEmpty
              ? null
              : () => actions.addAllToQueue(tracks),
          icon: const Icon(Icons.queue_music),
          label: const Text('Añadir todo a la cola'),
        ),
        if (jam != null || hasScope)
          Tooltip(
            message: blocked ?? '',
            child: OutlinedButton.icon(
              onPressed: tracks.isEmpty || blocked != null
                  ? null
                  : () => jam != null
                        ? actions.addToJam(tracks)
                        : actions.startJam(tracks),
              icon: const Icon(Icons.groups_outlined),
              label: Text(
                jam != null
                    ? 'Añadir todo a la Jam'
                    : 'Iniciar una Jam con esto',
              ),
            ),
          ),
      ],
    );
  }
}
