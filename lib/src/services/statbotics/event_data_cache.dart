import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:statbotics_client/statbotics_client.dart';

class CachedEventData {
  const CachedEventData({
    required this.eventKey,
    required this.eventName,
    required this.teamEvents,
    required this.matches,
    required this.teamNicknames,
    required this.fetchedAt,
  });

  final String eventKey;
  final String eventName;
  final List<StatboticsTeamEvent> teamEvents;
  final List<StatboticsMatch> matches;
  final Map<int, String> teamNicknames;
  final DateTime fetchedAt;
}

class EventDataCache {
  EventDataCache({this._preferences});

  static const String _eventPrefix = 'event_data_cache_v2:';
  static const String _eventsPrefix = 'event_list_cache_v1:';

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  Future<void> saveEventData(CachedEventData data) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_eventPrefix${data.eventKey}',
      jsonEncode(<String, dynamic>{
        'eventName': data.eventName,
        'fetchedAt': data.fetchedAt.toUtc().toIso8601String(),
        'teamEvents': data.teamEvents.map((t) => t.toJson()).toList(),
        'matches': data.matches.map((m) => m.toJson()).toList(),
        'teamNicknames': <String, String>{
          for (final entry in data.teamNicknames.entries)
            entry.key.toString(): entry.value,
        },
      }),
    );
  }

  Future<CachedEventData?> loadEventData(String eventKey) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_eventPrefix$eventKey');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEventData(
        eventKey: eventKey,
        eventName: (json['eventName'] as String?) ?? eventKey,
        fetchedAt:
            DateTime.tryParse((json['fetchedAt'] as String?) ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        teamEvents: ((json['teamEvents'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StatboticsTeamEvent.fromJson)
            .toList(growable: false),
        matches: ((json['matches'] as List<dynamic>?) ?? <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(StatboticsMatch.fromJson)
            .toList(growable: false),
        teamNicknames: <int, String>{
          for (final entry
              in ((json['teamNicknames'] as Map<String, dynamic>?) ??
                      <String, dynamic>{})
                  .entries)
            if (int.tryParse(entry.key) != null && entry.value is String)
              int.parse(entry.key): entry.value as String,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEventsForYear(int year, List<StatboticsEvent> events) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_eventsPrefix$year',
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<StatboticsEvent>?> loadEventsForYear(int year) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_eventsPrefix$year');
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(StatboticsEvent.fromJson)
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }
}
