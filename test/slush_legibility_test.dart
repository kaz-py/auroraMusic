import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/ui/aurora_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _songs = [
  Track(id: 'a', title: 'Luz de luna', artist: 'Mare Sol'),
  Track(id: 'b', title: 'Mar adentro', artist: 'Mare Sol'),
  Track(id: 'c', title: 'Noche', artist: 'Otro'),
];

/// Contraste mínimo bajo el cual un texto/icono se considera ilegible.
const _min = 3.0;

double _ratio(Color a, Color b) {
  final l1 = a.computeLuminance(), l2 = b.computeLuminance();
  return (l1 > l2 ? l1 + .05 : l2 + .05) / (l1 > l2 ? l2 + .05 : l1 + .05);
}

/// Corazón de Vinilo: icono decorativo de dos capas (contorno + relleno naranja).
const _decorativeHeart = 0xf738;

Color _over(Color top, Color under) => Color.alphaBlend(top, under);

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';

class _Hit {
  _Hit(this.text, this.fg, this.bg, this.ratio);
  final String text;
  final Color fg, bg;
  final double ratio;
}

/// Recorre el árbol de render y devuelve los textos/iconos con poco contraste.
List<_Hit> _scan(RenderObject root, Color fallbackBg, Size screen) {
  final out = <_Hit>[];
  void visit(RenderObject o) {
    if (o is RenderOffstage && o.offstage) return;
    if (o is RenderParagraph) _check(o, fallbackBg, screen, out);
    o.visitChildren(visit);
  }

  visit(root);
  return out;
}

void _check(RenderParagraph p, Color fallbackBg, Size screen, List<_Hit> out) {
  if (!p.hasSize || !p.attached) return;
  final plain = p.text.toPlainText().trim();
  if (plain.isEmpty) return;
  if (plain.runes.length == 1 && plain.runes.first == _decorativeHeart) return;
  var fg = p.text.style?.color ?? const Color(0xff000000);
  if (fg.a == 0) return;
  final origin = p.localToGlobal(Offset.zero);
  final rect = origin & p.size;
  if (rect.isEmpty ||
      !(Offset.zero & screen).overlaps(rect) ||
      rect.width < 1 ||
      rect.height < 1) {
    return;
  }
  var opacity = 1.0;
  final layers = <Color>[]; // de dentro hacia fuera
  var opaque = false;
  var image = false;
  for (RenderObject? a = p.parent; a != null; a = a.parent) {
    if (a is RenderOffstage && a.offstage) return;
    if (a is RenderOpacity) opacity *= a.opacity;
    if (a is RenderAnimatedOpacity) opacity *= a.opacity.value;
    if (a is RenderBox && a.hasSize) {
      // Recortes de scroll/clip: fuera de la ventana visible no cuenta.
      if (a is RenderClipRect || a is RenderViewportBase) {
        final r = a.localToGlobal(Offset.zero) & a.size;
        if (!r.overlaps(rect)) return;
      }
    }
    if (opaque || image) continue;
    Color? c;
    if (a is RenderDecoratedBox &&
        a.position == DecorationPosition.background) {
      final d = a.decoration;
      if (d is BoxDecoration) {
        if (d.image != null) {
          image = true;
          continue;
        }
        c = d.color;
        final g = d.gradient;
        if (c == null && g is LinearGradient && g.colors.isNotEmpty) {
          c = g.colors.first;
        }
      } else if (d is ShapeDecoration) {
        if (d.image != null) {
          image = true;
          continue;
        }
        c = d.color;
        final g = d.gradient;
        if (c == null && g is LinearGradient && g.colors.isNotEmpty) {
          c = g.colors.first;
        }
      }
    } else if (a is RenderCustomPaint && a.painter != null) {
      image = true; // fondo pintado a mano: no medible
      continue;
    } else if (a.runtimeType.toString() == '_RenderChip') {
      final e = (p.debugCreator is DebugCreator)
          ? (p.debugCreator! as DebugCreator).element
          : null;
      RawChip? chip;
      e?.visitAncestorElements((x) {
        if (x.widget is RawChip) {
          chip = x.widget as RawChip;
          return false;
        }
        return true;
      });
      if (chip == null || e == null) {
        image = true;
        continue;
      }
      final t = ChipTheme.of(e);
      c = chip!.selected == true
          ? (chip!.selectedColor ?? t.selectedColor)
          : (chip!.backgroundColor ?? t.backgroundColor);
      if (c == null) {
        image = true;
        continue;
      }
    } else if (a.runtimeType.toString() == '_RenderColoredBox') {
      c = (a as dynamic).color as Color;
    } else if (a is RenderPhysicalModel) {
      c = a.color;
    } else if (a is RenderPhysicalShape) {
      c = a.color;
    }
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= .999) opaque = true;
    }
  }
  if (image || opacity < .05) return;
  var bg = opaque ? layers.removeLast() : fallbackBg;
  for (final l in layers.reversed) {
    bg = _over(l, bg);
  }
  fg = fg.withValues(alpha: fg.a * opacity);
  final shown = _over(fg, bg);
  final r = _ratio(shown, bg);
  if (r < _min) {
    final cp = plain.runes.first;
    final label = plain.length == 1 && cp >= 0xe000 && cp <= 0xf8ff
        ? 'icono U+${cp.toRadixString(16)}'
        : plain.replaceAll('\n', ' ');
    out.add(
      _Hit(label.length > 32 ? label.substring(0, 32) : label, shown, bg, r),
    );
  }
}

