import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/android_update_service.dart';
import 'package:spectrumstrategy/src/services/desktop_update_service.dart';

http.Client _releaseClient({
  required String tag,
  List<Map<String, dynamic>> assets = const [],
  int status = 200,
}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'tag_name': tag,
        'html_url': 'https://example.com/releases/$tag',
        'assets': assets,
      }),
      status,
    );
  });
}

Future<SharedPreferences> Function() _prefsLoader() {
  var initialized = false;
  return () async {
    if (!initialized) {
      SharedPreferences.setMockInitialValues({});
      initialized = true;
    }
    return SharedPreferences.getInstance();
  };
}

AndroidUpdateService _service({
  http.Client? client,
  String currentVersion = '1.0.0',
  bool isAndroid = true,
  Future<AndroidInstallOutcome> Function(String path)? installer,
  DateTime Function()? now,
}) {
  return AndroidUpdateService(
    updateService: DesktopUpdateService(
      client: client ?? _releaseClient(tag: 'v1.0.0'),
      currentVersionLoader: () async => currentVersion,
      assetSelector: AndroidUpdateService.apkAsset,
    ),
    prefs: _prefsLoader(),
    isAndroid: () => isAndroid,
    installer: installer ?? (_) async => AndroidInstallOutcome.installed,
    now: now,
  );
}

