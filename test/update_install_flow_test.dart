import 'dart:async';
import 'dart:io';

import 'package:aurora_music/core/window_controls.dart';
import 'package:aurora_music/updater/hard_exit.dart';
import 'package:aurora_music/updater/update_controller.dart';
import 'package:aurora_music/updater/update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Service implements UpdateService {
  _Service(this.file);
  final File file;
  @override
  Future<File> download(
    ReleaseInfo release,
    ReleaseAsset asset,
    Directory dir, {
    void Function(int received, int total)? onProgress,
  }) async => file;
  @override
  Future<ReleaseInfo?> check(SemVer current, {bool beta = false}) async => null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ReleaseInfo _release(String v) => ReleaseInfo(
  tag: 'v$v',
  version: SemVer.tryParse(v)!,
  notes: '',
  prerelease: false,
  assets: [
    ReleaseAsset('Aurora-Setup-$v.exe', Uri.parse('https://x/a.exe'), 1),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File installer;
  late SharedPreferences prefs;
  late List<List<String>> launches;

  Future<UpdateController> make({
    required String installed,
    Future<void> Function()? hardExit,
    void Function(int)? exitProcess,
  }) async {
    PackageInfo.setMockInitialValues(
      appName: 'Aurora',
      packageName: 'a',
      version: installed,
      buildNumber: '1',
      buildSignature: '',
    );
    return UpdateController(
      prefs,
      service: _Service(installer),
      launcher: (exe, args) async => launches.add([exe, ...args]),
      hardExit: hardExit ?? () async {},
      exitProcess: exitProcess ?? (_) {},
      dirProvider: () async => dir,
      windows: true,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({'updateAuto': false});
    prefs = await SharedPreferences.getInstance();
    dir = Directory.systemTemp.createTempSync('aurora_upd');
    installer = File('${dir.path}/Aurora-Setup-1.2.2.exe')
      ..writeAsStringSync('x');
    launches = [];
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'lanza /SILENT con log, marca pendingUpdate y pasa por hardExit',
    () async {
      var hard = 0;
      final u = await make(installed: '1.2.1', hardExit: () async => hard++);
      u.release = _release('1.2.2');
      await u.install();
      expect(launches.single.first, installer.path);
      expect(launches.single.skip(1).take(5), [
        '/SILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/FORCECLOSEAPPLICATIONS',
      ]);
      expect(launches.single.last, startsWith('/LOG='));
      expect(launches.single.last, endsWith('install.log'));
      expect(prefs.getString('pendingUpdate'), '1.2.2');
      expect(u.phase, UpdatePhase.installing);
      expect(hard, 1);
    },
  );

  testWidgets('si hardExit no responde en 3 s cae a exit(0)', (tester) async {
    int? code;
    final u = UpdateController(
      prefs,
      service: _Service(installer),
      launcher: (exe, args) async {},
      hardExit: () => Completer<void>().future,
      exitProcess: (c) => code = c,
      dirProvider: () async => dir,
      windows: true,
    )..release = _release('1.2.2');
    unawaited(u.install());
    await tester.pump(const Duration(seconds: 2));
    expect(code, isNull);
    await tester.pump(const Duration(seconds: 2));
    expect(code, 0);
  });

  test(
    'al arrancar con versión objetivo: éxito, limpia marca e instaladores',
    () async {
      await prefs.setString('pendingUpdate', '1.2.2');
      File('${dir.path}/install.log').writeAsStringSync('log');
      final u = await make(installed: '1.2.2');
      await u.start();
      expect(u.outcome!.failed, isFalse);
      expect(prefs.getString('pendingUpdate'), isNull);
      expect(installer.existsSync(), isFalse);
      expect(File('${dir.path}/install.log').existsSync(), isFalse);
      u.dispose();
    },
  );

  test(
    'al arrancar con versión vieja: fracaso, conserva instalador y log',
    () async {
      await prefs.setString('pendingUpdate', '1.2.2');
      File('${dir.path}/install.log').writeAsStringSync('log');
      final u = await make(installed: '1.2.1');
      await u.start();
      expect(u.outcome!.failed, isTrue);
      expect(u.outcome!.logPath, endsWith('install.log'));
      expect(installer.existsSync(), isTrue);
      expect(File('${dir.path}/install.log').existsSync(), isTrue);
      await u.openInstaller();
      expect(launches.single.first, 'explorer.exe');
      expect(
        launches.single.last.replaceAll('/', r'\'),
        '/select,${installer.path}'.replaceAll('/', r'\'),
      );
      u.dispose();
    },
  );

  test('X / Alt+F4 / Salir (confirmClose) no usan el camino forzado', () async {
    var forced = 0;
    final old = hardExitHandler;
    hardExitHandler = () async => forced++;
    addTearDown(() => hardExitHandler = old);
    WindowControls.install();
    final codec = const StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'aurora/window',
          codec.encodeMethodCall(const MethodCall('confirmClose', true)),
          (_) {},
        );
    expect(forced, 0);
    // Y el vigilante nativo solo se arma dentro de hardExit.
    final cpp = File('windows/runner/flutter_window.cpp').readAsStringSync();
    final calls = RegExp(r'ArmExitWatchdog\(\);').allMatches(cpp).toList();
    expect(calls, hasLength(1));
    final hardBlock = cpp.indexOf('name == "hardExit"');
    final nextBlock = cpp.indexOf('name == "setBackground"');
    expect(calls.single.start, inInclusiveRange(hardBlock, nextBlock));
  });
}
