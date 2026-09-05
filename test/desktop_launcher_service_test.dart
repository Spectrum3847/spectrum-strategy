import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/desktop_launcher_service.dart';

void main() {
  test('desktopEntry points Exec at the quoted AppImage path', () {
    final entry = DesktopLauncherService.desktopEntry('/home/u/App x.AppImage');
    expect(entry, startsWith('[Desktop Entry]'));
    expect(entry, contains('Name=Spectrum Strategy'));
    expect(entry, contains('Exec="/home/u/App x.AppImage" %U'));
  });

  test('registerInLauncher writes the entry under the home dir', () async {
    final dir = Directory.systemTemp.createTempSync('launcher');
    final service = DesktopLauncherService(
      appImagePathLoader: () => '/tmp/App.AppImage',
      appDirLoader: () => null,
      homeLoader: () => dir.path,
    );

    final path = await service.registerInLauncher();

    expect(path, endsWith('/applications/spectrumstrategy.desktop'));
    final entry = File(path).readAsStringSync();
    expect(entry, contains('Exec="/tmp/App.AppImage"'));

    expect(entry, contains('Icon=spectrumstrategy\n'));
    dir.deleteSync(recursive: true);
  });

  test(
    'registerInLauncher installs the AppDir icon and references it',
    () async {
      final home = Directory.systemTemp.createTempSync('launcher-home');
      final appDir = Directory.systemTemp.createTempSync('launcher-appdir');
      File('${appDir.path}/spectrumstrategy.png')
          .writeAsBytesSync(List<int>.filled(200, 0x42));
      final service = DesktopLauncherService(
        appImagePathLoader: () => '/tmp/App.AppImage',
        appDirLoader: () => appDir.path,
        homeLoader: () => home.path,
      );

      final path = await service.registerInLauncher();

      final icon = '${home.path}/.local/share/icons/spectrumstrategy.png';
      expect(File(icon).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), contains('Icon=$icon\n'));
      home.deleteSync(recursive: true);
      appDir.deleteSync(recursive: true);
    },
  );

  test('registerInLauncher skips the placeholder stub icon', () async {
    final home = Directory.systemTemp.createTempSync('launcher-home');
    final appDir = Directory.systemTemp.createTempSync('launcher-appdir');

    File(
      '${appDir.path}/spectrumstrategy.png',
    ).writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final service = DesktopLauncherService(
      appImagePathLoader: () => '/tmp/App.AppImage',
      appDirLoader: () => appDir.path,
      homeLoader: () => home.path,
    );

    final path = await service.registerInLauncher();

    expect(File(path).readAsStringSync(), contains('Icon=spectrumstrategy\n'));
    home.deleteSync(recursive: true);
    appDir.deleteSync(recursive: true);
  });

  test('registerInLauncher throws without an AppImage path', () async {
    final service = DesktopLauncherService(
      appImagePathLoader: () => null,
      homeLoader: () => '/home/u',
    );

    await expectLater(service.registerInLauncher(), throwsStateError);
  });

  test('desktopEntry escapes reserved characters in the Exec path', () {
    final entry = DesktopLauncherService.desktopEntry(
      r'/home/a$b/`c`/d"e"/f\g/App.AppImage',
    );

    expect(
      entry,
      contains(r'Exec="/home/a\\$b/\\`c\\`/d\\"e\\"/f\\\\g/App.AppImage" %U'),
    );

    expect(entry, contains(' %U'));
  });

  test('desktopEntry doubles a literal percent in the Exec path', () {
    final entry = DesktopLauncherService.desktopEntry(
      '/home/u/100% Done/App.AppImage',
    );

    expect(entry, contains('Exec="/home/u/100%% Done/App.AppImage" %U'));
  });

  test('desktopEntry escapes a backslash and newline in the icon path', () {
    final entry = DesktopLauncherService.desktopEntry(
      '/home/u/App.AppImage',
      iconPath: 'C:\\icons\\a\nb.png',
    );

    expect(
      entry,
      contains(
        r'Icon=C:\\icons\\a\nb.png'
        '\n',
      ),
    );
  });

  test('desktopEntry leaves an ordinary path untouched', () {
    final entry = DesktopLauncherService.desktopEntry(
      '/home/user/Apps/Spectrum Strategy.AppImage',
    );

    expect(
      entry,
      contains('Exec="/home/user/Apps/Spectrum Strategy.AppImage" %U'),
    );
  });
}
