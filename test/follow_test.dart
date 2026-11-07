import 'dart:async';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/follow/follow_boost.dart';
import 'package:aurora_music/follow/follow_models.dart';
import 'package:aurora_music/follow/follow_repository.dart';
import 'package:aurora_music/follow/follow_service.dart';
import 'package:aurora_music/library/library_database.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ArtistRelease _rel(String id, {int year = 2024, String kind = 'Sencillo'}) =>
    ArtistRelease(id: id, title: 'Título $id', kind: kind, year: year);

void main() {
  group('migración', () {
    test('v2 -> v3 conserva los datos y añade las tablas de seguidos', () async {
      final db = LibraryDatabase(
        NativeDatabase.memory(
          setup: (raw) {
            // Esquema real de la versión 2.
            raw.execute(
              'CREATE TABLE tracks (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
            );
            raw.execute('CREATE TABLE favorites (track_id TEXT PRIMARY KEY)');
            raw.execute(
              'CREATE TABLE playlists (id TEXT PRIMARY KEY, name TEXT NOT NULL, tracks TEXT NOT NULL)',
            );
            raw.execute(
              'CREATE TABLE history (track_id TEXT PRIMARY KEY, played_at INTEGER NOT NULL)',
            );
            raw.execute(
              'CREATE TABLE downloads (id TEXT PRIMARY KEY, data TEXT NOT NULL)',
            );
            raw.execute(
              'CREATE TABLE track_vectors (track_key TEXT PRIMARY KEY, track TEXT NOT NULL, '
              'dims INTEGER NOT NULL, vector BLOB NOT NULL, updated_at INTEGER NOT NULL)',
            );
            raw.execute(
              'CREATE TABLE taste_profile (id INTEGER PRIMARY KEY CHECK (id = 1), '
              'dims INTEGER NOT NULL, vector BLOB NOT NULL, updated_at INTEGER NOT NULL)',
            );
            raw.execute(
              "INSERT INTO tracks VALUES ('t1', '{\"id\":\"t1\",\"title\":\"Canción\",\"artist\":\"Ana\"}')",
            );
            raw.execute("INSERT INTO favorites VALUES ('t1')");
            raw.execute(
              "INSERT INTO playlists VALUES ('p1','Lista','[\"t1\"]')",
            );
            raw.execute('PRAGMA user_version = 2');
          },
        ),
      );
      addTearDown(db.close);

      expect((await db.readTracks()).single.title, 'Canción');
      expect(await db.readFavorites(), {'t1'});
      expect((await db.readPlaylists()).single.trackIds, ['t1']);
      expect(await db.countTrackVectors(), 0);

      final repo = FollowRepository(db);
      expect(await repo.list(), isEmpty);
      await repo.follow('UC1', 'Ana');
      expect((await repo.list()).single.name, 'Ana');
      // Los datos viejos siguen ahí tras usar las tablas nuevas.
      expect(await db.readFavorites(), {'t1'});
    });

    test('una base nueva ya trae las tablas', () async {
      final db = LibraryDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      expect(await FollowRepository(db).list(), isEmpty);
      expect(await FollowRepository(db).news(), isEmpty);
    });
  });

  group('repositorio', () {
    late LibraryDatabase db;
    late FollowRepository repo;
    setUp(() {
      db = LibraryDatabase(NativeDatabase.memory());
      repo = FollowRepository(db);
    });
    tearDown(() async {
      await repo.close();
      await db.close();
    });

    test(
      'seguir es idempotente y dejar de seguir borra sus novedades',
      () async {
        await repo.follow('UC1', 'Ana', imageUrl: 'https://x/a.jpg');
        await repo.follow('UC1', 'Otro nombre');
        var list = await repo.list();
        expect(list, hasLength(1));
        expect(list.single.name, 'Ana');
        expect(list.single.imageUrl, 'https://x/a.jpg');
        expect(list.single.checkedAt, isNull);

        await repo.addNews([
          NewRelease(
            id: 'MPREb_1',
            artistId: 'UC1',
            artistName: 'Ana',
            title: 'Nuevo',
            subtitle: 'Sencillo • Ana • 2026',
            detectedAt: DateTime(2026),
          ),
        ]);
        expect(await repo.news(), hasLength(1));
        await repo.unfollow('UC1');
        list = await repo.list();
        expect(list, isEmpty);
        expect(await repo.news(), isEmpty);
      },
    );

    test('watch emite la lista actual y después los cambios', () async {
      final emitted = <List<String>>[];
      final sub = repo.watch().listen(
        (l) => emitted.add([for (final a in l) a.name]),
      );
      await pumpEventQueue();
      await repo.follow('UC1', 'Ana');
      await pumpEventQueue();
      await repo.unfollow('UC1');
      await pumpEventQueue();
      await sub.cancel();
      expect(emitted, [
        <String>[],
        ['Ana'],
        <String>[],
      ]);
    });

    test('guarda la línea base y los lanzamientos conocidos', () async {
      await repo.follow('UC1', 'Ana');
      final artist = (await repo.list()).single;
      await repo.saveCheck(
        artist.copyWith(
          knownReleases: {'a', 'b'},
          lastReleaseId: 'a',
          lastReleaseTitle: 'Título a',
          checkedAt: DateTime(2026, 1, 2),
        ),
      );
      final saved = (await repo.list()).single;
      expect(saved.knownReleases, {'a', 'b'});
      expect(saved.lastReleaseTitle, 'Título a');
      expect(saved.checkedAt, DateTime(2026, 1, 2));
    });
  });

  group('servicio de novedades (InnerTube simulado)', () {
    late LibraryDatabase db;
    late FollowService service;
    late DateTime clock;
    late Map<String, Object> pages; // browseId -> ArtistPage | Exception
    late List<String> fetched;
    late List<SearchEntry> searchHits;

    FollowService build({
      Duration timeout = const Duration(seconds: 5),
      Future<ArtistPage> Function(String id)? fetch,
    }) => FollowService(
      repository: FollowRepository(db),
      now: () => clock,
      timeout: timeout,
      fetchArtist:
          fetch ??
          (id) async {
            fetched.add(id);
            final page = pages[id];
            if (page is Exception) throw page;
            return page as ArtistPage? ?? const ArtistPage();
          },
      findArtist: (_) async => searchHits,
    );

    setUp(() {
      db = LibraryDatabase(NativeDatabase.memory());
      clock = DateTime(2026, 10, 1, 9);
      pages = {};
      fetched = [];
      searchHits = [];
      service = build();
    });
    tearDown(() async {
      service.dispose();
      await db.close();
    });

    test('la primera consulta fija la línea base y no anuncia nada', () async {
      pages['UC1'] = ArtistPage(releases: [_rel('A'), _rel('B', year: 2020)]);
      await service.follow('Ana', browseId: 'UC1');
      await pumpEventQueue();
      expect(service.news, isEmpty);
      final artist = service.artists.single;
      expect(artist.knownReleases, {'A', 'B'});
      expect(artist.lastReleaseId, 'A');
      expect(artist.checkedAt, clock);
    });

    test(
      'detecta un lanzamiento nuevo, no lo repite y respeta las 12 h',
      () async {
        pages['UC1'] = ArtistPage(releases: [_rel('A')]);
        await service.follow('Ana', browseId: 'UC1');
        await pumpEventQueue();
        fetched.clear();

        clock = clock.add(const Duration(hours: 5));
        pages['UC1'] = ArtistPage(releases: [_rel('N'), _rel('A')]);
        await service.refreshIfDue();
        expect(fetched, isEmpty, reason: 'aún no han pasado 12 h');
        expect(service.news, isEmpty);

        clock = clock.add(const Duration(hours: 8));
        await service.refreshIfDue();
        expect(fetched, ['UC1']);
        expect(service.news.map((n) => n.id), ['N']);
        final news = service.news.single;
        expect(news.subtitle, 'Sencillo • Ana • 2024');
        expect(news.entry.kind, SearchKind.albums);
        expect(news.entry.browseId, 'N');

        // Misma página 13 h después: nada repetido.
        clock = clock.add(const Duration(hours: 13));
        await service.refreshIfDue();
        expect(fetched, ['UC1', 'UC1']);
        expect(service.news, hasLength(1));

        // Descartada, no vuelve aunque la página siga mostrándola.
        await service.dismissNews();
        clock = clock.add(const Duration(hours: 13));
        await service.refreshIfDue();
        expect(service.news, isEmpty);
      },
    );

    test('las novedades sobreviven a reabrir la app', () async {
      pages['UC1'] = ArtistPage(releases: [_rel('A')]);
      await service.follow('Ana', browseId: 'UC1');
      await pumpEventQueue();
      clock = clock.add(const Duration(hours: 13));
      pages['UC1'] = ArtistPage(releases: [_rel('N'), _rel('A')]);
      await service.refreshIfDue();

      final reopened = build();
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.news.map((n) => n.id), ['N']);
      expect(reopened.artists.single.knownReleases, containsAll(['A', 'N']));
    });

    test('un artista que falla no impide a los demás y se reintenta', () async {
      pages['UC1'] = ArtistPage(releases: [_rel('A')]);
      pages['UC2'] = ArtistPage(releases: [_rel('X')]);
      await service.follow('Ana', browseId: 'UC1');
      await service.follow('Beto', browseId: 'UC2');
      await pumpEventQueue();

      clock = clock.add(const Duration(hours: 13));
      pages['UC1'] = StateError('Sin conexión con YouTube Music.');
      pages['UC2'] = ArtistPage(releases: [_rel('Y'), _rel('X')]);
      await service.refreshIfDue();
      expect(service.news.map((n) => n.id), ['Y']);
      final ana = service.artists.firstWhere((a) => a.browseId == 'UC1');
      expect(ana.checkedAt, isNot(clock), reason: 'sigue pendiente');

      pages['UC1'] = ArtistPage(releases: [_rel('Z'), _rel('A')]);
      await service.refreshIfDue();
      expect(service.news.map((n) => n.id).toSet(), {'Y', 'Z'});
    });

    test('un timeout cuenta como fallo, no cuelga la consulta', () async {
      final slow = build(
        fetch: (_) => Completer<ArtistPage>().future,
        timeout: const Duration(milliseconds: 20),
      );
      addTearDown(slow.dispose);
      await slow.repository.follow('UC1', 'Ana');
      await slow.load();
      await slow.refreshIfDue().timeout(const Duration(seconds: 2));
      expect(slow.checking, isFalse);
      expect(slow.news, isEmpty);
    });

    test('limita la concurrencia a 3 peticiones a la vez', () async {
      var inFlight = 0, peak = 0;
      final busy = build(
        fetch: (id) async {
          inFlight++;
          if (inFlight > peak) peak = inFlight;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          inFlight--;
          return const ArtistPage();
        },
      );
      addTearDown(busy.dispose);
      for (var i = 0; i < 8; i++) {
        await busy.repository.follow('UC$i', 'Artista $i');
      }
      await busy.load();
      await busy.refreshIfDue();
      expect(peak, 3);
      expect(busy.artists.every((a) => a.checkedAt != null), isTrue);
    });

    test(
      'seguir por nombre busca al artista; sin coincidencia falla',
      () async {
        searchHits = const [
          SearchEntry(
            kind: SearchKind.artists,
            browseId: 'UCwrong',
            title: 'Otra Persona',
          ),
          SearchEntry(
            kind: SearchKind.artists,
            browseId: 'UCana',
            title: 'Ana Núñez',
            artworkUrl: 'https://x/ana.jpg',
          ),
        ];
        final followed = await service.follow('ana nunez');
        expect(followed.browseId, 'UCana');
        expect(followed.name, 'Ana Núñez');
        expect(service.isFollowingName('Ana Núñez - Topic'), isTrue);
        await pumpEventQueue();

        await expectLater(service.follow('Nadie'), throwsStateError);
        expect(service.artists, hasLength(1));
      },
    );

    test('dejar de seguir quita al artista y sus novedades', () async {
      pages['UC1'] = ArtistPage(releases: [_rel('A')]);
      await service.follow('Ana', browseId: 'UC1');
      await pumpEventQueue();
      clock = clock.add(const Duration(hours: 13));
      pages['UC1'] = ArtistPage(releases: [_rel('N'), _rel('A')]);
      await service.refreshIfDue();
      expect(service.news, hasLength(1));
      await service.unfollow('UC1');
      expect(service.artists, isEmpty);
      expect(service.news, isEmpty);
      expect(service.followedArtistKeys, isEmpty);
    });
  });

  group('refuerzo del DJ', () {
    test('solo suma a pistas del artista seguido (sin acentos ni «Topic»)', () {
      final keys = {'ana núñez', 'ana nunez'};
      Track t(String artist) => Track(id: artist, title: 'x', artist: artist);
      expect(followedArtistBonus(t('Ana Núñez'), keys), followedArtistBoost);
      expect(
        followedArtistBonus(t('Ana Núñez, Otro'), keys),
        followedArtistBoost,
      );
      expect(followedArtistBonus(t('Otro, Ana Núñez'), keys), 0);
      expect(followedArtistBonus(t('Desconocido'), keys), 0);
      expect(followedArtistBonus(t('Ana Núñez'), const {}), 0);
    });
  });

  group('página de artista de YouTube Music', () {
    Map<String, Object?> two(
      String id,
      String title,
      List<String> sub, {
      String page = 'MUSIC_PAGE_TYPE_ALBUM',
    }) => {
      'musicTwoRowItemRenderer': {
        'title': {
          'runs': [
            {'text': title},
          ],
        },
        'subtitle': {
          'runs': [
            for (final s in sub) {'text': s},
          ],
        },
        'navigationEndpoint': {
          'browseEndpoint': {
            'browseId': id,
            'browseEndpointContextSupportedConfigs': {
              'browseEndpointContextMusicConfig': {'pageType': page},
            },
          },
        },
        'thumbnailRenderer': {
          'musicThumbnailRenderer': {
            'thumbnail': {
              'thumbnails': [
                {
                  'url': 'https://lh3.googleusercontent.com/a=w226-h226',
                  'width': 226,
                },
              ],
            },
          },
        },
      },
    };

    test('extrae nombre, imagen y solo álbumes/sencillos', () {
      final page = InnerTubeSource.parseArtistPage({
        'header': {
          'musicImmersiveHeaderRenderer': {
            'title': {
              'runs': [
                {'text': 'Ana Núñez'},
              ],
            },
            'thumbnail': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [
                    {
                      'url': 'https://lh3.googleusercontent.com/h=w500-h500',
                      'width': 500,
                    },
                  ],
                },
              },
            },
          },
        },
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'musicCarouselShelfRenderer': {
                            'contents': [
                              two('MPREb_a', 'Disco', ['Álbum', ' • ', '2023']),
                              two('MPREb_b', 'Suelto', [
                                'Sencillo',
                                ' • ',
                                '2026',
                              ]),
                              two('MPREb_b', 'Duplicado', ['2026']),
                              two('UCotro', 'Fans', [
                                'Artista',
                              ], page: 'MUSIC_PAGE_TYPE_ARTIST'),
                              two('PL1', 'Lista', [
                                'Lista',
                              ], page: 'MUSIC_PAGE_TYPE_PLAYLIST'),
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      });
      expect(page.name, 'Ana Núñez');
      expect(page.imageUrl, contains('w544-h544'));
      expect(page.releases.map((r) => r.id), ['MPREb_a', 'MPREb_b']);
      expect(page.releases[0].kind, 'Álbum');
      expect(page.releases[0].year, 2023);
      expect(page.releases[1].kind, 'Sencillo');
      expect(page.releases[1].year, 2026);
    });

    test('una respuesta inesperada da una página vacía, no un error', () {
      final page = InnerTubeSource.parseArtistPage({'contents': 'nada'});
      expect(page.releases, isEmpty);
      expect(page.name, isNull);
    });

    // Forma real (sondeo de «Bad Bunny», 2026-10): carrusel «Puede que
    // también te guste» con filas de tipo artista; «Destacado en» son listas.
    test('extrae los artistas afines sin duplicados', () {
      final page = InnerTubeSource.parseArtistPage({
        'contents': {
          'singleColumnBrowseResultsRenderer': {
            'tabs': [
              {
                'tabRenderer': {
                  'content': {
                    'sectionListRenderer': {
                      'contents': [
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [
                                    {'text': 'Destacado en'},
                                  ],
                                },
                              },
                            },
                            'contents': [
                              two('VLPL1', 'Lista', [
                                'Lista',
                              ], page: 'MUSIC_PAGE_TYPE_PLAYLIST'),
                            ],
                          },
                        },
                        {
                          'musicCarouselShelfRenderer': {
                            'header': {
                              'musicCarouselShelfBasicHeaderRenderer': {
                                'title': {
                                  'runs': [
                                    {'text': 'Puede que también te guste'},
                                  ],
                                },
                              },
                            },
                            'contents': [
                              for (final n in ['Ozuna', 'Anuel AA', 'Lunay'])
                                two('UC$n', n, [
                                  '1 M de suscriptores',
                                ], page: 'MUSIC_PAGE_TYPE_ARTIST'),
                              two('UCdup', 'Ozuna', [
                                '',
                              ], page: 'MUSIC_PAGE_TYPE_ARTIST'),
                            ],
                          },
                        },
                      ],
                    },
                  },
                },
              },
            ],
          },
        },
      });
      expect(page.relatedArtists, ['Ozuna', 'Anuel AA', 'Lunay']);
      expect(page.releases, isEmpty);
    });
  });
}
