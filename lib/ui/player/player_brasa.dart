/// Dueño: tema Brasa.
///
/// Posee el Modo Vinilo / reproductor completo (sección 4): maquetación y pintura del disco.
/// Escritorio: columna central con estado, portada 380 con resplandor, título
/// serif, chips y vista previa de letra, más una barra flotante de transporte.
/// Móvil: portada 268, letra de 2 líneas, chips, filamento, transporte y hoja
/// de cola. Las vistas vinilo y casete siguen disponibles (portada por defecto).
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../theme/brasa_theme.dart';
import '../../theme/brasa_widgets.dart';
import '../artwork.dart';
import '../follow_widgets.dart';
import '../mini_player/song_card.dart';
import '../right_panel/brasa_aside.dart';
import 'brasa_player_parts.dart';
import 'player_theme.dart';

/// Brasa: implementación de [PlayerTheme].
const PlayerTheme brasaPlayer = BrasaPlayerTheme();

class BrasaPlayerTheme extends PlayerTheme {
  const BrasaPlayerTheme();

  @override
  double get compactBreakpoint => 760;

  @override
  bool get rebuildsOnAudio => false;

  @override
  Widget buildLayout(
    BuildContext context,
    PlayerScope scope,
    Track? track,
    bool compact,
    BoxConstraints constraints,
  ) => compact
      ? _BrasaMobile(scope: scope, track: track, constraints: constraints)
      : _BrasaDesktop(scope: scope, track: track);
}

PlayerDiscStyle get _style => const PlayerDiscStyle(
  disc: Brasa.void_,
  label: Brasa.graphite,
  ring: Brasa.ember,
  ringWidth: 2,
  shadow: [],
  groove: Brasa.graphite,
  grooveHi: 1,
  grooveLo: .55,
  pivot: Brasa.cream,
  arm: Brasa.cream,
  needle: Brasa.cream,
);

/// 0 portada, 1 vinilo, 2 casete.
int _view(PlayerScope s) => s.modernPhoto ? 0 : (s.cassette ? 2 : 1);

/// Portada grande: radio 24, sombra flotante y filo claro al 7 %, con
/// resplandor de brasa detrás. Vinilo/casete usan el disco compartido.
class _BrasaCover extends StatelessWidget {
  const _BrasaCover({
    required this.scope,
    required this.track,
    required this.side,
    required this.radius,
  });
  final PlayerScope scope;
  final Track? track;
  final double side;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = track;
    final Widget art;
    if (_view(scope) != 0) {
      art = scope.record(context, scope.controller, t, side, _style);
    } else {
      art = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: Brasa.floatShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: const Color(0x12FFFFFF)),
            ),
            child: SizedBox.square(
              dimension: side,
              child: t == null
                  ? const ColoredBox(
                      color: Brasa.graphite,
                      child: Icon(
                        Icons.music_note_rounded,
                        size: 56,
                        color: Brasa.steel,
                      ),
                    )
                  : Artwork(
                      track: t,
                      artworkContext: ArtworkContext.player,
                      size: side,
                      radius: 0,
                    ),
            ),
          ),
        ),
      );
    }
    return BrasaGlow(
      child: RepaintBoundary(
        child: SizedBox.square(dimension: side, child: art),
      ),
    );
  }
}

/// Selector de vista (portada, vinilo, casete) para el escritorio.
class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.scope});
  final PlayerScope scope;

  @override
  Widget build(BuildContext context) {
    final view = _view(scope);
    const items = [
      (Icons.crop_square_rounded, 'Ver portada'),
      (Icons.album_outlined, 'Ver vinilo'),
      (Icons.sd_card_outlined, 'Ver casete'),
    ];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, item) in items.indexed)
          IconButton(
            tooltip: item.$2,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: () => scope.setModernView(i),
            color: view == i ? Brasa.ember : Brasa.cloud,
            icon: Icon(item.$1, size: 20),
          ),
      ],
    );
  }
}

