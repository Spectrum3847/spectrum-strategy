import 'dart:convert';

import 'package:spectrumstrategy/src/models/trex_trait_report.dart';
import 'package:spectrumstrategy/src/services/trex_trait_report_storage.dart';

class FakeTrexTraitReportStorage implements TrexTraitReportStorage {
  final Map<String, String> _reports = <String, String>{};

  Map<String, String> get rawReports =>
      Map<String, String>.unmodifiable(_reports);

  bool failNextSave = false;

  bool failNextDelete = false;

  @override
  Future<List<TrexTraitReport>> loadAll() async {
    final list = _reports.values
        .map(
          (raw) =>
              TrexTraitReport.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveReport(TrexTraitReport report) async {
    if (failNextSave) {
      failNextSave = false;
      throw Exception('save failed');
    }
    _reports[report.id] = jsonEncode(report.toJson());
  }

  @override
  Future<void> deleteReport(String id) async {
    if (failNextDelete) {
      failNextDelete = false;
      throw Exception('delete failed');
    }
    _reports.remove(id);
  }

  Set<String> syncedIds = <String>{};

  @override
  Future<Set<String>> loadSyncedIds() async => Set<String>.of(syncedIds);

  @override
  Future<void> saveSyncedIds(Set<String> ids) async {
    syncedIds = Set<String>.of(ids);
  }
}
