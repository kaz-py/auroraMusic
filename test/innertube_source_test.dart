import 'dart:async';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/dj/recommendations.dart';
import 'package:aurora_music/sources/innertube_source.dart';
import 'package:aurora_music/sources/stream/audio_proxy.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';
import 'package:aurora_music/sources/youtube_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

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

Map<String, Object?> _row(String id, String title, List<Object?> details) => {
  'musicResponsiveListItemRenderer': {
    'playlistItemData': {'videoId': id},
    'thumbnail': {
      'musicThumbnailRenderer': {
        'thumbnail': {
          'thumbnails': [
            {
              'url': 'https://lh3.googleusercontent.com/a=w60-h60-l90-rj',
              'width': 60,
            },
            {
              'url': 'https://lh3.googleusercontent.com/a=w120-h120-l90-rj',
              'width': 120,
            },
            {'url': 'http://insecure.test/big.jpg', 'width': 999},
          ],
        },
      },
    },
    'flexColumns': [
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {
            'runs': [
              {'text': title},
            ],
          },
        },
      },
      {
        'musicResponsiveListItemFlexColumnRenderer': {
          'text': {'runs': details},
        },
      },
    ],
  },
};

// Hand-trimmed from a real WEB_REMIX songs search response.
final _searchFixture = <String, dynamic>{
  'contents': {
    'tabbedSearchResultsRenderer': {
      'tabs': [
        {
          'tabRenderer': {
            'content': {
              'sectionListRenderer': {
                'contents': [
                  {
                    'musicShelfRenderer': {
                      'contents': [
                        _row('19y35jAcG6k', '120', [
                          _run('Bad Bunny', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' • '),
                          _run('EL ÚLTIMO TOUR', 'MUSIC_PAGE_TYPE_ALBUM'),
                          _run(' • '),
                          _run('2:32'),
                        ]),
                        _row('abcdefghijk', 'Dúo', [
                          _run('A', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' & '),
                          _run('B', 'MUSIC_PAGE_TYPE_ARTIST'),
                          _run(' • '),
                          _run('1:02:03'),
                        ]),
                        _row('bad', 'Invalid id', [_run('X')]),
                        _row('19y35jAcG6k', 'Duplicate', [_run('X')]),
                        _row('zyxwvutsrqp', 'Plain', [
                          _run('Uploader'),
                          _run(' • '),
                          _run('3:00'),
                        ]),
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
};

const _song = Track(
  id: 'yt:19y35jAcG6k',
  title: '120',
  artist: 'Bad Bunny',
  duration: Duration(seconds: 152),
  pageUrl: 'https://music.youtube.com/watch?v=19y35jAcG6k',
);

const _other = Track(
  id: 'yt:6geljA2OZSY',
  title: 'Otra',
  artist: 'X',
  duration: Duration(seconds: 100),
);

ResolvedStream _stream({bool expired = false}) => ResolvedStream(
  videoId: '19y35jAcG6k',
  url: Uri.parse('https://rr1.googlevideo.com/videoplayback?x=1'),
  expiresAt: DateTime.now().add(Duration(hours: expired ? -1 : 1)),
  client: 'VISIONOS',
  itag: 7,
);

class _FakeOrch implements StreamOrchestrator {
  final resolved = <String>[];
  final failures = <String>[];
  final forced = <int?>[];
  final blacklisted = <String>{};
  Duration? lastDuration;
  Object? error;
  Object? failOnce;
  final gates = <String, Completer<void>>{};
  @override
  AudioQuality quality = AudioQuality.high;
  @override
  Future<ResolvedStream> resolve(
    String videoId, {
    bool forceRefresh = false,
    Duration? trackDuration,
    int? sameItag,
  }) async {
    if (forceRefresh) forced.add(sameItag);
    resolved.add(videoId);
    lastDuration = trackDuration;
    await gates[videoId]?.future;
    if (failOnce != null) {
      final once = failOnce!;
      failOnce = null;
      throw once;
    }
    if (error != null) throw error!;
    return _stream();
  }

  @override
  void reportFailure(String videoId, {int? httpStatus, String? reason}) =>
      failures.add('$videoId:$httpStatus');
  @override
  bool isBlacklisted(String videoId) => blacklisted.contains(videoId);
}

class _FakeProxy implements AudioProxy {
  Future<ResolvedStream> Function()? refresh;
  void Function(int?, String)? onFailure;
  ResolvedStream? currentStream;
  final unregistered = <String>[];
  bool closed = false;
  @override
  Uri register(
    String videoId,
    ResolvedStream stream, {
    required Future<ResolvedStream> Function() refresh,
    void Function(int? status, String reason)? onFailure,
  }) {
    this.refresh = refresh;
    this.onFailure = onFailure;
    return Uri.parse('http://127.0.0.1:1/tok/a/$videoId');
  }

  bool? served = true;
  @override
  bool? servedToEnd(String videoId) => served;
  @override
  int get activeConnections => 0;
  @override
  int get chunkBytes => 4 << 20;
  @override
  bool Function(Uri target) get allowRedirect =>
      AudioProxy.isGoogleVideoRedirect;
  @override
  Duration get headerTimeout => Duration.zero;
  @override
  Duration get stallTimeout => Duration.zero;
  @override
  ResolvedStream? current(String videoId) => currentStream;
  @override
  void unregister(String videoId) => unregistered.add(videoId);
  @override
  Future<void> close() async => closed = true;
}

void main() {
  test('search parses songs rows into canonical YouTube tracks', () async {
    final requests = <(String, Map<String, Object?>)>[];
    final source = InnerTubeSource(
      FakeSource(),
      post: (endpoint, body) async {
        requests.add((endpoint, body));
        return _searchFixture;
      },
    );
    final tracks = await source.search('  bad bunny ');
    expect(requests.single.$1, 'search');
    expect(requests.single.$2['query'], 'bad bunny');
    expect(requests.single.$2.containsKey('key'), isFalse);
    expect(tracks.map((t) => t.id), [
      'yt:19y35jAcG6k',
      'yt:abcdefghijk',
      'yt:zyxwvutsrqp',
    ]);
    final first = tracks.first;
    expect(first.title, '120');
    expect(first.artist, 'Bad Bunny');
    expect(first.album, 'EL ÚLTIMO TOUR');
    expect(first.duration, const Duration(minutes: 2, seconds: 32));
    expect(
      first.artworkUrl,
      'https://lh3.googleusercontent.com/a=w544-h544-l90-rj',
    );
    expect(first.pageUrl, 'https://music.youtube.com/watch?v=19y35jAcG6k');
    expect(recommendationTrackKeys(first), contains('youtube:19y35jAcG6k'));
    expect(tracks[1].artist, 'A, B');
    expect(
      tracks[1].duration,
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(tracks[2].artist, 'Uploader');
    expect(await source.search('bad bunny', limit: 1), hasLength(1));
  });

  test('search sends links to the delegate and rejects long input', () async {
    final delegate = FakeSource()..searchMatches = [_song];
    var posts = 0;
    final source = InnerTubeSource(
      delegate,
      post: (_, _) async {
        posts++;
        return {};
      },
    );
    expect(await source.search('https://youtu.be/19y35jAcG6k'), [_song]);
    expect(await source.search('   '), isEmpty);
    expect(() => source.search('x' * 501), throwsArgumentError);
    expect(posts, 0);
  });

  test('video ids use the 11-character pattern', () {
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6k'), isTrue);
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6'), isFalse);
    expect(InnerTubeSource.isValidVideoId('19y35jAcG6k/'), isFalse);
    expect(InnerTubeSource.isValidVideoId('../etc/pass'), isFalse);
  });

  test('constructing the source opens no orchestrator or proxy', () {
    var created = 0;
    InnerTubeSource(
      FakeSource(),
      proxyFactory: () async => throw StateError('${++created}'),
      orchestratorFactory: () => throw StateError('${++created}'),
    );
    expect(created, 0);
  });

  test('resolve serves YouTube through the loopback proxy', () async {
    final delegate = FakeSource();
    final orch = _FakeOrch();
    final proxy = _FakeProxy();
    final source = InnerTubeSource(
      delegate,
      proxyFactory: () async => proxy,
      orchestratorFactory: () => orch,
    );
    expect(source.isExpiredStream(_song), isFalse);
    final audio = await source.resolve(_song);
    expect(audio.input, 'http://127.0.0.1:1/tok/a/19y35jAcG6k');
    expect(audio.headers, isEmpty);
    expect(audio.engine, AudioEngine.native);
    expect(audio.duration, _song.duration);
    expect(orch.resolved, ['19y35jAcG6k']);
    expect(orch.lastDuration, _song.duration);

    // Proxy-side failure reports once through the orchestrator.
    proxy.onFailure!(403, 'x');
    expect(orch.failures, ['19y35jAcG6k:403']);
    // Refresh forces a new resolve of the same itag.
    await proxy.refresh!();
    expect(orch.forced, [7]);

    // Playback errors reach the orchestrator, never the yt-dlp delegate.
    source.reportPlaybackFailure('HTTP 410 Gone');
    expect(orch.failures.last, '19y35jAcG6k:410');
    source.reportPlaybackFailure(
      'Error opening input: Server returned 4XX Client Error, but not one of 40{0,1,3,4}',
    );
    expect(orch.failures.last, '19y35jAcG6k:410');
    source.reportPlaybackFailure('premature EOF');
    expect(orch.failures.last, '19y35jAcG6k:null');
    expect(delegate.playbackFailures, isEmpty);

    // Expiry comes from the proxy's current stream, keyed by track id.
    proxy.currentStream = _stream(expired: true);
    expect(source.isExpiredStream(_song), isTrue);
    source.invalidateResolvedAudio(_song);
    expect(orch.failures.last, '19y35jAcG6k:null');
    expect(proxy.unregistered, ['19y35jAcG6k']);

    // Track change unregisters the previous video.
    await source.resolve(_song);
    await source.resolve(_other);
    expect(proxy.unregistered.last, '19y35jAcG6k');

    source.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(proxy.closed, isTrue);
  });

  test(
    'a stream cut before its last byte fails completion as premature EOF',
    () async {
      final proxy = _FakeProxy();
      final source = InnerTubeSource(
        FakeSource(),
        proxyFactory: () async => proxy,
        orchestratorFactory: () => _FakeOrch(),
      );
      final audio = await source.resolve(_song);
      await audio.validateCompletion!(); // served to the end
      proxy.served = null;
      await audio.validateCompletion!(); // unregistered: unknown, trusted
      proxy.served = false;
      await expectLater(
        audio.validateCompletion!(),
        throwsA(predicate((e) => '$e'.contains('Premature EOF'))),
      );
      source.dispose();
    },
  );

  test('blocked videos fall back to the web engine, others rethrow', () async {
    final orch = _FakeOrch();
    final source = InnerTubeSource(
      FakeSource(),
      proxyFactory: () async => _FakeProxy(),
      orchestratorFactory: () => orch,
      webFallback: true,
    );
    orch.blacklisted.add('19y35jAcG6k');
    var audio = await source.resolve(_song);
    expect(audio.engine, AudioEngine.web);
    expect(audio.input, 'https://music.youtube.com/watch?v=19y35jAcG6k');
    orch.blacklisted.clear();
    for (final kind in [
      YouTubeFailure.blocked,
      YouTubeFailure.accessDenied,
      YouTubeFailure.other,
    ]) {
      orch.error = StreamResolveException(kind, 'x');
      audio = await source.resolve(_song);
      expect(audio.engine, AudioEngine.web);
    }
    for (final kind in [YouTubeFailure.transient, YouTubeFailure.unavailable]) {
      orch.error = StreamResolveException(kind, 'x');
      await expectLater(
        source.resolve(_song),
        throwsA(isA<StreamResolveException>()),
      );
    }
    // Prefetch warms the orchestrator only and swallows errors.
    orch.resolved.clear();
    await source.prefetch(_song);
    expect(orch.resolved, ['19y35jAcG6k']);
  });

  test(
    'without web fallback a failure retries natively, then surfaces',
    () async {
      final orch = _FakeOrch();
      final source = InnerTubeSource(
        FakeSource(),
        proxyFactory: () async => _FakeProxy(),
        orchestratorFactory: () => orch,
        webFallback: false,
      );
      orch.blacklisted.add('19y35jAcG6k'); // ignored: no official player
      orch.failOnce = const StreamResolveException(YouTubeFailure.blocked, 'x');
      var audio = await source.resolve(_song);
      expect(audio.engine, AudioEngine.native);
      expect(orch.forced, [null]);
      orch.error = const StreamResolveException(YouTubeFailure.other, 'boom');
      await expectLater(
        source.resolve(_song),
        throwsA(isA<StreamResolveException>()),
      );
      orch.error = null;
      final failing = InnerTubeSource(
        FakeSource(),
        proxyFactory: () async => throw StateError('bind'),
        orchestratorFactory: () => orch,
        webFallback: false,
      );
      await expectLater(failing.resolve(_song), throwsStateError);
      source.dispose();
      failing.dispose();
    },
  );

  test('resolve rejects non-YouTube tracks', () async {
    final delegate = FakeSource();
    final source = InnerTubeSource(delegate);
    await expectLater(
      source.resolve(
        const Track(
          id: 'web:1',
          title: 'Otra',
          artist: 'Sitio',
          pageUrl: 'https://example.test/song',
        ),
      ),
      throwsStateError,
    );
    expect(delegate.resolved, isEmpty);
  });

  test(
    'out-of-order resolves: only the newest unregisters the previous',
    () async {
      final orch = _FakeOrch();
      final proxy = _FakeProxy();
      final source = InnerTubeSource(
        FakeSource(),
        proxyFactory: () async => proxy,
        orchestratorFactory: () => orch,
      );
      await source.resolve(_song);
      orch.gates['6geljA2OZSY'] = Completer();
      final stale = source.resolve(_other); // superseded below
      await Future<void>.delayed(Duration.zero);
      await source.resolve(_song); // newer call, same id as registered
      proxy.unregistered.clear();
      orch.gates['6geljA2OZSY']!.complete();
      await stale;
      expect(proxy.unregistered, isEmpty);
    },
  );

  test('proxy start failure falls back to web and is retried', () async {
    var calls = 0;
    final proxy = _FakeProxy();
    final source = InnerTubeSource(
      FakeSource(),
      proxyFactory: () async {
        if (calls++ == 0) throw StateError('bind');
        return proxy;
      },
      orchestratorFactory: () => _FakeOrch(),
      webFallback: true,
    );
    expect((await source.resolve(_song)).engine, AudioEngine.web);
    expect((await source.resolve(_song)).engine, AudioEngine.native);
  });

  test('prefetch never sets the failure target nor registers', () async {
    final orch = _FakeOrch();
    final proxy = _FakeProxy();
    final source = InnerTubeSource(
      FakeSource(),
      proxyFactory: () async => proxy,
      orchestratorFactory: () => orch,
    );
    await source.prefetch(_song);
    source.reportPlaybackFailure('HTTP 410');
    expect(orch.failures, isEmpty);
    expect(proxy.refresh, isNull);
  });

  test(
    'dispose during an in-flight resolve throws instead of registering',
    () async {
      final orch = _FakeOrch()..gates['19y35jAcG6k'] = Completer();
      final proxy = _FakeProxy();
      final source = InnerTubeSource(
        FakeSource(),
        proxyFactory: () async => proxy,
        orchestratorFactory: () => orch,
      );
      final pending = source.resolve(_song);
      await Future<void>.delayed(Duration.zero);
      source.dispose();
      orch.gates['19y35jAcG6k']!.complete();
      await expectLater(pending, throwsStateError);
      expect(proxy.refresh, isNull);
    },
  );
}
