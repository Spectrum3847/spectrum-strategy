library;

import 'dart:async' show unawaited;
import 'dart:io' show exit;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'minimize_to_tray_setting.dart';

class DesktopTrayService with WindowListener {
  DesktopTrayService({MinimizeToTraySetting? setting})
    : _setting = setting ?? MinimizeToTraySetting();

  static final DesktopTrayService shared = DesktopTrayService();

  final MinimizeToTraySetting _setting;
  TrayIcon? _trayIcon;

  Future<bool> isEnabled() => _setting.isEnabled();

  Future<void> setEnabled(bool enabled) => _setting.setEnabled(enabled);

  Future<void> start() async {
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(this);

      final trayIcon = TrayIcon.create();
      if (trayIcon == null) return;

      final iconPath = defaultTargetPlatform == TargetPlatform.windows
          ? 'assets/icon/tray_icon.ico'
          : 'assets/icon/tray_icon.png';
      final icon = ImageAsset.fromAsset(iconPath);
      if (icon == null) {
        trayIcon.dispose();
        return;
      }

      final menu = Menu.create()!;
      final showItem = MenuItem.createWithLabelAndType(
        'Show Spectrum Strategy',
        MenuItemType.normal,
      )!..addListener(_onShowItemEvent);
      final quitItem = MenuItem.createWithLabelAndType(
        'Quit',
        MenuItemType.normal,
      )!..addListener(_onQuitItemEvent);
      menu
        ..addItem(showItem)
        ..addSeparator()
        ..addItem(quitItem);

      trayIcon
        ..icon = icon
        ..setTooltip('Spectrum Strategy')
        ..setContextMenu(menu)
        ..setContextMenuTrigger(ContextMenuTrigger.rightClicked)
        ..addListener(_onTrayIconEvent)
        ..setVisible(true);

      _trayIcon = trayIcon;

      await windowManager.setPreventClose(true);
    } catch (_) {
      _trayIcon = null;
    }
  }

  void _onTrayIconEvent(TrayIconEvent event) {
    if (event is TrayIconClickedEvent) unawaited(showWindow());
  }

  void _onShowItemEvent(MenuEvent event) {
    if (event is MenuItemClickedEvent) unawaited(showWindow());
  }

  void _onQuitItemEvent(MenuEvent event) {
    if (event is MenuItemClickedEvent) unawaited(quit());
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
    if (_trayIcon != null && await isEnabled()) {
      await _hideToTray();
    } else {
      await quit();
    }
  }

  Future<void> _hideToTray() async {
    if (_trayIcon == null || !await isEnabled()) return;
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> showWindow() async {
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    _trayIcon?.dispose();
    _trayIcon = null;
    await windowManager.destroy();
    exit(0);
  }
}
