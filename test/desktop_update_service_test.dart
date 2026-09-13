import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:spectrumstrategy/src/services/desktop_self_update_service.dart'
    show DesktopSelfUpdatePlatform;
import 'package:spectrumstrategy/src/services/desktop_update_service.dart';

http.Client _clientReturning({required String tag, int status = 200}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'tag_name': tag,
        'html_url': 'https://example.com/releases/$tag',
      }),
      status,
    );
  });
}

void main() {
  test('reports an update when the release is newer', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.2.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    final info = (await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    )).update;
    expect(info, isNotNull);
    expect(info!.latestVersion, 'v1.2.0');
    expect(info.currentVersion, '1.1.0');
  });

  test('reports no update when the release is the same or older', () async {
    final same = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.1.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(
      (await same.checkForUpdate(channel: DesktopUpdateChannel.stable)).update,
      isNull,
    );

    final older = DesktopUpdateService(
      client: _clientReturning(tag: 'v1.0.0'),
      currentVersionLoader: () async => '1.1.0',
    );
    expect(
      (await older.checkForUpdate(channel: DesktopUpdateChannel.stable)).update,
      isNull,
    );
  });

  test('returns no release on a non-200 response', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v9.9.9', status: 404),
      currentVersionLoader: () async => '1.0.0',
    );
    final result = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(result.update, isNull);
    expect(result.hasRelease, isFalse);
  });

  test(
    'stable release exists but is not newer reports hasRelease with no update',
    () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.0.0'),
        currentVersionLoader: () async => '1.0.0',
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isTrue);
    },
  );

  test('an unreachable repository throws rather than reading as current', () {
    final service = DesktopUpdateService(
      client: MockClient(
        (_) async => throw http.ClientException('connection refused'),
      ),
      currentVersionLoader: () async => '1.1.0',
      repositories: const <String>['Spectrum3847/spectrum-strategy'],
    );

    expect(
      service.checkForUpdate(channel: DesktopUpdateChannel.stable),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('a transport failure is swallowed once another answered', () async {
    var calls = 0;
    final service = DesktopUpdateService(
      client: MockClient((request) async {
        if (calls++ == 0) throw http.ClientException('connection refused');
        return http.Response(
          jsonEncode({
            'tag_name': 'v1.0.0',
            'html_url': 'https://example.com/releases/v1.0.0',
          }),
          200,
        );
      }),
      currentVersionLoader: () async => '1.1.0',
      repositories: const <String>['Spectrum3847/gone', 'Spectrum3847/live'],
    );

    final result = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(result.update, isNull);
    expect(result.hasRelease, isTrue);
  });

  test('one reachable repository is enough to answer', () async {
    var calls = 0;
    final service = DesktopUpdateService(
      client: MockClient((request) async {
        if (calls++ == 0) throw http.ClientException('connection refused');
        return http.Response(
          jsonEncode({
            'tag_name': 'v2.0.0',
            'html_url': 'https://example.com/releases/v2.0.0',
          }),
          200,
        );
      }),
      currentVersionLoader: () async => '1.1.0',
      repositories: const <String>['Spectrum3847/gone', 'Spectrum3847/live'],
    );

    final info = (await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    )).update;
    expect(info?.latestVersion, 'v2.0.0');
    expect(info?.repository, 'Spectrum3847/live');
  });

  test('returns no update when the current version cannot be parsed', () async {
    final service = DesktopUpdateService(
      client: _clientReturning(tag: 'v2.0.0'),
      currentVersionLoader: () async => 'unknown',
    );
    final result = await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    );
    expect(result.update, isNull);
    expect(result.hasRelease, isTrue);
  });

  test('captures the AppImage asset url when present', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'tag_name': 'v2.0.0',
          'html_url': 'https://example.com/releases/v2.0.0',
          'assets': [
            {
              'name': 'SpectrumStrategy-windows-x64.zip',
              'browser_download_url': 'https://example.com/win.zip',
            },
            {
              'name': 'SpectrumStrategy-linux-x86_64.AppImage',
              'browser_download_url': 'https://example.com/app.AppImage',
            },
          ],
        }),
        200,
      );
    });
    final service = DesktopUpdateService(
      client: client,
      currentVersionLoader: () async => '1.0.0',
    );
    final info = (await service.checkForUpdate(
      channel: DesktopUpdateChannel.stable,
    )).update;
    expect(info, isNotNull);
    expect(info!.assetUrl, 'https://example.com/app.AppImage');
  });

  group('platform asset selection', () {
    http.Client clientWithAllAssets() {
      return MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v2.0.0',
            'html_url': 'https://example.com/releases/v2.0.0',
            'assets': [
              {
                'name': 'SpectrumStrategy-linux-x86_64.AppImage',
                'browser_download_url': 'https://example.com/linux.AppImage',
                'digest': 'sha256:${'1' * 64}',
              },
              {
                'name': 'SpectrumStrategy-macos.zip',
                'browser_download_url': 'https://example.com/macos.zip',
                'digest': 'sha256:${'2' * 64}',
              },
              {
                'name': 'SpectrumStrategy-windows-x64.zip',
                'browser_download_url': 'https://example.com/win.zip',
                'digest': 'sha256:${'3' * 64}',
              },
            ],
          }),
          200,
        );
      });
    }

    Future<DesktopUpdateInfo> check(DesktopSelfUpdatePlatform platform) async {
      final service = DesktopUpdateService(
        client: clientWithAllAssets(),
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => platform,
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      )).update;
      expect(info, isNotNull);
      return info!;
    }

    test('windows picks the windows zip and its digest', () async {
      final info = await check(DesktopSelfUpdatePlatform.windows);
      expect(info.assetUrl, 'https://example.com/win.zip');
      expect(info.expectedSha256, '3' * 64);
    });

    test('macos picks the macos zip and its digest', () async {
      final info = await check(DesktopSelfUpdatePlatform.macos);
      expect(info.assetUrl, 'https://example.com/macos.zip');
      expect(info.expectedSha256, '2' * 64);
    });

    test('reports no asset when the platform has no matching upload', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v2.0.0'),
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
      )).update;
      expect(info!.assetUrl, isNull);
      expect(info.expectedSha256, isNull);
    });
  });

  group('multiple same-platform assets on the rolling release', () {
    http.Client clientWithTwoWindowsAssets() {
      return MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'nightly',
            'html_url': 'https://example.com/releases/nightly',
            'assets': [
              {
                'name': 'SpectrumStrategy-windows-x64-11.zip',
                'browser_download_url': 'https://example.com/win-11.zip',
                'digest': 'sha256:${'1' * 64}',
                'created_at': '2026-08-27T06:10:00Z',
              },
              {
                'name': 'SpectrumStrategy-windows-x64-12.zip',
                'browser_download_url': 'https://example.com/win-12.zip',
                'digest': 'sha256:${'2' * 64}',
                'created_at': '2026-08-28T06:10:00Z',
              },
            ],
          }),
          200,
        );
      });
    }

    test(
      'picks the most recently created asset, not the first listed',
      () async {
        final service = DesktopUpdateService(
          client: clientWithTwoWindowsAssets(),
          currentVersionLoader: () async => '1.0.0',
          platformLoader: () => DesktopSelfUpdatePlatform.windows,
        );
        final info = (await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        )).update;
        expect(info, isNotNull);
        expect(info!.assetUrl, 'https://example.com/win-12.zip');
        expect(info.expectedSha256, '2' * 64);
      },
    );

    test('an asset with no created_at never displaces a dated one', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'nightly',
            'html_url': 'https://example.com/releases/nightly',
            'assets': [
              {
                'name': 'SpectrumStrategy-windows-x64-12.zip',
                'browser_download_url': 'https://example.com/win-12.zip',
                'digest': 'sha256:${'2' * 64}',
                'created_at': '2026-08-28T06:10:00Z',
              },
              {
                'name': 'SpectrumStrategy-windows-x64-13.zip',
                'browser_download_url': 'https://example.com/win-13.zip',
                'digest': 'sha256:${'3' * 64}',
              },
            ],
          }),
          200,
        );
      });
      final service = DesktopUpdateService(
        client: client,
        currentVersionLoader: () async => '1.0.0',
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      )).update;
      expect(info, isNotNull);
      expect(info!.assetUrl, 'https://example.com/win-12.zip');
    });
  });

  group('prerelease ordering', () {
    test(
      'a stable release is newer than an rc of the same core version',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'v1.0.0'),
          currentVersionLoader: () async => '1.0.0-rc.19',
        );
        final info = (await service.checkForUpdate(
          channel: DesktopUpdateChannel.stable,
        )).update;
        expect(info, isNotNull);
        expect(info!.latestVersion, 'v1.0.0');
      },
    );

    test(
      'a later rc is newer than an earlier rc of the same core version',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'v1.0.0-rc.20'),
          currentVersionLoader: () async => '1.0.0-rc.19',
        );
        final info = (await service.checkForUpdate(
          channel: DesktopUpdateChannel.stable,
        )).update;
        expect(info, isNotNull);
        expect(info!.latestVersion, 'v1.0.0-rc.20');
      },
    );

    test(
      'an rc release is not newer than the stable version it precedes',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'v1.0.0-rc.5'),
          currentVersionLoader: () async => '1.0.0',
        );
        expect(
          (await service.checkForUpdate(channel: DesktopUpdateChannel.stable))
              .update,
          isNull,
        );
      },
    );
  });
  group('update channel', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to stable when nothing is persisted', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.0.0'),
        currentVersionLoader: () async => '1.0.0',
      );
      expect(await service.currentChannel(), DesktopUpdateChannel.stable);
    });

    test(
      'setChannel persists the choice for currentChannel to read back',
      () async {
        final service = DesktopUpdateService(
          client: _clientReturning(tag: 'v1.0.0'),
          currentVersionLoader: () async => '1.0.0',
        );
        await service.setChannel(DesktopUpdateChannel.nightly);
        expect(await service.currentChannel(), DesktopUpdateChannel.nightly);

        await service.setChannel(DesktopUpdateChannel.stable);
        expect(await service.currentChannel(), DesktopUpdateChannel.stable);
      },
    );

    test(
      'checkForUpdate with no explicit channel reads the persisted one',
      () async {
        final service = DesktopUpdateService(
          client: MockClient((request) async {
            expect(
              request.url.path,
              '/repos/Spectrum3847/spectrum-strategy/releases/tags/nightly',
            );
            return http.Response(
              jsonEncode({
                'tag_name': 'nightly',
                'html_url': 'https://example.com/releases/nightly',
              }),
              200,
            );
          }),
          currentVersionLoader: () async => '1.0.0',
          repositories: const <String>['Spectrum3847/spectrum-strategy'],
        );
        await service.setChannel(DesktopUpdateChannel.nightly);
        final info = (await service.checkForUpdate()).update;
        expect(info?.latestVersion, 'nightly');
      },
    );
  });

  group('nightly channel', () {
    test(
      'reads the rolling nightly release, whose tag is not semantic versioning',
      () async {
        final service = DesktopUpdateService(
          client: MockClient((request) async {
            expect(
              request.url.path,
              '/repos/Spectrum3847/spectrum-strategy/releases/tags/nightly',
            );
            return http.Response(
              jsonEncode({
                'tag_name': 'nightly',
                'html_url': 'https://example.com/releases/nightly',
                'assets': [
                  {
                    'name': 'SpectrumStrategy-linux-x86_64.AppImage',
                    'browser_download_url':
                        'https://example.com/nightly.AppImage',
                    'digest': 'sha256:${'a' * 64}',
                  },
                ],
              }),
              200,
            );
          }),
          currentVersionLoader: () async => '1.0.0',
        );
        final info = (await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        )).update;
        expect(info, isNotNull);
        expect(info!.latestVersion, 'nightly');
        expect(info.assetUrl, 'https://example.com/nightly.AppImage');
        expect(info.expectedSha256, 'a' * 64);
      },
    );

    test('is reported with no version gate', () async {
      final service = DesktopUpdateService(
        client: _nightlyClientReturning(),
        currentVersionLoader: () async => '9.9.9',
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      )).update;
      expect(info, isNotNull);
    });

    test('reports nothing while the build is younger than 4 hours', () async {
      var requested = false;
      final service = DesktopUpdateService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 3, 59),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isTrue);
      expect(requested, isFalse);
    });

    test('reports an update once the build is older than 4 hours', () async {
      final service = DesktopUpdateService(
        client: _nightlyClientReturning(),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 4, 1),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(result.hasRelease, isTrue);
      expect(result.update?.latestVersion, 'nightly');
    });

    test('a build just inside the freshness window stays current', () async {
      var requested = false;
      final service = DesktopUpdateService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 3, 59, 59),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isTrue);
      expect(requested, isFalse);
    });

    test(
      'reports no update when the build timestamp is in the future',
      () async {
        var requested = false;
        final service = DesktopUpdateService(
          client: MockClient((_) async {
            requested = true;
            return http.Response('{}', 200);
          }),
          currentVersionLoader: () async => '1.0.0',
          buildTimestamp: '2026-08-31T00:00:00Z',
          now: () => DateTime.utc(2026, 8, 30),
        );
        final result = await service.checkForUpdate(
          channel: DesktopUpdateChannel.nightly,
        );
        expect(result.update, isNull);
        expect(result.hasRelease, isTrue);
        expect(requested, isFalse);
      },
    );

    test('offers the nightly when BUILD_TIMESTAMP is empty', () async {
      final service = DesktopUpdateService(
        client: _nightlyClientReturning(),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '',
        now: () => DateTime.utc(2026, 8, 30),
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      )).update;
      expect(info?.latestVersion, 'nightly');
    });

    test('a fresh nightly is up to date even with ignoreVersionGate, with no request', () async {
      var requested = false;
      final service = DesktopUpdateService(
        client: MockClient((_) async {
          requested = true;
          return http.Response('{}', 200);
        }),
        currentVersionLoader: () async => '1.0.0',
        buildTimestamp: '2026-08-30T00:00:00Z',
        now: () => DateTime.utc(2026, 8, 30, 1),
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
        ignoreVersionGate: true,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isTrue);
      expect(requested, isFalse);
    });

    test('returns no release when no nightly release exists yet', () async {
      final service = DesktopUpdateService(
        client: MockClient((_) async => http.Response('Not Found', 404)),
        currentVersionLoader: () async => '1.0.0',
      );
      final result = await service.checkForUpdate(
        channel: DesktopUpdateChannel.nightly,
      );
      expect(result.update, isNull);
      expect(result.hasRelease, isFalse);
    });
  });

  group('ignoreVersionGate', () {
    test('offers the stable release even when it is not newer', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.0.0'),
        currentVersionLoader: () async => '1.5.0',
      );
      expect(
        (await service.checkForUpdate(channel: DesktopUpdateChannel.stable))
            .update,
        isNull,
      );
      final info = (await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
        ignoreVersionGate: true,
      )).update;
      expect(info?.latestVersion, 'v1.0.0');
    });

    test('reports up to date, not an update, when switching to a track '
        'already running its newest release', () async {
      final service = DesktopUpdateService(
        client: _clientReturning(tag: 'v1.8.0'),
        currentVersionLoader: () async => '1.8.0',
      );
      final check = await service.checkForUpdate(
        channel: DesktopUpdateChannel.stable,
        ignoreVersionGate: true,
      );
      expect(check.update, isNull);
      expect(check.hasRelease, isTrue);
    });
  });
}

http.Client _nightlyClientReturning() {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'tag_name': 'nightly',
        'html_url': 'https://example.com/releases/nightly',
      }),
      200,
    );
  });
}
