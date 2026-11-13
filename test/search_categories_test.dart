import 'dart:async';

import 'package:aurora_music/app_controller.dart';
import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/core/source_backend.dart';
import 'package:aurora_music/main.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Track _t(String id, [String artist = 'Artista']) => Track(
  id: 'yt:$id',
  title: 'Tema $id',
  artist: artist,
  pageUrl: 'https://music.youtube.com/watch?v=$id',
);

Map<String, Object?> _run(String text, [String? pageType]) => {
  'text': text,
  if (pageType != null)
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': pageType},
        },
      },
    },
};

Map<String, Object?> _entryRow(
  String id,
  String type,
  String title,
  String sub,
) => {
  'musicResponsiveListItemRenderer': {
    'navigationEndpoint': {
      'browseEndpoint': {
        'browseId': id,
        'browseEndpointContextSupportedConfigs': {
          'browseEndpointContextMusicConfig': {'pageType': type},
        },
      },
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [_run(title)],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [_run('Álbum'), _run(' • '), _run('Daft Punk')],
          },
        },
      },
    ],
  },
};

Map<String, Object?> _songRow(String id, {bool withArtist = false}) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [_run('Tema $id')],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              if (withArtist)
                _run('Daft Punk', 'MUSIC_PAGE_TYPE_ARTIST')
              else
                _run('1,2 M reproducciones'),
            ],
          },
        },
      },
    ],
    'fixedColumns': [
      {
        'musicResponsiveListItemFixedColumnRenderer': {
          'text': {
            'runs': [_run('3:05')],
          },
        },
      },
    ],
  },
};

class _PagedSource extends FakeSource {
  final tokens = <String?>[];
  final pages = <String?, Completer<SearchPage>>{};
  Completer<List<Track>>? browse;
  final kinds = <SearchKind>[];

  @override
  Future<SearchPage> searchPage(
    String query,
    SearchKind kind, {
    String? continuation,
  }) {
    searchQueries.add(query);
    kinds.add(kind);
    tokens.add(continuation);
    return (pages[continuation ?? query] ??= Completer<SearchPage>()).future;
  }

  @override
  Future<List<Track>> browseTracks(SearchEntry entry) =>
      browse?.future ?? Future.value([_t('b1'), _t('b2')]);
}