/// Silenciar / restaurar volumen.
class _MuteButton extends StatefulWidget {
  const _MuteButton({required this.controller});
  final AppController controller;

  @override
  State<_MuteButton> createState() => _MuteButtonState();
}

class _MuteButtonState extends State<_MuteButton> {
  double _last = .75;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c.audio,
      builder: (context, _) {
        final muted = c.audio.volume <= 0;
        return BrasaIconButton(
          icon: muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          tooltip: muted ? 'Quitar silencio' : 'Silenciar',
          onPressed: () {
            if (muted) {
              c.setVolume(_last);
            } else {
              _last = c.audio.volume;
              c.setVolume(0);
            }
          },
        );
      },
    );
  }
}

Widget _artistLine(
  AppController c,
  PlayerScope scope,
  Track? track,
  double size, {
  Widget? trailing,
}) => Wrap(
  spacing: 12,
  runSpacing: 0,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: [
    MouseRegion(
      cursor: track == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: track == null ? null : () => c.openArtist(track.artist),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              track?.artist ?? 'Elige una canci\u00f3n de tu biblioteca',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brasa.sans(size, color: Brasa.cloud),
            ),
          ),
        ),
      ),
    ),
    if (scope.follow != null &&
        track != null &&
        primaryArtist(track.artist).isNotEmpty)
      FollowButton(service: scope.follow!, name: primaryArtist(track.artist)),
    ?trailing,
  ],
);

/// Chips con datos reales: códec (archivo local), EQ activo, Jam.
List<Widget> _chips(PlayerScope scope, Track? track, {bool always = false}) {
  final c = scope.controller;
  final codec = brasaCodec(track);
  final eq = brasaEqLabel(c);
  final listeners = brasaJamListeners(scope.jam);
  return [
    if (codec != null) BrasaChip(label: codec, outline: true),
    if (eq != null || always)
      BrasaChip(
        label: eq ?? 'EQ',
        icon: Icons.tune_rounded,
        tooltip: 'Abrir ecualizador',
        onTap: scope.onSection == null ? null : () => scope.onSection!(13),
      ),
    if (always) BrasaSleepChip(controller: c, short: true),
    if (listeners > 0 || always)
      BrasaChip(
        label: listeners > 0 ? 'Jam · $listeners' : 'Jam',
        icon: Icons.group_outlined,
        tooltip: 'Abrir Jam',
        onTap: scope.onSection == null ? null : () => scope.onSection!(9),
      ),
  ];
}

// ---------------------------------------------------------------- escritorio

class _BrasaDesktop extends StatelessWidget {
  const _BrasaDesktop({required this.scope, required this.track});
  final PlayerScope scope;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 1000;
        final side = math.max(
          160.0,
          math.min(380.0, math.min(box.maxWidth * .46, box.maxHeight - 220)),
        );
        final status = ListenableBuilder(
          listenable: c,
          builder: (context, _) => Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Brasa.ember,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  brasaStatusLine(c, c.nowTrack, scope.jam),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Brasa.mono(11, color: Brasa.cloud),
                ),
              ),
            ],
          ),
        );
        final header = Row(
          children: [
            Expanded(child: status),
            const SizedBox(width: 12),
            _ViewSwitch(scope: scope),
            const SizedBox(width: 8),
            BrasaSleepChip(controller: c),
          ],
        );
        final info = ListenableBuilder(
          listenable: c,
          builder: (context, _) => _DesktopInfo(
            scope: scope,
            track: track,
            titleSize: wide ? 52 : 40,
          ),
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              Expanded(
                child: LayoutBuilder(
                  builder: (context, area) => SingleChildScrollView(
                    clipBehavior: Clip.none,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: area.maxHeight),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _BrasaCover(
                              scope: scope,
                              track: track,
                              side: side,
                              radius: 24,
                            ),
                            SizedBox(width: wide ? 56 : 32),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 560,
                                ),
                                child: info,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _DesktopBar(scope: scope, track: track),
            ],
          ),
        );
      },
    );
  }
}

