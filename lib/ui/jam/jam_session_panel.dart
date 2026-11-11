import 'package:flutter/material.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../jam/jam_models.dart';
import '../../jam/jam_service.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/modern_theme.dart';
import '../../theme/modern_widgets.dart';
import '../../theme/slush_theme.dart';
import '../../theme/slush_widgets.dart';
import '../artwork.dart';
import '../studio/studio_components.dart';
import '../undo_snackbar.dart';
import 'jam_add_sheet.dart';
import 'jam_flows.dart';
import 'jam_widgets.dart';

Track jamTrackAsTrack(JamTrack t) => Track(
  id: t.key,
  title: t.title,
  artist: t.artist,
  artworkUrl: t.artworkUrl,
  duration: Duration(milliseconds: t.durationMs),
);

/// Panel de la Jam. Se usa embebido en la página, en la hoja móvil y en el
/// panel lateral de escritorio.
class JamSessionPanel extends StatefulWidget {
  const JamSessionPanel({super.key, required this.controller, this.scroll});
  final JamController controller;
  final ScrollController? scroll;
  @override
  State<JamSessionPanel> createState() => _JamSessionPanelState();
}

class _JamSessionPanelState extends State<JamSessionPanel> {
  double? _seekPreview;
  JamController get c => widget.controller;
  JamService get s => c.service;

  Future<void> _do(Future<void> Function() action) async {
    try {
      await action();
    } on JamException catch (failure) {
      _say(failure.message);
    } catch (_) {
      _say('No se pudo completar la acción. Inténtalo de nuevo.');
    }
  }

