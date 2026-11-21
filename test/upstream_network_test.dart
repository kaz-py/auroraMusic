import 'dart:io';

import 'package:aurora_music/sources/stream/upstream_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final yt = Uri.parse('https://music.youtube.com/youtubei/v1/player');
  final cdn = Uri.parse('https://rr1---sn-x.googlevideo.com/videoplayback');
  final loop = Uri.parse('http://127.0.0.1:4000/t/a/x');
  late Map<String, String> saved;

  setUp(() => saved = UpstreamNetwork.environment);
  tearDown(() => UpstreamNetwork.environment = saved);

  test('no proxy configured: everything direct', () {
    UpstreamNetwork.environment = {};
    expect(UpstreamNetwork.findProxy(yt), 'DIRECT');
    expect(UpstreamNetwork.describe(), 'direct');
    expect(UpstreamNetwork.warning(), isNull);
  });

  test('https_proxy routes player and CDN alike, never loopback', () {
    UpstreamNetwork.environment = {'HTTPS_PROXY': 'http://10.0.0.2:3128'};
    expect(UpstreamNetwork.findProxy(yt), 'PROXY 10.0.0.2:3128');
    expect(UpstreamNetwork.findProxy(cdn), 'PROXY 10.0.0.2:3128');
    expect(UpstreamNetwork.findProxy(loop), 'DIRECT');
    expect(UpstreamNetwork.describe(), 'proxy 10.0.0.2:3128');
  });

  test('an http all_proxy is used when the specific ones are unset', () {
    UpstreamNetwork.environment = {'ALL_PROXY': 'http://10.0.0.3:8080'};
    expect(UpstreamNetwork.findProxy(yt), 'PROXY 10.0.0.3:8080');
  });

  test('SOCKS cannot be routed: direct, with a warning', () {
    UpstreamNetwork.environment = {'all_proxy': 'socks5h://10.0.0.4:1080'};
    expect(UpstreamNetwork.findProxy(yt), 'DIRECT');
    expect(UpstreamNetwork.warning(), contains('socks5h://'));
    expect(UpstreamNetwork.describe(), startsWith('direct ('));
  });

  test('no_proxy is kept and credentials never reach the description', () {
    UpstreamNetwork.environment = {
      'https_proxy': 'http://user:secret@10.0.0.5:3128',
      'no_proxy': 'googlevideo.com',
    };
    expect(UpstreamNetwork.findProxy(cdn), 'DIRECT');
    expect(UpstreamNetwork.describe(), isNot(contains('secret')));
  });

  test('client() sends https traffic to the proxy as CONNECT', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final firstLine = server.first.then((socket) async {
      final bytes = await socket.first;
      socket.destroy();
      return String.fromCharCodes(bytes).split('\r\n').first;
    });
    UpstreamNetwork.environment = {
      'https_proxy': 'http://127.0.0.1:${server.port}',
    };
    final client = UpstreamNetwork.client(
      connectionTimeout: const Duration(seconds: 2),
    );
    addTearDown(() => client.close(force: true));
    final request = client.getUrl(yt).then((r) => r.close());
    expect(await firstLine, 'CONNECT music.youtube.com:443 HTTP/1.1');
    await expectLater(request, throwsA(anything));
  });
}