class _DesktopInfo extends StatelessWidget {
  const _DesktopInfo({
    required this.scope,
    required this.track,
    required this.titleSize,
  });
  final PlayerScope scope;
  final Track? track;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    final meta = brasaMetaLine(c, track);
    final chips = _chips(scope, track);
    final dim = Brasa.serif(28, color: Brasa.cream.withValues(alpha: .4));
    final live = Brasa.serif(36);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (meta != null) ...[
          Text(
            meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Brasa.mono(12),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          (track?.title ?? 'Nada sonando').trim(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Brasa.serif(titleSize, height: 1.06),
        ),
        const SizedBox(height: 4),
        _artistLine(
          c,
          scope,
          track,
          20,
          trailing: BrasaHeart(controller: c, track: track),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: chips),
        ],
        BrasaLyricsFeed(
          controller: c,
          builder: (context, lines, active) {
            if (lines.isEmpty) return const SizedBox.shrink();
            final from = active < 0 ? 0 : active - 1;
            final shown = <Widget>[];
            for (
              var i = math.max(0, from);
              i < math.min(lines.length, from + 4);
              i++
            ) {
              if (lines[i].text.trim().isEmpty) continue;
              final isActive = i == active;
              shown.add(
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: brasaLyricLine(
                    lines[i].text,
                    isActive ? live : dim,
                    accent: isActive,
                  ),
                ),
              );
            }
            if (shown.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 20),
              child: RepaintBoundary(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: shown,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Barra flotante de transporte (radio 20, sombra flotante, filo 7 %).
class _DesktopBar extends StatelessWidget {
  const _DesktopBar({required this.scope, required this.track});
  final PlayerScope scope;
  final Track? track;

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    final go = scope.onSection;
    return Container(
      decoration: BoxDecoration(
        color: Brasa.bar,
        borderRadius: BorderRadius.circular(20),
        boxShadow: Brasa.floatShadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: BrasaHeart(controller: c, track: track),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width >= 1200 ? 520 : 340,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrasaTransport(controller: c, playSize: 56, spread: false),
                  BrasaSeekBar(controller: c, liveDuration: scope.liveDuration),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  children: [
                    BrasaIconButton(
                      icon: Icons.lyrics_outlined,
                      tooltip: 'Letras',
                      onPressed: go == null ? null : () => go(6),
                    ),
                    BrasaIconButton(
                      icon: Icons.queue_music_rounded,
                      tooltip: 'Cola',
                      onPressed: go == null ? null : () => go(5),
                    ),
                    BrasaIconButton(
                      icon: Icons.tune_rounded,
                      tooltip: 'Ecualizador',
                      onPressed: go == null ? null : () => go(13),
                    ),
                    _MuteButton(controller: c),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- móvil

class _BrasaMobile extends StatelessWidget {
  const _BrasaMobile({
    required this.scope,
    required this.track,
    required this.constraints,
  });
  final PlayerScope scope;
  final Track? track;
  final BoxConstraints constraints;

  void _back() {
    if (scope.onBack != null) {
      scope.onBack!();
    } else {
      scope.onSection?.call(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    final side = math.max(
      140.0,
      math.min(
        268.0,
        math.min(constraints.maxWidth - 96, constraints.maxHeight - 520),
      ),
    );
    final top = Row(
      children: [
        IconButton(
          tooltip: 'Cerrar reproductor',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: _back,
          color: Brasa.cream,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Text(
              brasaStatusLine(c, c.nowTrack, null),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Brasa.mono(11, color: Brasa.cloud),
            ),
          ),
        ),
        Builder(
          builder: (b) => IconButton(
            tooltip: 'Más acciones',
            icon: const Icon(Icons.more_horiz_rounded, color: Brasa.cream),
            iconSize: 24,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: track == null
                ? null
                : () {
                    final box = b.findRenderObject()! as RenderBox;
                    showSongCard(
                      context,
                      c,
                      track!,
                      box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                      openQueue: () => scope.onSection?.call(5),
                      extras: [
                        (
                          label: 'Ver portada',
                          icon: Icons.image_outlined,
                          run: () => scope.setModernView(0),
                        ),
                        (
                          label: 'Ver vinilo',
                          icon: Icons.album_outlined,
                          run: () => scope.setModernView(1),
                        ),
                        (
                          label: 'Ver casete',
                          icon: Icons.album_rounded,
                          run: () => scope.setModernView(2),
                        ),
                      ],
                    );
                  },
          ),
        ),
      ],
    );
    final go = scope.onSection;
    final body = ListenableBuilder(
      listenable: c,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: _BrasaCover(
                scope: scope,
                track: track,
                side: side,
                radius: 24,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (track?.title ?? 'Nada sonando').trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Brasa.serif(30, height: 1.1),
                      ),
                      _artistLine(c, scope, track, 16),
                    ],
                  ),
                ),
                BrasaHeart(controller: c, track: track),
              ],
            ),
            BrasaLyricsFeed(
              controller: c,
              builder: (context, lines, active) {
                if (lines.isEmpty) return const SizedBox.shrink();
                final rows = <Widget>[];
                final from = active < 0 ? 0 : active - 1;
                for (
                  var i = math.max(0, from);
                  i < math.min(lines.length, from + 2);
                  i++
                ) {
                  if (lines[i].text.trim().isEmpty) continue;
                  final isActive = i == active;
                  rows.add(
                    brasaLyricLine(
                      lines[i].text,
                      isActive
                          ? Brasa.serif(24, height: 1.2)
                          : Brasa.serif(
                              20,
                              height: 1.2,
                              color: Brasa.cream.withValues(alpha: .4),
                            ),
                      accent: isActive,
                      maxLines: 2,
                    ),
                  );
                }
                if (rows.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: RepaintBoundary(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: rows,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 0,
              children: _chips(scope, track, always: true),
            ),
            const SizedBox(height: 4),
            BrasaSeekBar(
              controller: c,
              liveDuration: scope.liveDuration,
              height: 6,
            ),
            const SizedBox(height: 8),
            BrasaTransport(controller: c),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                BrasaIconButton(
                  icon: Icons.lyrics_outlined,
                  tooltip: 'Letras',
                  onPressed: go == null ? null : () => go(6),
                ),
                BrasaIconButton(
                  icon: Icons.queue_music_rounded,
                  tooltip: 'Cola',
                  onPressed: go == null ? null : () => go(5),
                ),
                BrasaIconButton(
                  icon: Icons.tune_rounded,
                  tooltip: 'Ecualizador',
                  onPressed: go == null ? null : () => go(13),
                ),
                _MuteButton(controller: c),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    return Column(
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(4, 8, 4, 0), child: top),
        Expanded(child: SingleChildScrollView(child: body)),
        _QueueHandle(scope: scope),
      ],
    );
  }
}

/// Asa inferior «Cola · N pistas» que abre la hoja de cola.
class _QueueHandle extends StatelessWidget {
  const _QueueHandle({required this.scope});
  final PlayerScope scope;

  @override
  Widget build(BuildContext context) {
    final c = scope.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final left = math.max(
          0,
          c.queue.length - math.max(0, c.queueIndex + 1),
        );
        final listeners = brasaJamListeners(scope.jam);
        final label = StringBuffer(
          'Cola · $left ${left == 1 ? 'pista' : 'pistas'}',
        );
        if (listeners > 0) {
          label.write(
            ' · Jam con $listeners ${listeners == 1 ? 'persona' : 'personas'}',
          );
        }
        return Material(
          color: Brasa.graphite,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            onTap: () => showBrasaQueueSheet(
              context,
              controller: c,
              jam: scope.jam,
              onJam: () => scope.onSection?.call(9),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Brasa.steel,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label.toString(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Brasa.sans(14, weight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
