import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/jam/jam_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track _t(int i) => Track(id: 'yt:t$i', title: 'Canción $i', artist: 'Artista');

/// 3 páginas de 20 pistas, con una repetida al principio de la segunda.
class _PagedSource extends FakeSource {
  final tokens = <String?>[];
  bool failNext = false;

  @override
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) async {
    tokens.add(continuation);
    if (failNext && continuation != null) throw StateError('sin red');
    final page = continuation == null ? 0 : int.parse(continuation);
    return SearchPage(
      tracks: [
        for (var i = page * 20 - (page > 0 ? 1 : 0); i < page * 20 + 20; i++)
          _t(i),
      ],
      continuation: page < 2 ? '${page + 1}' : null,
    );
  }
}

void main() {
  test('«Añadir» pide más páginas, sin repetidas, hasta agotarlas', () async {
    final source = _PagedSource();
    final app = await createTestController(source: source);
    addTearDown(() => closeTestController(app));
    final jam = JamController(app: app);

    await jam.search('rock');
    expect(jam.results, hasLength(20));
    expect(jam.hasMoreResults, isTrue);

    await jam.loadMoreResults();
    await jam.loadMoreResults();
    expect(jam.results, hasLength(60));
    expect({for (final t in jam.results) t.id}, hasLength(60));
    expect(jam.hasMoreResults, isFalse);

    // Sin más páginas no vuelve a preguntar.
    await jam.loadMoreResults();
    expect(source.tokens, [null, '1', '2']);
  });

  test(
    'un fallo al paginar no se reintenta en bucle; otra búsqueda lo rearma',
    () async {
      final source = _PagedSource();
      final app = await createTestController(source: source);
      addTearDown(() => closeTestController(app));
      final jam = JamController(app: app);

      await jam.search('rock');
      source.failNext = true;
      await jam.loadMoreResults();
      expect(jam.results, hasLength(20));
      expect(jam.hasMoreResults, isFalse);
      await jam.loadMoreResults();
      expect(source.tokens, [null, '1']);

      source.failNext = false;
      await jam.search('rock');
      expect(jam.hasMoreResults, isTrue);
    },
  );
}
