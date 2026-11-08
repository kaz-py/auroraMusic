import 'dart:async';
import 'dart:io';

import 'package:aurora_music/core/models.dart';
import 'package:aurora_music/sources/web_music_source.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const youtubeTrack = Track(
  id: 'yt:abcdefghijk',
  title: 'Song',
  artist: 'Artist',
  pageUrl: 'https://www.youtube.com/watch?v=abcdefghijk',
);

class _VideoUtility extends FakeSource {
  int audioDownloads = 0;
  int listings = 0;
  Uri? videoUrl;
  File? videoDestination;
  String? videoJob;
  int updates = 0;

  @override
  Future<List<Track>> importPlaylist(Uri url) async {
    listings++;
    return [];
  }

  @override
  Future<File> download(
    Track track,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    audioDownloads++;
    return destination;
  }

  @override
  Future<void> downloadVideo(
    Uri url,
    File destination, {
    required String jobId,
    void Function(double)? onProgress,
  }) async {
    videoUrl = url;
    videoDestination = destination;
    videoJob = jobId;
    onProgress?.call(1);
  }

  @override
  Future<void> checkForUpdates() async => updates++;
}

class _MediaClient extends Fake implements HttpClient {
  _MediaClient(this.responses);
  final List<_MediaResponse> responses;
  final List<Uri> requests = [];
  bool closed = false;
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requests.add(url);
    return _MediaRequest(responses.removeAt(0));
  }

  @override
  void close({bool force = false}) => closed = true;
}

class _MediaRequest extends Fake implements HttpClientRequest {
  _MediaRequest(this.response);
  final _MediaResponse response;
  @override
  bool followRedirects = true;
  @override
  Future<HttpClientResponse> close() async {
    expect(followRedirects, isFalse);
    return response;
  }
}

class _MediaHeaders extends Fake implements HttpHeaders {
  _MediaHeaders(this.location);
  final String? location;
  @override
  String? value(String name) => location;
}

