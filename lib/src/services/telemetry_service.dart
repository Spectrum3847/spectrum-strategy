import 'dart:ui' show PlatformDispatcher;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'debug_info.dart';

class TelemetryService {
  TelemetryService({
    this._firestore,
    this._write,
    Future<SharedPreferences> Function()? prefs,
    Future<DebugInfo> Function()? debugInfo,
  }) : _prefsLoader = prefs ?? SharedPreferences.getInstance,
       _debugInfoLoader = debugInfo ?? DebugInfo.gather;

  static const String enabledKey = 'telemetry_enabled';
  static const String _deviceIdKey = 'telemetry_device_id';

  final FirebaseFirestore? _firestore;
  final Future<void> Function(String docPath, Map<String, dynamic> data)?
  _write;
  final Future<SharedPreferences> Function() _prefsLoader;
  final Future<DebugInfo> Function() _debugInfoLoader;

  FirebaseFirestore get _db => _firestore ?? FirebaseFirestore.instance;

  Future<bool> isEnabled() async {
    final prefs = await _prefsLoader();
    return prefs.getBool(enabledKey) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await _prefsLoader();
    await prefs.setBool(enabledKey, enabled);
  }

  Future<String> _deviceId(SharedPreferences prefs) async {
    final existing = prefs.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    return _deviceIdFuture ??= _createDeviceId(prefs);
  }

  Future<String>? _deviceIdFuture;

  Future<String> _createDeviceId(SharedPreferences prefs) async {
    try {
      final id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
      return id;
    } catch (_) {
      _deviceIdFuture = null;
      rethrow;
    }
  }

  static String _clamp(String value, int max) =>
      value.length <= max ? value : value.substring(0, max);

  static String _locale() {
    try {
      return PlatformDispatcher.instance.locale.toLanguageTag();
    } catch (_) {
      return '';
    }
  }

  Future<void> logEvent(String type, {String? detail}) async {
    try {
      final prefs = await _prefsLoader();
      if (!(prefs.getBool(enabledKey) ?? true)) return;
      final deviceId = await _deviceId(prefs);
      final info = await _debugInfoLoader();
      final locale = _locale();
      final id = const Uuid().v4();
      final data = <String, dynamic>{
        'id': id,
        'type': _clamp(type, 64),
        'deviceId': deviceId,
        'appVersion': _clamp(info.reportVersion, 64),
        'platform': _clamp(info.platform, 64),
        'osVersion': _clamp(info.osVersion, 128),
        if (locale.isNotEmpty) 'locale': _clamp(locale, 32),
        if (detail != null && detail.isNotEmpty) 'detail': _clamp(detail, 128),
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      final write = _write;
      if (write != null) {
        await write('telemetry/$id', data);
      } else {
        await _db.collection('telemetry').doc(id).set(data);
      }
    } catch (_) {}
  }
}
