/// Dueño: tema Brasa. Banda «DJ personal» de la portada: resplandor de brasa,
/// estado real del DJ, botón de inicio/parada y ajustes (modo, novedades y
/// filtros) que antes vivían en `DjPanel`.
library;

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../core/models.dart';
import '../../dj/dj_modes.dart';
import '../../theme/brasa_theme.dart';
import '../dj_filters_panel.dart';
import '../studio/home_introduction.dart';
import 'brasa_home_widgets.dart';

class BrasaDjBand extends StatefulWidget {
  const BrasaDjBand({
    super.key,
    required this.controller,
    required this.covers,
    this.wide = true,
  });
  final AppController controller;

  /// Portadas reales para la pila decorativa (hasta 3 en ancho, 1 en estrecho).
  final List<Track> covers;
  final bool wide;

  @override
  State<BrasaDjBand> createState() => _BrasaDjBandState();
}

class _BrasaDjBandState extends State<BrasaDjBand> {
  bool _starting = false, _failed = false, _settings = false;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _failed = false;
    });
    final c = widget.controller;
    final ok = await c.startDjSession(
      includeDiscovery: c.personalDjIncludeDiscovery,
    );
    if (mounted) {
      setState(() {
        _starting = false;
        _failed = !ok;
      });
    }
  }

  String _title(bool active) {
    if (active) return 'DJ activo · ${widget.controller.djMode.label}';
    final h = studioClock().hour;
    return h >= 20 || h < 6 ? 'Tu sesión nocturna' : 'Tu sesión de hoy';
  }

  String _description(bool active) {
    final c = widget.controller;
    if (active) {
      final next = c.personalDjNextReason;
      return next == null
          ? 'La cola no termina: el DJ sigue sumando canciones.'
          : 'A continuación: $next';
    }
    final n = c.tracks.length;
    return n == 0
        ? 'Empieza una sesión sin fin con tu perfil y recomendaciones de YouTube.'
        : 'Mezcla $n ${n == 1 ? 'pista' : 'pistas'} de tu biblioteca, modo ${c.djMode.label.toLowerCase()}.';
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final wide = widget.wide;
    final active = c.personalDjActive;
    final jam = c.jamPlaybackActive;
    final note = jam
        ? 'Hay una Jam en curso: el DJ queda en pausa hasta que termine.'
        : _failed && !active
        ? 'No hay con qué empezar: añade música a tu biblioteca, busca una canción o revisa tu conexión.'
        : null;
    final covers = widget.covers.take(wide ? 3 : 1).toList();
    final scheme = Theme.of(context).colorScheme;

    final button = FilledButton.icon(
      key: const ValueKey('dj-toggle'),
      style: FilledButton.styleFrom(
        backgroundColor: Brasa.ember,
        foregroundColor: Brasa.onEmber,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Brasa.sans(14, weight: FontWeight.w700, height: 1.2),
      ),
      onPressed: _starting || jam
          ? null
          : active
          ? c.stopPersonalDj
          : _start,
      icon: _starting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Brasa.onEmber,
              ),
            )
          : Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
      label: Text(
        _starting
            ? 'Preparando el DJ…'
            : active
            ? 'Detener DJ'
            : 'Iniciar DJ',
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const BrasaCaption('DJ personal', dot: true),
        const SizedBox(height: 8),
        Semantics(
          liveRegion: true,
          child: Text(
            _title(active),
            key: const ValueKey('dj-status'),
            style: Brasa.serif(wide ? 26 : 22),
          ),
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 440 : 230),
          child: Text(
            _description(active),
            style: Brasa.sans(wide ? 15 : 14, color: Brasa.cloud),
          ),
        ),
        SizedBox(height: wide ? 14 : 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            button,
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Brasa.cloud,
                minimumSize: const Size(0, 48),
              ),
              onPressed: () => setState(() => _settings = !_settings),
              icon: Icon(_settings ? Icons.expand_less : Icons.tune, size: 20),
              label: const Text('Ajustes del DJ'),
            ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(note, style: TextStyle(color: scheme.error)),
          ),
        if (active && c.personalDjError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              c.personalDjError!,
              style: TextStyle(color: scheme.error),
            ),
          ),
      ],
    );

    final stack = covers.isEmpty
        ? null
        : wide
        ? SizedBox(
            width: 96 + (covers.length - 1) * 68.0,
            height: 120,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < covers.length; i++)
                  Positioned(
                    left: i * 68.0,
                    top: i == 1 ? 0 : 12,
                    width: 96,
                    height: 96,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: BrasaCover(track: covers[i], radius: 16, px: 192),
                    ),
                  ),
              ],
            ),
          )
        : null;

    final body = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              if (stack != null) ...[const SizedBox(width: 32), stack],
            ],
          )
        : Stack(
            children: [
              if (covers.isNotEmpty)
                Positioned(
                  right: -16,
                  top: 0,
                  width: 110,
                  child: Transform.rotate(
                    angle: .14,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x80000000),
                            blurRadius: 24,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: BrasaCover(
                        track: covers.first,
                        radius: 20,
                        px: 220,
                      ),
                    ),
                  ),
                ),
              text,
            ],
          );

    final settings = _settings
        ? Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Material(
              type: MaterialType.transparency,
              child: _DjSettings(controller: c),
            ),
          )
        : null;

    return RepaintBoundary(
      child: Container(
        key: const ValueKey('dj-session-card'),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 20, vertical: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: Brasa.graphite,
          gradient: RadialGradient(
            center: Alignment.bottomRight,
            radius: wide ? 1.1 : .95,
            colors: [
              Brasa.ember.withValues(alpha: .38),
              Brasa.ember.withValues(alpha: 0),
            ],
            stops: const [0, .6],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [body, ?settings],
        ),
      ),
    );
  }
}

class _DjSettings extends StatelessWidget {
  const _DjSettings({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final mode in DjMode.values)
                BrasaChip(
                  label: mode.label,
                  active: c.djMode == mode,
                  mobile: true,
                  onTap: () => c.setDjMode(mode),
                ),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: Brasa.ember,
            title: Text('Incluir novedades de YouTube', style: Brasa.sans(14)),
            subtitle: Text(
              'Hasta 2 búsquedas por recarga, guiadas por tu perfil.',
              style: Brasa.sans(13, color: Brasa.cloud),
            ),
            value: c.personalDjIncludeDiscovery,
            onChanged: c.setPersonalDjIncludeDiscovery,
          ),
          DjFiltersPanel(controller: c),
        ],
      ),
    );
  }
}
