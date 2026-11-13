/// Dueño: tema Atelier («Papel y tinta»).
///
/// Posee la pintura de la cola completa (QueuePanel) y el panel derecho de
/// 352 px con pestañas de texto (Cola / Ahora suena / Letras), la tarjeta Jam y
/// el temporizador de sueño.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../jam/jam_controller.dart';
import '../../theme/atelier_theme.dart';
import '../jam/jam_widgets.dart';
import '../shell/atelier_widgets.dart';
import '../studio/studio_components.dart';
import 'right_panel_theme.dart';

/// Atelier («Papel y tinta»): implementación de [RightPanelTheme].
const RightPanelTheme atelierRightPanel = AtelierRightPanelTheme();

class AtelierRightPanelTheme extends RightPanelTheme {
  const AtelierRightPanelTheme();

  @override
  Widget queueCard(Widget child) => child;

  @override
  String get nowPlayingLabel => 'SUENA AHORA';

  @override
  TextStyle? nowPlayingStyle(BuildContext context) =>
      AtelierTokens.of(context).mono(size: 11);

  @override
  TextStyle artistStyle(BuildContext context) {
    final t = AtelierTokens.of(context);
    return t.serif(18, italic: true, color: t.ink2);
  }

  @override
  TextStyle? get tileTitleStyle => const TextStyle(
    fontFamily: 'Newsreader',
    fontSize: 17,
    fontWeight: FontWeight.w400,
  );

  @override
  TextStyle? get tileSubtitleStyle => const TextStyle(fontSize: 12);

  @override
  double get currentArtRadius => 2;

  @override
  ButtonStyle? get playButtonStyle => null;

  @override
  ShapeBorder? get tileShape => null;

  @override
  double get tileArtRadius => 2;

  @override
  Widget asidePanel(Widget child) => StudioPanel(child: child);

  @override
  String get asideTitleFont => 'Newsreader';

  @override
  FontWeight get asideTitleWeight => FontWeight.w400;

  @override
  FontWeight? get asideQueueTitleWeight => null;

  @override
  double get asideSectionGap => 24;
}

/// Panel derecho del escritorio (352 px).
class AtelierAside extends StatefulWidget {
  const AtelierAside({
    super.key,
    required this.controller,
    required this.onJam,
    required this.onQueue,
    required this.onLyrics,
    this.jam,
    this.onStartJam,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onJam, onQueue, onLyrics;
  final VoidCallback? onStartJam;

  @override
  State<AtelierAside> createState() => _AtelierAsideState();
}

class _AtelierAsideState extends State<AtelierAside> {
  int _tab = 0;
  static const _tabs = ['Cola', 'Ahora suena', 'Letras'];

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, ?widget.jam]),
      builder: (context, _) => Container(
        width: 352,
        color: t.panel,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.rule)),
                ),
                child: Wrap(
                  spacing: 20,
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Semantics(
                        button: true,
                        selected: _tab == i,
                        child: InkWell(
                          onTap: () => setState(() => _tab = i),
                          child: IntrinsicWidth(
                            child: Container(
                              constraints: const BoxConstraints(minHeight: 40),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: _tab == i
                                        ? t.accent
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                              ),
                              child: Text(
                                _tabs[i],
                                style: t.ui(
                                  14,
                                  weight: _tab == i
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: _tab == i ? t.accentText : t.ink2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: _body(context, t)),
            _JamCard(
              jam: widget.jam,
              onJam: widget.onJam,
              onStartJam: widget.onStartJam,
            ),
            _SleepCard(controller: widget.controller),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AtelierTokens t) => switch (_tab) {
    1 => _NowPlaying(controller: widget.controller),
    2 => _LyricsTab(controller: widget.controller, onLyrics: widget.onLyrics),
    _ => _QueueTab(
      controller: widget.controller,
      jam: widget.jam,
      onJam: widget.onJam,
    ),
  };
}

class _QueueTab extends StatelessWidget {
  const _QueueTab({
    required this.controller,
    required this.jam,
    required this.onJam,
  });
  final AppController controller;
  final JamController? jam;
  final VoidCallback onJam;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final c = controller;
    final session = jam?.service;
    final shared = session?.connected == true
        ? session!.queue
              .where((e) => e.id != jam!.bridge.currentEntryId)
              .toList()
        : null;
    final upcoming = c.queue.skip(c.queueIndex + 1).toList();
    final total = upcoming.fold(Duration.zero, (sum, e) => sum + e.duration);
    final current = c.nowTrack;
    final count = shared?.length ?? upcoming.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      children: [
        Text('SUENA AHORA', style: t.mono(size: 10.5)),
        const SizedBox(height: 8),
        if (current == null)
          Text('Nada sonando', style: t.serif(18, color: t.ink2))
        else
          Row(
            children: [
              AtelierCover(track: current, size: 48, shadow: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.serif(18, color: t.accentText),
                    ),
                    Text(
                      current.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.ui(12.5, color: t.ink2),
                    ),
                  ],
                ),
              ),
              Icon(
                c.audio.isPlaying
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                size: 18,
                color: t.accentText,
              ),
            ],
          ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'SIGUIENTE · $count ${count == 1 ? 'PISTA' : 'PISTAS'}',
                style: t.mono(size: 10.5),
              ),
            ),
            if (shared == null && total > Duration.zero)
              Text('${total.inMinutes} MIN', style: t.mono(size: 10.5)),
          ],
        ),
        const SizedBox(height: 6),
        if (count == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('La cola está vacía', style: t.ui(13, color: t.ink2)),
          ),
        if (shared != null)
          for (final (i, entry) in shared.indexed)
            _Row(
              number: i + 1,
              track: Track(
                id: entry.track.key,
                title: entry.track.title,
                artist: entry.track.artist,
                artworkUrl: entry.track.artworkUrl,
                duration: Duration(milliseconds: entry.track.durationMs),
              ),
              subtitle: 'Por ${session!.participantName(entry.addedBy)}',
              onTap: onJam,
            )
        else
          for (final (i, track) in upcoming.indexed.take(40))
            _Row(
              number: c.queueIndex + 2 + i,
              track: track,
              subtitle: track.artist,
              onTap: () => c.playQueueAt(c.queueIndex + 1 + i),
            ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.number,
    required this.track,
    required this.subtitle,
    required this.onTap,
  });
  final int number;
  final Track track;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text(
                number.toString().padLeft(2, '0'),
                style: t.mono(size: 11, color: t.accentText),
              ),
            ),
            AtelierCover(track: track, size: 40, shadow: false),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.serif(16),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.ui(12, color: t.ink2),
                  ),
                ],
              ),
            ),
            if (track.duration > Duration.zero) ...[
              const SizedBox(width: 8),
              Text(atelierClock(track.duration), style: t.mono(size: 11)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final track = controller.nowTrack;
    if (track == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Nada sonando', style: t.serif(18, color: t.ink2)),
      );
    }
    final format = atelierFormat(track);
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      children: [
        AtelierCover(track: track, size: 240),
        const SizedBox(height: 16),
        Text(track.title, style: t.serif(26)),
        const SizedBox(height: 4),
        Text(track.artist, style: t.serif(16, italic: true, color: t.ink2)),
        const SizedBox(height: 12),
        if (track.album?.trim().isNotEmpty == true)
          Text(
            'ÁLBUM · ${track.album!.toUpperCase()}',
            style: t.mono(size: 10.5),
          ),
        if (format != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: AtelierFormatChip(format),
          ),
        ],
      ],
    );
  }
}

