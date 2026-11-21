import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum YtDlpUpdateStatus { updated, upToDate, deferred, throttled, failed }

class YtDlpUpdateResult {
  const YtDlpUpdateResult(this.status, {this.version, this.error});

  final YtDlpUpdateStatus status;
  final String? version;
  final String? error;
}

/// Updates only the official Windows x64 nightly executable.
///
/// The caller must hold off new extraction operations while [isInstalling], and
/// [canUpdate] must be false during playback, extraction and shutdown. Failed
/// checks also consume the daily allowance; restarting cannot hammer GitHub.
class YtDlpUpdater {
  YtDlpUpdater({
    required this.executable,
    required this.stateFile,
    required this.canUpdate,
    Future<List<int>> Function(Uri)? fetch,
    Future<String> Function(File)? executableVersion,
    Future<void> Function(File, File)? replace,
    DateTime Function()? clock,
  }) : _fetch = fetch ?? _download,
       _executableVersion = executableVersion ?? _readVersion,
       _replace = replace ?? _rename,
       _clock = clock ?? DateTime.now;

  final File executable;
  final File stateFile;
  final bool Function() canUpdate;
  final Future<List<int>> Function(Uri) _fetch;
  final Future<String> Function(File) _executableVersion;
  final Future<void> Function(File, File) _replace;
  final DateTime Function() _clock;
  static final _inFlight = <String, Future<YtDlpUpdateResult>>{};
  static final _installing = <String>{};
  static final _releaseUrl = Uri.parse(
    'https://api.github.com/repos/yt-dlp/yt-dlp-nightly-builds/releases/latest',
  );

  String get _key => p.normalize(executable.absolute.path).toLowerCase();
  bool get isUpdating => _inFlight.containsKey(_key);
  bool get isInstalling => _installing.contains(_key);

  Future<YtDlpUpdateResult> checkForUpdate() => _start(recoveryOnly: false);

  /// Call before allowing extraction at startup. This never contacts GitHub.
  Future<YtDlpUpdateResult> recoverPendingInstallation() =>
      _start(recoveryOnly: true);

  Future<YtDlpUpdateResult> _start({required bool recoveryOnly}) {
    final existing = _inFlight[_key];
    if (existing != null) return existing;
    final future = _check(recoveryOnly: recoveryOnly).whenComplete(() {
      _inFlight.remove(_key);
    });
    _inFlight[_key] = future;
    return future;
  }