class _MediaResponse extends Stream<List<int>> implements HttpClientResponse {
  _MediaResponse({this.location, this.bytes = const [1, 2, 3]});
  final String? location;
  final List<int> bytes;
  @override
  int get statusCode => location == null ? HttpStatus.ok : HttpStatus.found;
  @override
  bool get isRedirect => location != null;
  @override
  int get contentLength => bytes.length;
  @override
  HttpHeaders get headers => _MediaHeaders(location);
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(bytes).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native media downloads use HTTPS directly without yt-dlp and refuse YouTube redirects',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'web_native_download_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final utility = _VideoUtility();
      final source = WebMusicSource(utility);
      const radio = Track(
        id: 'radio',
        title: 'Radio',
        artist: 'Station',
        pageUrl: 'https://radio.example.test/live.mp3',
      );
      final client = _MediaClient([
        _MediaResponse(bytes: [1, 2, 3]),
      ]);
      final destination = File('${directory.path}/radio.mp3');
      await HttpOverrides.runZoned(
        () => source.download(radio, destination, jobId: 'radio'),
        createHttpClient: (_) => client,
      );
      expect(await destination.readAsBytes(), [1, 2, 3]);
      expect(client.closed, isTrue);
      expect(await directory.list().length, 1);
      for (final redirect in [
        'https://rr1.googlevideo.com/videoplayback?signature=secret',
        'https://music.youtube.com/watch?v=abcdefghijk',
        'http://radio.example.test/live.mp3',
        'https://name:secret@radio.example.test/live.mp3',
      ]) {
        final redirected = _MediaClient([_MediaResponse(location: redirect)]);
        await HttpOverrides.runZoned(
          () => expectLater(
            source.download(
              radio,
              File('${directory.path}/blocked.mp3'),
              jobId: 'blocked',
            ),
            throwsStateError,
          ),
          createHttpClient: (_) => redirected,
        );
        expect(redirected.requests.length, 1);
        expect(redirected.closed, isTrue);
      }
      expect(utility.audioDownloads, 0);
      expect(utility.resolved, isEmpty);
      expect(await File('${directory.path}/blocked.mp3').exists(), isFalse);
      await expectLater(
        source.download(radio, destination, jobId: 'existing'),
        throwsStateError,
      );
      expect(await destination.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'official mode blocks all YouTube extraction, listing, and audio downloads',
    () async {
      final utility = _VideoUtility();
      final source = WebMusicSource(utility);
      final directory = await Directory.systemTemp.createTemp(
        'web_music_source_',
      );
      addTearDown(() => directory.delete(recursive: true));
      expect(source.usesOfficialYouTubeMusic, isTrue);
      expect(source.supportsPlaybackCache, isFalse);
      expect(source.supportsExperimentalProgressivePlayback, isFalse);
      for (final track in [
        youtubeTrack,
        youtubeTrack.copyWith(localPath: '${directory.path}/missing.mp3'),
        const Track(
          id: 'old',
          title: 'Old',
          artist: 'Artist',
          pageUrl: 'https://rr1.googlevideo.com/videoplayback?signature=secret',
        ),
        const Track(
          id: 'spoof',
          title: 'Bad',
          artist: 'Artist',
          pageUrl: 'https://name:secret@example.test/song.mp3',
        ),
      ]) {
        await expectLater(source.resolve(track), throwsStateError);
        await expectLater(
          source.download(
            track,
            File('${directory.path}/audio.mp3'),
            jobId: 'audio',
          ),
          throwsStateError,
        );
      }
      expect(await source.search('Artist songs'), isEmpty);
      await expectLater(
        source.importPlaylist(
          Uri.https('music.youtube.com', '/playlist', {'list': 'PLabc'}),
        ),
        throwsUnsupportedError,
      );
      expect(utility.resolved, isEmpty);
      expect(utility.searchQueries, isEmpty);
      expect(utility.listings, 0);
      expect(utility.audioDownloads, 0);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'historical local YouTube audio and non-YouTube media stay native',
    () async {
      final utility = _VideoUtility();
      final source = WebMusicSource(utility);
      final directory = await Directory.systemTemp.createTemp(
        'web_music_local_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/historical.mp3',
      ).writeAsBytes([1]);
      final local = youtubeTrack.copyWith(localPath: file.path);
      expect(WebMusicSource.isOnlineYouTube(local), isFalse);
      expect((await source.resolve(local)).input, file.path);
      expect(
        (await source.resolve(
          const Track(
            id: 'radio',
            title: 'Radio',
            artist: 'Station',
            pageUrl: 'https://radio.example.test/live.mp3',
          ),
        )).input,
        'https://radio.example.test/live.mp3',
      );
      expect(utility.resolved, isEmpty);
    },
  );

  test(
    'explicit video downloads and tool updates reach delegated utility',
    () async {
      final utility = _VideoUtility();
      final source = WebMusicSource(utility);
      final url = Uri.parse(youtubeTrack.pageUrl!);
      final destination = File('video.mp4');
      double progress = 0;
      await source.downloadVideo(
        url,
        destination,
        jobId: 'video',
        onProgress: (value) => progress = value,
      );
      await source.checkForUpdates();
      expect(utility.videoUrl, url);
      expect(utility.videoDestination, destination);
      expect(utility.videoJob, 'video');
      expect(progress, 1);
      expect(utility.updates, 1);
      expect(utility.audioDownloads, 0);
      expect(FakeSource().usesOfficialYouTubeMusic, isFalse);
      await expectLater(
        FakeSource().downloadVideo(url, destination, jobId: 'unsupported'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'official navigation maps videos and playlists and discards secrets',
    () {
      for (final input in [
        'https://youtu.be/abcdefghijk?si=secret&t=20',
        'https://www.youtube.com/watch?v=abcdefghijk&signature=secret',
        'https://m.youtube.com/shorts/abcdefghijk',
        'https://youtube.com/embed/abcdefghijk',
      ]) {
        expect(
          WebMusicSource.officialUri(Uri.parse(input)).toString(),
          'https://music.youtube.com/watch?v=abcdefghijk',
        );
      }
      expect(
        WebMusicSource.officialUri(
          Uri.parse('https://www.youtube.com/playlist?list=PL_abc&auth=secret'),
        ).toString(),
        'https://music.youtube.com/playlist?list=PL_abc',
      );
      expect(
        WebMusicSource.officialUri(
          Uri.parse('https://youtu.be/abcdefghijk?list=PL_abc'),
        ).queryParameters,
        {'v': 'abcdefghijk', 'list': 'PL_abc'},
      );
      expect(WebMusicSource.officialUri(), WebMusicSource.home);
      for (final input in [
        'http://youtube.com/watch?v=abcdefghijk',
        'https://username:secret@music.youtube.com/watch?v=abcdefghijk',
        'https://music.youtube.com.evil.test/watch?v=abcdefghijk',
        'https://music.youtube.com:444/watch?v=abcdefghijk',
        'https://rr1.googlevideo.com/videoplayback?signature=secret',
        'https://youtube.com/watch?v=invalid',
        'https://youtube.com/playlist?list=..%2Fsecret',
      ]) {
        expect(
          () => WebMusicSource.officialUri(Uri.parse(input)),
          throwsArgumentError,
        );
      }
      expect(
        WebMusicSource.uriForTrack(
          const Track(
            id: 'old',
            title: 'Old',
            artist: 'Artist',
            pageUrl:
                'https://rr1.googlevideo.com/videoplayback?signature=secret',
          ),
        ),
        WebMusicSource.home,
      );
    },
  );
}
