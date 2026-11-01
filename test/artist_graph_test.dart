import 'dart:convert';

import 'package:aurora_music/dj/artist_graph.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  var clock = DateTime(2026, 10, 27, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    clock = DateTime(2026, 10, 27, 12);
  });

  ArtistGraph graph({
    Future<List<String>> Function(String)? related,
    Future<List<String>> Function(String)? similar,
    Future<List<String>> Function(String)? tags,
  }) => ArtistGraph(
    preferences: prefs,
    youtubeRelated: related,
    lastfmSimilar: similar,
    lastfmTags: tags,
    now: () => clock,
  );

  test('caché: un acierto no vuelve a pedir; tras ttl sí', () async {
    var calls = 0;
    final g = graph(
      related: (a) async {
        calls++;
        return ['Ozuna', 'Anuel AA'];
      },
      tags: (a) async => ['Reggaeton'],
    );
    await g.warm(['Bad Bunny']);
    await g.warm(['bad bunny', 'BAD BUNNY']);
    expect(calls, 1);
    expect(g.neighborsOf('Bad Bunny'), {'ozuna', 'anuel aa'});
    expect(g.tagsOf('Bad Bunny'), ['reggaeton']);
    clock = clock.add(ArtistGraph.ttl + const Duration(minutes: 1));
    await g.warm(['Bad Bunny']);
    expect(calls, 2);
  });

  test(
    'todas las fuentes fallan: vacío y se reintenta tras failureTtl',
    () async {
      var calls = 0;
      final g = graph(
        related: (a) async {
          calls++;
          throw 'sin red';
        },
      );
      await g.warm(['A']);
      expect(g.neighborsOf('A'), isEmpty);
      expect(
        (jsonDecode(prefs.getString(ArtistGraph.prefsKey)!) as Map)['a']['ok'],
        isFalse,
      );
      clock = clock.add(const Duration(minutes: 30));
      await g.warm(['A']);
      expect(calls, 1);
      clock = clock.add(ArtistGraph.failureTtl);
      await g.warm(['A']);
      expect(calls, 2);
    },
  );

  test('sin resultados no es fallo; el error de red sí', () async {
    final g = graph(related: (a) async => const []);
    await g.warm(['A']);
    Map entry() =>
        (jsonDecode(prefs.getString(ArtistGraph.prefsKey)!) as Map)['a'];
    expect(entry()['ok'], isTrue);
    clock = clock.add(ArtistGraph.ttl + const Duration(minutes: 1));
    await graph(related: (a) async => throw 'sin red').warm(['A']);
    expect(entry()['ok'], isFalse);
  });

  test('Last.fm inactivo: conserva etiquetas y marca fallo', () async {
    var active = true;
    final g = graph(
      tags: (a) async => active ? ['Rock'] : throw StateError('inactivo'),
    );
    await g.warm(['A']);
    expect(g.tagsOf('A'), ['rock']);
    active = false;
    clock = clock.add(ArtistGraph.ttl + const Duration(minutes: 1));
    await g.warm(['A']);
    expect(g.tagsOf('A'), ['rock']);
    final e = (jsonDecode(prefs.getString(ArtistGraph.prefsKey)!) as Map)['a'];
    expect(e['ok'], isFalse);
    clock = clock.add(ArtistGraph.failureTtl);
    active = true;
    await g.warm(['A']);
    expect(g.tagsOf('A'), ['rock']);
  });

  test('warm corta al presupuesto', () async {
    final g = graph(
      related: (a) => Future.delayed(const Duration(seconds: 1), () => ['X']),
    );
    final watch = Stopwatch()..start();
    await g.warm(['A'], budget: const Duration(milliseconds: 50));
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
    expect(g.neighborsOf('A'), isEmpty);
  });

  test('co-escucha: hacen falta al menos 2 apariciones', () async {
    final g = graph();
    g.learnCoListened('A', ['B', 'B', 'C', 'A', 'A']);
    expect(g.neighborsOf('a'), {'b'});
    g.learnCoListened('A', ['D', 'd']);
    expect(g.neighborsOf('a'), {'b', 'd'}, reason: 'nunca quita vecinos');
  });

  test('co-escucha no impide pedir las fuentes', () async {
    var calls = 0;
    final g = graph(
      related: (a) async {
        calls++;
        return ['C'];
      },
    );
    g.learnCoListened('A', ['B', 'B']);
    await g.warm(['A']);
    expect(calls, 1);
    expect(g.neighborsOf('A'), {'b', 'c'});
  });

  test('poda las entradas más viejas por encima de maxEntries', () {
    final g = graph();
    for (var i = 0; i < ArtistGraph.maxEntries + 5; i++) {
      clock = clock.add(const Duration(seconds: 1));
      g.learnCoListened('artista $i', ['x', 'x']);
    }
    final saved = jsonDecode(prefs.getString(ArtistGraph.prefsKey)!) as Map;
    expect(saved, hasLength(ArtistGraph.maxEntries));
    expect(saved.containsKey('artista 0'), isFalse);
    expect(saved.containsKey('artista ${ArtistGraph.maxEntries + 4}'), isTrue);
  });

  test('guardar y cargar conserva vecinos y etiquetas', () async {
    await graph(
      similar: (a) async => ['Beyoncé'],
      tags: (a) async => ['pop'],
    ).warm(['Rihanna']);
    final reloaded = graph();
    expect(reloaded.neighborsOf('rihanna'), {'beyonce'});
    expect(reloaded.tagsOf('Rihanna'), ['pop']);
  });
}
