import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../home/home_theme.dart';
import 'studio_components.dart';

/// Reloj de la portada; los tests lo fijan para no depender de la hora real.
DateTime Function() studioClock = DateTime.now;

/// Título editorial de la portada según la hora local.
String studioGreeting(DateTime t) => switch (t.hour) {
  < 5 => 'Madrugada acústica',
  < 8 => 'Amanecer sonoro',
  < 12 => 'Mañana en calma',
  < 15 => 'Mediodía de vinilo',
  < 19 => 'Tarde en cinta',
  < 22 => 'Anochecer cálido',
  _ => 'Noche de válvulas',
};

/// Cabecera editorial de la portada; cada tema la dibuja en `HomeTheme.introduction`
/// (`ui/home/home_<tema>.dart`).
class StudioHomeIntroduction extends StatelessWidget {
  const StudioHomeIntroduction({
    super.key,
    required this.controller,
    required this.onSearch,
    required this.onVinyl,
    this.onSearchQuery,
  });
  final AppController controller;
  final VoidCallback onSearch, onVinyl;
  final ValueChanged<String>? onSearchQuery;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final track =
        c.currentTrack ??
        c.recentTracks.firstOrNull ??
        c.tracks.where((t) => !t.isPendingSpotifyMatch).firstOrNull;
    return homeThemeOf(context).introduction(context, this, track);
  }
}

/// Título y hora de la portada; se actualiza solo cuando cambia el minuto.
class StudioGreetingRow extends StatefulWidget {
  const StudioGreetingRow({super.key});

  @override
  State<StudioGreetingRow> createState() => _StudioGreetingRowState();
}

class _StudioGreetingRowState extends State<StudioGreetingRow> {
  late DateTime _now = studioClock();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      final now = studioClock();
      if (now.hour != _now.hour || now.minute != _now.minute) {
        setState(() => _now = now);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = MediaQuery.sizeOf(context).width;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 20,
      runSpacing: 8,
      children: [
        Text(
          studioGreeting(_now),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontStyle: FontStyle.italic,
            fontSize: width <= 400
                ? 28
                : width < 600
                ? 38
                : 56,
          ),
        ),
        StudioStamp(
          TimeOfDay.fromDateTime(_now).format(context),
          filled: true,
          color: colors.primary,
        ),
      ],
    );
  }
}
