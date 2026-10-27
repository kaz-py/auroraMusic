import '../friends_page.dart';
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../core/window_controls.dart';
import '../../theme/slush_theme.dart';
import '../artwork.dart';

/// Pestañas de la barra superior: (sección del shell, etiqueta).
const slushTabs = <(int, String)>[
  (0, 'INICIO'),
  (1, 'BUSCAR'),
  (12, 'ARTISTAS'),
  (2, 'BIBLIOTECA'),
  (3, 'DESCARGAS'),
  (8, 'DJ'),
  (9, 'JAM'),
  (14, 'AMIGOS'),
];

Widget _round(
  BuildContext context,
  String tip,
  IconData icon,
  VoidCallback? onTap, {
  double size = 34,
}) => Tooltip(
  message: tip,
  child: Material(
    color: context.slush.paper,
    shape: CircleBorder(side: context.slush.border),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: SizedBox.square(
        dimension: size,
        child: Icon(icon, size: size * .52, color: context.slush.ink),
      ),
    ),
  ),
);

/// Barra superior en píldora: logo, pestañas, búsqueda, «Iniciar Jam» y «+».
class SlushTopBar extends StatelessWidget {
  const SlushTopBar({
    super.key,
    required this.selected,
    required this.onNavigate,
    required this.onSession,
    required this.onAdd,
    this.sessionText = 'INICIAR JAM',
  });
  final int selected;
  final ValueChanged<int> onNavigate;
  final VoidCallback onSession, onAdd;
  final String sessionText;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final tabs = Semantics(
      container: true,
      label: 'Navegación principal',
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.slush.paper,
          shape: StadiumBorder(side: context.slush.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (section, label) in slushTabs)
                _Tab(
                  label,
                  active: section == selected,
                  onTap: () => onNavigate(section),
                ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: context.slush.paper,
          shape: StadiumBorder(side: context.slush.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              GestureDetector(
                onPanStart: (_) => WindowControls.invoke('drag'),
                onDoubleTap: () => WindowControls.invoke('maximize'),
                child: Semantics(
                  label: 'Aurora',
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: context.slush.paper,
                      shape: CircleBorder(side: context.slush.border),
                    ),
                    child: SizedBox.square(
                      dimension: 34,
                      child: Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            fontFamily: 'Bagel Fat One',
                            fontSize: 18,
                            color: context.slush.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                // El arrastre de ventana va debajo: no compite con los toques.
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => WindowControls.invoke('drag'),
                        onDoubleTap: () => WindowControls.invoke('maximize'),
                      ),
                    ),
                    FittedBox(fit: BoxFit.scaleDown, child: tabs),
                  ],
                ),
              ),
              _round(
                context,
                'Buscar',
                Icons.search,
                () => onNavigate(1),
                size: 30,
              ),
              const SizedBox(width: 8),
              Material(
                color: context.slush.ink,
                shape: const StadiumBorder(),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onSession,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.groups_rounded,
                          size: 14,
                          color: context.slush.paper,
                        ),
                        if (w > 900) ...[
                          const SizedBox(width: 6),
                          Text(
                            sessionText,
                            style: TextStyle(
                              color: context.slush.paper,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _round(context, 'Crear lista', Icons.add, onAdd, size: 30),
              const SizedBox(width: 8),
              _round(
                context,
                'Ajustes',
                Icons.tune,
                () => onNavigate(7),
                size: 30,
              ),
              if (WindowControls.supported) ...[
                const SizedBox(width: 6),
                for (final (op, icon, tip) in const [
                  ('minimize', Icons.remove, 'Minimizar'),
                  ('maximize', Icons.crop_square, 'Maximizar o restaurar'),
                  ('close', Icons.close, 'Cerrar ventana'),
                ])
                  IconButton(
                    tooltip: tip,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => WindowControls.invoke(op),
                    icon: Icon(icon, size: 15),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, {required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    child: Material(
      color: active ? context.slush.ink : Colors.transparent,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .3,
              color: active ? context.slush.paper : context.slush.ink,
            ),
          ),
        ),
      ),
    ),
  );
}

String _mmss(Duration d) {
  final s = d.inSeconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// Barra de reproducción inferior en píldora blanca.
class SlushPlayerBar extends StatefulWidget {
  const SlushPlayerBar({
    super.key,
    required this.controller,
    required this.onLyrics,
    required this.onVinyl,
    required this.onQueue,
    required this.onEqualizer,
    required this.onSettings,
    required this.onOpenPlayer,
  });
  final AppController controller;
  final VoidCallback onLyrics,
      onVinyl,
      onQueue,
      onEqualizer,
      onSettings,
      onOpenPlayer;

  @override
  State<SlushPlayerBar> createState() => _SlushPlayerBarState();
}

class _SlushPlayerBarState extends State<SlushPlayerBar> {
  double? _scrub;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final Track? t = c.currentTrack;
      final has = t != null;
      final dur = c.audio.duration;
      final pos = c.audio.position;
      final max = dur.inMilliseconds.toDouble();
      final value = (_scrub ?? pos.inMilliseconds.toDouble()).clamp(
        0,
        max <= 0 ? 1 : max,
      );
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      final fav = has && c.favoriteIds.contains(t.id);
      Widget ic(String tip, IconData i, VoidCallback? f, {bool on = false}) =>
          IconButton(
            tooltip: tip,
            visualDensity: VisualDensity.compact,
            onPressed: f,
            icon: Icon(i, size: 18, color: on ? Slush.blue : context.slush.ink),
          );
      final transport = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ic(
            'Aleatorio',
            Icons.shuffle,
            has ? () => c.setShuffle(!c.shuffle) : null,
            on: c.shuffle,
          ),
          ic('Anterior', Icons.skip_previous_rounded, has ? c.previous : null),
          Tooltip(
            message: c.audio.isPlaying ? 'Pausa' : 'Reproducir',
            child: Material(
              color: context.slush.ink,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: has ? c.togglePlayback : null,
                child: SizedBox.square(
                  dimension: 38,
                  child: c.busy
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: context.slush.paper,
                          ),
                        )
                      : Icon(
                          c.audio.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: context.slush.paper,
                        ),
                ),
              ),
            ),
          ),
          ic('Siguiente', Icons.skip_next_rounded, has ? c.next : null),
          ic(
            'Repetir',
            c.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
            has ? c.cycleRepeat : null,
            on: c.repeat != RepeatMode.off,
          ),
        ],
      );
      final slider = SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: SliderComponentShape.noOverlay,
      );
      final progress = Row(
        children: [
          Text(_mmss(pos), style: const TextStyle(fontSize: 10)),
          Expanded(
            child: SliderTheme(
              data: slider,
              child: Slider(
                value: value.toDouble(),
                max: max <= 0 ? 1 : max,
                semanticFormatterCallback: (v) =>
                    'Posición ${_mmss(Duration(milliseconds: v.toInt()))}',
                onChanged: max <= 0 || !has
                    ? null
                    : (v) => setState(() => _scrub = v),
                onChangeEnd: max <= 0 || !has
                    ? null
                    : (v) {
                        c.seek(Duration(milliseconds: v.toInt()));
                        setState(() => _scrub = null);
                      },
              ),
            ),
          ),
          Text(_mmss(dur), style: const TextStyle(fontSize: 10)),
        ],
      );
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: context.slush.paper,
            shape: StadiumBorder(side: context.slush.border),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  SizedBox(
                    width: wide ? 280 : 210,
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: has ? widget.onOpenPlayer : null,
                      child: Row(
                        children: [
                          if (has)
                            Artwork(
                              track: t,
                              artworkContext: ArtworkContext.thumbnailCompact,
                              radius: 28,
                            )
                          else
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                color: Slush.orange,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox.square(dimension: 44),
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t?.title ?? 'Elige una canción',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                                if (t != null)
                                  Text(
                                    t.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          ic(
                            'Favorito',
                            fav ? Icons.favorite : Icons.favorite_border,
                            has ? () => c.toggleFavorite(t) : null,
                            on: fav,
                          ),
                          if (has && !t.isLocal)
                            FriendsGate(
                              builder: (context, f) => ic(
                                'Enviar a un amigo',
                                Icons.send_outlined,
                                () => showSendToFriendSheet(context, f, t),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        transport,
                        SizedBox(height: 18, child: progress),
                      ],
                    ),
                  ),
                  ic('Cola', Icons.queue_music, widget.onQueue),
                  ic('Modo Vinilo', Icons.album_outlined, widget.onVinyl),
                  ic('Letras', Icons.lyrics_outlined, widget.onLyrics),
                  ic('Ajustes', Icons.tune, widget.onSettings),
                  if (wide) ...[
                    ic('Ecualizador', Icons.equalizer, widget.onEqualizer),
                    Icon(
                      c.audio.volume <= 0
                          ? Icons.volume_off
                          : Icons.volume_up_outlined,
                      size: 16,
                    ),
                    SizedBox(
                      width: 110,
                      child: SliderTheme(
                        data: slider,
                        child: Slider(
                          semanticFormatterCallback: (v) =>
                              'Volumen ${(v * 100).round()} por ciento',
                          value: c.audio.volume.clamp(0, 1),
                          onChanged: c.setVolume,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
