import 'dart:convert';

import 'package:spectrumstrategy/src/models/match_brief.dart';
import 'package:spectrumstrategy/src/services/match_brief_storage.dart';

class FakeMatchBriefStorage implements MatchBriefStorage {
  final Map<String, String> _briefs = <String, String>{};
  Set<String> _pendingIds = <String>{};

  final List<MatchBrief> saved = <MatchBrief>[];

  Object? failNextSave;

  @override
  Future<List<MatchBrief>> loadAll() async {
    return _briefs.values
        .map(
          (raw) => MatchBrief.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<void> saveBrief(MatchBrief brief) async {
    final failure = failNextSave;
    if (failure != null) {
      failNextSave = null;
      throw failure;
    }
    saved.add(brief);
    _briefs[brief.id] = jsonEncode(brief.toJson());
  }

  @override
  Future<Set<String>> loadPendingIds() async => _pendingIds.toSet();

  @override
  Future<void> savePendingIds(Set<String> ids) async {
    _pendingIds = ids.toSet();
  }
}
