import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;

import 'http_timeout_client.dart';

enum DesktopSelfUpdatePlatform {
  linux,
  windows,
  macos;

  static DesktopSelfUpdatePlatform detect() {
    if (Platform.isWindows) return windows;
    if (Platform.isMacOS) return macos;
    return linux;
  }
}

class DesktopSelfUpdateService {
  DesktopSelfUpdateService({
    http.Client? client,
    String? Function()? appImagePathLoader,
    String? Function()? runningExePathLoader,
    Future<void> Function(String archivePath, String destinationPath)?
    extractArchive,
    Future<void> Function(String path)? makeExecutable,
    Future<void> Function(String path)? relaunch,
    DesktopSelfUpdatePlatform Function()? platformLoader,
  }) : _client = client ?? TimeoutHttpClient(),
       _appImagePath = appImagePathLoader ?? _defaultAppImagePath,
       _runningExePath = runningExePathLoader ?? _defaultRunningExePath,
       _extractArchive = extractArchive ?? _defaultExtractArchive,
       _makeExecutable = makeExecutable ?? _defaultMakeExecutable,
       _relaunch = relaunch ?? _defaultRelaunch,
       _platform = platformLoader ?? DesktopSelfUpdatePlatform.detect;

  final http.Client _client;
  final String? Function() _appImagePath;
  final String? Function() _runningExePath;
  final Future<void> Function(String archivePath, String destinationPath)
  _extractArchive;
  final Future<void> Function(String path) _makeExecutable;
  final Future<void> Function(String path) _relaunch;
  final DesktopSelfUpdatePlatform Function() _platform;

  bool get canSelfUpdate =>
      !kIsWeb &&
      switch (_platform()) {
        DesktopSelfUpdatePlatform.linux =>
          (_appImagePath()?.isNotEmpty ?? false),
        DesktopSelfUpdatePlatform.windows ||
        DesktopSelfUpdatePlatform.macos => true,
      };

  Future<void> update(Uri url, {required String expectedSha256}) async {
    if (url.scheme != 'https') {
      throw StateError('Refusing to download a non-https update URL');
    }
    switch (_platform()) {
      case DesktopSelfUpdatePlatform.linux:
        await _updateAppImage(url, expectedSha256);
      case DesktopSelfUpdatePlatform.windows:
        await _updateWindowsZip(url, expectedSha256);
      case DesktopSelfUpdatePlatform.macos:
        await _updateMacBundle(url, expectedSha256);
    }
  }

  Future<void> _updateAppImage(Uri url, String expectedSha256) async {
    final path = _appImagePath();
    if (path == null || path.isEmpty) {
      throw StateError('Not running as an AppImage');
    }
    final response = await _downloadVerified(url, expectedSha256);

    final staged = File('$path.new');
    await staged.writeAsBytes(response.bodyBytes, flush: true);
    await _makeExecutable(staged.path);
    await staged.rename(path);
    await _relaunch(path);
  }

  Future<void> _updateWindowsZip(Uri url, String expectedSha256) async {
    final exePath = _requiredExePath();
    final installDir = File(exePath).parent.path;
    final exeName = _baseName(exePath);
    final response = await _downloadVerified(url, expectedSha256);
    final staging = Directory.systemTemp.createTempSync(
      'spectrum_strategy_update_',
    );
    try {
      final zipFile = File('${staging.path}/update.zip');
      await zipFile.writeAsBytes(response.bodyBytes, flush: true);
      final payload = Directory('${staging.path}/payload')..createSync();
      await _extractArchive(zipFile.path, payload.path);

      final payloadRoot = _descendSingleFolder(payload);
      if (!File('${payloadRoot.path}/$exeName').existsSync()) {
        throw StateError('The extracted update does not contain $exeName');
      }
      final script = File('${staging.path}/apply-update.bat');
      await script.writeAsString(
        windowsRelaunchScript(
          pid: pid,
          stagingDir: staging.path,
          payloadDir: payloadRoot.path,
          installDir: installDir,
          executableName: exeName,
        ),
        flush: true,
      );

      await _relaunch(script.path);
    } catch (_) {
      _deleteStaging(staging);
      rethrow;
    }
  }

