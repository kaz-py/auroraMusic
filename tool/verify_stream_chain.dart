// ignore_for_file: avoid_print
// Manual end-to-end check (real network, not run in CI) of the playback chain:
// StreamOrchestrator → AudioProxy (loopback) → first bytes, for several
// tracks in a row with one shared orchestrator and proxy, as the app does.
//
// Usage: dart run tool/verify_stream_chain.dart [--relay] [--check-ip] [id...]
//   --relay     route all upstream traffic through an in-process CONNECT
//               relay that records each destination: proves the player call
//               and googlevideo both leave by the configured proxy route.
//   --check-ip  print the egress IP (api.ipify.org) via the route and direct.
// The route otherwise comes from https_proxy/http_proxy/all_proxy/no_proxy.
// Exit code 0 only if every track starts and (with --relay) both hosts were
// seen at the relay.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/sources/stream/audio_proxy.dart';
import 'package:aurora_music/sources/stream/resolved_stream.dart';
import 'package:aurora_music/sources/stream/stream_orchestrator.dart';
import 'package:aurora_music/sources/stream/upstream_network.dart';

const _defaultIds = [
  'dQw4w9WgXcQ',
  'kJQP7kiw5Fk',
  'fJ9rUzIMcZQ',
  'hTWKbfoikeg',
  '9bZkp7q19f0',
];
const _firstBytes = 256 * 1024;

Future<void> main(List<String> args) async {
  final relayMode = args.contains('--relay');
  final checkIp = args.contains('--check-ip');
  final ids = args.where((a) => !a.startsWith('--')).toList();
  if (ids.isEmpty) ids.addAll(_defaultIds);

  _Relay? relay;
  if (relayMode) {
    relay = await _Relay.start();
    UpstreamNetwork.environment = {
      ...Platform.environment,
      'https_proxy': 'http://127.0.0.1:${relay.port}',
      'http_proxy': 'http://127.0.0.1:${relay.port}',
    };
  }
  UpstreamNetwork.log = (line) => print('  $line');
  print('route: ${UpstreamNetwork.describe()}');
  if (checkIp) await _printEgress();

  final orch = StreamOrchestrator();
  final proxy = await AudioProxy.start();
  // The player side of the loopback hop is always direct, like the engine.
  final local = HttpClient()..findProxy = (_) => 'DIRECT';
  final resolveMs = <int>[], ttfbMs = <int>[];
  var failures = 0;
  String? previous;
  final rss0 = ProcessInfo.currentRss;

  for (final id in ids) {
    final watch = Stopwatch()..start();
    try {
      final ResolvedStream stream = await orch.resolve(id);
      final resolved = watch.elapsedMilliseconds;
      if (previous != null) proxy.unregister(previous);
      previous = id;
      final uri = proxy.register(
        id,
        stream,
        refresh: () =>
            orch.resolve(id, forceRefresh: true, sameItag: stream.itag),
        onFailure: (status, reason) =>
            orch.reportFailure(id, httpStatus: status, reason: reason),
      );
      final request = await local.getUrl(uri);
      request.headers.set('Range', 'bytes=0-${_firstBytes - 1}');
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      var got = 0;
      int? ttfb;
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        ttfb ??= watch.elapsedMilliseconds;
        got += chunk.length;
      }
      if (response.statusCode != 206 ||
          got != _firstBytes.clamp(0, stream.contentLength ?? _firstBytes)) {
        throw StateError(
          'loopback answered ${response.statusCode} with $got bytes',
        );
      }
      resolveMs.add(resolved);
      ttfbMs.add(ttfb!);
      print(
        'OK   $id client=${stream.client} itag=${stream.itag} '
        'resolve=${resolved}ms first-byte=${ttfb}ms ${got ~/ 1024}KiB',
      );
    } catch (e) {
      failures++;
      print('FAIL $id after ${watch.elapsedMilliseconds}ms: $e');
    }
  }

  local.close(force: true);
  await proxy.close();
  final rss1 = ProcessInfo.currentRss;

  print('');
  print('tracks: ${ids.length - failures}/${ids.length} started');
  if (resolveMs.isNotEmpty) {
    print('resolve ms: avg ${_avg(resolveMs)} max ${_max(resolveMs)}');
    print('first byte ms: avg ${_avg(ttfbMs)} max ${_max(ttfbMs)}');
  }
  print(
    'rss: ${rss0 >> 20} MiB -> ${rss1 >> 20} MiB (peak ${ProcessInfo.maxRss >> 20} MiB)',
  );

  var ok = failures == 0;
  if (relay != null) {
    await relay.close();
    print('relay saw: ${relay.hosts}');
    final player = relay.hosts.keys.any(
      (h) => h.startsWith('music.youtube.com'),
    );
    final cdn = relay.hosts.keys.any((h) => h.contains('.googlevideo.com'));
    print('player via proxy: $player, googlevideo via proxy: $cdn');
    ok = ok && player && cdn;
  }
  print(ok ? 'RESULT: PASS' : 'RESULT: FAIL');
  exit(ok ? 0 : 1);
}

