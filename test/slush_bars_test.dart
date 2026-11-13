import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/theme/slush_theme.dart';
import 'package:aurora_music/ui/slush/slush_bars.dart';
import 'package:aurora_music/ui/slush/slush_home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('cabecera Slush: búsqueda, Jam y perfil', (t) async {
    t.view.physicalSize = const Size(1400, 300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final ctrl = TextEditingController();
    final focus = FocusNode();
    addTearDown(ctrl.dispose);
    addTearDown(focus.dispose);
    final searched = <String>[];
    var jam = 0, profile = 0;
    await t.pumpWidget(
      MaterialApp(
        theme: slushTheme(Brightness.light, Colors.blue),
        home: Scaffold(
          body: SlushDesktopHeader(
            searchController: ctrl,
            searchFocus: focus,
            onSearch: searched.add,
            onSession: () => jam++,
            onProfile: (_) => profile++,
            sessionText: 'Iniciar Jam',
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextField), 'luna');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.tap(find.text('Iniciar Jam'));
    await t.tap(find.byType(SlushProfileButton));
    expect(searched, ['luna']);
    expect(jam, 1);
    expect(profile, 1);
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
