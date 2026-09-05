import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

import '../assistant/team_brief.dart';
import 'statbotics_switch.dart';

class TeamHistoryService {
  TeamHistoryService({
    required this._client,
    this._tbaClient,
    bool? statboticsEnabled,
    Future<SharedPreferences> Function()? prefsLoader,
    DateTime Function()? now,
  }) : _statboticsEnabled = statboticsEnabled ?? kStatboticsEnabled,
       _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _now = now ?? DateTime.now;

  final StatboticsClient _client;

  final TbaClient? _tbaClient;

  final bool _statboticsEnabled;
  final Future<SharedPreferences> Function() _prefsLoader;
  final DateTime Function() _now;

  final Map<int, List<StatboticsTeamYear>> _memory =
      <int, List<StatboticsTeamYear>>{};

  final Map<String, List<StatboticsTeamEvent>> _eventMemory =
      <String, List<StatboticsTeamEvent>>{};
  final Map<String, List<TeamAwardRow>> _awardMemory =
      <String, List<TeamAwardRow>>{};
  final Map<String, List<TeamAlliancePlacement>> _allianceMemory =
      <String, List<TeamAlliancePlacement>>{};

  static const String _prefix = 'team_seasons_cache_v1:';
  static const String _eventPrefix = 'team_events_cache_v1:';
  static const String _awardPrefix = 'team_awards_cache_v1:';
  static const String _alliancePrefix = 'team_alliances_cache_v1:';

  static const Duration freshFor = Duration(hours: 6);

  static const int defaultSeasonCount = 2;

  Future<List<StatboticsTeamYear>> seasonsFor(
    int teamNumber, {
    int seasons = defaultSeasonCount,
  }) async {
    final all = await _allSeasons(teamNumber);
    return List<StatboticsTeamYear>.unmodifiable(all.take(seasons));
  }

  Future<TeamBriefInputs> briefInputsFor(
    int teamNumber, {
    int seasons = defaultSeasonCount,
  }) async {
    final seasonRows = await seasonsFor(teamNumber, seasons: seasons);
    final years = seasonRows.map((s) => s.year).toList();
    final events = await eventsFor(teamNumber, years: years);
    final awards = await awardsFor(teamNumber, years: years);
    final alliances = await alliancesFor(
      teamNumber,
      eventKeys: events.map((e) => e.event).toList(),
    );
    return TeamBriefInputs(
      seasons: seasonRows,
      events: events,
      awards: awards,
      alliances: alliances,
    );
  }

  Future<List<StatboticsTeamEvent>> eventsFor(
    int teamNumber, {
    required List<int> years,
  }) async {
    if (years.isEmpty) {
      return const <StatboticsTeamEvent>[];
    }

    final scope = '$teamNumber:${(List<int>.from(years)..sort()).join('-')}';
    final remembered = _eventMemory[scope];
    if (remembered != null) {
      return remembered;
    }

    final prefs = await _prefsLoader();
    final stored = _readCache(
      prefs,
      '$_eventPrefix$scope',
      StatboticsTeamEvent.fromJson,
    );
    if (stored != null && _now().difference(stored.fetchedAt) < freshFor) {
      _eventMemory[scope] = stored.rows;
      return stored.rows;
    }

    if (!_statboticsEnabled) {
      final fallback = stored?.rows ?? const <StatboticsTeamEvent>[];
      _eventMemory[scope] = fallback;
      return fallback;
    }

    try {
      final rows = <StatboticsTeamEvent>[];
      for (final year in years) {
        rows.addAll(await _client.getTeamEvents(teamNumber, year: year));
      }
      rows.sort((a, b) => b.year.compareTo(a.year));
      final result = List<StatboticsTeamEvent>.unmodifiable(rows);
      _eventMemory[scope] = result;
      await _writeCache(
        prefs,
        '$_eventPrefix$scope',
        result.map((e) => e.toJson()).toList(),
      );
      return result;
    } catch (_) {
      return stored?.rows ?? const <StatboticsTeamEvent>[];
    }
  }

  Future<List<TeamAwardRow>> awardsFor(
    int teamNumber, {
    required List<int> years,
  }) async {
    final tba = _tbaClient;
    if (tba == null || years.isEmpty) {
      return const <TeamAwardRow>[];
    }

    final scope = '$teamNumber:${(List<int>.from(years)..sort()).join('-')}';
    final remembered = _awardMemory[scope];
    if (remembered != null) {
      return remembered;
    }

    final prefs = await _prefsLoader();
    final stored = _readCache(
      prefs,
      '$_awardPrefix$scope',
      TeamAwardRow.fromJson,
    );
    if (stored != null && _now().difference(stored.fetchedAt) < freshFor) {
      _awardMemory[scope] = stored.rows;
      return stored.rows;
    }

    try {
      final rows = <TeamAwardRow>[];
      for (final year in years) {
        final awards = await tba.getTeamAwards(teamNumber, year: year);
        for (final award in awards) {
          final isTeamAward = award.recipients.every((r) => r.awardee == null);
          if (!isTeamAward) {
            continue;
          }
          rows.add(
            TeamAwardRow(
              name: award.name,
              eventKey: award.eventKey,
              year: award.year,
              isWinOrFinalist: award.isWinOrFinalist,
            ),
          );
        }
      }
      rows.sort((a, b) => b.year.compareTo(a.year));
      final result = List<TeamAwardRow>.unmodifiable(rows);
      _awardMemory[scope] = result;
      await _writeCache(
        prefs,
        '$_awardPrefix$scope',
        result.map((a) => a.toJson()).toList(),
      );
      return result;
    } catch (_) {
      return stored?.rows ?? const <TeamAwardRow>[];
    }
  }

