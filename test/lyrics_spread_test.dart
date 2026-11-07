import 'package:aurora_music/lyrics/lyrics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LyricsService.spreadLines', () {
    test('reparte las líneas no vacías entre el 6 % y el 94 %', () {
      final lines = LyricsService.spreadLines(
        'a\n\nb',
        const Duration(seconds: 100),
      );
      expect(lines.map((l) => l.text), ['a', 'b']);
      expect(lines.map((l) => l.at), [
        const Duration(seconds: 6),
        const Duration(seconds: 50),
      ]);
    });

    test('sin texto o sin duración no hay nada que repartir', () {
      expect(
        LyricsService.spreadLines('', const Duration(seconds: 100)),
        isEmpty,
      );
      expect(
        LyricsService.spreadLines(' \n ', const Duration(seconds: 100)),
        isEmpty,
      );
      expect(LyricsService.spreadLines('a\nb', Duration.zero), isEmpty);
    });
  });
}
