import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/post_match_report.dart';

abstract class PostMatchReportStorage {
  Future<List<PostMatchReport>> loadAll();
  Future<void> saveReport(PostMatchReport report);
}

class SharedPreferencesPostMatchReportStorage
    implements PostMatchReportStorage {
  SharedPreferencesPostMatchReportStorage({this._preferences});

  static const String _reportsKey = 'post_match_reports_v1';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_reportsKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.cast<String, dynamic>();
    }
    return <String, dynamic>{};
  }

  Future<void> _writeMap(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    await prefs.setString(_reportsKey, jsonEncode(data));
  }

  @override
  Future<List<PostMatchReport>> loadAll() async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    final reports = <PostMatchReport>[];
    for (final value in data.values) {
      if (value is! Map) {
        continue;
      }
      try {
        reports.add(PostMatchReport.fromJson(value.cast<String, dynamic>()));
      } catch (_) {}
    }
    return reports;
  }

  @override
  Future<void> saveReport(PostMatchReport report) async {
    final prefs = await _resolvedPreferences;
    final data = await _readMap(prefs);
    data[report.id] = report.toJson();
    await _writeMap(prefs, data);
  }
}
