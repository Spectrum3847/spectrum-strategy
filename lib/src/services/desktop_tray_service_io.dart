library;

import 'dart:async' show unawaited;
import 'dart:io' show Platform, Process, ProcessException, exit;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'minimize_to_tray_setting.dart';

class DesktopTrayService {
  DesktopTrayService({
    MinimizeToTraySetting? setting,
    Future<void> Function()? destroyWindow,
    void Function(int code)? exitProcess,
  }) : _setting = setting ?? MinimizeToTraySetting(),
       _destroyWindow = destroyWindow ?? _closeWindow,
       _exitProcess = exitProcess ?? exit;

  static final DesktopTrayService shared = DesktopTrayService();

  static const _flushTimeout = Duration(seconds: 2);

  static Future<void> _closeWindow() async {
    WindowManager.instance.getCurrent()?.close();
  }

  final MinimizeToTraySetting _setting;
  final Future<void> Function() _destroyWindow;
  final void Function(int code) _exitProcess;
  Window? _window;
  TrayIcon? _trayIcon;

  Future<void> Function()? flushBeforeQuit;

  Future<bool> isEnabled() => _setting.isEnabled();

  Future<void> setEnabled(bool enabled) => _setting.setEnabled(enabled);

  Future<void> start() async {
    try {
      final window = WindowManager.instance.getCurrent();
      if (window == null) return;
      window.addListener(_onWindowEvent);
      _window = window;

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

  void _onWindowEvent(WindowEvent event) {
    switch (event) {
      case WindowMinimizedEvent():
        unawaited(_hideToTray());

      case WindowCloseRequestedEvent(:final request) when _trayIcon != null:
        request.cancel();
        unawaited(_handleClose());
      default:
        break;
    }
  }

  Future<void> _handleClose() async {
    if (!await _hideToTray()) await quit();
  }

  Future<bool> _hideToTray() async {
    if (!await _canHideToTray()) return false;
    _window
      ?..hide()
      ..isVisibleInTaskbar = false;
    return true;
  }

  Future<bool> _canHideToTray() async {
    return shouldHideToTray(
      enabled: await isEnabled(),
      hasTrayIcon: _trayIcon != null,
      isLinux: Platform.isLinux,
      linuxTrayHost: Platform.isLinux && await _linuxTrayHostPresent(),
    );
  }

  Future<bool> _linuxTrayHostPresent() async {
    try {
      final result = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.DBus',
        '--object-path',
        '/org/freedesktop/DBus',
        '--method',
        'org.freedesktop.DBus.NameHasOwner',
        'org.kde.StatusNotifierWatcher',
      ]);
      return result.exitCode == 0 && (result.stdout as String).contains('true');
    } on ProcessException {
      return false;
    }
  }

  Future<void> showWindow() async {
    final window = _window;
    if (window == null) return;
    window.isVisibleInTaskbar = true;
    if (window.isMinimized) window.restore();
    window
      ..show()
      ..focus();
  }

  Future<void> flushPendingSaves() async {
    try {
      await flushBeforeQuit?.call().timeout(_flushTimeout, onTimeout: () {});
    } catch (_) {
      // Intentionally empty.
    }
  }

  Future<void> quit() async {
    await flushPendingSaves();
    _trayIcon?.dispose();
    _trayIcon = null;
    await _destroyWindow();
    _exitProcess(0);
  }
}