  Future<YtDlpUpdateResult> _check({required bool recoveryOnly}) async {
    final candidate = File('${executable.path}.aurora-new.exe');
    final backup = File('${executable.path}.aurora-previous');
    var replaced = false;
    var committed = false;
    var recovering = false;
    Map<String, dynamic>? state;
    try {
      if (!canUpdate()) {
        return const YtDlpUpdateResult(YtDlpUpdateStatus.deferred);
      }
      state = await _readState();
      recovering = state.containsKey('pendingInstallation');
      final recovery = await _recover(state);
      recovering = false;
      if (recovery?.status == YtDlpUpdateStatus.deferred) return recovery!;
      if (!await executable.exists()) {
        throw const FormatException('No installed yt-dlp executable.');
      }
      if (recoveryOnly) {
        return recovery ??
            YtDlpUpdateResult(
              YtDlpUpdateStatus.upToDate,
              version: state['version'] as String?,
            );
      }
      final now = _clock().toUtc();
      final last = DateTime.tryParse(state['lastCheckAt'] as String? ?? '');
      if (last != null && now.difference(last) < const Duration(hours: 24)) {
        return YtDlpUpdateResult(
          YtDlpUpdateStatus.throttled,
          version: state['version'] as String?,
        );
      }
      state['lastCheckAt'] = now.toIso8601String();
      await _writeState(state);

      final release = jsonDecode(utf8.decode(await _fetch(_releaseUrl))) as Map;
      final version = release['tag_name'] as String;
      if (!RegExp(r'^\d{4}\.\d{2}\.\d{2}\.\d{6}$').hasMatch(version) ||
          release['draft'] != false) {
        throw const FormatException('Invalid official nightly release.');
      }
      final assets = release['assets'] as List;
      final binary = _asset(assets, version, 'yt-dlp.exe');
      final sums = _asset(assets, version, 'SHA2-256SUMS');
      final checksum = utf8.decode(await _fetch(sums));
      final hashes = const LineSplitter()
          .convert(checksum)
          .map(
            (line) => RegExp(
              r'^([0-9a-fA-F]{64})\s+\*?yt-dlp\.exe\s*$',
            ).firstMatch(line),
          )
          .whereType<RegExpMatch>()
          .toList();
      if (hashes.length != 1) {
        throw const FormatException('Missing or ambiguous official SHA-256.');
      }
      final expected = hashes.single.group(1)!.toLowerCase();
      final current = (await sha256.bind(executable.openRead()).first)
          .toString();
      if (current == expected) {
        state['version'] = version;
        state['sha256'] = expected;
        await _writeState(state);
        return YtDlpUpdateResult(YtDlpUpdateStatus.upToDate, version: version);
      }

      final bytes = await _fetch(binary);
      if (sha256.convert(bytes).toString() != expected ||
          bytes.length < 2 ||
          bytes[0] != 0x4d ||
          bytes[1] != 0x5a) {
        throw const FormatException('yt-dlp integrity verification failed.');
      }
      await candidate.writeAsBytes(bytes, flush: true);
      if (await _executableVersion(candidate) != version) {
        throw const FormatException('Nightly executable version mismatch.');
      }

      // Preserve notices from the exact source commit used for this nightly.
      final sourceCommit = RegExp(
        r'Generated from: https://github\.com/yt-dlp/yt-dlp/commit/([0-9a-f]{40})(?:\s|$)',
      ).firstMatch(release['body'] as String? ?? '')?.group(1);
      if (sourceCommit == null) {
        throw const FormatException('Missing nightly source provenance.');
      }
      final licenses = Directory(p.join(executable.parent.path, 'licenses'));
      await licenses.create(recursive: true);
      for (final name in ['LICENSE', 'THIRD_PARTY_LICENSES.txt']) {
        final notice = await _fetch(
          Uri.parse(
            'https://raw.githubusercontent.com/yt-dlp/yt-dlp/$sourceCommit/$name',
          ),
        );
        if (notice.isEmpty || notice.length > 1024 * 1024) {
          throw const FormatException('Invalid yt-dlp license notice.');
        }
        // Keep the previous package notices alongside update-specific notices.
        await File(
          p.join(licenses.path, 'yt-dlp-$version-$name'),
        ).writeAsBytes(notice, flush: true);
      }
      if (!canUpdate()) {
        return const YtDlpUpdateResult(YtDlpUpdateStatus.deferred);
      }
      _installing.add(_key);
      await executable.copy(backup.path);
      state['pendingInstallation'] = {
        'sha256': expected,
        'previousSha256': current,
        'version': version,
        'sourceCommit': sourceCommit,
      };
      await _writeState(state);
      // Same-directory rename replaces the executable without a missing-file
      // window. A sharing violation leaves the existing executable intact.
      await _replace(candidate, executable);
      replaced = true;
      if (await _executableVersion(executable) != version) {
        throw const FormatException('Installed nightly failed validation.');
      }
      final completed = {
        ...state,
        'version': version,
        'sha256': expected,
        'sourceCommit': sourceCommit,
      }..remove('pendingInstallation');
      await _writeState(completed);
      committed = true;
      return YtDlpUpdateResult(YtDlpUpdateStatus.updated, version: version);
    } catch (_) {
      if (recovering) {
        return const YtDlpUpdateResult(
          YtDlpUpdateStatus.failed,
          error: 'No se pudo recuperar yt-dlp. Se conservó la copia anterior.',
        );
      }
      if (replaced && !committed && state != null) {
        try {
          await _restorePrevious(state, backup);
        } catch (_) {
          // Keep the backup for recovery if antivirus/another process locks it.
          return const YtDlpUpdateResult(
            YtDlpUpdateStatus.failed,
            error:
                'No se pudo restaurar yt-dlp. Se conservó la copia anterior.',
          );
        }
      }
      return const YtDlpUpdateResult(
        YtDlpUpdateStatus.failed,
        error: 'No se pudo actualizar yt-dlp; se conserva la versión anterior.',
      );
    } finally {
      try {
        if (await candidate.exists()) await candidate.delete();
        if (committed && await backup.exists()) await backup.delete();
      } on FileSystemException {
        // Leftover staging/backup files do not invalidate an installed binary.
      } finally {
        _installing.remove(_key);
      }
    }
  }

  Future<YtDlpUpdateResult?> _recover(Map<String, dynamic> state) async {
    final pending = state['pendingInstallation'];
    if (pending == null) return null;
    if (pending is! Map ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(pending['sha256'] as String? ?? '') ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(pending['previousSha256'] as String? ?? '') ||
        !RegExp(
          r'^\d{4}\.\d{2}\.\d{2}\.\d{6}$',
        ).hasMatch(pending['version'] as String? ?? '') ||
        !RegExp(
          r'^[0-9a-f]{40}$',
        ).hasMatch(pending['sourceCommit'] as String? ?? '')) {
      throw const FormatException('Invalid pending installation journal.');
    }
    if (!canUpdate()) {
      return const YtDlpUpdateResult(YtDlpUpdateStatus.deferred);
    }
    _installing.add(_key);
    final backup = File('${executable.path}.aurora-previous');
    try {
      var valid = false;
      if (await executable.exists() &&
          (await sha256.bind(executable.openRead()).first).toString() ==
              pending['sha256']) {
        try {
          valid = await _executableVersion(executable) == pending['version'];
        } catch (_) {
          // An unlaunchable candidate must recover the verified previous file.
        }
      }
      if (!valid) {
        await _restorePrevious(state, backup);
        return YtDlpUpdateResult(
          YtDlpUpdateStatus.upToDate,
          version: state['version'] as String?,
        );
      }
      final completed = <String, dynamic>{
        ...state,
        'version': pending['version'],
        'sha256': pending['sha256'],
        'sourceCommit': pending['sourceCommit'],
      }..remove('pendingInstallation');
      await _writeState(completed);
      state
        ..clear()
        ..addAll(completed);
      await _deleteBackup(backup);
      return YtDlpUpdateResult(
        YtDlpUpdateStatus.updated,
        version: pending['version'] as String,
      );
    } finally {
      _installing.remove(_key);
    }
  }

