import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/strategy_session.dart';

String? _asString(Object? value) => value is String ? value : null;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

class MatchSummary {
  const MatchSummary({
    required this.id,
    this.eventKey = '',
    required this.eventName,
    required this.matchNumber,
    required this.alliance,
    required this.updatedAt,
  });

  factory MatchSummary.fromSession(StrategySession session) {
    return MatchSummary(
      id: session.id,
      eventKey: session.eventKey,
      eventName: session.eventName,
      matchNumber: session.matchNumber,
      alliance: session.alliance,
      updatedAt: session.updatedAt,
    );
  }

  factory MatchSummary.fromJson(Map<String, dynamic> json) {
    final id = _asString(json['id']);
    if (id == null) {
      throw const FormatException('MatchSummary.fromJson: missing id');
    }
    return MatchSummary(
      id: id,
      eventKey: _asString(json['eventKey']) ?? '',
      eventName: _asString(json['eventName']) ?? '',
      matchNumber: _asInt(json['matchNumber']) ?? 1,
      alliance: _asString(json['alliance']) ?? 'Red',
      updatedAt:
          DateTime.tryParse(_asString(json['updatedAt']) ?? '') ??
          DateTime.now(),
    );
  }

  final String id;

  final String eventKey;
  final String eventName;
  final int matchNumber;
  final String alliance;
  final DateTime updatedAt;

  String get title {
    if (eventName.trim().isEmpty) {
      return 'Match $matchNumber';
    }
    return '$eventName - Match $matchNumber';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'eventName': eventName,
    'matchNumber': matchNumber,
    'alliance': alliance,
    'updatedAt': updatedAt.toIso8601String(),
  };
}

abstract class MatchDirectory {
  Future<List<MatchSummary>> listMatches();
  Future<StrategySession?> loadMatch(String id);
  Future<void> saveMatch(StrategySession session);
  Future<void> deleteMatch(String id);
  Future<String?> getActiveMatchId();
  Future<void> setActiveMatchId(String? id);
}

class SharedPreferencesMatchDirectory implements MatchDirectory {
  SharedPreferencesMatchDirectory({this._preferences});

  static const String _boardKeyPrefix = 'strategy_match_v3_';

  static const String _summariesKey = 'strategy_match_summaries_v2';

  static const String _activeKey = 'strategy_active_match_id';

  static const String _legacyMatchesKey = 'strategy_matches_v2';

  static const String _legacySummariesKey = 'strategy_match_summaries_v1';

  static const String _legacyDraftKey = 'strategy_session_draft';

  final SharedPreferences? _preferences;

  Future<void>? _migrationFuture;

  Future<void> _summaryQueue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _summaryQueue = _summaryQueue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<SharedPreferences> get _resolvedPreferences async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  String _boardKey(String id) => '$_boardKeyPrefix$id';

  Set<String> _boardIds(SharedPreferences prefs) => prefs
      .getKeys()
      .where((k) => k.startsWith(_boardKeyPrefix))
      .map((k) => k.substring(_boardKeyPrefix.length))
      .toSet();

