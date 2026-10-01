import 'package:shared_preferences/shared_preferences.dart';

abstract class TourService {
  Future<bool> isSeen();
  Future<void> markSeen();
}

class SharedPreferencesTourService implements TourService {
  SharedPreferencesTourService({this._preferences});

  static const String prefsKey = 'welcome_tour_seen_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _resolved async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<bool> isSeen() async {
    final prefs = await _resolved;
    return prefs.getBool(prefsKey) ?? false;
  }

  @override
  Future<void> markSeen() async {
    final prefs = await _resolved;
    await prefs.setBool(prefsKey, true);
  }
}