  Future<List<TeamAlliancePlacement>> alliancesFor(
    int teamNumber, {
    required List<String> eventKeys,
  }) async {
    final tba = _tbaClient;
    if (tba == null || eventKeys.isEmpty) {
      return const <TeamAlliancePlacement>[];
    }

    final sorted = List<String>.from(eventKeys)..sort();
    final scope = '$teamNumber:${sorted.join('-')}';
    final remembered = _allianceMemory[scope];
    if (remembered != null) {
      return remembered;
    }

    final prefs = await _prefsLoader();
    final stored = _readCache(
      prefs,
      '$_alliancePrefix$scope',
      TeamAlliancePlacement.fromJson,
    );
    if (stored != null && _now().difference(stored.fetchedAt) < freshFor) {
      _allianceMemory[scope] = stored.rows;
      return stored.rows;
    }

    try {
      final teamKey = 'frc$teamNumber';
      final rows = <TeamAlliancePlacement>[];
      for (final eventKey in eventKeys) {
        final alliances = await tba.getEventAlliances(eventKey);
        if (alliances == null) {
          continue;
        }
        for (var i = 0; i < alliances.alliances.length; i++) {
          final alliance = alliances.alliances[i];
          final pick = alliance.picks.indexOf(teamKey);
          if (pick < 0) {
            continue;
          }
          rows.add(
            TeamAlliancePlacement(
              eventKey: eventKey,
              allianceNumber: i + 1,
              pickIndex: pick,
              roundReached: alliance.status,
            ),
          );
          break;
        }
      }
      final result = List<TeamAlliancePlacement>.unmodifiable(rows);
      _allianceMemory[scope] = result;
      await _writeCache(
        prefs,
        '$_alliancePrefix$scope',
        result.map((a) => a.toJson()).toList(),
      );
      return result;
    } catch (_) {
      return stored?.rows ?? const <TeamAlliancePlacement>[];
    }
  }

  Future<List<StatboticsTeamYear>> _allSeasons(int teamNumber) async {
    final remembered = _memory[teamNumber];
    if (remembered != null) {
      return remembered;
    }

    final prefs = await _prefsLoader();
    final stored = _readCache(
      prefs,
      '$_prefix$teamNumber',
      StatboticsTeamYear.fromJson,
    );
    if (stored != null && _now().difference(stored.fetchedAt) < freshFor) {
      _memory[teamNumber] = stored.rows;
      return stored.rows;
    }

    if (!_statboticsEnabled) {
      final fallback = stored?.rows ?? const <StatboticsTeamYear>[];
      _memory[teamNumber] = fallback;
      return fallback;
    }

    try {
      final fetched = await _client.getTeamYears(teamNumber);
      final sorted = List<StatboticsTeamYear>.from(fetched)
        ..sort((a, b) => b.year.compareTo(a.year));
      final result = List<StatboticsTeamYear>.unmodifiable(sorted);
      _memory[teamNumber] = result;
      await _writeCache(
        prefs,
        '$_prefix$teamNumber',
        result.map((s) => s.toJson()).toList(),
      );
      return result;
    } catch (_) {
      return stored?.rows ?? const <StatboticsTeamYear>[];
    }
  }

  _Cached<T>? _readCache<T>(
    SharedPreferences prefs,
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = prefs.getString(key);
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.tryParse(
        decoded['fetchedAt'] as String? ?? '',
      );
      if (fetchedAt == null) {
        return null;
      }
      final rows = (decoded['rows'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((row) => fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false);
      return _Cached<T>(
        rows: List<T>.unmodifiable(rows),
        fetchedAt: fetchedAt.toUtc(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(
    SharedPreferences prefs,
    String key,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      await prefs.setString(
        key,
        jsonEncode(<String, dynamic>{
          'fetchedAt': _now().toUtc().toIso8601String(),
          'rows': rows,
        }),
      );
    } catch (_) {}
  }
}

class _Cached<T> {
  const _Cached({required this.rows, required this.fetchedAt});

  final List<T> rows;
  final DateTime fetchedAt;
}
