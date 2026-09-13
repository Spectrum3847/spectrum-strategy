import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tba_client/tba_client.dart';

class FirestoreTbaConfig implements TbaConfig {
  FirestoreTbaConfig({
    this._remoteFetcher,
    Future<SharedPreferences> Function()? prefsLoader,
    this._fallback = const CompileTimeTbaConfig(),
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String prefsKey = 'tba_team_api_key';
  static const String _docPath = 'appConfig/apiKeys';

  final Future<String?> Function()? _remoteFetcher;
  final Future<SharedPreferences> Function() _prefsLoader;
  final TbaConfig _fallback;

  String? _cached;
  bool _cleared = false;

  static const Duration absentTtl = Duration(minutes: 1);
  DateTime? _absentSince;

  DateTime Function() nowFn = DateTime.now;

  @override
  Future<String?> resolveApiKey() async {
    final team = await teamKey();
    if (team != null) {
      return team;
    }
    return _fallback.resolveApiKey();
  }

  Future<String?> teamKey() async {
    if (_cached != null) {
      return _cached;
    }
    if (_cleared) {
      return null;
    }
    final absentSince = _absentSince;
    if (absentSince != null && nowFn().difference(absentSince) < absentTtl) {
      return null;
    }
    try {
      final fetched = (await _fetchRemote())?.trim();
      if (fetched != null) {
        final prefs = await _prefsLoader();
        if (fetched.isEmpty) {
          _cleared = true;
          await prefs.remove(prefsKey);
          return null;
        }
        _cached = fetched;
        _absentSince = null;
        await prefs.setString(prefsKey, fetched);
        return fetched;
      }

      _absentSince = nowFn();
    } catch (_) {}
    final prefs = await _prefsLoader();
    final mirrored = prefs.getString(prefsKey)?.trim();
    return (mirrored == null || mirrored.isEmpty) ? null : mirrored;
  }

  Future<String?> _fetchRemote() async {
    final fetcher = _remoteFetcher;
    if (fetcher != null) {
      return fetcher();
    }
    final doc = await FirebaseFirestore.instance.doc(_docPath).get();
    if (!doc.exists) {
      return null;
    }
    final value = doc.data()?['tba'];
    return value is String ? value : null;
  }
}