class _LyricsTab extends StatelessWidget {
  const _LyricsTab({required this.controller, required this.onLyrics});
  final AppController controller;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final has = controller.nowTrack != null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            has
                ? 'Las letras sincronizadas se leen en el modo letra, a pantalla completa.'
                : 'Elige una canción para ver su letra.',
            style: t.serif(18, italic: true, color: t.ink2, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (has)
            OutlinedButton.icon(
              onPressed: onLyrics,
              icon: const Icon(Icons.lyrics_outlined, size: 18),
              label: const Text('Abrir letras'),
            ),
        ],
      ),
    );
  }
}

class _JamCard extends StatelessWidget {
  const _JamCard({
    required this.jam,
    required this.onJam,
    required this.onStartJam,
  });
  final JamController? jam;
  final VoidCallback onJam;
  final VoidCallback? onStartJam;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final session = jam?.service;
    final connected = session?.connected == true;
    final names = connected
        ? [
            for (final p in session!.participants)
              if (p.connected) p.name,
          ]
        : const <String>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Semantics(
        button: true,
        label: connected ? 'Abrir la Jam' : 'Iniciar una Jam',
        excludeSemantics: true,
        child: Tooltip(
          message: connected ? 'Abrir la Jam' : 'Iniciar una Jam',
          child: InkWell(
            onTap: connected ? onJam : (onStartJam ?? onJam),
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: t.rule),
                color: t.paper,
              ),
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, size: 22, color: t.ink2),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          connected
                              ? 'Jam · ${names.length} ${names.length == 1 ? 'oyente' : 'oyentes'}'
                              : 'Iniciar una Jam',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.ui(13.5, weight: FontWeight.w600),
                        ),
                        Text(
                          connected
                              ? '${jam!.roleLabel} · ${jam!.modeLabel}'
                              : 'Escuchen juntos con un QR o un código',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.ui(12, color: t.ink2),
                        ),
                      ],
                    ),
                  ),
                  if (connected) JamAvatarStack(names: names, size: 26, max: 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final t = AtelierTokens.of(context);
    final label = atelierSleepLabel(controller);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: InkWell(
        onTap: () => showAtelierSleepSheet(context, controller),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: t.rule),
            color: t.paper,
          ),
          child: Row(
            children: [
              Icon(Icons.bedtime_outlined, size: 22, color: t.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Temporizador de sueño',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.ui(13.5, weight: FontWeight.w600),
                    ),
                    Text(
                      label == null ? 'Desactivado' : 'Se detiene en $label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.ui(12, color: t.ink2),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: label == null ? t.panel2 : t.ink,
                child: Text(
                  label == null ? 'OFF' : 'ON',
                  style: t.mono(
                    size: 10.5,
                    color: label == null ? t.ink2 : t.paper,
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
