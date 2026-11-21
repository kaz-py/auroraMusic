import 'package:aurora_music/audio/stream_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('guard rejects raw YouTube hosts and allows loopback and files', () {
    for (final bad in [
      'https://music.youtube.com/watch?v=abcdefghijk',
      'https://youtube.com/watch?v=abcdefghijk',
      'https://youtu.be/abcdefghijk',
      'https://rr3---sn-x.googlevideo.com/videoplayback?id=1',
      'https://i.ytimg.com/vi/x/a.jpg',
      'https://yt3.ggpht.com/a',
      'https://YouTube.com/x',
      'https://rr1.googlevideo.com./videoplayback',
      ' https://rr1.googlevideo.com/x',
      'https://[bad.googlevideo.com/x',
    ]) {
      expect(() => assertNotRawYouTube(bad), throwsStateError, reason: bad);
    }
    for (final ok in [
      'http://127.0.0.1:4000/0123456789abcdef0123456789abcdef/a/0123456789abcdef',
      'http://127.0.0.1:4000/aurora-progressive/token',
      r'C:\Music\a.mp3',
      r'C:\Music\youtube.com - x.mp3',
      '/storage/emulated/0/a.mp3',
      'file:///a.mp3',
      'https://example.test/notyoutube.com',
      'https://evilyoutube.com/x',
    ]) {
      assertNotRawYouTube(ok);
    }
  });
}