int _avg(List<int> v) => v.reduce((a, b) => a + b) ~/ v.length;
int _max(List<int> v) => v.reduce((a, b) => a > b ? a : b);

Future<void> _printEgress() async {
  Future<String> ip(HttpClient c) async {
    try {
      final r = await (await c.getUrl(
        Uri.parse('https://api.ipify.org'),
      )).close();
      return (await r.transform(utf8.decoder).join()).trim();
    } catch (e) {
      return 'error: $e';
    } finally {
      c.close(force: true);
    }
  }

  final routed = await ip(
    UpstreamNetwork.client(connectionTimeout: const Duration(seconds: 8)),
  );
  final direct = await ip(
    HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..findProxy = ((_) => 'DIRECT'),
  );
  print('egress ip: route=$routed direct=$direct');
}

/// Minimal HTTPS CONNECT relay on loopback that counts destinations.
class _Relay {
  _Relay(this._server);

  final ServerSocket _server;
  final hosts = <String, int>{};
  final _open = <Socket>{};

  int get port => _server.port;

  static Future<_Relay> start() async {
    final relay = _Relay(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    relay._server.listen(relay._handle);
    return relay;
  }

  Future<void> _handle(Socket client) async {
    _open.add(client);
    final head = <int>[];
    late StreamSubscription<List<int>> sub;
    Socket? upstream;
    sub = client.listen(
      (data) async {
        if (upstream != null) {
          upstream!.add(data);
          return;
        }
        head.addAll(data);
        final text = latin1.decode(head, allowInvalid: true);
        final end = text.indexOf('\r\n\r\n');
        if (end < 0) return;
        final line = text.substring(0, text.indexOf('\r\n')).split(' ');
        if (line.length < 2 || line[0] != 'CONNECT') {
          client.add(latin1.encode('HTTP/1.1 405 Method Not Allowed\r\n\r\n'));
          await client.close();
          return;
        }
        final target = line[1];
        final colon = target.lastIndexOf(':');
        final host = target.substring(0, colon);
        // rr3---sn-abc.googlevideo.com → *.googlevideo.com
        final key = host.replaceAll(RegExp(r'^rr\d+---sn-[^.]+\.'), '*.');
        hosts[key] = (hosts[key] ?? 0) + 1;
        sub.pause();
        try {
          final up = await Socket.connect(
            host,
            int.parse(target.substring(colon + 1)),
            timeout: const Duration(seconds: 10),
          );
          upstream = up;
          _open.add(up);
          client.add(
            latin1.encode('HTTP/1.1 200 Connection established\r\n\r\n'),
          );
          final rest = head.sublist(end + 4);
          if (rest.isNotEmpty) up.add(rest);
          up.listen(
            client.add,
            onDone: () => client.destroy(),
            onError: (Object _) => client.destroy(),
          );
          sub.resume();
        } catch (_) {
          client.add(latin1.encode('HTTP/1.1 502 Bad Gateway\r\n\r\n'));
          client.destroy();
        }
      },
      onDone: () => upstream?.destroy(),
      onError: (Object _) => upstream?.destroy(),
    );
  }

  Future<void> close() async {
    for (final s in _open) {
      s.destroy();
    }
    await _server.close();
  }
}
