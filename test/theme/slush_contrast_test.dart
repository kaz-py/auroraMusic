import 'dart:math' as math;

import 'package:aurora_music/theme/slush_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _ratio(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (math.max(x, y) + .05) / (math.min(x, y) + .05);
}

const _accents = [
  Color(0xffff0000),
  Color(0xff2255cc),
  Color(0xff22aa66),
  Color(0xffffcc00),
  Color(0xff8844cc),
  Color(0xffe86927),
  Color(0xff777777),
  Slush.mint,
  Slush.yellow,
  Slush.lilac,
  Slush.orange,
  Slush.blue,
  Slush.violet,
];

const _vivid = [
  Slush.mint,
  Slush.yellow,
  Slush.lilac,
  Slush.orange,
  Slush.blue,
];

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'oscuro' : 'claro';
    final p = dark ? SlushPalette.dark : SlushPalette.light;
    final bgs = [
      for (final a in _accents) Slush.background(a, dark: dark),
      if (dark) Slush.darkBackground,
    ];

    test('Slush $mode: texto >= 4.5 sobre cada capa', () {
      final layers = {
        'paper': p.paper,
        'raised': p.raised,
        'inset': p.inset,
        'screen': p.screen,
        for (var i = 0; i < bgs.length; i++) 'bg$i': bgs[i],
      };
      for (final e in layers.entries) {
        for (final t in {
          'ink': p.ink,
          'ink2': p.ink2,
          'ink3': p.ink3,
        }.entries) {
          expect(
            _ratio(t.value, e.value),
            greaterThanOrEqualTo(4.5),
            reason: '${t.key} sobre ${e.key}',
          );
        }
        expect(
          _ratio(p.error, e.value),
          greaterThanOrEqualTo(4.5),
          reason: 'error sobre ${e.key}',
        );
      }
    });

    test('Slush $mode: controles y bordes >= 3 (UI)', () {
      final surfaces = [p.paper, p.raised, ...bgs];
      for (final s in surfaces) {
        for (final c in {
          'line': p.line,
          'lineSoft': p.lineSoft,
          'focus': p.focus,
          'violetAccent': p.violetAccent,
        }.entries) {
          expect(
            _ratio(c.value, s),
            greaterThanOrEqualTo(3),
            reason: '${c.key} sobre $s',
          );
        }
      }
      // Campo en reposo: borde lineSoft contra su relleno.
      expect(_ratio(p.lineSoft, p.inset), greaterThanOrEqualTo(3));
      // Pista inactiva del slider.
      final t = slushTheme(
        dark ? Brightness.dark : Brightness.light,
        Slush.lilac,
      ).sliderTheme;
      expect(_ratio(t.inactiveTrackColor!, p.paper), greaterThanOrEqualTo(3));
      expect(_ratio(t.thumbColor!, p.paper), greaterThanOrEqualTo(3));
    });

    test('Slush $mode: texto deshabilitado legible y estados con texto', () {
      expect(_ratio(p.disabledText, p.disabledFill), greaterThanOrEqualTo(4));
      expect(_ratio(p.disabledBorder, p.paper), greaterThanOrEqualTo(2.5));
      for (final fill in [p.paper, p.raised]) {
        for (final over in [p.hover, p.pressed]) {
          final blended = Color.alphaBlend(over, fill);
          expect(
            _ratio(p.ink, blended),
            greaterThanOrEqualTo(7),
            reason: 'ink sobre $blended',
          );
        }
      }
    });

    test('Slush $mode: el tema expone los mismos tokens', () {
      final t = slushTheme(
        dark ? Brightness.dark : Brightness.light,
        Slush.mint,
      );
      expect(t.extension<SlushPalette>(), p);
      expect(t.colorScheme.onSurfaceVariant, p.ink2);
      expect(t.colorScheme.error, p.error);
      expect(t.colorScheme.outlineVariant, p.lineSoft);
    });
  }

  test('Vivos: tinta (o blanco sobre violeta) >= 4.5 en ambos modos', () {
    for (final v in _vivid) {
      expect(_ratio(Slush.ink, v), greaterThanOrEqualTo(4.5), reason: '$v');
    }
    expect(_ratio(Slush.onViolet, Slush.violet), greaterThanOrEqualTo(4.5));
    // La tinta sobre violeta NO llega: por eso el texto es blanco.
    expect(_ratio(Slush.ink, Slush.violet), lessThan(4.5));
  });

  test('Violeta: relleno en claro, violetOnDark sobre superficies oscuras', () {
    final d = SlushPalette.dark;
    for (final s in [Slush.darkBackground, d.paper, d.raised]) {
      expect(_ratio(Slush.violetOnDark, s), greaterThanOrEqualTo(4.5));
    }
    expect(d.violetAccent, Slush.violetOnDark);
    expect(SlushPalette.light.violetAccent, Slush.violet);
    expect(
      _ratio(Slush.violet, SlushPalette.light.paper),
      greaterThanOrEqualTo(4.5),
    );
    // El violeta crudo sobre oscuro no cumple UI 3:1 (hallazgo 4).
    expect(_ratio(Slush.violet, d.paper), lessThan(3));
  });

  test('Foco: anillo visible sobre papel y vivos', () {
    for (final v in [Slush.mint, Slush.yellow, Slush.lilac]) {
      expect(
        _ratio(SlushPalette.light.focus, v),
        greaterThanOrEqualTo(3),
        reason: '$v',
      );
    }
    expect(
      _ratio(SlushPalette.dark.focus, SlushPalette.dark.paper),
      greaterThanOrEqualTo(3),
    );
  });

  test('Oscuro: capas de atrás hacia delante y sombra no crema', () {
    const d = SlushPalette.dark;
    for (final a in _accents) {
      final bg = Slush.background(a, dark: true);
      expect(d.paper.computeLuminance(), greaterThan(bg.computeLuminance()));
      expect(d.screen.computeLuminance(), greaterThan(bg.computeLuminance()));
    }
    expect(d.screen.computeLuminance(), lessThan(d.paper.computeLuminance()));
    expect(d.paper.computeLuminance(), lessThan(d.raised.computeLuminance()));
    expect(d.inset.computeLuminance(), lessThan(d.paper.computeLuminance()));
    expect(
      d.inset.computeLuminance(),
      lessThan(Slush.darkBackground.computeLuminance()),
    );
    expect(d.shadow, isNot(d.ink));
    expect(d.shadow, isNot(d.line));
    expect(d.lineSoft, isNot(d.line));
    expect(SlushPalette.light.lineSoft, SlushPalette.light.line);
  });

  test('Oscuro: fondo de portada profundo y poco saturado', () {
    for (final a in _accents) {
      final h = HSLColor.fromColor(Slush.background(a, dark: true));
      expect(h.lightness, closeTo(.07, .01));
      expect(h.saturation, lessThanOrEqualTo(.35));
    }
  });

  for (final dark in [false, true]) {
    testWidgets('slushOnColor ${dark ? 'oscuro' : 'claro'}: tinta / violeta', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: slushTheme(
            dark ? Brightness.dark : Brightness.light,
            Slush.lilac,
          ),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      for (final v in _vivid) {
        expect(slushOnColor(ctx, v), Slush.ink);
      }
      expect(slushOnColor(ctx, Slush.violet), Slush.onViolet);
      final p = ctx.slush;
      expect(slushOnColor(ctx, p.paper), dark ? p.ink : Slush.ink);
    });
  }

  test('Paleta: lerp y copyWith cubren todos los campos', () {
    final mid = SlushPalette.light.lerp(SlushPalette.dark, .5);
    expect(
      mid.paper,
      Color.lerp(SlushPalette.light.paper, SlushPalette.dark.paper, .5),
    );
    expect(
      SlushPalette.light.lerp(SlushPalette.dark, 0).raised,
      SlushPalette.light.raised,
    );
    expect(
      SlushPalette.light.lerp(SlushPalette.dark, 1).divider,
      SlushPalette.dark.divider,
    );
    final c = SlushPalette.dark.copyWith(inset: Colors.red);
    expect(c.inset, Colors.red);
    expect(c.ink3, SlushPalette.dark.ink3);
    expect(SlushPalette.dark.shadows.single.offset, const Offset(3, 4));
    expect(
      SlushPalette.dark.shadowsFor(SlushElevation.control).single.offset,
      const Offset(2, 3),
    );
    expect(SlushPalette.dark.shadowsFor(SlushElevation.none), isEmpty);
  });
}