  void _say(String text) {
    if (mounted) {
      showUndoSnackBar(ScaffoldMessenger.maybeOf(context), Text(text));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final shown = _shownQueue();
      // La cola es un sliver: solo se construyen las filas visibles y, al
      // reordenar, el arrastre se desplaza con el scroll de toda la hoja.
      return CustomScrollView(
        controller: widget.scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _header(context),
                const SizedBox(height: 16),
                _nowPlaying(context),
                const SizedBox(height: 20),
                _queueHead(context, shown),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: c.canReorder
                ? SliverReorderableList(
                    itemCount: shown.length,
                    onReorder: (from, to) {
                      if (to > from) to--;
                      c.reorder(shown[from], s.queue.indexOf(shown[to]));
                    },
                    itemBuilder: (context, i) =>
                        _entry(context, shown[i], i, shown),
                  )
                : SliverList.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) =>
                        _entry(context, shown[i], i, shown),
                  ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _people(context),
                if (s.isHost) ...[
                  const SizedBox(height: 20),
                  _hostSettings(context),
                ],
                const SizedBox(height: 20),
                _leave(context),
              ]),
            ),
          ),
        ],
      );
    },
  );

  Widget _title(BuildContext context, String text, {Widget? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: isSlush(context)
                    ? Theme.of(context).textTheme.titleLarge
                    : isBrasa(context)
                    ? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)
                    : isModern(context)
                    ? const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.18,
                      )
                    : const TextStyle(
                        fontFamily: 'Newsreader',
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
              ),
            ),
            ?trailing,
          ],
        ),
      );

  Widget _header(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final invite = s.invite;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: isBrasa(context)
                    ? Text(
                        s.connected ? 'Jam activa' : 'Sin conexión con la Jam',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : isModern(context)
                    ? ModernHeadline(
                        before: s.connected
                            ? 'Jam '
                            : 'Sin conexión con la Jam',
                        emphasis: s.connected ? 'activa' : '',
                        size: 24,
                      )
                    : Text(
                        s.connected ? 'Jam activa' : 'Sin conexión con la Jam',
                        style: const TextStyle(
                          fontFamily: 'Newsreader',
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StudioStamp('${c.peopleCount} EN LA JAM', filled: true),
              if (isModern(context)) ...[
                ModernBadge(c.roleLabel),
                ModernBadge(
                  c.modeLabel,
                  tone: c.listeningTogether
                      ? ModernTone.mint
                      : ModernTone.neutral,
                ),
                if (invite != null && invite.isRemote)
                  isSlush(context)
                      ? _CodeBadge(invite.code)
                      : ModernBadge(invite.code),
              ] else ...[
                Chip(
                  avatar: const Icon(Icons.badge_outlined, size: 16),
                  label: Text(c.roleLabel),
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  avatar: Icon(
                    c.listeningTogether
                        ? Icons.headphones_outlined
                        : Icons.queue_music,
                    size: 16,
                  ),
                  label: Text(c.modeLabel),
                  visualDensity: VisualDensity.compact,
                ),
                if (invite != null && invite.isRemote)
                  Chip(
                    label: Text(
                      invite.code,
                      style: isBrasa(context)
                          ? const TextStyle(letterSpacing: 1)
                          : const TextStyle(
                              fontFamily: 'monospace',
                              letterSpacing: 2,
                            ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: s.connected
                    ? () => showJamInviteSheet(context, c)
                    : null,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Invitar'),
              ),
              JamInviteFriendButton(jam: c),
              OutlinedButton.icon(
                onPressed: c.canAdd ? () => showJamAddSheet(context, c) : null,
                icon: const Icon(Icons.add),
                label: const Text('Añadir música'),
              ),
              if (!s.connected)
                OutlinedButton.icon(
                  onPressed: c.busy ? null : c.reconnect,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reconectar'),
                ),
            ],
          ),
          if (s.isHost) ...[
            const SizedBox(height: 12),
            SegmentedButton<JamMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: JamMode.synchronized,
                  icon: Icon(Icons.headphones_outlined),
                  label: Text('Escuchando'),
                ),
                ButtonSegment(
                  value: JamMode.queueOnly,
                  icon: Icon(Icons.queue_music),
                  label: Text('Solo añadir'),
                ),
              ],
              selected: {s.mode},
              onSelectionChanged: c.busy
                  ? null
                  : (value) => c.setMode(value.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                c.listeningTogether
                    ? 'Todos oyen lo mismo a la vez, cada uno con sus fuentes.'
                    : 'Cada persona escucha lo suyo; la cola se comparte.',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ),
          ],
          if (!s.isHost && c.listeningTogether)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Escuchar en este dispositivo'),
              subtitle: const Text(
                'Aurora resolverá cada canción con tus propias fuentes de audio.',
              ),
              value: c.bridge.enabled,
              onChanged: c.busy || !s.connected ? null : c.setListening,
            ),
          if (c.bridge.warning != null) ...[
            const SizedBox(height: 8),
            jamNotice(
              context,
              c.bridge.warning!,
              Icons.headphones_outlined,
              action: TextButton(
                onPressed: c.busy ? null : c.bridge.retry,
                child: const Text('Reintentar audio'),
              ),
            ),
          ],
          if (c.error != null) ...[
            const SizedBox(height: 8),
            jamNotice(context, c.error!, Icons.info_outline),
          ],
        ],
      ),
    );
  }

  JamQueueEntry? get _playing =>
      s.queue.where((e) => e.id == s.playback?.entryId).firstOrNull;

  Widget _nowPlaying(BuildContext context) {
    final entry = _playing;
    final audio = c.app.audio;
    final duration = audio.duration.inMilliseconds;
    final position = (_seekPreview ?? audio.position.inMilliseconds.toDouble())
        .clamp(0.0, duration > 0 ? duration.toDouble() : 1.0);
    final lock = 'Lo controla ${c.hostName}';
    final playing = s.playback?.isPlaying ?? audio.isPlaying;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Sonando ahora'),
        if (entry == null)
          jamNotice(
            context,
            s.isHost
                ? 'Nada suena todavía. Añade canciones y pulsa reproducir en una de la cola.'
                : 'Esperando a que ${c.hostName} ponga algo. Mientras, añade tus canciones.',
            Icons.graphic_eq,
          )
        else
          StudioPanel(
            recessed: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Artwork(
                      track: jamTrackAsTrack(entry.track),
                      artworkContext: ArtworkContext.thumbnailDetail,
                      radius: 6,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.track.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            entry.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          _addedBy(entry),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      style: isSlush(context)
                          ? IconButton.styleFrom(
                              backgroundColor: Slush.mint,
                              foregroundColor: Slush.ink,
                              disabledBackgroundColor:
                                  context.slush.disabledFill,
                              disabledForegroundColor:
                                  context.slush.disabledText,
                            )
                          : isModern(context)
                          ? IconButton.styleFrom(
                              backgroundColor: Tracky.mint,
                              foregroundColor: Tracky.navy,
                              disabledBackgroundColor: Tracky.stone,
                            )
                          : null,
                      tooltip: c.canPause
                          ? (playing ? 'Pausar la Jam' : 'Reanudar la Jam')
                          : lock,
                      onPressed: c.busy || !c.canPause
                          ? null
                          : () => _do(() async {
                              if (s.isHost) {
                                await c.togglePlayback();
                              } else {
                                s.requestPlayPause(!playing);
                              }
                            }),
                      icon: Icon(
                        playing ? Icons.pause_circle : Icons.play_circle,
                        size: 36,
                      ),
                    ),
                    IconButton(
                      tooltip: c.canSkip
                          ? 'Siguiente'
                          : s.rules.votes
                          ? 'Votar para saltar'
                          : lock,
                      onPressed: c.busy || (!c.canSkip && !s.rules.votes)
                          ? null
                          : () => _do(() async {
                              if (c.canSkip) {
                                await c.next();
                              } else {
                                s.voteSkip();
                              }
                            }),
                      icon: Icon(
                        c.canSkip
                            ? Icons.skip_next
                            : Icons.how_to_vote_outlined,
                      ),
                    ),
                    const Spacer(),
                    if (duration > 0)
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${_duration(position.toInt())} / ${_duration(duration)}',
                            style: isSlush(context)
                                ? jamCodeStyle(12, color: context.slush.ink2)
                                : TextStyle(
                                    fontFamily: isBrasa(context)
                                        ? null
                                        : 'monospace',
                                    fontSize: 11,
                                  ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (s.isHost && duration > 0)
                  Slider(
                    value: position,
                    max: duration.toDouble(),
                    onChanged: c.busy
                        ? null
                        : (v) => setState(() => _seekPreview = v),
                    onChangeEnd: (v) async {
                      await c.seek(Duration(milliseconds: v.toInt()));
                      if (mounted) setState(() => _seekPreview = null);
                    },
                  ),
                if (c.bridge.loading) const LinearProgressIndicator(),
              ],
            ),
          ),
      ],
    );
  }

  Widget _addedBy(JamQueueEntry e) {
    final suggested = e.suggestedFor != null;
    final who = s.participantName(suggested ? e.suggestedFor! : e.addedBy);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        JamAvatar(
          name: who,
          size: 20,
          image: c.avatarOf(suggested ? e.suggestedFor! : e.addedBy),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            suggested ? 'Sugerida para $who' : 'Añadida por $who',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: isSlush(context) ? 12 : 11),
          ),
        ),
        if (suggested) ...[
          const SizedBox(width: 4),
          const Icon(Icons.auto_awesome, size: 12),
        ],
      ],
    );
  }

  List<JamQueueEntry> _shownQueue() {
    final playingId = s.playback?.entryId;
    return [
      for (final e in s.queue)
        if (e.id != playingId) e,
    ];
  }

  Widget _queueHead(BuildContext context, List<JamQueueEntry> shown) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(
          context,
          'Cola · ${shown.length}',
          trailing: TextButton.icon(
            onPressed: c.canAdd ? () => showJamAddSheet(context, c) : null,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Añadir'),
          ),
        ),
        if (shown.isEmpty)
          jamNotice(
            context,
            s.rules.autoplay
                ? 'La cola está vacía. Con el autoplay, Aurora añadirá canciones que le gusten al grupo; también puedes añadir las tuyas.'
                : 'La Jam empieza en silencio. Pulsa «Añadir» para buscar canciones o usar una playlist; solo suena lo que añade la gente.',
            Icons.queue_music,
          ),
      ],
    );
  }

  Widget _entry(
    BuildContext context,
    JamQueueEntry e,
    int i,
    List<JamQueueEntry> shown,
  ) {
    final me = s.participantId;
    final pending = e.status == JamEntryStatus.pending;
    final mine = e.up.contains(me);
    return Padding(
      key: ValueKey(e.id),
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: isSlush(context)
            ? RoundedRectangleBorder(
                side: context.slush.borderSoft,
                borderRadius: BorderRadius.circular(SlushRadius.r16),
              )
            : null,
        borderRadius: isSlush(context)
            ? null
            : isBrasa(context)
            ? BorderRadius.circular(6)
            : isModern(context)
            ? BorderRadius.circular(8)
            : null,
        clipBehavior: isModern(context) || isBrasa(context)
            ? Clip.antiAlias
            : Clip.none,
        child: Row(
          children: [
            if (c.canReorder)
              ReorderableDragStartListener(
                index: i,
                child: const Tooltip(
                  message: 'Arrastra para reordenar',
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(Icons.drag_indicator, size: 20),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Artwork(
                track: jamTrackAsTrack(e.track),
                artworkContext: ArtworkContext.thumbnail,
                radius: isSlush(context) ? SlushRadius.r8 : 4,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isModern(context) || isBrasa(context)
                        ? const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          )
                        : const TextStyle(
                            fontFamily: 'Newsreader',
                            fontSize: 15,
                          ),
                  ),
                  Text(
                    e.track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: isSlush(context) ? 12 : 11),
                  ),
                  _addedBy(e),
                  if (pending) const StudioStamp('ESPERA APROBACIÓN DEL HOST'),
                ],
              ),
            ),
            if (pending && c.isStaff) ...[
              IconButton(
                tooltip: 'Aprobar',
                onPressed: () => s.approve(e.id, accept: true),
                icon: const Icon(Icons.check_circle_outline),
              ),
              IconButton(
                tooltip: 'Rechazar',
                onPressed: () => s.approve(e.id, accept: false),
                icon: const Icon(Icons.cancel_outlined),
              ),
            ] else ...[
              if (s.rules.votes && !pending)
                TextButton.icon(
                  onPressed: s.connected
                      ? () => _do(() async => s.vote(e.id, mine ? 0 : 1))
                      : null,
                  icon: Icon(
                    mine ? Icons.thumb_up : Icons.thumb_up_outlined,
                    size: 16,
                  ),
                  label: Text('${e.up.length}'),
                ),
              PopupMenuButton<String>(
                tooltip: 'Acciones de ${e.track.title}',
                enabled: s.connected,
                onSelected: (action) {
                  switch (action) {
                    case 'play':
                      c.play(e);
                    case 'up':
                      c.reorder(e, s.queue.indexOf(shown[i - 1]));
                    case 'down':
                      c.reorder(e, s.queue.indexOf(shown[i + 1]));
                    case 'remove':
                      c.remove(e);
                  }
                },
                itemBuilder: (_) => [
                  if (s.isHost && !pending)
                    const PopupMenuItem(
                      value: 'play',
                      child: Text('Reproducir ahora'),
                    ),
                  if (c.canReorder && i > 0)
                    const PopupMenuItem(value: 'up', child: Text('Subir')),
                  if (c.canReorder && i + 1 < shown.length)
                    const PopupMenuItem(value: 'down', child: Text('Bajar')),
                  if (c.canRemove || e.addedBy == me)
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Quitar de la cola'),
                    ),
                  if (!s.isHost && !c.canReorder && !c.canRemove)
                    PopupMenuItem(
                      enabled: false,
                      child: Text('Lo controla ${c.hostName}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _people(BuildContext context) {
    final people = [...s.participants]
      ..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        return byRole != 0 ? byRole : a.name.compareTo(b.name);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Participantes · ${c.peopleCount}'),
        _peopleCard(context, [
          for (final p in people)
            if (isSlush(context))
              _slushPerson(context, p)
            else
              ListTile(
                contentPadding: isModern(context)
                    ? const EdgeInsets.symmetric(horizontal: 8)
                    : EdgeInsets.zero,
                minVerticalPadding: 4,
                leading: JamAvatar(
                  name: p.name,
                  size: 36,
                  image: c.avatarOf(p.id),
                ),
                title: Text(
                  p.id == s.participantId ? '${p.name} (tú)' : p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    jamRoleLabel(p.role),
                    if (!p.connected) 'Desconectado',
                    if (p.muted) 'Silenciado',
                  ].join(' · '),
                ),
                trailing: s.isHost && p.id != 'host' && p.id != s.participantId
                    ? _personMenu(p)
                    : null,
              ),
        ]),
      ],
    );
  }

  /// Slush: avatar 44, nombre en una línea y estado en píldoras.
  Widget _slushPerson(BuildContext context, JamParticipant p) {
    final pal = context.slush;
    final name = p.id == s.participantId ? '${p.name} (tú)' : p.name;
    final menu = s.isHost && p.id != 'host' && p.id != s.participantId;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Row(
        children: [
          JamAvatar(name: p.name, size: 44, image: c.avatarOf(p.id)),
          const SizedBox(width: SlushSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: SlushSpacing.s4),
                Wrap(
                  spacing: SlushSpacing.s8,
                  runSpacing: SlushSpacing.s4,
                  children: [
                    SlushPill(
                      jamRoleLabel(p.role),
                      color: switch (p.role) {
                        JamRole.host => Slush.yellow,
                        JamRole.coHost => Slush.lilac,
                        JamRole.guest => Slush.mint,
                      },
                    ),
                    if (!p.connected)
                      SlushPill('Desconectado', color: pal.raised),
                    if (p.muted)
                      const SlushPill('Silenciado', color: Slush.orange),
                  ],
                ),
              ],
            ),
          ),
          if (menu) _personMenu(p),
        ],
      ),
    );
  }

  /// Modern: participantes en una tarjeta con filas de radio 8; Atelier, lista plana.
  Widget _peopleCard(BuildContext context, List<Widget> rows) {
    if (!isModern(context)) return Column(children: rows);
    return ModernCard(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: row,
            ),
        ],
      ),
    );
  }

  Widget _personMenu(JamParticipant p) => PopupMenuButton<String>(
    tooltip: 'Acciones para ${p.name}',
    onSelected: (action) => _do(() async {
      switch (action) {
        case 'mute':
          await s.setMuted(p.id, !p.muted);
        case 'cohost':
          await s.setCoHost(p.id, p.role != JamRole.coHost);
        case 'perms':
          await _permissions(p);
        case 'kick':
          await s.kick(p.id);
        case 'ban':
          if (await _confirm(
            'Bloquear a ${p.name}',
            'No podrá volver a entrar a esta Jam.',
            'Bloquear',
          )) {
            await s.kick(p.id, ban: true);
          }
      }
    }),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'mute',
        child: Text(p.muted ? 'Quitar silencio' : 'Silenciar'),
      ),
      PopupMenuItem(
        value: 'cohost',
        child: Text(
          p.role == JamRole.coHost ? 'Quitar co-host' : 'Hacer co-host',
        ),
      ),
      if (p.role == JamRole.guest)
        const PopupMenuItem(value: 'perms', child: Text('Permisos…')),
      const PopupMenuItem(value: 'kick', child: Text('Quitar de la Jam')),
      const PopupMenuItem(value: 'ban', child: Text('Bloquear')),
    ],
  );

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _permissions(JamParticipant person) async {
    var permissions = person.permissions;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget tile(
            String label,
            bool value,
            JamPermissions Function(bool) change,
          ) => CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(label),
            value: value,
            onChanged: (v) => setDialogState(() => permissions = change(v!)),
          );
          return AlertDialog(
            title: Text('Permisos de ${person.name}'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tile(
                    'Añadir canciones',
                    permissions.add,
                    (v) => permissions.copyWith(add: v),
                  ),
                  tile(
                    'Pausar y reanudar',
                    permissions.pause,
                    (v) => permissions.copyWith(pause: v),
                  ),
                  tile(
                    'Saltar canciones',
                    permissions.skip,
                    (v) => permissions.copyWith(skip: v),
                  ),
                  tile(
                    'Reordenar la cola',
                    permissions.reorder,
                    (v) => permissions.copyWith(reorder: v),
                  ),
                  tile(
                    'Quitar canciones',
                    permissions.remove,
                    (v) => permissions.copyWith(remove: v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  c.setPermissions(person.id, permissions);
                  Navigator.pop(context);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// «Permitir que otros cambien lo que suena»: pausa y saltos de los invitados.
  bool get _guestsControl {
    final guests = s.participants.where((p) => p.role == JamRole.guest);
    return guests.isNotEmpty &&
        guests.every((p) => p.permissions.pause && p.permissions.skip);
  }

  Widget _hostSettings(BuildContext context) {
    JamRules r = s.rules;
    Widget sw(
      String title,
      String sub,
      bool value,
      Future<void> Function(bool) set,
    ) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(sub, style: const TextStyle(fontSize: 12)),
      value: value,
      onChanged: (v) => _do(() => set(v)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context, 'Ajustes de la Jam'),
        sw(
          'Permitir que otros cambien lo que suena',
          'Los invitados podrán pausar y saltar. Si no, solo añaden canciones.',
          _guestsControl,
          (v) async {
            for (final p in s.participants.where(
              (p) => p.role == JamRole.guest,
            )) {
              c.setPermissions(p.id, p.permissions.copyWith(pause: v, skip: v));
            }
          },
        ),
        sw(
          'Aprobar sugerencias',
          'Lo que añadan los invitados espera tu visto bueno.',
          r.approve,
          (v) => s.setRules(r.copyWith(approve: v)),
        ),
        sw(
          'Votos',
          'Pueden votar canciones y proponer saltar la que suena.',
          r.votes,
          (v) => s.setRules(r.copyWith(votes: v)),
        ),
        sw(
          'Autoplay de la Jam',
          'Apagado: solo suena lo que añade la gente. Encendido: si la cola se queda corta, Aurora añade música que le guste al grupo.',
          r.autoplay,
          (v) => s.setRules(r.copyWith(autoplay: v)),
        ),
        sw(
          'Aceptar nuevas personas',
          'Apágalo para cerrar el acceso sin terminar la Jam.',
          r.open,
          (v) => s.setRules(r.copyWith(open: v)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Límite de personas: ${r.maxGuests + 1}'),
          subtitle: Slider(
            min: 1,
            max: 15,
            divisions: 14,
            label: '${r.maxGuests + 1}',
            semanticFormatterCallback: (v) => '${v.round() + 1} personas',
            value: r.maxGuests.toDouble(),
            onChanged: (v) => s.setRules(r.copyWith(maxGuests: v.round())),
          ),
        ),
        if (s.isRemote)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _do(() async {
                if (await _confirm(
                  'Cambiar el código',
                  'El código y el QR anteriores dejarán de funcionar.',
                  'Cambiar código',
                )) {
                  await s.rotateCode();
                }
              }),
              icon: const Icon(Icons.autorenew),
              label: const Text('Cambiar código'),
            ),
          ),
      ],
    );
  }

  Widget _leave(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.error,
      ),
      onPressed: c.busy
          ? null
          : () async {
              final host = s.isHost;
              if (!host ||
                  await _confirm(
                    'Terminar la Jam',
                    'Se cerrará para todos. Si prefieres que siga, otra persona recibirá el mando.',
                    'Terminar',
                  )) {
                await c.leave();
                if (context.mounted) Navigator.maybeOf(context)?.maybePop();
              }
            },
      icon: const Icon(Icons.logout),
      label: Text(s.isHost ? 'Terminar la Jam' : 'Salir de la Jam'),
    ),
  );

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// Código de invitación (Slush): píldora de control con cifras tabulares.
class _CodeBadge extends StatelessWidget {
  const _CodeBadge(this.code);
  final String code;
  @override
  Widget build(BuildContext context) {
    final p = context.slush;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: p.paper,
        shape: StadiumBorder(side: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: SelectableText(
          code,
          style: jamCodeStyle(14, color: p.ink, spacing: 2),
        ),
      ),
    );
  }
}

Widget jamNotice(
  BuildContext context,
  String message,
  IconData icon, {
  Widget? action,
}) {
  final modern = isModern(context);
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isSlush(context)
          ? Slush.yellow
          : modern
          ? Tracky.butter
          : Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(
        isBrasa(context)
            ? 6
            : isSlush(context)
            ? SlushRadius.r16
            : modern
            ? 16
            : 12,
      ),
      border: isSlush(context)
          ? Border.fromBorderSide(context.slush.borderSoft)
          : null,
    ),
    child: DefaultTextStyle.merge(
      style: TextStyle(
        color: isSlush(context)
            ? Slush.ink
            : modern
            ? Tracky.navy
            : null,
      ),
      child: IconTheme.merge(
        data: IconThemeData(
          color: isSlush(context)
              ? Slush.ink
              : modern
              ? Tracky.navy
              : null,
        ),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(icon, size: 22),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(message),
            ),
            ?action,
          ],
        ),
      ),
    ),
  );
}
