import 'package:aurora_music/lastfm/lastfm_stats.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('artistTopTags: count >= 10, sin etiquetas de ruido, máx. 5', () {
    final tags = LfmParser.artistTopTags({
      'toptags': {
        'tag': [
          {'name': 'Reggaeton', 'count': 100},
          {'name': 'seen live', 'count': 90},
          {'name': 'Latin', 'count': '60'},
          {'name': 'Favorites', 'count': 50},
          {'name': 'urbano latino', 'count': 40},
          {'name': 'trap latino', 'count': 30},
          {'name': 'pop', 'count': 20},
          {'name': 'dembow', 'count': 15},
          {'name': 'raro', 'count': 9},
        ],
      },
    });
    expect(tags, ['reggaeton', 'latin', 'urbano latino', 'trap latino', 'pop']);
  });

  test('artistTopTags: una sola etiqueta como objeto y forma inesperada', () {
    expect(
      LfmParser.artistTopTags({
        'toptags': {
          'tag': {'name': 'Rock', 'count': 100},
        },
      }),
      ['rock'],
    );
    expect(LfmParser.artistTopTags({'error': 6}), isEmpty);
  });
}
