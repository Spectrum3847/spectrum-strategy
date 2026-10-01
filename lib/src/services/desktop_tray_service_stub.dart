library;

import 'minimize_to_tray_setting.dart';

class DesktopTrayService {
  DesktopTrayService({MinimizeToTraySetting? setting})
    : _setting = setting ?? MinimizeToTraySetting();

  static final DesktopTrayService shared = DesktopTrayService();

  final MinimizeToTraySetting _setting;

  Future<bool> isEnabled() => _setting.isEnabled();

  Future<void> setEnabled(bool enabled) => _setting.setEnabled(enabled);

  Future<void> start() async {}

  Future<void> showWindow() async {}

  Future<void> quit() async {}
}