  Future<void> _restorePrevious(Map<String, dynamic> state, File backup) async {
    final pending = state['pendingInstallation'] as Map;
    if (!await backup.exists() ||
        (await sha256.bind(backup.openRead()).first).toString() !=
            pending['previousSha256']) {
      throw const FormatException(
        'Previous yt-dlp backup failed integrity check.',
      );
    }
    // Copy, rather than consume, the backup until the journal clear is durable.
    final restored = await backup.copy('${executable.path}.aurora-new.exe');
    await _replace(restored, executable);
    final completed = {...state}..remove('pendingInstallation');
    await _writeState(completed);
    state
      ..clear()
      ..addAll(completed);
    await _deleteBackup(backup);
  }

  static Future<void> _deleteBackup(File backup) async {
    try {
      if (await backup.exists()) await backup.delete();
    } on FileSystemException {
      // A committed journal makes an undeletable leftover backup harmless.
    }
  }

  static Uri _asset(List assets, String version, String name) {
    final matches = assets.where(
      (asset) => asset is Map && asset['name'] == name,
    );
    if (matches.length != 1) {
      throw const FormatException('Missing release asset.');
    }
    final url = Uri.parse(matches.single['browser_download_url'] as String);
    final expected = Uri.parse(
      'https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/download/$version/$name',
    );
    if (url != expected) {
      throw const FormatException('Untrusted release asset.');
    }
    return url;
  }

  Future<Map<String, dynamic>> _readState() async {
    if (!await stateFile.exists()) return {};
    final value = jsonDecode(await stateFile.readAsString());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid updater state.');
    }
    return value;
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    await stateFile.parent.create(recursive: true);
    final staged = File('${stateFile.path}.new');
    await staged.writeAsString(jsonEncode(state), flush: true);
    await staged.rename(stateFile.path);
  }

  static Future<void> _rename(File from, File to) async {
    await from.rename(to.path);
  }

  static Future<String> _readVersion(File file) async {
    final process = await Process.start(file.path, [
      '--ignore-config',
      '--version',
    ]);
    try {
      final output = process.stdout.transform(utf8.decoder).join();
      final errors = process.stderr.drain<void>();
      final code = await process.exitCode.timeout(const Duration(seconds: 20));
      await errors;
      if (code != 0) {
        throw const FormatException('yt-dlp version check failed.');
      }
      return (await output).trim();
    } finally {
      process.kill();
    }
  }

  static Future<List<int>> _download(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      return await (() async {
        var destination = uri;
        for (var redirects = 0; redirects <= 5; redirects++) {
          if (destination.scheme != 'https' ||
              destination.port != 443 ||
              destination.userInfo.isNotEmpty ||
              !const {
                'github.com',
                'api.github.com',
                'raw.githubusercontent.com',
                'release-assets.githubusercontent.com',
                'objects.githubusercontent.com',
              }.contains(destination.host)) {
            throw const HttpException('Untrusted nightly asset destination.');
          }
          final request = await client.getUrl(destination);
          request.followRedirects = false;
          request.headers.set(
            HttpHeaders.userAgentHeader,
            'Aurora-nightly-updater',
          );
          final response = await request.close();
          if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
            final location = response.headers.value(HttpHeaders.locationHeader);
            if (location == null || redirects == 5) {
              throw const HttpException('Invalid nightly asset redirect.');
            }
            destination = destination.resolve(location);
            await response.drain<void>();
            continue;
          }
          if (response.statusCode != HttpStatus.ok) {
            throw const HttpException(
              'Nightly update server rejected request.',
            );
          }
          // Uint8List: 1 byte por byte (una List<int> gastaría 8 y duplicaría al crecer).
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in response) {
            if (bytes.length + chunk.length > 100 * 1024 * 1024) {
              throw const HttpException('Nightly asset exceeds size limit.');
            }
            bytes.add(chunk);
          }
          return bytes.takeBytes();
        }
        throw const HttpException('Nightly redirect limit exceeded.');
      })().timeout(
        uri.path.endsWith('.exe')
            ? const Duration(minutes: 3)
            : const Duration(seconds: 15),
      );
    } finally {
      client.close(force: true);
    }
  }
}
