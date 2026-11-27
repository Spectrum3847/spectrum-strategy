import 'package:flutter_test/flutter_test.dart';
import 'package:spectrumstrategy/src/services/desktop_tray_service.dart';

void main() {
  test('hides on Windows and macOS when the icon exists', () {
    expect(
      shouldHideToTray(
        enabled: true,
        hasTrayIcon: true,
        isLinux: false,
        linuxTrayHost: false,
      ),
      isTrue,
    );
  });

  test('hides on Linux when a panel shows the icon', () {
    expect(
      shouldHideToTray(
        enabled: true,
        hasTrayIcon: true,
        isLinux: true,
        linuxTrayHost: true,
      ),
      isTrue,
    );
  });

  test('does not hide on Linux without a panel, even with an icon', () {
    expect(
      shouldHideToTray(
        enabled: true,
        hasTrayIcon: true,
        isLinux: true,
        linuxTrayHost: false,
      ),
      isFalse,
    );
  });

  test('does not hide when the setting is off', () {
    expect(
      shouldHideToTray(
        enabled: false,
        hasTrayIcon: true,
        isLinux: true,
        linuxTrayHost: true,
      ),
      isFalse,
    );
  });

  test('does not hide without a tray icon', () {
    expect(
      shouldHideToTray(
        enabled: true,
        hasTrayIcon: false,
        isLinux: false,
        linuxTrayHost: false,
      ),
      isFalse,
    );
  });
}
