import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spectrumstrategy/src/services/desktop_self_update_service.dart';

void main() {
  test('update swaps the AppImage and relaunches', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    var madeExec = '';
    var relaunched = '';
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (p) async => madeExec = p,
      relaunch: (p) async => relaunched = p,
    );

    await service.update(
      Uri.parse('https://example.com/App.AppImage'),
      expectedSha256: sha256.convert(payload).toString(),
    );

    expect(target.readAsBytesSync(), payload);

    expect(madeExec, '${target.path}.new');
    expect(relaunched, target.path);
  });

  test('update accepts an uppercase or padded digest', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await service.update(
      Uri.parse('https://example.com/App.AppImage'),
      expectedSha256: '  ${sha256.convert(payload).toString().toUpperCase()}\n',
    );

    expect(target.readAsBytesSync(), payload);
  });

  test('update throws on a too-small download', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response('not found', 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test(
    'update throws on a non-200 response and leaves the target unchanged',
    () async {
      final dir = Directory.systemTemp.createTempSync('selfupdate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/App.AppImage')
        ..writeAsBytesSync([1, 2, 3]);
      final payload = List<int>.filled(200000, 77);
      final service = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 500)),
        appImagePathLoader: () => target.path,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
      );

      await expectLater(
        service.update(
          Uri.parse('https://example.com/x'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );

      expect(target.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('update rejects a non-https URL', () async {
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes([], 200)),
      appImagePathLoader: () => '/tmp/App.AppImage',
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('http://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test('update verifies a supplied checksum and aborts on mismatch', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    final payload = List<int>.filled(200000, 88);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes(payload, 200)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/App.AppImage'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
    expect(target.readAsBytesSync(), [1, 2, 3]);
  });

  test('update throws when not running as an AppImage', () async {
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response.bytes([], 200)),
      appImagePathLoader: () => null,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/x'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
  });

  test(
    'update rejects a redirect to a non-https URL without touching the target',
    () async {
      final dir = Directory.systemTemp.createTempSync('selfupdate');
      addTearDown(() => dir.deleteSync(recursive: true));
      final target = File('${dir.path}/App.AppImage')
        ..writeAsBytesSync([1, 2, 3]);
      final service = DesktopSelfUpdateService(
        client: MockClient(
          (_) async => http.Response(
            'moved',
            302,
            headers: {'location': 'http://insecure.example.com/App.AppImage'},
          ),
        ),
        appImagePathLoader: () => target.path,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
      );

      await expectLater(
        service.update(
          Uri.parse('https://example.com/App.AppImage'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );
      expect(target.readAsBytesSync(), [1, 2, 3]);
    },
  );

  test('update follows a 302 to an https URL and installs it', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')..writeAsBytesSync([0]);
    final payload = List<int>.filled(200000, 66);
    var madeExec = '';
    var relaunched = '';
    var hop = 0;
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async {
        if (hop++ == 0) {
          return http.Response(
            'moved',
            302,
            headers: {'location': 'https://cdn.example.com/App.AppImage'},
          );
        }
        return http.Response.bytes(payload, 200);
      }),
      appImagePathLoader: () => target.path,
      makeExecutable: (p) async => madeExec = p,
      relaunch: (p) async => relaunched = p,
    );

    await service.update(
      Uri.parse('https://example.com/App.AppImage'),
      expectedSha256: sha256.convert(payload).toString(),
    );

    expect(target.readAsBytesSync(), payload);
    expect(madeExec, '${target.path}.new');
    expect(relaunched, target.path);
  });

  test('update throws when a redirect has no location header', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    final service = DesktopSelfUpdateService(
      client: MockClient((_) async => http.Response('moved', 302)),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/App.AppImage'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
    expect(target.readAsBytesSync(), [1, 2, 3]);
  });

  test('update throws rather than hanging on a redirect loop', () async {
    final dir = Directory.systemTemp.createTempSync('selfupdate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final target = File('${dir.path}/App.AppImage')
      ..writeAsBytesSync([1, 2, 3]);
    final service = DesktopSelfUpdateService(
      client: MockClient(
        (_) async => http.Response(
          'moved',
          302,
          headers: {'location': 'https://example.com/App.AppImage'},
        ),
      ),
      appImagePathLoader: () => target.path,
      makeExecutable: (_) async {},
      relaunch: (_) async {},
    );

    await expectLater(
      service.update(
        Uri.parse('https://example.com/App.AppImage'),
        expectedSha256: '0' * 64,
      ),
      throwsStateError,
    );
    expect(target.readAsBytesSync(), [1, 2, 3]);
  });

  group('canSelfUpdate', () {
    DesktopSelfUpdateService service(
      DesktopSelfUpdatePlatform platform, {
      String? Function()? appImagePath,
    }) {
      return DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes([], 200)),
        appImagePathLoader: appImagePath ?? () => null,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
        platformLoader: () => platform,
      );
    }

    test('is true on Windows regardless of AppImage variables', () {
      expect(service(DesktopSelfUpdatePlatform.windows).canSelfUpdate, isTrue);
    });

    test('is true on macOS', () {
      expect(service(DesktopSelfUpdatePlatform.macos).canSelfUpdate, isTrue);
    });

    test('on Linux requires an AppImage path', () {
      expect(service(DesktopSelfUpdatePlatform.linux).canSelfUpdate, isFalse);
      expect(
        service(
          DesktopSelfUpdatePlatform.linux,
          appImagePath: () => '',
        ).canSelfUpdate,
        isFalse,
      );
      expect(
        service(
          DesktopSelfUpdatePlatform.linux,
          appImagePath: () => '/tmp/App.AppImage',
        ).canSelfUpdate,
        isTrue,
      );
    });
  });

  group('windows zip update', () {
    late Directory dir;
    late String installDir;
    late String exePath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('selfupdate-win');
      addTearDown(() => dir.deleteSync(recursive: true));
      installDir = '${dir.path}/install/SpectrumStrategy';
      Directory(installDir).createSync(recursive: true);
      exePath = '$installDir/spectrumstrategy.exe';
      File(exePath).writeAsBytesSync([0]);
    });

    DesktopSelfUpdateService service({
      required void Function(String archivePath, String destinationPath)
      onExtract,
      Future<void> Function(String path)? relaunchProbe,
    }) {
      return DesktopSelfUpdateService(
        client: MockClient(
          (_) async => http.Response.bytes(List<int>.filled(200000, 66), 200),
        ),
        runningExePathLoader: () => exePath,
        extractArchive: (archivePath, destinationPath) async =>
            onExtract(archivePath, destinationPath),
        makeExecutable: (_) async {},
        relaunch: relaunchProbe ?? (_) async {},
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );
    }

    test(
      'stages, extracts, writes the relauncher, and hands off to it',
      () async {
        final payload = List<int>.filled(200000, 66);
        String? archivePath;
        var payloadDir = '';
        String? relaunched;
        final svc = DesktopSelfUpdateService(
          client: MockClient((_) async => http.Response.bytes(payload, 200)),
          runningExePathLoader: () => exePath,

          extractArchive: (archive, destinationPath) async {
            archivePath = archive;
            payloadDir = destinationPath;
            File('$destinationPath/spectrumstrategy.exe').writeAsBytesSync([1]);
          },
          makeExecutable: (_) async {},
          relaunch: (p) async => relaunched = p,
          platformLoader: () => DesktopSelfUpdatePlatform.windows,
        );

        await svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-windows-x64.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        );

        expect(archivePath, isNotNull);
        expect(File(archivePath!).readAsBytesSync(), payload);
        expect(relaunched, endsWith('apply-update.bat'));
        final script = File(relaunched!).readAsStringSync();
        expect(
          script,
          contains('tasklist /FI "PID eq $pid" /NH 2>NUL | find "$pid" >NUL'),
        );
        expect(script, contains('ping -n 2 127.0.0.1 >NUL'));

        expect(script, contains(r'if %WAITED% LSS 60 goto wait'));

        expect(script, contains('set "PAYLOAD=$payloadDir"'));

        expect(script, contains(r'robocopy "%PAYLOAD%" "%STAGED%" /MIR'));
        expect(script, contains(r'move /y "%INSTALL%" "%OLDDIR%" >NUL'));
        expect(script, contains(r'move /y "%STAGED%" "%INSTALL%" >NUL'));
        expect(script, contains(r'start "" "%INSTALL%\%EXE%"'));

        expect(Directory(payloadDir).parent.existsSync(), isTrue);
      },
    );

    test('throws when the extraction has no executable', () async {
      final payload = List.filled(200000, 66);
      var stagingDir = '';
      final svc = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        runningExePathLoader: () => exePath,
        extractArchive: (_, destinationPath) async {
          stagingDir = Directory(destinationPath).parent.path;
          File('$destinationPath/readme.txt').writeAsStringSync('nope');
        },
        makeExecutable: (_) async {},
        relaunch: (_) async {},
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-windows-x64.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        ),
        throwsStateError,
      );

      expect(stagingDir, isNotEmpty);
      expect(Directory(stagingDir).existsSync(), isFalse);
    });

    test('refuses a non-ASCII install path and cleans up staging', () async {
      final payload = List.filled(200000, 66);
      var stagingDir = '';
      var relaunched = false;
      final svc = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        runningExePathLoader: () => '${dir.path}/instalación/app.exe',
        extractArchive: (_, destinationPath) async {
          stagingDir = Directory(destinationPath).parent.path;
          File('$destinationPath/app.exe').writeAsBytesSync([1]);
        },
        makeExecutable: (_) async {},
        relaunch: (_) async => relaunched = true,
        platformLoader: () => DesktopSelfUpdatePlatform.windows,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-windows-x64.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        ),
        throwsStateError,
      );
      expect(relaunched, isFalse);
      expect(stagingDir, isNotEmpty);
      expect(Directory(stagingDir).existsSync(), isFalse);
    });

    test('verifies the digest before staging anything', () async {
      var extracted = false;
      final svc = service(onExtract: (_, _) => extracted = true);

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-windows-x64.zip'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );
      expect(extracted, isFalse);
    });
  });

  group('macos app bundle update', () {
    late Directory dir;
    late String bundlePath;
    late String exePath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('selfupdate-mac');
      addTearDown(() => dir.deleteSync(recursive: true));
      bundlePath = '${dir.path}/Applications/Spectrum Strategy.app';
      final macosDir = '$bundlePath/Contents/MacOS';
      Directory(macosDir).createSync(recursive: true);
      exePath = '$macosDir/spectrumstrategy';
      File(exePath).writeAsBytesSync([0]);
    });

    test(
      'stages, extracts, writes the relauncher, and hands off to it',
      () async {
        final payload = List<int>.filled(200000, 66);
        var stagedApp = '';
        String? relaunched;
        final svc = DesktopSelfUpdateService(
          client: MockClient((_) async => http.Response.bytes(payload, 200)),
          runningExePathLoader: () => exePath,

          extractArchive: (_, destinationPath) async {
            stagedApp = '$destinationPath/Spectrum Strategy.app';
            Directory('$stagedApp/Contents/MacOS').createSync(recursive: true);
            File('$stagedApp/Contents/MacOS/spectrumstrategy')
                .writeAsBytesSync([1]);
          },
          makeExecutable: (_) async {},
          relaunch: (p) async => relaunched = p,
          platformLoader: () => DesktopSelfUpdatePlatform.macos,
        );

        await svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-macos.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        );

        expect(relaunched, endsWith('apply-update.sh'));
        final script = File(relaunched!).readAsStringSync();
        expect(script, contains('APP_PID=$pid'));

        expect(script, contains(r'while kill -0 "$APP_PID" 2>/dev/null; do'));
        expect(script, contains(r'[ "$n" -ge 60 ] && break'));

        expect(
          script,
          contains('STAGED=${DesktopSelfUpdateService.shellQuote(stagedApp)}'),
        );
        expect(script, contains(r'cp -R "$STAGED" "$NEW"'));
        final movedAside = script.indexOf(r'mv "$INSTALL" "$OLD"');
        final swappedIn = script.indexOf(r'mv "$NEW" "$INSTALL"');
        final droppedOld = script.indexOf(r'rm -rf "$OLD"', swappedIn);
        expect(movedAside, lessThan(swappedIn));
        expect(droppedOld, greaterThan(swappedIn));

        expect(script, isNot(contains(r'rm -rf "$INSTALL"')));
        expect(
          script,
          endsWith(
            r'open "$INSTALL"'
            '\n',
          ),
        );
      },
    );

    test('throws when the extracted bundle lacks the executable', () async {
      final payload = List.filled(200000, 66);
      var stagingDir = '';
      var relaunched = false;
      final svc = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        runningExePathLoader: () => exePath,

        extractArchive: (_, destinationPath) async {
          stagingDir = Directory(destinationPath).parent.path;
          Directory('$destinationPath/Spectrum.app/Contents')
              .createSync(recursive: true);
        },
        makeExecutable: (_) async {},
        relaunch: (_) async => relaunched = true,
        platformLoader: () => DesktopSelfUpdatePlatform.macos,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-macos.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        ),
        throwsStateError,
      );
      expect(relaunched, isFalse);

      expect(stagingDir, isNotEmpty);
      expect(Directory(stagingDir).existsSync(), isFalse);
    });

    test('cleans up staging when extraction fails', () async {
      final payload = List.filled(200000, 66);
      var stagingDir = '';
      var relaunched = false;
      final svc = DesktopSelfUpdateService(
        client: MockClient((_) async => http.Response.bytes(payload, 200)),
        runningExePathLoader: () => exePath,
        extractArchive: (_, destinationPath) async {
          stagingDir = Directory(destinationPath).parent.path;
          throw StateError('disk full');
        },
        makeExecutable: (_) async {},
        relaunch: (_) async => relaunched = true,
        platformLoader: () => DesktopSelfUpdatePlatform.macos,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-macos.zip'),
          expectedSha256: sha256.convert(payload).toString(),
        ),
        throwsStateError,
      );
      expect(relaunched, isFalse);
      expect(stagingDir, isNotEmpty);
      expect(Directory(stagingDir).existsSync(), isFalse);
    });

    test('verifies the digest before staging anything', () async {
      var extracted = false;
      final svc = DesktopSelfUpdateService(
        client: MockClient(
          (_) async => http.Response.bytes(List.filled(200000, 66), 200),
        ),
        runningExePathLoader: () => exePath,
        extractArchive: (_, _) async => extracted = true,
        makeExecutable: (_) async {},
        relaunch: (_) async {},
        platformLoader: () => DesktopSelfUpdatePlatform.macos,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-macos.zip'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );
      expect(extracted, isFalse);
    });

    test('throws before downloading when not inside an .app bundle', () async {
      var downloaded = false;
      final svc = DesktopSelfUpdateService(
        client: MockClient((_) async {
          downloaded = true;
          return http.Response.bytes(List.filled(200000, 66), 200);
        }),
        runningExePathLoader: () => '/opt/bin/spectrumstrategy',
        extractArchive: (_, _) async {},
        makeExecutable: (_) async {},
        relaunch: (_) async {},
        platformLoader: () => DesktopSelfUpdatePlatform.macos,
      );

      await expectLater(
        svc.update(
          Uri.parse('https://example.com/SpectrumStrategy-macos.zip'),
          expectedSha256: '0' * 64,
        ),
        throwsStateError,
      );
      expect(downloaded, isFalse);
    });
  });

  test('appBundleContaining walks up to the enclosing bundle', () {
    expect(
      DesktopSelfUpdateService.appBundleContaining(
        '/Applications/Spectrum Strategy.app/Contents/MacOS/spectrumstrategy',
      ),
      '/Applications/Spectrum Strategy.app',
    );
    expect(
      DesktopSelfUpdateService.appBundleContaining('/opt/bin/app'),
      isNull,
    );
  });

  test('windowsRelaunchScript swaps via siblings and rolls back', () {
    final script = DesktopSelfUpdateService.windowsRelaunchScript(
      stagingDir: r'C:\Temp\staging',
      pid: 4242,
      payloadDir: r'C:\Users\FIRST Robotics\AppData\Local\Temp\stage\payload',
      installDir: r'C:\Program Files\Spectrum Strategy',
      executableName: 'spectrumstrategy.exe',
    );

    expect(
      script,
      contains(
        r'set "PAYLOAD=C:\Users\FIRST Robotics'
        r'\AppData\Local\Temp\stage\payload"',
      ),
    );
    expect(
      script,
      contains(r'set "INSTALL=C:\Program Files\Spectrum Strategy"'),
    );

    expect(
      script,
      contains(r'tasklist /FI "PID eq 4242" /NH 2>NUL | find "4242" >NUL'),
    );
    expect(script, contains(r'if %WAITED% LSS 60 goto wait'));

    expect(script, contains(r'robocopy "%PAYLOAD%" "%STAGED%" /MIR'));
    final movedAside = script.indexOf(r'move /y "%INSTALL%" "%OLDDIR%"');
    final swappedIn = script.indexOf(r'move /y "%STAGED%" "%INSTALL%"');
    final droppedOld = script.indexOf(r'rmdir /s /q "%OLDDIR%"', swappedIn);
    expect(movedAside, lessThan(swappedIn));
    expect(droppedOld, greaterThan(swappedIn));

    final steppedAside = script.indexOf(r'cd /d "%STAGING%"');
    expect(steppedAside, isNonNegative);
    expect(steppedAside, lessThan(movedAside));

    expect(script, isNot(contains(r'rmdir /s /q "%INSTALL%"')));

    expect(script, contains(r':rollback'));
    expect(script, contains(r'move /y "%OLDDIR%" "%INSTALL%"'));
    expect(script, contains(r'start "" "%INSTALL%\%EXE%"'));

    expect(
      script.indexOf(r'rmdir /s /q "%PAYLOAD%"'),
      greaterThan(script.indexOf(r'move /y "%STAGED%" "%INSTALL%"')),
    );
    expect(script, contains(r'del /q "%STAGING%\update.zip"'));
  });

  test('windowsRelaunchScript refuses paths cmd cannot parse safely', () {
    void build(String installDir) =>
        DesktopSelfUpdateService.windowsRelaunchScript(
          pid: 1,
          stagingDir: r'C:\Temp\stage',
          payloadDir: r'C:\Temp\stage\payload',
          installDir: installDir,
          executableName: 'app.exe',
        );

    expect(() => build(r'C:\Users\José\App'), throwsStateError);

    expect(() => build(r'C:\100% done\App'), throwsStateError);
  });

  test('macosRelaunchScript swaps via siblings and restores on failure', () {
    final script = DesktopSelfUpdateService.macosRelaunchScript(
      stagingDir: '/tmp/staging',
      pid: 99,
      stagedAppBundle: '/var/folders/x/T/stage/Payload/Spectrum.app',
      installedAppBundle: '/Applications/Spectrum.app',
    );
    expect(script, startsWith('#!/bin/sh'));
    expect(script, contains('set -u'));

    expect(
      script,
      contains("STAGED='/var/folders/x/T/stage/Payload/Spectrum.app'"),
    );
    expect(script, contains("INSTALL='/Applications/Spectrum.app'"));

    expect(script, contains(r'while kill -0 "$APP_PID" 2>/dev/null; do'));
    expect(script, contains(r'[ "$n" -ge 60 ] && break'));

    expect(script, contains(r'cp -R "$STAGED" "$NEW"'));
    final movedAside = script.indexOf(r'mv "$INSTALL" "$OLD"');
    final swappedIn = script.indexOf(r'mv "$NEW" "$INSTALL"');
    final droppedOld = script.indexOf(r'rm -rf "$OLD"', swappedIn);
    expect(movedAside, lessThan(swappedIn));
    expect(droppedOld, greaterThan(swappedIn));

    expect(script, isNot(contains(r'rm -rf "$INSTALL"')));
    expect(script, contains(r'mv "$OLD" "$INSTALL"'));
    expect(
      script,
      endsWith(
        r'open "$INSTALL"'
        '\n',
      ),
    );

    expect(script, contains(r'rm -rf "$OLD" "$STAGING"'));
  });

  test('macosRelaunchScript escapes single quotes in paths', () {
    final script = DesktopSelfUpdateService.macosRelaunchScript(
      stagingDir: '/tmp/staging',
      pid: 7,
      stagedAppBundle: "/tmp/O'Brien stage/Spectrum.app",
      installedAppBundle: "/Applications/O'Brien.app",
    );

    expect(script, contains("STAGED='/tmp/O'\\''Brien stage/Spectrum.app'"));
    expect(script, contains("INSTALL='/Applications/O'\\''Brien.app'"));

    expect(script, isNot(contains("/Applications/O'B")));
  });

  group('macosRelaunchScript executes against a real sh', () {
    late Directory dir;
    late String installBundle;
    late String stagedBundle;
    late String stagingDir;
    late String scriptPath;
    late File installedExe;
    late File openLog;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('selfupdate-mac-run');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bin = Directory('${dir.path}/bin')..createSync();

      final open = File('${bin.path}/open')
        ..writeAsStringSync(
          "#!/bin/sh\nprintf '%s\\n' \"\$1\" >> '${dir.path}/open.log'\n",
        );
      openLog = File('${dir.path}/open.log');
      Process.runSync('chmod', <String>['+x', open.path]);
      installBundle = '${dir.path}/Applications/Spectrum Strategy.app';
      Directory('$installBundle/Contents/MacOS').createSync(recursive: true);
      installedExe = File('$installBundle/Contents/MacOS/spectrumstrategy')
        ..writeAsStringSync('old');
      stagedBundle = '${dir.path}/stage/Spectrum Strategy.app';
      Directory('$stagedBundle/Contents/MacOS').createSync(recursive: true);
      File('$stagedBundle/Contents/MacOS/spectrumstrategy')
          .writeAsStringSync('new');
      stagingDir = '${dir.path}/staging';
      Directory(stagingDir).createSync();
      scriptPath = '$stagingDir/apply-update.sh';
    });

    void shim(String name, String failOnSource) {
      final path = File('${dir.path}/bin/$name');
      path.writeAsStringSync(
        '#!/bin/sh\n'
        r'case "${1##*/}" in'
        '\n'
        '  $failOnSource) exit 42 ;;\n'
        'esac\n'
        'exec /bin/$name "\$@"\n',
      );
      Process.runSync('chmod', <String>['+x', path.path]);
    }

    Future<ProcessResult> runScript() async {
      final exited = await Process.start('true', const <String>[]);
      await exited.exitCode;
      File(scriptPath).writeAsStringSync(
        DesktopSelfUpdateService.macosRelaunchScript(
          pid: exited.pid,
          stagingDir: stagingDir,
          stagedAppBundle: stagedBundle,
          installedAppBundle: installBundle,
        ),
      );
      return Process.run(
        '/bin/sh',
        <String>[scriptPath],
        environment: <String, String>{
          'PATH': '${dir.path}/bin:${Platform.environment['PATH'] ?? ''}',
        },
      );
    }

    test('a clean swap installs the staged bundle and opens it', () async {
      final result = await runScript();

      expect(result.exitCode, 0);
      expect(installedExe.readAsStringSync(), 'new');
      expect(Directory('$installBundle.update-old').existsSync(), isFalse);
      expect(Directory('$installBundle.update-new').existsSync(), isFalse);

      expect(Directory(stagingDir).existsSync(), isFalse);
      expect(openLog.readAsStringSync(), '$installBundle\n');
    });

    test('a failed swap rolls back and reopens the restored install', () async {
      shim('mv', r'*.update-new');
      final result = await runScript();

      expect(result.exitCode, 1);
      expect(installedExe.readAsStringSync(), 'old');
      expect(Directory('$installBundle.update-old').existsSync(), isFalse);
      expect(Directory('$installBundle.update-new').existsSync(), isFalse);
      expect(Directory(stagingDir).existsSync(), isFalse);
      expect(openLog.readAsStringSync(), '$installBundle\n');
    });

    test('a failed restore opens the old bundle where it sits', () async {
      shim('mv', r'*.update-new|*.update-old');
      final result = await runScript();

      expect(result.exitCode, 1);
      expect(installedExe.existsSync(), isFalse);
      final parkedExe = File(
        '$installBundle.update-old/Contents/MacOS/spectrumstrategy',
      );
      expect(parkedExe.readAsStringSync(), 'old');
      expect(Directory('$installBundle.update-new').existsSync(), isFalse);
      expect(Directory(stagingDir).existsSync(), isFalse);
      expect(openLog.readAsStringSync(), '$installBundle.update-old\n');
    });
  }, skip: Platform.isWindows ? 'requires a POSIX sh host' : null);

  test('shellQuote wraps paths and escapes embedded quotes', () {
    expect(
      DesktopSelfUpdateService.shellQuote('/Applications/App.app'),
      "'/Applications/App.app'",
    );
    expect(
      DesktopSelfUpdateService.shellQuote("/opt/Ain't.app"),
      "'/opt/Ain'\\''t.app'",
    );
  });
}
