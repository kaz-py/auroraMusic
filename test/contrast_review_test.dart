// Renders a state gallery to build/contrast_review/*.png for visual review.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:aurora_music/theme/atelier_theme.dart';
import 'package:aurora_music/ui/aurora_states.dart';
import 'package:aurora_music/ui/studio/studio_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

ThemeData legacy(ThemeData t) {
  final dark = t.brightness == Brightness.dark;
  final base = dark ? Colors.white : Colors.black;
  return t.copyWith(
    hoverColor: base.withValues(alpha: .04),
    focusColor: base.withValues(alpha: .12),
    highlightColor: base.withValues(alpha: .04),
    splashColor: base.withValues(alpha: .08),
    listTileTheme: ListTileThemeData(
      selectedColor: t.colorScheme.onPrimaryContainer,
      selectedTileColor: t.colorScheme.primaryContainer,
      iconColor: t.colorScheme.onSurfaceVariant,
    ),
  );
}

Widget gallery(ThemeData theme, bool old) {
  final c = theme.colorScheme;
  Widget row(String k, String t, {bool sel = false}) => Builder(
    builder: (context) => ListTile(
      key: Key(k),
      selected: sel,
      selectedTileColor: old ? c.primary.withValues(alpha: .06) : null,
      shape: sel && !old
          ? auroraSelectedShape(context)
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: const Icon(Icons.music_note),
      title: Text(t),
      subtitle: const Text('Artista · 3:42'),
      trailing: const Icon(Icons.more_horiz),
      onTap: () {},
    ),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: Scaffold(
      body: RepaintBoundary(
        key: const Key('shot'),
        child: Material(
          color: c.surface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row('r0', 'En reposo'),
                row('r1', 'Con el cursor encima (hover)'),
                row('r2', 'Seleccionada / sonando', sel: true),
                const SizedBox(height: 8),
                StudioPanel(
                  child: Column(
                    children: [
                      row('p0', 'Cola: siguiente'),
                      row('p1', 'Cola: actual', sel: true),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: () {},
                      child: const Text('Reproducir'),
                    ),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Contorno'),
                    ),
                    TextButton(onPressed: () {}, child: const Text('Texto')),
                    const FilledButton(
                      onPressed: null,
                      child: Text('Desactivado'),
                    ),
                    const OutlinedButton(
                      onPressed: null,
                      child: Text('Desactivado'),
                    ),
                    ChoiceChip(
                      label: const Text('Canciones'),
                      selected: true,
                      onSelected: (_) {},
                    ),
                    ChoiceChip(
                      label: const Text('Álbumes'),
                      selected: false,
                      onSelected: (_) {},
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const TextField(
                  decoration: InputDecoration(
                    hintText: 'Buscar música',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(value: true, onChanged: (_) {}),
                    Switch(value: false, onChanged: (_) {}),
                    Expanded(child: Slider(value: .4, onChanged: (_) {})),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.favorite_border),
                    ),
                    const IconButton(
                      onPressed: null,
                      icon: Icon(Icons.skip_next),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  final dir = Directory('build/contrast_review')..createSync(recursive: true);
  for (final old in [true, false]) {
    for (final b in Brightness.values) {
      testWidgets('review ${old ? 'before' : 'after'} $b', (tester) async {
        tester.view.physicalSize = const Size(900, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var theme = auroraTheme(b, const Color(0xffe86927));
        if (old) theme = legacy(theme);
        await tester.pumpWidget(gallery(theme, old));
        await tester.pumpAndSettle();
        final mouse = await tester.createGesture(
          kind: ui.PointerDeviceKind.mouse,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byKey(const Key('r1'))));
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const Key('shot')),
          );
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${dir.path}/${old ? 'before' : 'after'}_${b.name}.png',
          ).writeAsBytesSync(data!.buffer.asUint8List());
        });
      });
    }
  }
}