void main() {
  for (final mode in const ['light', 'dark']) {
    for (final size in const [Size(1440, 900), Size(390, 844)]) {
      final wide = size.width > 600;
      testWidgets(
        'Slush $mode legible a ${size.width.toInt()} px',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final c = (await tester.runAsync(
            () => createTestController(
              tracks: _songs,
              playlists: const [
                MusicPlaylist(id: 'p1', name: 'Jazz', trackIds: ['a', 'b']),
              ],
              preferences: {'themeKind': 'slush', 'themeMode': mode},
            ),
          ))!;
          c.queue = [..._songs];
          await tester.runAsync(() => c.playQueueAt(0));
          await c.audio.pause();
          final container = ProviderContainer(
            overrides: [controllerProvider.overrideWith((ref) => c)],
          );
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await tester.runAsync(() async {
              await c.closed;
              if (await c.supportDirectory.exists()) {
                await c.supportDirectory.delete(recursive: true);
              }
            });
          });
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: const AuroraApp(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(AuroraShell), findsOneWidget);

          final rows = <String>[];
          void audit(String screen) {
            // Desbordes de fuentes de test no son asunto de esta prueba.
            tester.takeException();
            final scaffold = find.byType(Scaffold).first;
            final bg =
                tester.widget<Scaffold>(scaffold).backgroundColor ??
                Theme.of(tester.element(scaffold)).scaffoldBackgroundColor;
            final hits = _scan(tester.binding.renderViews.first, bg, size);
            final seen = <String>{};
            for (final h in hits) {
              final row =
                  '$screen | $mode | ${size.width.toInt()} | "${h.text}" | '
                  'fg ${_hex(h.fg)} | bg ${_hex(h.bg)} | ${h.ratio.toStringAsFixed(2)}';
              if (seen.add(row)) rows.add(row);
            }
          }

          Future<void> go(Finder tap, String screen) async {
            expect(tap, findsWidgets, reason: screen);
            await tester.tap(tap.first);
            await tester.pumpAndSettle();
            audit(screen);
          }

          Future<void> more(String label, String screen) async {
            await tester.tap(find.byIcon(Icons.more_horiz).first);
            await tester.pumpAndSettle();
            await go(find.text(label).last, screen);
          }

          audit('Inicio');
          if (wide) {
            await go(find.text('BUSCAR'), 'Busqueda');
            await go(find.text('BIBLIOTECA'), 'Biblioteca');
            await go(find.text('DJ'), 'DJ');
            await go(find.text('JAM'), 'Jam');
            await go(find.byTooltip('Ecualizador'), 'EQ+Cola');
            await go(find.text('VINILO'), 'Vinilo');
            await go(find.byTooltip('Ajustes'), 'Ajustes');
            await go(find.text('DESCARGAS'), 'Descargas');
            await go(find.text('ARTISTAS'), 'Artistas');
            await go(find.text('AMIGOS'), 'Amigos');
          } else {
            await go(find.byTooltip('Buscar'), 'Busqueda');
            await go(find.byTooltip('Biblioteca'), 'Biblioteca');
            await go(find.byTooltip('DJ'), 'DJ');
            await go(find.byTooltip('Jam'), 'Jam');
            await more('Ecualizador', 'EQ+Cola');
            await more('Modo Vinilo', 'Vinilo');
            await go(find.byTooltip('Inicio'), 'Inicio2');
            await go(find.byIcon(Icons.dark_mode_outlined), 'Ajustes');
            await more('Descargas', 'Descargas');
            await more('Artistas', 'Artistas');
            await more('Amigos', 'Amigos');
          }

          debugPrint(
            '--- LEGIBILIDAD ${mode.toUpperCase()} ${size.width.toInt()} ---\n'
            '${rows.isEmpty ? '(sin ofensores)' : rows.join('\n')}',
          );
          expect(rows, isEmpty);
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }
  }
}
