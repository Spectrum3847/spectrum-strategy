import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/firestore_active_event_service.dart';
import '../services/statbotics/event_data_cache.dart';
import '../services/statbotics/statbotics_switch.dart';

import 'package:statbotics_client/statbotics_client.dart';
import 'package:tba_client/tba_client.dart';

const _kEventKey = 'selected_event_key';

const _kMyTeamNumberKey = 'my_team_number';

class EventController extends ChangeNotifier {
  EventController({
    StatboticsClient? client,
    this._tbaClient,
    EventDataCache? cache,
    this._syncService,
    DateTime Function()? clock,
    bool? statboticsEnabled,
  }) : _client = client ?? StatboticsClient(),
       _cache = cache ?? EventDataCache(),
       _clock = clock ?? DateTime.now,
       _statboticsEnabled = statboticsEnabled ?? kStatboticsEnabled;

  final StatboticsClient _client;

  final bool _statboticsEnabled;

  final TbaClient? _tbaClient;
  final EventDataCache _cache;
  final ActiveEventSyncService? _syncService;
  final DateTime Function() _clock;
  Future<void>? _bootstrapFuture;
  StreamSubscription<String?>? _remoteSubscription;

  bool _applyingRemote = false;

  String _eventKey = '';
  String _eventName = '';
  int? _myTeamNumber;
  List<StatboticsTeamEvent> _teamEvents = const <StatboticsTeamEvent>[];
  List<StatboticsMatch> _matches = const <StatboticsMatch>[];
  Map<int, String> _teamNicknames = const <int, String>{};
  bool _loading = false;
  String? _error;
  String? _dataNotice;

  Set<String> _unloadedParts = const <String>{};

  bool _tbaKeyMissing = false;

  bool _tbaKeyRejected = false;

  List<StatboticsEvent> _availableEvents = const <StatboticsEvent>[];
  bool _eventsLoading = false;
  String? _eventsError;
  int? _loadingForYear;

  String get eventKey => _eventKey;
  String get eventName => _eventName;

  int? get myTeamNumber => _myTeamNumber;

  TbaClient? get tbaClient => _tbaClient;
  List<StatboticsTeamEvent> get teamEvents => _teamEvents;

  List<StatboticsTeamEvent> get displayTeams {
    if (_teamEvents.isNotEmpty) return _teamEvents;
    if (_teamNicknames.isEmpty) return _teamEvents;
    final teams = _teamNicknames.keys.toList(growable: false)..sort();
    return <StatboticsTeamEvent>[
      for (final team in teams)
        StatboticsTeamEvent(
          team: team,
          event: _eventKey,
          eventName: _eventName,

          year: _eventKey.length >= 4
              ? int.tryParse(_eventKey.substring(0, 4)) ?? 0
              : 0,
          wins: 0,
          losses: 0,
          ties: 0,
          epa: StatboticsEpa.empty,
        ),
    ];
  }

  bool get teamsAreRosterOnly =>
      _teamEvents.isEmpty && _teamNicknames.isNotEmpty;
  List<StatboticsMatch> get matches => _matches;
  Map<int, String> get teamNicknames => _teamNicknames;
  bool get isLoading => _loading;
  String? get error => _error;

  String? get dataNotice => _dataNotice;

  String? get scheduleError =>
      _unloadedParts.contains('match schedule') ? _error : null;

  List<StatboticsEvent> get availableEvents => _availableEvents;
  bool get eventsLoading => _eventsLoading;
  String? get eventsError => _eventsError;

  List<int> get teamNumbers =>
      _teamEvents.map((te) => te.team).toList(growable: false);

  bool get hasEvent => _eventKey.isNotEmpty;
  bool get hasMatches => _matches.isNotEmpty;

  String teamName(int team) {
    final nick = _teamNicknames[team];
    if (nick == null || nick.isEmpty) return team.toString();
    return '$team — $nick';
  }

