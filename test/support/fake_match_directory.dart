import 'dart:convert';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';

class FakeMatchDirectory implements MatchDirectory {
  final Map<String, String> _matches = <String, String>{};
  String? _activeId;

  Map<String, String> get rawMatches =>
      Map<String, String>.unmodifiable(_matches);

  StrategySession? get savedSession {
    if (_activeId == null) {
      return null;
    }
    final raw = _matches[_activeId];
    if (raw == null) {
      return null;
    }
    return StrategySession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<List<MatchSummary>> listMatches() async {
    final summaries =
        _matches.values
            .map(
              (raw) => StrategySession.fromJson(
                jsonDecode(raw) as Map<String, dynamic>,
              ),
            )
            .map(MatchSummary.fromSession)
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  @override
  Future<StrategySession?> loadMatch(String id) async {
    final raw = _matches[id];
    if (raw == null) {
      return null;
    }
    return StrategySession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> saveMatch(StrategySession session) async {
    _matches[session.id] = jsonEncode(session.toJson());
  }

  @override
  Future<void> deleteMatch(String id) async {
    _matches.remove(id);
    if (_activeId == id) {
      _activeId = null;
    }
  }

  @override
  Future<String?> getActiveMatchId() async => _activeId;

  @override
  Future<void> setActiveMatchId(String? id) async {
    _activeId = id;
  }
}