  Map<String, dynamic>? _readSummaries(SharedPreferences prefs) {
    final raw = prefs.getString(_summariesKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _writeSummaries(
    SharedPreferences prefs,
    Map<String, dynamic> entries,
  ) async {
    await prefs.setString(_summariesKey, jsonEncode(entries));
  }

  static int _stampFor(String raw) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < raw.length; i++) {
      final unit = raw.codeUnitAt(i);

      hash ^= unit & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
      hash ^= (unit >> 8) & 0xff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  int? _entryStamp(Object? entry) =>
      entry is Map && entry['stamp'] is int ? entry['stamp'] as int : null;

  Map<String, dynamic>? _entrySummaryJson(Object? entry) {
    if (entry is Map && entry['summary'] is Map) {
      return (entry['summary'] as Map).cast<String, dynamic>();
    }
    return null;
  }

  Map<String, dynamic> _entryFor(MatchSummary summary, int stamp) =>
      <String, dynamic>{'summary': summary.toJson(), 'stamp': stamp};

  Future<void> _updateSummaryEntry(
    SharedPreferences prefs,
    String id,
    MatchSummary? summary,
    int? stamp,
  ) async {
    final entries = _readSummaries(prefs) ?? <String, dynamic>{};
    if (summary == null) {
      entries.remove(id);
    } else {
      entries[id] = _entryFor(summary, stamp!);
    }
    await _writeSummaries(prefs, entries);
  }

  Future<Map<String, dynamic>> _ensureFreshSummaries(
    SharedPreferences prefs,
  ) async {
    final ids = _boardIds(prefs);
    final stored = _readSummaries(prefs) ?? <String, dynamic>{};
    final staleIds = stored.keys.toSet().difference(ids);
    final toRepair = <String>{};
    for (final id in ids) {
      final entry = stored[id];
      if (entry == null) {
        toRepair.add(id);
        continue;
      }
      final storedStamp = _entryStamp(entry);
      final currentRaw = prefs.getString(_boardKey(id));
      final currentStamp = currentRaw == null ? null : _stampFor(currentRaw);
      if (storedStamp == null || storedStamp != currentStamp) {
        toRepair.add(id);
      }
    }
    if (toRepair.isEmpty && staleIds.isEmpty) {
      return stored;
    }
    final repaired = Map<String, dynamic>.of(stored);
    for (final id in staleIds) {
      repaired.remove(id);
    }
    for (final id in toRepair) {
      repaired.remove(id);
      final raw = prefs.getString(_boardKey(id));
      if (raw == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          continue;
        }
        final session = StrategySession.fromJson(
          decoded.cast<String, dynamic>(),
        );
        repaired[id] = _entryFor(
          MatchSummary.fromSession(session),
          _stampFor(raw),
        );
      } catch (_) {}
    }
    await _writeSummaries(prefs, repaired);
    return repaired;
  }

  Future<void> _migrateIfNeeded(SharedPreferences prefs) {
    return _migrationFuture ??= _runMigration(prefs);
  }

  Future<void> _runMigration(SharedPreferences prefs) async {
    await _migrateLegacyDraft(prefs);
    await _migrateLegacyBlob(prefs);
  }

  Future<void> _migrateLegacyDraft(SharedPreferences prefs) async {
    final legacy = prefs.getString(_legacyDraftKey);
    if (legacy == null || legacy.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(legacy);
      if (decoded is! Map) {
        return;
      }
      final session = StrategySession.fromJson(decoded.cast<String, dynamic>());
      final key = _boardKey(session.id);
      if (!prefs.containsKey(key)) {
        final raw = jsonEncode(session.toJson());
        await prefs.setString(key, raw);
        await _updateSummaryEntry(
          prefs,
          session.id,
          MatchSummary.fromSession(session),
          _stampFor(raw),
        );
      }
      if (prefs.getString(_activeKey) == null) {
        await prefs.setString(_activeKey, session.id);
      }
    } catch (_) {
    } finally {
      await prefs.remove(_legacyDraftKey);
    }
  }

  Future<void> _migrateLegacyBlob(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyMatchesKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    Map<String, dynamic> legacyMap;
    try {
      final decoded = jsonDecode(raw);
      legacyMap = decoded is Map
          ? decoded.cast<String, dynamic>()
          : <String, dynamic>{};
    } catch (_) {
      legacyMap = <String, dynamic>{};
    }
    final ids = legacyMap.keys.toList();
    for (final id in ids) {
      final key = _boardKey(id);
      if (prefs.containsKey(key)) {
        continue;
      }
      await prefs.setString(key, jsonEncode(legacyMap[id]));
    }
    final allPresent = ids.every((id) => prefs.containsKey(_boardKey(id)));
    if (allPresent) {
      await prefs.remove(_legacyMatchesKey);

      await prefs.remove(_legacySummariesKey);
    }
  }

  @override
  Future<List<MatchSummary>> listMatches() async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final entries = await _serialized(() => _ensureFreshSummaries(prefs));
    final result = <MatchSummary>[];
    for (final entry in entries.values) {
      final summaryJson = _entrySummaryJson(entry);
      if (summaryJson == null) {
        continue;
      }
      try {
        result.add(MatchSummary.fromJson(summaryJson));
      } catch (_) {}
    }
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  @override
  Future<StrategySession?> loadMatch(String id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final raw = prefs.getString(_boardKey(id));
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return StrategySession.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveMatch(StrategySession session) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);
    final raw = jsonEncode(session.toJson());

    await prefs.setString(_boardKey(session.id), raw);
    await _serialized(
      () => _updateSummaryEntry(
        prefs,
        session.id,
        MatchSummary.fromSession(session),
        _stampFor(raw),
      ),
    );
  }

  @override
  Future<void> deleteMatch(String id) async {
    final prefs = await _resolvedPreferences;
    await _migrateIfNeeded(prefs);

    await prefs.remove(_boardKey(id));
    await _serialized(() => _updateSummaryEntry(prefs, id, null, null));

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