void main() {
  group('parsing', () {
    test('album and artist rows become entries with a continuation', () {
      final data = {
        'contents': {
          'sections': [
            _entryRow('MPREb_1', 'MUSIC_PAGE_TYPE_ALBUM', 'Discovery', ''),
            _entryRow('UC_1', 'MUSIC_PAGE_TYPE_ARTIST', 'Daft Punk', ''),
            _entryRow('MPREb_1', 'MUSIC_PAGE_TYPE_ALBUM', 'Discovery', ''),
          ],
          'continuations': [
            {
              'nextContinuationData': {'continuation': 'TOKEN'},
            },
          ],
        },
      };
      final albums = InnerTubeSource.parseSearchPage(data, SearchKind.albums);
      expect(albums.entries.single.browseId, 'MPREb_1');
      expect(albums.entries.single.subtitle, 'Álbum • Daft Punk');
      expect(albums.continuation, 'TOKEN');
      final artists = InnerTubeSource.parseSearchPage(data, SearchKind.artists);
      expect(artists.entries.single.title, 'Daft Punk');
    });

    test('continuation response yields tracks and the next token', () {
      final page = InnerTubeSource.parseSearchPage({
        'continuationContents': {
          'musicShelfContinuation': {
            'contents': [_songRow('abcdefghijk', withArtist: true)],
            'continuations': [
              {
                'nextContinuationData': {'continuation': 'NEXT'},
              },
            ],
          },
        },
      }, SearchKind.songs);
      expect(page.tracks.single.id, 'yt:abcdefghijk');
      expect(page.tracks.single.artist, 'Daft Punk');
      expect(page.continuation, 'NEXT');
      expect(
        InnerTubeSource.parseSearchPage({}, SearchKind.songs).continuation,
        isNull,
      );
    });

    test('album and artist browse rows take header metadata', () {
      final data = {
        'contents': [_songRow('abcdefghijk'), _songRow('lmnopqrstuv')],
      };
      final tracks = InnerTubeSource.parseBrowseTracks(
        data,
        artist: 'Daft Punk',
        album: 'Discovery',
        artwork: 'https://x.test/a.jpg',
      );
      expect(tracks.map((t) => t.id), ['yt:abcdefghijk', 'yt:lmnopqrstuv']);
      expect(tracks.first.artist, 'Daft Punk');
      expect(tracks.first.album, 'Discovery');
      expect(tracks.first.artworkUrl, 'https://x.test/a.jpg');
      expect(tracks.first.duration, const Duration(minutes: 3, seconds: 5));
      expect(
        tracks.first.pageUrl,
        'https://music.youtube.com/watch?v=abcdefghijk',
      );
    });

    test('searchPage posts the category filter and the continuation', () async {
      final bodies = <Map<String, Object?>>[];
      final source = InnerTubeSource(
        FakeSource(),
        post: (endpoint, body) async {
          bodies.add(body);
          return {};
        },
      );
      await source.searchPage('x', SearchKind.albums);
      await source.searchPage('x', SearchKind.albums, continuation: 'T');
      expect(bodies[0]['params'], contains('IYAW'));
      expect(bodies[1]['continuation'], 'T');
      expect(bodies[1].containsKey('query'), isFalse);
    });
  });

  group('controller', () {
    late _PagedSource source;
    late AppController c;
    setUp(() async {
      source = _PagedSource();
      c = await createTestController(source: source);
    });
    tearDown(() => closeTestController(c));

    test('load more follows the continuation and stops without one', () async {
      final first = c.search('daft');
      source.pages['daft']!.complete(
        SearchPage(tracks: [_t('a1'), _t('a2')], continuation: 'C1'),
      );
      await first;
      expect(c.hasMoreSearchResults, isTrue);
      final more = c.loadMoreSearch();
      source.pages['C1']!.complete(SearchPage(tracks: [_t('a2'), _t('a3')]));
      await more;
      expect(c.searchResults.map((t) => t.id), ['yt:a1', 'yt:a2', 'yt:a3']);
      expect(c.hasMoreSearchResults, isFalse);
      await c.loadMoreSearch();
      expect(source.tokens, [null, 'C1']);
    });

    test('a newer query discards a stale response', () async {
      final old = c.search('uno');
      final fresh = c.search('dos');
      source.pages['dos']!.complete(SearchPage(tracks: [_t('b1')]));
      await fresh;
      source.pages['uno']!.complete(SearchPage(tracks: [_t('z1')]));
      await old;
      expect(c.searchResults.single.id, 'yt:b1');
      expect(c.searching, isFalse);
    });

    test('failures are kept apart and results survive a failed page', () async {
      final first = c.search('daft');
      source.pages['daft']!.complete(
        SearchPage(tracks: [_t('a1')], continuation: 'C1'),
      );
      await first;
      final more = c.loadMoreSearch();
      source.pages['C1']!.completeError(StateError('Sin conexión'));
      await more;
      expect(c.searchResults, hasLength(1));
      expect(c.searchError, 'Sin conexión');
      expect(c.hasMoreSearchResults, isTrue);
    });

    test('albums open their tracks, stale details are dropped', () async {
      final search = c.search('daft', kind: SearchKind.albums);
      source.pages['daft']!.complete(
        const SearchPage(
          entries: [
            SearchEntry(
              kind: SearchKind.albums,
              browseId: 'MPREb_1',
              title: 'Discovery',
            ),
          ],
        ),
      );
      await search;
      expect(source.kinds.single, SearchKind.albums);
      expect(c.searchEntries, hasLength(1));
      source.browse = Completer<List<Track>>();
      final stale = c.openSearchEntry(c.searchEntries.first);
      expect(c.searchDetailLoading, isTrue);
      await c.openSearchEntry(null);
      source.browse!.complete([_t('late')]);
      await stale;
      expect(c.searchDetail, isNull);
      expect(c.searchDetailTracks, isEmpty);
      source.browse = null;
      await c.openSearchEntry(c.searchEntries.first);
      expect(c.searchDetailTracks.map((t) => t.id), ['yt:b1', 'yt:b2']);
    });

    test('recent searches keep ten, dedupe, remove and clear', () async {
      for (var i = 0; i < 12; i++) {
        unawaited(c.search('q$i'));
      }
      unawaited(c.search('q5'));
      await Future<void>.delayed(Duration.zero);
      expect(c.recentSearches, hasLength(10));
      expect(c.recentSearches.first, 'q5');
      expect(c.recentSearches.where((q) => q == 'q5'), hasLength(1));
      await c.removeRecentSearch('q5');
      expect(c.recentSearches, isNot(contains('q5')));
      await c.clearRecentSearches();
      expect(c.recentSearches, isEmpty);
    });
  });

  testWidgets('category chips switch at narrow width', (tester) async {
    final source = _PagedSource();
    final c = (await tester.runAsync(
      () => createTestController(source: source),
    ))!;
    addTearDown(() => tester.runAsync(() => closeTestController(c)));
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [controllerProvider.overrideWith((ref) => c)],
        child: const AuroraApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Buscar música').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Canciones'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'daft');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    source.pages['daft']!.complete(SearchPage(tracks: [_t('a1')]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Tema a1'), findsOneWidget);
    await tester.tap(find.text('Álbumes'));
    await tester.pump();
    expect(source.kinds.last, SearchKind.albums);
    expect(c.searchKind, SearchKind.albums);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
