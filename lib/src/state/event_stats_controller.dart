import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

import '../models/event_stat_table.dart';

const _kStatColumnsKey = 'tba_stat_columns_v1';

class EventStatsController extends ChangeNotifier {
  EventStatsController({required this._tbaClient});

  final TbaClient? _tbaClient;

  Future<void>? _bootstrapFuture;
  EventStatTable _table = const EventStatTable.empty();
  TbaEventRankings? _rankings;
  Set<String> _selectedColumns = defaultStatColumns.toSet();
  bool _loading = false;
  String? _error;

  EventStatTable get table => _table;

  TbaEventRankings? get rankings => _rankings;

  int? rankFor(int team) {
    final rows = _rankings?.rankings;
    if (rows == null) return null;
    for (final row in rows) {
      if (teamNumberFromKey(row.teamKey) == team) return row.rank;
    }
    return null;
  }

  double? rankPercentileFor(int team) {
    final rows = _rankings?.rankings;
    if (rows == null || rows.isEmpty) return null;
    final rank = rankFor(team);
    if (rank == null) return null;
    if (rows.length == 1) return 1;
    return (rows.length - rank) / (rows.length - 1);
  }

  String? recordFor(int team) {
    final rows = _rankings?.rankings;
    if (rows == null) return null;
    for (final row in rows) {
      if (teamNumberFromKey(row.teamKey) == team) return row.record;
    }
    return null;
  }

  num? oprFor(int team) => _table.valueFor(team, oprStatName);
  bool get isLoading => _loading;
  String? get error => _error;

  Set<String> get selectedColumns => Set<String>.unmodifiable(_selectedColumns);

  List<String> get visibleColumns => _table.visibleColumns(_selectedColumns);

  bool get hasNoStats => !_loading && _error == null && _table.isEmpty;

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
    final stored = prefs.getStringList(_kStatColumnsKey);

    if (stored != null) {
      _selectedColumns = stored.toSet();
    }
    notifyListeners();
  }

  Future<void> load(String eventKey) async {
    final request = ++_loadSequence;
    if (eventKey.isEmpty) {
      _table = const EventStatTable.empty();
      _rankings = null;
      _loadedEventKey = eventKey;
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final tba = _tbaClient;
    if (tba == null) {
      _error = 'TBA stats need a TBA API key. Set one in Settings.';
      _table = const EventStatTable.empty();
      _rankings = null;
      _loading = false;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    if (eventKey != _loadedEventKey) {
      _table = const EventStatTable.empty();
      _rankings = null;
      _loadedEventKey = eventKey;
    }
    notifyListeners();

    final failures = <String>[];

    final oprsCall = _guard(() => tba.getEventOprs(eventKey), 'OPR', failures);
    final coprsCall = _guard(
      () => tba.getEventCoprs(eventKey),
      'component OPR',
      failures,
    );

    final rankingFailures = <String>[];
    final rankingsCall = _guard(
      () => tba.getEventRankings(eventKey),
      'rankings',
      rankingFailures,
    );
    final oprs = await oprsCall;
    final coprs = await coprsCall;
    final rankings = await rankingsCall;

    if (request != _loadSequence) return;

    _table = EventStatTable.from(eventKey: eventKey, oprs: oprs, coprs: coprs);
    _rankings = rankings;
    _loading = false;
    if (failures.isNotEmpty && _table.isEmpty) {
      _error = 'Could not load ${failures.join(' or ')} stats from TBA.';
    }
    notifyListeners();
  }

  int _loadSequence = 0;

  String? _loadedEventKey;

  Future<T?> _guard<T>(
    Future<T?> Function() call,
    String label,
    List<String> failures,
  ) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('EventStatsController: $label stats failed — $e');
      failures.add(label);
      return null;
    }
  }

  Future<void> toggleColumn(String statName) async {
    final next = Set<String>.of(_selectedColumns);
    if (!next.remove(statName)) next.add(statName);
    await _setColumns(next);
  }

  Future<void> resetColumns() => _setColumns(defaultStatColumns.toSet());

  Future<void> _setColumns(Set<String> next) async {
    _selectedColumns = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kStatColumnsKey, next.toList());
  }
}