  Future<void> _updateMacBundle(Uri url, String expectedSha256) async {
    final exePath = _requiredExePath();
    final installedBundle = appBundleContaining(exePath);
    if (installedBundle == null) {
      throw StateError('Not running from inside an .app bundle');
    }
    final response = await _downloadVerified(url, expectedSha256);
    final staging = Directory.systemTemp.createTempSync(
      'spectrum_strategy_update_',
    );
    try {
      final zipFile = File('${staging.path}/update.zip');
      await zipFile.writeAsBytes(response.bodyBytes, flush: true);
      final payload = Directory('${staging.path}/payload')..createSync();
      await _extractArchive(zipFile.path, payload.path);

      final stagedBundle = _findAppBundleIn(payload);
      if (stagedBundle == null) {
        throw StateError('The extracted update does not contain an .app');
      }

      final exeName = _baseName(exePath);
      if (!File('$stagedBundle/Contents/MacOS/$exeName').existsSync()) {
        throw StateError('The extracted update does not contain $exeName');
      }
      final script = File('${staging.path}/apply-update.sh');
      await script.writeAsString(
        macosRelaunchScript(
          pid: pid,
          stagingDir: staging.path,
          stagedAppBundle: stagedBundle,
          installedAppBundle: installedBundle,
        ),
        flush: true,
      );
      await _relaunch(script.path);
    } catch (_) {
      _deleteStaging(staging);
      rethrow;
    }
  }

  static const int _maxRedirects = 5;

  Future<http.Response> _downloadVerified(
    Uri url,
    String expectedSha256,
  ) async {
    var target = url;
    http.Response? response;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final request = http.Request('GET', target)..followRedirects = false;
      final streamed = await _client.send(request);
      final hopResponse = await http.Response.fromStream(streamed);
      if (!_isRedirect(hopResponse.statusCode)) {
        response = hopResponse;
        break;
      }
      target = _redirectTarget(target, hopResponse);
    }
    if (response == null) {
      throw StateError('Update download redirected too many times');
    }
    if (response.statusCode != 200 || response.bodyBytes.length < 100000) {
      throw StateError('Download failed (status ${response.statusCode})');
    }

    final actual = sha256.convert(response.bodyBytes).toString();
    final expected = expectedSha256.trim().toLowerCase();
    if (!_constantTimeHexEquals(actual, expected)) {
      throw StateError('Downloaded update failed its checksum verification');
    }
    return response;
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static Uri _redirectTarget(Uri from, http.Response response) {
    final location = response.headers['location'];
    if (location == null || location.trim().isEmpty) {
      throw StateError('Update download redirected without a location');
    }
    final next = Uri.tryParse(location.trim());
    if (next == null) {
      throw StateError('Update download redirected to an unreadable URL');
    }
    final resolved = from.resolveUri(next);
    if (resolved.scheme != 'https') {
      throw StateError('Refusing to follow a non-https update redirect');
    }
    return resolved;
  }

  static bool _constantTimeHexEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  String _requiredExePath() {
    final path = _runningExePath();
    if (path == null || path.isEmpty) {
      throw StateError('Cannot locate the running executable');
    }
    return path;
  }

  static void _deleteStaging(Directory staging) {
    try {
      staging.deleteSync(recursive: true);
    } catch (_) {}
  }

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

