import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_bars.dart';
import 'package:aurora_music/ui/slush/slush_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('barra superior Slush: pestañas, Jam y crear lista', (t) async {
    t.view.physicalSize = const Size(1400, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final nav = <int>[];
    var jam = 0, add = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.light, Colors.blue),
        home: Scaffold(
          body: SlushTopBar(
            selected: 0,
            onNavigate: nav.add,
            onSession: () => jam++,
            onAdd: () => add++,
            onProfile: (_) {},
          ),
        ),
      ),
    );
    await t.tap(find.text('ARTISTAS'));
    await t.tap(find.text('JAM'));
    await t.tap(find.text('INICIAR JAM'));
    await t.tap(find.byTooltip('Crear lista'));
    expect(nav, [12, 9]);
    expect(jam, 1);
    expect(add, 1);
  });

  test('duración total del mix', () {
    Track tr(int m) => Track(
      id: '$m',
      title: 't',
      artist: 'a',
      duration: Duration(minutes: m),
    );
    expect(slushTotalTime([tr(60), tr(64)]), '2 h 04');
    expect(slushTotalTime([tr(30)]), '30 min');
    expect(slushTotalTime(const []), isNull);
  });
}
