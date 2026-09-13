import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tba_client/tba_client.dart';

const _kSectionsKey = 'tba_sections_v1';

enum EventSection {
  rankings('Rankings', 'Qualification ranking order, record and RP'),
  alliances('Alliances', 'Playoff alliances in pick order'),
  awards('Awards', 'Awards presented at the event'),
  matchResults('Match results', 'Final scores and match times on each row'),
  matchVideos('Match videos', 'A link to the match video where one exists'),
  rankingPoints(
    'Ranking points',
    'Each alliance\'s RP from the score breakdown',
  ),
  predictedScores(
    'Predicted scores',
    'TBA\'s predicted score for each alliance on an unplayed match',
  );

  const EventSection(this.label, this.description);

  final String label;
  final String description;

  static EventSection? fromName(String name) {
    for (final section in EventSection.values) {
      if (section.name == name) return section;
    }

    return null;
  }
}

const Set<EventSection> defaultSections = <EventSection>{};

class EventSectionsController extends ChangeNotifier {
  EventSectionsController({required this._tbaClient});

  final TbaClient? _tbaClient;

  Future<void>? _bootstrapFuture;
  Set<EventSection> _visible = defaultSections.toSet();
  TbaEventRankings? _rankings;
  TbaEventAlliances? _alliances;
  TbaEventAwards? _awards;
  Map<String, TbaMatchPrediction> _predictions =
      const <String, TbaMatchPrediction>{};

  Map<String, TbaScheduleMatch> _matchesByKey =
      const <String, TbaScheduleMatch>{};
  bool _loading = false;
  String? _error;
  int _loadSequence = 0;

  Set<EventSection> get visible => Set<EventSection>.unmodifiable(_visible);
  TbaEventRankings? get rankings => _rankings;
  TbaEventAlliances? get alliances => _alliances;
  TbaEventAwards? get awards => _awards;

  TbaMatchPrediction? predictionFor(String matchKey) => _predictions[matchKey];

  TbaScheduleMatch? matchFor(String matchKey) => _matchesByKey[matchKey];

  bool get needsMatches =>
      _visible.contains(EventSection.matchResults) ||
      _visible.contains(EventSection.matchVideos) ||
      _visible.contains(EventSection.rankingPoints);

  bool get _needsDetailedMatches =>
      _visible.contains(EventSection.matchVideos) ||
      _visible.contains(EventSection.rankingPoints);
  bool get isLoading => _loading;
  String? get error => _error;

  bool isVisible(EventSection section) => _visible.contains(section);

  bool get isAllHidden => _visible.isEmpty;

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
    final stored = prefs.getStringList(_kSectionsKey);

    if (stored != null) {
      _visible = stored
          .map(EventSection.fromName)
          .whereType<EventSection>()
          .toSet();
    }
    notifyListeners();
  }

  Future<void> load(String eventKey) async {
    final request = ++_loadSequence;
    if (eventKey.isEmpty || _visible.isEmpty) {
      _clearData();
      _error = null;
      _loading = false;
      notifyListeners();
      return;
    }

    final tba = _tbaClient;
    if (tba == null) {
      _error = 'TBA event sections need a TBA API key. Set one in Settings.';
      _clearData();
      _loading = false;
      notifyListeners();
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    final failures = <String>[];

    final rankingsCall = _visible.contains(EventSection.rankings)
        ? _guard(() => tba.getEventRankings(eventKey), 'rankings', failures)
        : null;
    final alliancesCall = _visible.contains(EventSection.alliances)
        ? _guard(() => tba.getEventAlliances(eventKey), 'alliances', failures)
        : null;
    final awardsCall = _visible.contains(EventSection.awards)
        ? _guard(() => tba.getEventAwards(eventKey), 'awards', failures)
        : null;

    final predictionsCall = _visible.contains(EventSection.predictedScores)
        ? _guard(
            () => tba.getEventPredictions(eventKey),
            'predicted scores',
            failures,
          )
        : null;
    final matchesCall = needsMatches
        ? _guard(
            () => _needsDetailedMatches
                ? tba.getEventMatchesDetailed(eventKey)
                : tba.getEventMatches(eventKey),
            'match results',
            failures,
          )
        : null;
    final rankings = await rankingsCall;
    final alliances = await alliancesCall;
    final awards = await awardsCall;
    final matches = await matchesCall;
    final predictions = await predictionsCall;

    if (request != _loadSequence) return;

    _rankings = rankings;
    _alliances = alliances;
    _awards = awards;
    _matchesByKey = <String, TbaScheduleMatch>{
      for (final match in matches ?? const <TbaScheduleMatch>[])
        if (match.key.isNotEmpty) match.key: match,
    };
    _predictions = predictions ?? const <String, TbaMatchPrediction>{};
    _loading = false;
    if (failures.isNotEmpty) {
      _error = 'Could not load ${failures.join(', ')} from TBA.';
    }
    notifyListeners();
  }

  void _clearData() {
    _rankings = null;
    _alliances = null;
    _awards = null;
    _matchesByKey = const <String, TbaScheduleMatch>{};
    _predictions = const <String, TbaMatchPrediction>{};
  }

  Future<void> toggle(EventSection section) {
    final next = Set<EventSection>.of(_visible);
    if (!next.remove(section)) next.add(section);
    return _setVisible(next);
  }

  Future<void> showAll() => _setVisible(EventSection.values.toSet());

  Future<void> hideAll() => _setVisible(<EventSection>{});

  Future<void> _setVisible(Set<EventSection> next) async {
    _visible = next;

    if (!next.contains(EventSection.rankings)) _rankings = null;
    if (!next.contains(EventSection.alliances)) _alliances = null;
    if (!next.contains(EventSection.awards)) _awards = null;

    if (!next.contains(EventSection.matchResults) &&
        !next.contains(EventSection.matchVideos) &&
        !next.contains(EventSection.rankingPoints)) {
      _matchesByKey = const <String, TbaScheduleMatch>{};
    }
    if (!next.contains(EventSection.predictedScores)) {
      _predictions = const <String, TbaMatchPrediction>{};
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kSectionsKey,
      next.map((s) => s.name).toList(growable: false),
    );
  }

  Future<T?> _guard<T>(
    Future<T?> Function() call,
    String label,
    List<String> failures,
  ) async {
    try {
      return await call();
    } catch (e) {
      debugPrint('EventSectionsController: $label failed — $e');
      failures.add(label);
      return null;
    }
  }
}
