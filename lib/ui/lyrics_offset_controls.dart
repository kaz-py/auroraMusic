import 'package:flutter/material.dart';

/// Ajuste fino de la letra: la mueve en pasos de [step] ms. `offsetMs`
/// negativo = la letra sale más tarde (se usa cuando va adelantada).
class LyricsOffsetControls extends StatelessWidget {
  const LyricsOffsetControls({
    super.key,
    required this.offsetMs,
    required this.onChanged,
    this.step = 500,
  });

  final int offsetMs;
  final ValueChanged<int> onChanged;
  final int step;

  String get _label {
    if (offsetMs == 0) return 'Letra: sin ajuste';
    final seconds = (offsetMs.abs() / 1000).toStringAsFixed(1);
    return offsetMs < 0
        ? 'Letra −${seconds}s (más tarde)'
        : 'Letra +${seconds}s (más pronto)';
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        key: const ValueKey('lyrics-later'),
        tooltip: 'Letra más tarde (si va adelantada)',
        icon: const Icon(Icons.remove_rounded),
        onPressed: () => onChanged(offsetMs - step),
      ),
      Tooltip(
        message: offsetMs == 0 ? _label : '$_label · toca para quitar',
        child: InkWell(
          key: const ValueKey('lyrics-offset-reset'),
          borderRadius: BorderRadius.circular(8),
          onTap: offsetMs == 0 ? null : () => onChanged(0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Text(_label, style: Theme.of(context).textTheme.labelMedium),
          ),
        ),
      ),
      IconButton(
        key: const ValueKey('lyrics-earlier'),
        tooltip: 'Letra más pronto (si va atrasada)',
        icon: const Icon(Icons.add_rounded),
        onPressed: () => onChanged(offsetMs + step),
      ),
    ],
  );
}
