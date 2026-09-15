import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhotoWorkerConfig {
  PhotoWorkerConfig({
    this._remoteFetcher,
    Future<SharedPreferences> Function()? prefsLoader,
    this._fallback = _compileTimeOrigin,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance;

  static const String prefsKey = 'photo_worker_origin';
  static const String docPath = 'appConfig/apiKeys';
  static const String fieldName = 'photoWorker';
  static const String _compileTimeOrigin = String.fromEnvironment(
    'PHOTO_WORKER_ORIGIN',
  );

  final Future<String?> Function()? _remoteFetcher;
  final Future<SharedPreferences> Function() _prefsLoader;
  final String _fallback;

  String? _cached;

  Future<String?> resolve() async {
    final remote = await _remote();
    if (remote != null) return remote;
    final mirrored = await _mirrored();
    if (mirrored != null) return mirrored;
    return _fallback.trim().isEmpty ? null : _fallback.trim();
  }

  Future<String?> _remote() async {
    if (_cached != null) return _cached;
    final fetcher = _remoteFetcher ?? _fetchFromFlutterFire;
    String? value;
    try {
      value = (await fetcher())?.trim();
    } catch (_) {
      return null;
    }
    if (value == null || value.isEmpty) return null;
    _cached = value;
    try {
      final prefs = await _prefsLoader();
      await prefs.setString(prefsKey, value);
    } catch (_) {}
    return value;
  }

  static Future<String?> _fetchFromFlutterFire() async {
    final doc = await FirebaseFirestore.instance.doc(docPath).get();
    if (!doc.exists) return null;
    final value = doc.data()?[fieldName];
    return value is String ? value : null;
  }

  Future<String?> _mirrored() async {
    try {
      final stored = (await _prefsLoader()).getString(prefsKey)?.trim();
      return stored == null || stored.isEmpty ? null : stored;
    } catch (_) {
      return null;
    }
  }
}
