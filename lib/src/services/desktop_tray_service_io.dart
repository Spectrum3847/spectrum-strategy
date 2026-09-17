library;

import 'dart:async' show unawaited;
import 'dart:io' show exit;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'minimize_to_tray_setting.dart';

class DesktopTrayService with TrayListener, WindowListener {
  DesktopTrayService({MinimizeToTraySetting? setting})
    : _setting = setting ?? MinimizeToTraySetting();

  static final DesktopTrayService shared = DesktopTrayService();

  static const String _showMenuKey = 'show';
  static const String _quitMenuKey = 'quit';

  final MinimizeToTraySetting _setting;
  bool _trayReady = false;

  Future<bool> isEnabled() => _setting.isEnabled();

  Future<void> setEnabled(bool enabled) => _setting.setEnabled(enabled);

  Future<void> start() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);
      trayManager.addListener(this);

      final iconPath = defaultTargetPlatform == TargetPlatform.windows
          ? 'assets/icon/tray_icon.ico'
          : 'assets/icon/tray_icon.png';
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Spectrum Strategy');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: _showMenuKey, label: 'Show Spectrum Strategy'),
            MenuItem.separator(),
            MenuItem(key: _quitMenuKey, label: 'Quit'),
          ],
        ),
      );
      _trayReady = true;

      await windowManager.setPreventClose(true);
    } catch (_) {
      _trayReady = false;
    }
  }

  @override
  void onWindowMinimize() {
    unawaited(_hideToTray());
  }

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (_trayReady && await isEnabled()) {
      await _hideToTray();
    } else {
      await quit();
    }
  }

  Future<void> _hideToTray() async {
    if (!_trayReady || !await isEnabled()) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case _showMenuKey:
        unawaited(showWindow());
      case _quitMenuKey:
        unawaited(quit());
    }
  }

  Future<void> quit() async {
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }
}
