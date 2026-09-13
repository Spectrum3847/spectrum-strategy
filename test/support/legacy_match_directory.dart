import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:spectrumstrategy/src/models/strategy_session.dart';
import 'package:spectrumstrategy/src/services/match_directory.dart';

typedef _SummariesRead = ({int stamp, Map<String, dynamic> entries});

class LegacyMatchDirectory implements MatchDirectory {
  LegacyMatchDirectory({this._preferences});

  static const String _matchesKey = 'strategy_matches_v2';

  static const String _summariesKey = 'strategy_match_summaries_v1';

  static const String _activeKey = 'strategy_active_match_id';

  static const String _legacyDraftKey = 'strategy_session_draft';

  final SharedPreferences? _preferences;
  bool _migrated = false;

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  Future<Map<String, dynamic>> _readMap(SharedPreferences prefs) async {
    final raw = prefs.getString(_matchesKey);
    if (raw == null || raw.isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  Future<void> _writeMap(
    SharedPreferences prefs,
    Map<String, dynamic> data,
  ) async {
    await prefs.setString(_matchesKey, jsonEncode(data));
  }

  int _matchesStamp(SharedPreferences prefs) =>
      prefs.getString(_matchesKey)?.length ?? 0;

  _SummariesRead? _readSummaries(SharedPreferences prefs) {
    final raw = prefs.getString(_summariesKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final stamp = decoded['stamp'];
        final entries = decoded['entries'];
        if (stamp is int && entries is Map) {
          return (stamp: stamp, entries: entries.cast<String, dynamic>());
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeSummaries(
    SharedPreferences prefs,
    Map<String, dynamic> entries,
    int stamp,
  ) async {
    await prefs.setString(
      _summariesKey,
      jsonEncode(<String, dynamic>{'stamp': stamp, 'entries': entries}),
    );
  }

  Future<Map<String, dynamic>> _rebuildSummaries(
    SharedPreferences prefs,
  ) async {
    final data = await _readMap(prefs);
    final summaries = <String, dynamic>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is! Map) {
        continue;
      }
      try {
        final session = StrategySession.fromJson(value.cast<String, dynamic>());
        summaries[entry.key] = MatchSummary.fromSession(session).toJson();
      } catch (_) {}
    }
    return summaries;
  }

  Future<Map<String, dynamic>> _ensureFreshSummaries(
    SharedPreferences prefs,
  ) async {
    final stamp = _matchesStamp(prefs);
    final stored = _readSummaries(prefs);
    if (stored != null && stored.stamp == stamp) {
      return stored.entries;
    }
    final rebuilt = await _rebuildSummaries(prefs);
    await _writeSummaries(prefs, rebuilt, stamp);
    return rebuilt;
  }

  Future<Map<String, dynamic>> _summaryEntriesForWrite(
    SharedPreferences prefs,
  ) async {
    final stored = _readSummaries(prefs);
    if (stored != null) {
      return stored.entries;
    }
    return _rebuildSummaries(prefs);
  }

  Future<void> _migrateIfNeeded(SharedPreferences prefs) async {
    if (_migrated) {
      return;
    }
    _migrated = true;
    final legacy = prefs.getString(_legacyDraftKey);
    if (legacy == null || legacy.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(legacy);
      if (decoded is! Map) {
        await prefs.remove(_legacyDraftKey);
        return;
      }
      final session = StrategySession.fromJson(decoded.cast<String, dynamic>());
      final data = await _readMap(prefs);

      if (!data.containsKey(session.id)) {
        data[session.id] = session.toJson();
        await _writeMap(prefs, data);
      }
      if (prefs.getString(_activeKey) == null) {
        await prefs.setString(_activeKey, session.id);
      }
    } catch (_) {
    } finally {
      await prefs.remove(_legacyDraftKey);
    }
  }

  @override
  Future<List<MatchSummary>> listMatches() async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final entries = await _ensureFreshSummaries(prefs);
    final result = <MatchSummary>[];
    for (final value in entries.values) {
      if (value is! Map) {
        continue;
      }
      try {
        result.add(MatchSummary.fromJson(value.cast<String, dynamic>()));
      } catch (_) {}
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<StrategySession?> loadMatch(String id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final data = await _readMap(prefs);
    final raw = data[id];
    if (raw is! Map) {
      return null;
    }
    try {
      return StrategySession.fromJson(raw.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveMatch(StrategySession session) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final data = await _readMap(prefs);
    data[session.id] = session.toJson();
    await _writeMap(prefs, data);

    final entries = await _summaryEntriesForWrite(prefs);
    entries[session.id] = MatchSummary.fromSession(session).toJson();
    await _writeSummaries(prefs, entries, _matchesStamp(prefs));
  }

  @override
  Future<void> deleteMatch(String id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final data = await _readMap(prefs);
    if (data.remove(id) != null) {
      await _writeMap(prefs, data);
    }

    final entries = await _summaryEntriesForWrite(prefs);
    entries.remove(id);
    await _writeSummaries(prefs, entries, _matchesStamp(prefs));

    if (prefs.getString(_activeKey) == id) {
      await prefs.remove(_activeKey);
    }
  }

  @override
  Future<String?> getActiveMatchId() async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    return prefs.getString(_activeKey);
  }

  @override
  Future<void> setActiveMatchId(String? id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    if (id == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, id);
    }
  }
}
