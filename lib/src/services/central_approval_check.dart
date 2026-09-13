import 'package:shared_preferences/shared_preferences.dart';

const Duration centralApprovalRecheckInterval = Duration(hours: 24);

const Duration centralApprovalRetryInterval = Duration(minutes: 15);

class CentralApprovalCheck {
  CentralApprovalCheck({
    Future<SharedPreferences> Function()? prefsLoader,
    DateTime Function()? now,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  static const String _prefsKey = 'central_approval_checked_at_v1';
  static const String _denialsKey = 'central_approval_denials_v1';

  static const int denialsBeforeSignOut = 2;

  final Future<SharedPreferences> Function() _prefsLoader;
  final DateTime Function() _now;

  Future<bool> isDue() async {
    try {
      final prefs = await _prefsLoader();
      final millis = prefs.getInt(_prefsKey);
      if (millis == null) return true;
      final last = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      final elapsed = _now().toUtc().difference(last);

      return elapsed.isNegative || elapsed >= centralApprovalRecheckInterval;
    } catch (_) {
      return false;
    }
  }

  Future<void> markChecked() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.setInt(_prefsKey, _now().toUtc().millisecondsSinceEpoch);
      await prefs.remove(_denialsKey);
    } catch (_) {}
  }

  Future<int> recordDenial() async {
    try {
      final prefs = await _prefsLoader();
      final next = (prefs.getInt(_denialsKey) ?? 0) + 1;
      await prefs.setInt(_denialsKey, next);
      await prefs.setInt(_prefsKey, _now().toUtc().millisecondsSinceEpoch);
      return next;
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _prefsLoader();
      await prefs.remove(_prefsKey);
      await prefs.remove(_denialsKey);
    } catch (_) {}
  }
}