void main() {
  group('checkForUpdate', () {
    test('is a no-op off Android', () async {
      final service = _service(isAndroid: false);
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.supported, isFalse);
      expect(result.update, isNull);
    });

    test('reports an update with the apk asset and its digest', () async {
      final service = _service(
        client: _releaseClient(
          tag: 'v1.2.0',
          assets: [
            {
              'name': 'SpectrumStrategy-1.2.0.apk',
              'browser_download_url': 'https://example.com/app.apk',
              'digest': 'sha256:${'a' * 64}',
            },
          ],
        ),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.supported, isTrue);
      expect(result.hasRelease, isTrue);
      expect(result.update, isNotNull);
      expect(result.update!.latestVersion, 'v1.2.0');
      expect(result.update!.apkUrl, 'https://example.com/app.apk');
      expect(result.update!.expectedSha256, 'a' * 64);
    });

    test('ignores a non-apk asset', () async {
      final service = _service(
        client: _releaseClient(
          tag: 'v1.2.0',
          assets: [
            {
              'name': 'SpectrumStrategy-linux-x86_64.AppImage',
              'browser_download_url': 'https://example.com/app.AppImage',
              'digest': 'sha256:${'b' * 64}',
            },
          ],
        ),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.update, isNotNull);
      expect(result.update!.apkUrl, isNull);
      expect(result.update!.expectedSha256, isNull);
    });

    test('reports no update when the release is not newer', () async {
      final service = _service(client: _releaseClient(tag: 'v1.0.0'));
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isTrue);
    });

    test('reports no release on a 404', () async {
      final service = _service(
        client: _releaseClient(tag: 'v9.9.9', status: 404),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isFalse);
    });
  });

  group('dueForStartupCheck', () {
    test('true when never checked', () async {
      final service = _service();
      expect(await service.dueForStartupCheck(), isTrue);
    });

    test('false right after a recorded check, true a day later', () async {
      var clock = DateTime.utc(2026, 1, 1);
      final service = _service(now: () => clock);
      await service.checkForUpdate(channel: DesktopUpdateChannel.stable);
      expect(await service.dueForStartupCheck(), isFalse);

      clock = clock.add(const Duration(days: 1, minutes: 1));
      expect(await service.dueForStartupCheck(), isTrue);
    });
  });

  group('downloadAndInstall', () {
    test('refuses a release with no digest', () async {
      final service = _service();
      expect(
        () => service.downloadAndInstall(
          AndroidUpdateInfo(
            currentVersion: '1.0.0',
            latestVersion: 'v1.1.0',
            releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
            apkUrl: 'https://example.com/app.apk',
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses a non-https download URL', () async {
      final service = _service();
      expect(
        () => service.downloadAndInstall(
          AndroidUpdateInfo(
            currentVersion: '1.0.0',
            latestVersion: 'v1.1.0',
            releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
            apkUrl: 'http://example.com/app.apk',
            expectedSha256: 'a' * 64,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses a download whose digest does not match', () async {
      final payload = List<int>.filled(200000, 42);
      final service = AndroidUpdateService(
        updateService: DesktopUpdateService(),
        prefs: _prefsLoader(),
        isAndroid: () => true,
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        installer: (_) async => AndroidInstallOutcome.installed,
      );

      expect(
        () => service.downloadAndInstall(
          AndroidUpdateInfo(
            currentVersion: '1.0.0',
            latestVersion: 'v1.1.0',
            releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
            apkUrl: 'https://example.com/app.apk',
            expectedSha256: 'a' * 64,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('downloads, verifies, and hands the file to the installer', () async {
      final payload = List<int>.filled(200000, 42);
      final digest = sha256.convert(payload).toString();
      String? installedPath;
      final tempDir = Directory.systemTemp.createTempSync('android_update');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final service = AndroidUpdateService(
        updateService: DesktopUpdateService(),
        prefs: _prefsLoader(),
        isAndroid: () => true,
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        cacheDirLoader: () async => tempDir,
        installer: (path) async {
          installedPath = path;
          return AndroidInstallOutcome.installed;
        },
      );

      final outcome = await service.downloadAndInstall(
        AndroidUpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: 'v1.1.0',
          releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
          apkUrl: 'https://example.com/app.apk',
          expectedSha256: digest,
        ),
      );

      expect(outcome, AndroidInstallOutcome.installed);
      expect(installedPath, isNotNull);
      expect(installedPath, startsWith('${tempDir.path}/update/'));
      expect(File(installedPath!).readAsBytesSync(), payload);
    });

    test(
      'writes each download to a unique path and clears stale ones',
      () async {
        final payloadA = List<int>.filled(200000, 1);
        final digestA = sha256.convert(payloadA).toString();
        final payloadB = List<int>.filled(200000, 2);
        final digestB = sha256.convert(payloadB).toString();
        var nextPayload = payloadA;
        final tempDir = Directory.systemTemp.createTempSync('android_update');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        final installedPaths = <String>[];
        final service = AndroidUpdateService(
          updateService: DesktopUpdateService(),
          prefs: _prefsLoader(),
          isAndroid: () => true,
          client: MockClient(
            (_) async => http.Response.bytes(nextPayload, 200),
          ),
          cacheDirLoader: () async => tempDir,
          installer: (path) async {
            installedPaths.add(path);
            return AndroidInstallOutcome.installed;
          },
        );

        await service.downloadAndInstall(
          AndroidUpdateInfo(
            currentVersion: '1.0.0',
            latestVersion: 'v1.1.0',
            releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
            apkUrl: 'https://example.com/app.apk',
            expectedSha256: digestA,
          ),
        );

        nextPayload = payloadB;
        await service.downloadAndInstall(
          AndroidUpdateInfo(
            currentVersion: '1.0.0',
            latestVersion: 'v1.2.0',
            releaseUrl: Uri.parse('https://example.com/releases/v1.2.0'),
            apkUrl: 'https://example.com/app.apk',
            expectedSha256: digestB,
          ),
        );

        expect(installedPaths, hasLength(2));
        expect(installedPaths[0], isNot(installedPaths[1]));
        final updateDir = Directory('${tempDir.path}/update');
        final remaining = updateDir.listSync().map((f) => f.path).toList();
        expect(remaining, [installedPaths[1]]);
      },
    );

    test(
      'keeps the verified file for a retry after permission_required',
      () async {
        final payload = List<int>.filled(200000, 3);
        final digest = sha256.convert(payload).toString();
        final tempDir = Directory.systemTemp.createTempSync('android_update');
        addTearDown(() => tempDir.deleteSync(recursive: true));

        var downloadCount = 0;
        final installedPaths = <String>[];
        var permissionGranted = false;
        final service = AndroidUpdateService(
          updateService: DesktopUpdateService(),
          prefs: _prefsLoader(),
          isAndroid: () => true,
          client: MockClient((_) async {
            downloadCount++;
            return http.Response.bytes(payload, 200);
          }),
          cacheDirLoader: () async => tempDir,
          installer: (path) async {
            installedPaths.add(path);
            return permissionGranted
                ? AndroidInstallOutcome.installed
                : AndroidInstallOutcome.permissionRequired;
          },
        );

        final update = AndroidUpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: 'v1.1.0',
          releaseUrl: Uri.parse('https://example.com/releases/v1.1.0'),
          apkUrl: 'https://example.com/app.apk',
          expectedSha256: digest,
        );

        final first = await service.downloadAndInstall(update);
        expect(first, AndroidInstallOutcome.permissionRequired);

        permissionGranted = true;
        final second = await service.downloadAndInstall(update);
        expect(second, AndroidInstallOutcome.installed);

        expect(downloadCount, 1);
        expect(installedPaths[0], installedPaths[1]);
      },
    );
  });

  group('apkAsset', () {
    test('picks the most recently created apk asset', () {
      final asset = AndroidUpdateService.apkAsset([
        {
          'name': 'SpectrumStrategy-1.0.0.apk',
          'browser_download_url': 'https://example.com/old.apk',
          'digest': 'sha256:${'1' * 64}',
          'created_at': '2026-01-01T00:00:00Z',
        },
        {
          'name': 'SpectrumStrategy-1.0.1.apk',
          'browser_download_url': 'https://example.com/new.apk',
          'digest': 'sha256:${'2' * 64}',
          'created_at': '2026-02-01T00:00:00Z',
        },
      ]);
      expect(asset.url, 'https://example.com/new.apk');
      expect(asset.digest, '2' * 64);
    });

    test('returns nulls when nothing matches', () {
      final asset = AndroidUpdateService.apkAsset([
        {
          'name': 'SpectrumStrategy-windows-x64.zip',
          'browser_download_url': 'https://example.com/app.zip',
        },
      ]);
      expect(asset.url, isNull);
      expect(asset.digest, isNull);
    });
  });
}
