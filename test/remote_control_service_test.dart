import 'dart:convert';
import 'dart:io';

import 'package:aurora_music/remote/remote_control_server.dart';
import 'package:aurora_music/remote/remote_control_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoActions implements RemoteControlActions {
  @override
  Future<void> play() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> toggle() async {}
  @override
  Future<void> next() async {}
  @override
  Future<void> previous() async {}
  @override
  Future<Map<String, Object?>> startJam({String mode = 'auto'}) async => {};
  @override
  Map<String, Object?> status() => {'playing': false};
}

void main() {
  late Directory directory;
  late File discovery;
  late RemoteControlService service;

  Future<RemoteControlService> create([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    return RemoteControlService(
      await SharedPreferences.getInstance(),
      _NoActions(),
      supported: true,
      defaultPort: 0,
      discoveryFile: discovery,
    );
  }

  Future<int> status(String baseUrl, String token) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse('$baseUrl/status'));
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> readDiscovery() =>
      jsonDecode(discovery.readAsStringSync()) as Map<String, dynamic>;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aurora_remote_');
    discovery = File('${directory.path}/remote_control.json');
  });
  tearDown(() async {
    service.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    directory.deleteSync(recursive: true);
  });

  test('is off by default: no port and no discovery file', () async {
    service = await create();
    await service.start();
    expect(service.enabled, isFalse);
    expect(service.running, isFalse);
    expect(discovery.existsSync(), isFalse);
  });

  test(
    'enabling publishes URL and token for the plugin, disabling removes them',
    () async {
      service = await create();
      await service.setEnabled(true);
      expect(service.running, isTrue);
      final info = readDiscovery();
      expect(info['baseUrl'], service.baseUrl);
      expect(info['port'], service.port);
      expect(info['token'], service.token);
      expect(
        await status(info['baseUrl'] as String, info['token'] as String),
        200,
      );

      await service.setEnabled(false);
      expect(service.running, isFalse);
      expect(discovery.existsSync(), isFalse);
    },
  );

  test(
    'regenerating the token updates the file and revokes the old one',
    () async {
      service = await create();
      await service.setEnabled(true);
      final before = readDiscovery();
      await service.regenerateToken();
      final after = readDiscovery();
      expect(after['token'], isNot(before['token']));
      expect(await status(service.baseUrl, before['token'] as String), 401);
      expect(await status(service.baseUrl, after['token'] as String), 200);
    },
  );

  test('a saved enabled flag starts the API on launch', () async {
    service = await create({RemoteControlService.enabledKey: true});
    await service.start();
    expect(service.running, isTrue);
    expect(discovery.existsSync(), isTrue);
  });

  test('a busy port reports the problem and publishes nothing', () async {
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(taken.close);
    service = await create({RemoteControlService.portKey: taken.port});
    await service.setEnabled(true);
    expect(service.running, isFalse);
    expect(service.problem, contains('${taken.port}'));
    expect(discovery.existsSync(), isFalse);
  });

  test('unsupported platforms never open anything', () async {
    SharedPreferences.setMockInitialValues({
      RemoteControlService.enabledKey: true,
    });
    service = RemoteControlService(
      await SharedPreferences.getInstance(),
      _NoActions(),
      supported: false,
      discoveryFile: discovery,
    );
    await service.start();
    await service.setEnabled(true);
    expect(service.enabled, isFalse);
    expect(service.running, isFalse);
  });
}
