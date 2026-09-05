import 'dart:convert';

import 'package:spectrumstrategy/src/models/post_match_report.dart';
import 'package:spectrumstrategy/src/services/post_match_report_storage.dart';

class FakePostMatchReportStorage implements PostMatchReportStorage {
  FakePostMatchReportStorage({this.delayFirst = false});

  final bool delayFirst;

  final Map<String, String> _reports = <String, String>{};

  final List<PostMatchReport> saved = <PostMatchReport>[];

  Object? failNextSave;

  int _saves = 0;

  @override
  Future<List<PostMatchReport>> loadAll() async {
    return _reports.values
        .map(
          (raw) =>
              PostMatchReport.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> saveReport(PostMatchReport report) async {
    final isFirst = _saves++ == 0;
    if (delayFirst && isFirst) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    saved.add(report);
    _reports[report.id] = jsonEncode(report.toJson());
  }
}