  static String _dirName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    if (parts.length <= 1) return '';
    return parts.sublist(0, parts.length - 1).join('/');
  }

  @visibleForTesting
  static String? appBundleContaining(String exePath) {
    var dir = _dirName(exePath);
    while (!dir.endsWith('.app')) {
      final parent = _dirName(dir);
      if (parent == dir) return null;
      dir = parent;
    }
    return dir;
  }

  static Directory _descendSingleFolder(Directory dir) {
    var current = dir;
    for (;;) {
      final entries = current.listSync();
      if (entries.length != 1 || entries.single is! Directory) return current;
      final next = entries.single as Directory;
      if (_baseName(next.path).endsWith('.app')) return current;
      current = next;
    }
  }

  static String? _findAppBundleIn(Directory payload) {
    for (final entry in _descendSingleFolder(payload).listSync()) {
      if (entry is Directory && _baseName(entry.path).endsWith('.app')) {
        return entry.path;
      }
    }
    return null;
  }

  @visibleForTesting
  static String shellQuote(String value) =>
      "'${value.replaceAll("'", r"'\''")}'";

  static void _requireCmdSafe(String label, String value) {
    final safe = value.codeUnits.every(
      (unit) => unit >= 0x20 && unit <= 0x7e && unit != 0x25 && unit != 0x22,
    );
    if (!safe) {
      throw StateError(
        'Cannot build the Windows updater: the $label is not plain ASCII '
        '(cmd would misparse it); falling back to a manual download',
      );
    }
  }

  @visibleForTesting
  static String windowsRelaunchScript({
    required int pid,
    required String stagingDir,
    required String payloadDir,
    required String installDir,
    required String executableName,
  }) {
    _requireCmdSafe('staging directory', stagingDir);
    _requireCmdSafe('payload directory', payloadDir);
    _requireCmdSafe('install directory', installDir);
    _requireCmdSafe('executable name', executableName);
    const delay = r'ping -n 2 127.0.0.1 >NUL';
    final lines = <String>[
      '@echo off',
      'rem Spectrum Strategy updater: written by the app next to the staged',
      'rem build and launched detached just before the app exits.',
      'set "PAYLOAD=$payloadDir"',
      'set "STAGING=$stagingDir"',
      'set "INSTALL=$installDir"',
      'set "EXE=$executableName"',
      'set "STAGED=%INSTALL%.update-new"',
      'set "OLDDIR=%INSTALL%.update-old"',
      'set /a WAITED=0',

      'cd /d "%STAGING%"',

      'if exist "%STAGED%" rmdir /s /q "%STAGED%"',
      'if exist "%OLDDIR%" rmdir /s /q "%OLDDIR%"',

      ':wait',
      'tasklist /FI "PID eq $pid" /NH 2>NUL | find "$pid" >NUL',
      'if errorlevel 1 goto stage',
      delay,
      'set /a WAITED+=1',
      'if %WAITED% LSS 60 goto wait',
      ':stage',

      'robocopy "%PAYLOAD%" "%STAGED%" /MIR /R:2 /W:2 /NFL /NDL /NJH /NJS'
          ' >NUL',
      'if errorlevel 8 goto failure',

      'move /y "%INSTALL%" "%OLDDIR%" >NUL || goto failure',
      'move /y "%STAGED%" "%INSTALL%" >NUL || goto rollback',
      'rmdir /s /q "%OLDDIR%"',

      'rmdir /s /q "%PAYLOAD%"',
      'del /q "%STAGING%\\update.zip" 2>NUL',
      'start "" "%INSTALL%\\%EXE%"',
      'exit /b 0',
      ':rollback',

      'move /y "%OLDDIR%" "%INSTALL%" >NUL'
          ' || (start "" "%OLDDIR%\\%EXE%" & exit /b 1)',
      ':failure',
      'if exist "%STAGED%" rmdir /s /q "%STAGED%"',
      'if exist "%PAYLOAD%" rmdir /s /q "%PAYLOAD%"',
      'del /q "%STAGING%\\update.zip" 2>NUL',

      'start "" "%INSTALL%\\%EXE%"',
      'exit /b 1',
    ];
    return lines.join('\r\n');
  }

  @visibleForTesting
  static String macosRelaunchScript({
    required int pid,
    required String stagingDir,
    required String stagedAppBundle,
    required String installedAppBundle,
  }) {
    final lines = <String>[
      '#!/bin/sh',
      '# Spectrum Strategy updater: written by the app next to the staged',
      '# bundle and launched detached just before the app exits.',
      'set -u',
      'APP_PID=$pid',
      'STAGED=${shellQuote(stagedAppBundle)}',
      'STAGING=${shellQuote(stagingDir)}',
      'INSTALL=${shellQuote(installedAppBundle)}',
      'NEW="\$INSTALL.update-new"',
      'OLD="\$INSTALL.update-old"',
      '',
      '# Bounded wait: 60 x 1s, then proceed anyway -- the old process is',
      '# either gone or wedged, and proceeding beats hanging forever.',
      'n=0',
      'while kill -0 "\$APP_PID" 2>/dev/null; do',
      '  n=\$((n + 1))',
      '  [ "\$n" -ge 60 ] && break',
      '  sleep 1',
      'done',
      '',
      '# Stage the new bundle on a same-volume sibling of the install.',
      'rm -rf "\$NEW" "\$OLD"',
      'if ! cp -R "\$STAGED" "\$NEW"; then',
      '  rm -rf "\$NEW" "\$STAGING"',
      '  open "\$INSTALL"',
      '  exit 1',
      'fi',
      '',
      '# Swap by rename: the running bundle moves aside once the copy has',
      '# fully succeeded, and comes back if anything below fails.',
      'if ! mv "\$INSTALL" "\$OLD"; then',
      '  rm -rf "\$NEW" "\$STAGING"',
      '  open "\$INSTALL"',
      '  exit 1',
      'fi',
      'if ! mv "\$NEW" "\$INSTALL"; then',
      '  # A failed restore must still leave a launchable app: open the old',
      '  # bundle where it sits rather than a path that no longer exists.',
      '  if ! mv "\$OLD" "\$INSTALL"; then',
      '    rm -rf "\$NEW" "\$STAGING"',
      '    open "\$OLD"',
      '    exit 1',
      '  fi',
      '  rm -rf "\$NEW" "\$STAGING"',
      '  open "\$INSTALL"',
      '  exit 1',
      'fi',
      '',
      '# Success: now, and only now, drop the old bundle and reopen the app.',

      'rm -rf "\$OLD" "\$STAGING"',
      'open "\$INSTALL"',
    ];
    return '${lines.join('\n')}\n';
  }

  static String? _defaultAppImagePath() => Platform.environment['APPIMAGE'];

  static String? _defaultRunningExePath() => Platform.resolvedExecutable;

  static Future<void> _defaultExtractArchive(
    String archivePath,
    String destinationPath,
  ) async {
    final result = Platform.isMacOS
        ? await Process.run('ditto', <String>[
            '-x',
            '-k',
            archivePath,
            destinationPath,
          ])
        : await Process.run('tar', <String>[
            '-xf',
            archivePath,
            '-C',
            destinationPath,
          ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Archive extraction failed (exit ${result.exitCode}): '
        '${result.stderr}',
      );
    }
  }

  static Future<void> _defaultMakeExecutable(String path) async {
    final result = await Process.run('chmod', <String>['+x', path]);
    if (result.exitCode != 0) {
      throw StateError(
        'chmod +x failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
  }

  static Future<void> _defaultRelaunch(String path) async {
    if (path.endsWith('.bat')) {
      await Process.start('cmd.exe', <String>[
        '/c',
        path,
      ], mode: ProcessStartMode.detached);
    } else if (path.endsWith('.sh')) {
      await Process.start('/bin/sh', <String>[
        path,
      ], mode: ProcessStartMode.detached);
    } else {
      await Process.start(
        path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
    }
    exit(0);
  }
}
