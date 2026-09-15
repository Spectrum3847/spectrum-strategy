import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/trex_trait_report.dart';

abstract class TrexTraitReportStorage {
  Future<List<TrexTraitReport>> loadAll();
  Future<void> saveReport(TrexTraitReport report);
  Future<void> deleteReport(String id);

  Future<Set<String>> loadSyncedIds();
  Future<void> saveSyncedIds(Set<String> ids);
}

class SharedPreferencesTrexTraitReportStorage
    implements TrexTraitReportStorage {
  SharedPreferencesTrexTraitReportStorage({this._preferences});

  static const String _reportsKey = 'trex_trait_reports_v1';
  static const String _syncedIdsKey = 'trex_trait_report_synced_ids_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _resolvedPreferences async =>
      _preferences ?? SharedPreferences.getInstance();

  Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_reportsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(raw);
    if (decoded is Map) return decoded.cast<String, dynamic>();
    return <String, dynamic>{};
  }

  @override
  Future<List<TrexTraitReport>> loadAll() async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    final reports = <TrexTraitReport>[];
    for (final value in data.values) {
      if (value is! Map) continue;
      try {
        reports.add(TrexTraitReport.fromJson(value.cast<String, dynamic>()));
      } catch (_) {}
    }
    reports.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return reports;
  }

  @override
  Future<void> saveReport(TrexTraitReport report) async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    data[report.id] = report.toJson();
    await prefs.setString(_reportsKey, jsonEncode(data));
  }

  @override
  Future<void> deleteReport(String id) async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    if (data.remove(id) == null) return;
    await prefs.setString(_reportsKey, jsonEncode(data));
  }

  @override
  Future<Set<String>> loadSyncedIds() async {
    final prefs = await _resolvedPreferences;
    final raw = prefs.getString(_syncedIdsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.map((e) => e.toString()).toSet();
    }
    return <String>{};
  }

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    final prefs = await _resolvedPreferences;
    await prefs.setString(_syncedIdsKey, jsonEncode(ids.toList()));
  }
}
