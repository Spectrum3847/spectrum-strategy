import 'dart:async';
import 'dart:convert';

import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';

class LaggyMatchDirectory implements MatchDirectory {
  final List<StrategySession> savedSessions = <StrategySession>[];
  final Map<String, String> _matches = <String, String>{};
  String? _activeId;
  Completer<void>? firstSaveGate;

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
    final clone = StrategySession.fromJson(session.toJson());
    savedSessions.add(clone);
    _matches[session.id] = jsonEncode(session.toJson());
    if (firstSaveGate != null && !firstSaveGate!.isCompleted) {
      await firstSaveGate!.future;
    }
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
