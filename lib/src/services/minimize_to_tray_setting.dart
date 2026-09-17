import 'package:shared_preferences/shared_preferences.dart';

class MinimizeToTraySetting {
  MinimizeToTraySetting({Future<SharedPreferences> Function()? prefs})
    : _prefsLoader = prefs ?? SharedPreferences.getInstance;

  static const String key = 'desktop_minimize_to_tray';

  final Future<SharedPreferences> Function() _prefsLoader;

  Future<bool> isEnabled() async {
    final prefs = await _prefsLoader();
    return prefs.getBool(key) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await _prefsLoader();
    await prefs.setBool(key, enabled);
  }
}
