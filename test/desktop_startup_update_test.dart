import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/services/desktop_self_update_service.dart';
import 'package:spectrumstrategy/src/services/desktop_startup_update.dart';
import 'package:spectrumstrategy/src/services/desktop_update_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('installs a verified update silently on launch', () async {
    final dir = Directory.systemTemp.createTempSync('startupupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    var relaunched = '';

    final updateService = DesktopUpdateService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v9.9.9',
            'html_url': 'https://example.com/releases/v9.9.9',
            'assets': [
              {
                'name': 'SpectrumStrategy-linux-x86_64.AppImage',
                'browser_download_url': 'https://example.com/App.AppImage',
                'digest': 'sha256:${sha256.convert(payload)}',
              },
            ],
          }),
          200,
        );
      }),
      currentVersionLoader: () async => '1.0.0',
    );
    await updateService.setAutoUpdateEnabled(true);
    final selfUpdate = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (p) async => relaunched = p,
    );

    await runDesktopStartupUpdateCheck(
      updateService: updateService,
      selfUpdate: selfUpdate,
    );

    expect(target.readAsBytesSync(), payload);
    expect(relaunched, target.path);
  });

  test('does nothing when auto-update is left off (the default)', () async {
    final dir = Directory.systemTemp.createTempSync('startupupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    var checked = false;

    final updateService = DesktopUpdateService(
      client: MockClient((request) async {
        checked = true;
        return http.Response('', 500);
      }),
      currentVersionLoader: () async => '1.0.0',
    );
    final selfUpdate = DesktopSelfUpdateService(
      appImagePathLoader: () => target.path,
    );

    await runDesktopStartupUpdateCheck(
      updateService: updateService,
      selfUpdate: selfUpdate,
    );

    expect(checked, isFalse);
    expect(target.readAsBytesSync(), [0]);
  });

  test('leaves the install untouched when nothing is newer', () async {
    final dir = Directory.systemTemp.createTempSync('startupupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);

    final updateService = DesktopUpdateService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.0',
            'html_url': 'https://example.com/releases/v1.0.0',
          }),
          200,
        );
      }),
      currentVersionLoader: () async => '1.0.0',
    );
    await updateService.setAutoUpdateEnabled(true);
    final selfUpdate = DesktopSelfUpdateService(
      appImagePathLoader: () => target.path,
    );

    await runDesktopStartupUpdateCheck(
      updateService: updateService,
      selfUpdate: selfUpdate,
    );

    expect(target.readAsBytesSync(), [0]);
  });

  test('swallows a network failure instead of throwing', () async {
    final dir = Directory.systemTemp.createTempSync('startupupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);

    final updateService = DesktopUpdateService(
      client: MockClient((request) async => throw const SocketException('x')),
      currentVersionLoader: () async => '1.0.0',
    );
    await updateService.setAutoUpdateEnabled(true);
    final selfUpdate = DesktopSelfUpdateService(
      appImagePathLoader: () => target.path,
    );

    await expectLater(
      runDesktopStartupUpdateCheck(
        updateService: updateService,
        selfUpdate: selfUpdate,
      ),
      completes,
    );
  });
}