  Future<void> bootstrap() {
    return _bootstrapFuture ??= _bootstrap().onError<Object>((
      error,
      stackTrace,
    ) {
      _bootstrapFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _myTeamNumber = prefs.getInt(_kMyTeamNumberKey);
    final stored = prefs.getString(_kEventKey) ?? '';
    if (stored.isNotEmpty) {
      _eventKey = stored;

      unawaited(_fetch());
    }

    final sync = _syncService;
    if (sync != null) {
      _remoteSubscription = sync.eventKeyStream.listen(_onRemoteEventKey);
      try {
        await sync.initialize();
      } catch (_) {}
    }
  }

  void _onRemoteEventKey(String? remoteKey) {
    if (remoteKey == null) return;
    final trimmed = remoteKey.trim();
    if (trimmed == _eventKey) return;
    _applyingRemote = true;
    unawaited(setEventKey(trimmed).whenComplete(() => _applyingRemote = false));
  }

  Future<void> setEventKey(String key) async {
    final trimmed = key.trim();
    if (trimmed == _eventKey) {
      if (trimmed.isNotEmpty && !_applyingRemote) await refresh();
      return;
    }
    _eventKey = trimmed;
    _eventName = '';
    _teamEvents = const <StatboticsTeamEvent>[];
    _matches = const <StatboticsMatch>[];
    _teamNicknames = const <int, String>{};
    _error = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEventKey, trimmed);

    _autoPush(trimmed);

    if (trimmed.isNotEmpty) {
      await _fetch();
    }
  }

  Future<void> setMyTeamNumber(int? teamNumber) async {
    if (teamNumber == _myTeamNumber) return;
    _myTeamNumber = teamNumber;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    if (teamNumber == null) {
      await prefs.remove(_kMyTeamNumberKey);
    } else {
      await prefs.setInt(_kMyTeamNumberKey, teamNumber);
    }
  }

  void _autoPush(String eventKey) {
    final sync = _syncService;
    if (sync == null) return;

    if (_applyingRemote) return;
    unawaited(() async {
      try {
        await sync.push(eventKey);
      } catch (e) {
        debugPrint('Failed to auto-push active event: $e');
      }
    }());
  }

  Future<void> refresh() async {
    if (_eventKey.isEmpty) return;

    if (_loading) return;
    await _fetch();
  }

  Future<void> loadEventsForYear(int year) async {
    if (_eventsLoading && _loadingForYear == year) return;
    _loadingForYear = year;
    _eventsLoading = true;
    _eventsError = null;
    notifyListeners();

    try {
      if (!_statboticsEnabled) {
        throw StatboticsApiException(500, 'Statbotics disabled by switch');
      }
      _availableEvents = await _withOffseasonEvents(
        year,
        await _client.getEvents(year),
      );
      _eventsError = null;
      await _cache.saveEventsForYear(year, _availableEvents);
    } catch (e) {
      debugPrint('EventController: events load error — $e');
      _tbaKeyMissing = false;
      _tbaKeyRejected = false;
      final recovered = await _loadEventsFallback(year);
      if (recovered) {
        _eventsError = null;
      } else {
        _eventsError =
            'Could not load the event list (${_causeOf(e)}).'
            '${_tbaKeyHint()}';
      }
    } finally {
      _eventsLoading = false;
      notifyListeners();
    }
  }

  Future<List<StatboticsEvent>> _withOffseasonEvents(
    int year,
    List<StatboticsEvent> known,
  ) async {
    final tba = _tbaClient;
    if (tba == null) return known;
    try {
      final keys = known.map((StatboticsEvent e) => e.key).toSet();
      final extra = (await tba.getEventsForYear(year))
          .where((e) => !keys.contains(e.key))
          .map(_asStatboticsEvent);
      if (extra.isEmpty) return known;
      return _byStartDate(<StatboticsEvent>[...known, ...extra]);
    } catch (e) {
      debugPrint('EventController: offseason event merge failed — $e');
      return known;
    }
  }

  static StatboticsEvent _asStatboticsEvent(TbaEvent e) => StatboticsEvent(
    key: e.key,
    name: e.name,
    year: e.year,
    week: e.week,
    country: e.country,
    state: e.stateProv,
    startDate: e.startDate,
    endDate: e.endDate,
  );

  static List<StatboticsEvent> _byStartDate(List<StatboticsEvent> events) {
    events.sort((StatboticsEvent a, StatboticsEvent b) {
      final byDate = (a.startDate ?? '9999').compareTo(b.startDate ?? '9999');
      return byDate != 0 ? byDate : a.name.compareTo(b.name);
    });
    return List<StatboticsEvent>.unmodifiable(events);
  }

  Future<bool> _loadEventsFallback(int year) async {
    final tba = _tbaClient;
    if (tba != null) {
      try {
        final events = await tba.getEventsForYear(year);
        if (events.isNotEmpty) {
          _availableEvents = _byStartDate(
            events.map(_asStatboticsEvent).toList(),
          );
          await _cache.saveEventsForYear(year, _availableEvents);
          return true;
        }
      } catch (e) {
        _noteTbaFailure(e);
        debugPrint('EventController: TBA events fallback failed — $e');
      }
    }
    final cached = await _cache.loadEventsForYear(year);
    if (cached != null && cached.isNotEmpty) {
      _availableEvents = cached;
      return true;
    }
    return false;
  }

  Future<void> _fetch() async {
    if (_eventKey.isEmpty) return;
    _loading = true;
    _error = null;
    _dataNotice = null;
    _unloadedParts = const <String>{};
    notifyListeners();

    final failures = <String, String>{};
    _tbaKeyMissing = false;
    _tbaKeyRejected = false;
    Future<T> guarded<T>(String part, Future<T> Function() run, T fallback) {
      if (!_statboticsEnabled) {
        failures[part] = _causeOf(
          StatboticsApiException(500, 'Statbotics disabled by switch'),
        );
        debugPrint('EventController: $part skipped — Statbotics disabled');
        return Future<T>.value(fallback);
      }
      return run().catchError((Object e) {
        failures[part] = _causeOf(e);
        debugPrint('EventController: $part failed — $e');
        return fallback;
      });
    }

    final results = await Future.wait(<Future<dynamic>>[
      guarded<StatboticsEvent?>(
        'event info',
        () => _client.getEvent(_eventKey),
        null,
      ),
      guarded<List<StatboticsTeamEvent>>(
        'team stats',
        () => _client.getEventTeams(_eventKey),
        const <StatboticsTeamEvent>[],
      ),
      guarded<List<StatboticsMatch>>(
        'match schedule',
        () => _client.getEventMatches(_eventKey),
        const <StatboticsMatch>[],
      ),
    ]);
    final event = results[0] as StatboticsEvent?;
    final teamEvents = results[1] as List<StatboticsTeamEvent>;
    final matches = results[2] as List<StatboticsMatch>;

    _eventName = event?.name ?? _eventKey;
    _teamEvents = teamEvents;
    _matches = matches;

    _teamNicknames = {
      for (final t in teamEvents)
        if (t.teamName.isNotEmpty) t.team: t.teamName,
    };

    final noStatboticsCoverage =
        failures.length == 1 &&
        failures.containsKey('event info') &&
        teamEvents.isEmpty &&
        matches.isEmpty;

    if (failures.isEmpty) {
      if (event == null && teamEvents.isEmpty && matches.isEmpty) {
        _dataNotice =
            'Statbotics has no data for this event yet, which is common for '
            'offseason events. Scouting still works; team stats and the '
            'schedule appear once Statbotics covers the event.';
      } else {
        if (teamEvents.isEmpty) {
          _dataNotice =
              'Statbotics has no team stats for $_eventKey yet. That is '
              'normal before qualification matches are played, and it is also '
              'what you see if the event key is wrong.';
        }
        await _saveSnapshotQuietly();
      }
    } else {
      final servedFromCache = await _recoverFromFailures(
        failures,
        noStatboticsCoverage: noStatboticsCoverage,
      );

      await _saveSnapshotQuietly(servedFromCache: servedFromCache);
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _saveSnapshotQuietly({bool servedFromCache = false}) async {
    try {
      await _saveSnapshot(servedFromCache: servedFromCache);
    } catch (e) {
      debugPrint('EventController: caching the event snapshot failed — $e');
    }
  }

  Future<void> _saveSnapshot({bool servedFromCache = false}) async {
    final cached = await _cache.loadEventData(_eventKey);

    var carriedOver = servedFromCache;
    var teamEvents = _teamEvents;
    if (teamEvents.isEmpty && (cached?.teamEvents.isNotEmpty ?? false)) {
      teamEvents = cached!.teamEvents;
      carriedOver = true;
    }
    var matches = _matches;
    if (matches.isEmpty && (cached?.matches.isNotEmpty ?? false)) {
      matches = cached!.matches;
      carriedOver = true;
    }
    var nicknames = _teamNicknames;
    if (nicknames.isEmpty && (cached?.teamNicknames.isNotEmpty ?? false)) {
      nicknames = cached!.teamNicknames;
      carriedOver = true;
    }

    await _cache.saveEventData(
      CachedEventData(
        eventKey: _eventKey,
        eventName: _eventName.isEmpty ? (cached?.eventName ?? '') : _eventName,
        teamEvents: teamEvents,
        matches: matches,
        teamNicknames: nicknames,
        fetchedAt: carriedOver ? (cached?.fetchedAt ?? _clock()) : _clock(),
      ),
    );
  }

  Future<bool> _recoverFromFailures(
    Map<String, String> failures, {
    bool noStatboticsCoverage = false,
  }) async {
    final firstCause = failures.values.first;
    var tbaUsed = false;
    DateTime? cacheAge;

    var namesMissing = _teamNicknames.isEmpty;

    var scheduleFromTba = false;
    var namesFromTba = false;
    var eventNameFromTba = false;
    final scheduleMissing =
        failures.containsKey('match schedule') ||
        (noStatboticsCoverage && _matches.isEmpty);

    final tba = _tbaClient;
    if (tba != null) {
      if (scheduleMissing) {
        try {
          final tbaMatches = await tba.getEventMatches(_eventKey);
          if (tbaMatches.isNotEmpty) {
            _matches = tbaMatches
                .map(
                  (m) => StatboticsMatch(
                    key: m.key,
                    event: _eventKey,
                    matchNumber: m.matchNumber,
                    compLevel: m.compLevel,
                    redTeams: m.redTeams,
                    blueTeams: m.blueTeams,
                  ),
                )
                .toList(growable: false);
            failures.remove('match schedule');
            tbaUsed = true;
            scheduleFromTba = true;
          }
        } catch (e) {
          _noteTbaFailure(e);
          debugPrint('EventController: TBA schedule fallback failed — $e');
        }
      }
      if (namesMissing) {
        try {
          final tbaTeams = await tba.getEventTeams(_eventKey);
          if (tbaTeams.isNotEmpty) {
            _teamNicknames = {
              for (final t in tbaTeams)
                if (t.nickname.isNotEmpty) t.teamNumber: t.nickname,
            };
            namesMissing = false;
            tbaUsed = true;
            namesFromTba = true;
          }
        } catch (e) {
          _noteTbaFailure(e);
          debugPrint('EventController: TBA team names fallback failed — $e');
        }
      }
      if (failures.containsKey('event info')) {
        try {
          final tbaEvent = await tba.getEvent(_eventKey);
          if (tbaEvent != null && tbaEvent.name.isNotEmpty) {
            _eventName = tbaEvent.name;
            failures.remove('event info');
            tbaUsed = true;
            eventNameFromTba = true;
          }
        } catch (e) {
          _noteTbaFailure(e);
          debugPrint('EventController: TBA event info fallback failed — $e');
        }
      }
    }

    final cached = await _cache.loadEventData(_eventKey);
    if (cached != null) {
      if (failures.containsKey('team stats') && cached.teamEvents.isNotEmpty) {
        _teamEvents = cached.teamEvents;
        failures.remove('team stats');
        cacheAge = cached.fetchedAt;
      }
      if (failures.containsKey('match schedule') && cached.matches.isNotEmpty) {
        _matches = cached.matches;
        failures.remove('match schedule');
        cacheAge = cached.fetchedAt;
      }
      if (namesMissing && cached.teamNicknames.isNotEmpty) {
        _teamNicknames = cached.teamNicknames;
        namesMissing = false;
        cacheAge = cached.fetchedAt;
      }
      if (failures.containsKey('event info')) {
        _eventName = cached.eventName;
        failures.remove('event info');
        cacheAge = cached.fetchedAt;
      }
    }

    if (noStatboticsCoverage) {
      const lead =
          'Statbotics has no data for this event, which is normal for '
          'an offseason event. EPA stats stay empty.';

      final fromTba = <String>[
        if (eventNameFromTba) 'event name',
        if (scheduleFromTba) 'schedule',
        if (namesFromTba) 'team names',
      ];
      if (fromTba.isEmpty) {
        _dataNotice =
            '$lead Scouting and strategy boards still work.'
            '${_tbaKeyHint()}';
      } else {
        _dataNotice =
            '$lead The ${_joinWithAnd(fromTba)} '
            '${fromTba.length == 1 ? 'is' : 'are'} live from '
            'The Blue Alliance.';
      }
      failures.clear();
      return cacheAge != null;
    }

    if (tbaUsed && cacheAge != null) {
      _dataNotice =
          'Statbotics is unavailable ($firstCause). The schedule and team '
          'names are live from The Blue Alliance; EPA stats are cached from '
          '${_ago(cacheAge)}.';
    } else if (tbaUsed) {
      _dataNotice =
          'Statbotics is unavailable ($firstCause). The schedule and team '
          'names are live from The Blue Alliance; EPA stats return when '
          'Statbotics recovers.';

      failures.remove('team stats');
    } else if (cacheAge != null) {
      _dataNotice =
          'Statbotics is unreachable ($firstCause). Showing cached event '
          'data from ${_ago(cacheAge)}.';
    }

    _unloadedParts = failures.keys.toSet();

    if (failures.length >= 3) {
      _error =
          'Could not load event data (${failures.values.first}). '
          'Check your connection, then retry.${_tbaKeyHint()}';
    } else if (failures.isNotEmpty) {
      final parts = failures.entries
          .map((f) => '${f.key}: ${f.value}')
          .join('; ');
      _error =
          'Some event data failed to load ($parts). Retry to fill it in.'
          '${_tbaKeyHint()}';
    }

    return cacheAge != null;
  }

  static String _joinWithAnd(List<String> parts) {
    if (parts.length == 1) return parts.first;
    return '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }

  void _noteTbaFailure(Object e) {
    if (e is TbaApiKeyMissingException) {
      _tbaKeyMissing = true;
    } else if (e is TbaApiException && e.statusCode == 401) {
      _tbaKeyRejected = true;
    }
  }

  String _tbaKeyHint() {
    if (_tbaKeyMissing) {
      return ' The Blue Alliance fallback needs a team TBA key; ask an admin '
          'to add one to the shared app config.';
    }
    if (_tbaKeyRejected) {
      return ' The Blue Alliance rejected the team TBA key; ask an admin to '
          'replace it in the shared app config.';
    }
    return '';
  }

  String _ago(DateTime then) {
    final elapsed = _clock().difference(then);
    if (elapsed.inMinutes < 1) return 'moments ago';
    if (elapsed.inMinutes < 60) {
      final m = elapsed.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (elapsed.inHours < 48) {
      final h = elapsed.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    final d = elapsed.inDays;
    return '$d days ago';
  }

  static String _causeOf(Object e) {
    if (e is StatboticsApiException) {
      if (e.statusCode == 429) return 'Statbotics is rate-limiting us';
      if (e.statusCode >= 500) return 'Statbotics is busy (${e.statusCode})';
      return 'Statbotics error ${e.statusCode}';
    }
    if (e is FormatException || e is TypeError) {
      return 'unexpected data from Statbotics';
    }
    return 'network error';
  }

  @override
  void dispose() {
    _remoteSubscription?.cancel();
    _syncService?.dispose();
    _client.close();
    super.dispose();
  }
}
