import 'package:flutter/widgets.dart';

import '../../app_controller.dart';
import '../../jam/jam_controller.dart';
import '../../shortcuts/shortcut_service.dart';
import '../studio/studio_transport.dart';

/// Lo que necesitan las barras de antes del mini reproductor 1.5.0
/// (`StudioTransport`). Las rellena el
/// shell; los temas nuevos no lo usan y, al migrar, se borra este archivo.
class MiniPlayerLegacyBars {
  const MiniPlayerLegacyBars({
    required this.shortcuts,
    required this.onJam,
    required this.onStartJam,
    required this.onLyrics,
    required this.onVinyl,
    required this.onQueue,
    required this.onEqualizer,
    required this.onSettings,
    required this.onOpenPlayer,
  });

  final ShortcutService? shortcuts;
  final VoidCallback onJam,
      onStartJam,
      onLyrics,
      onVinyl,
      onQueue,
      onEqualizer,
      onSettings;

  /// Hoja del reproductor (el `onOpenPlayer` de `StudioTransport`).
  final VoidCallback onOpenPlayer;
}

/// Contexto que el host entrega a los temas aún «legacy».
class MiniPlayerLegacyScope extends InheritedWidget {
  const MiniPlayerLegacyScope({
    super.key,
    required this.controller,
    required this.jam,
    required this.bars,
    required this.rail,
    required this.onOpenVinyl,
    required this.onTogglePlay,
    required super.child,
  });

  final AppController controller;
  final JamController? jam;
  final MiniPlayerLegacyBars bars;

  /// Diseño con carril lateral (≥ 600): la barra es el transporte completo.
  final bool rail;

  /// Abre la sección del reproductor (4); `onOpen` del mini de Slush.
  final VoidCallback onOpenVinyl;
  final VoidCallback onTogglePlay;

  static MiniPlayerLegacyScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<MiniPlayerLegacyScope>();
    assert(scope != null, 'legacyMiniPlayerBar fuera de MiniPlayerHost');
    return scope!;
  }

  @override
  bool updateShouldNotify(MiniPlayerLegacyScope old) =>
      old.controller != controller ||
      old.jam != jam ||
      old.bars != bars ||
      old.rail != rail ||
      old.onOpenVinyl != onOpenVinyl ||
      old.onTogglePlay != onTogglePlay;
}

/// La barra que había antes de los minis nuevos: `StudioTransport` (Slush ya
/// no pasa por aquí).
Widget legacyMiniPlayerBar(BuildContext context) {
  final s = MiniPlayerLegacyScope.of(context);
  final bars = s.bars;
  final c = s.controller;
  return StudioTransport(
    shortcuts: bars.shortcuts,
    jam: s.jam,
    onJam: bars.onJam,
    onStartJam: bars.onStartJam,
    controller: c,
    onLyrics: bars.onLyrics,
    onVinyl: bars.onVinyl,
    onQueue: bars.onQueue,
    onOpenPlayer: bars.onOpenPlayer,
  );
}
