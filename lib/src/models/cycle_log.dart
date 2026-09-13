import '../theme/strategy_palette.dart';

enum CycleEventKind { intake, score, feed, defense }

class CycleEvent {
  const CycleEvent({
    required this.kind,
    required this.offsetMs,
    required this.phase,
  });

  final CycleEventKind kind;
  final int offsetMs;
  final StrategyPhase phase;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.name,
    'offsetMs': offsetMs,
    'phase': phase.name,
  };

  factory CycleEvent.fromJson(Map<String, dynamic> json) {
    return CycleEvent(
      kind: CycleEventKind.values.byName(json['kind'] as String),
      offsetMs: (json['offsetMs'] as num).toInt(),
      phase: StrategyPhase.values.byName(json['phase'] as String),
    );
  }
}

class CycleLog {
  const CycleLog({
    required this.matchKey,
    required this.team,
    this.events = const <CycleEvent>[],
  });

  final String matchKey;
  final int team;
  final List<CycleEvent> events;

  CycleLog copyWith({List<CycleEvent>? events}) =>
      CycleLog(matchKey: matchKey, team: team, events: events ?? this.events);

  static String keyFor(String matchKey, int team) => '$matchKey|$team';
  String get key => keyFor(matchKey, team);

  List<int> get cycleTimesMs {
    final times = <int>[];
    final sorted = <CycleEvent>[...events]
      ..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
    int? pendingIntake;
    for (final event in sorted) {
      if (event.kind == CycleEventKind.intake) {
        pendingIntake = event.offsetMs;
      } else if (event.kind == CycleEventKind.score && pendingIntake != null) {
        times.add(event.offsetMs - pendingIntake);
        pendingIntake = null;
      }
    }
    return times;
  }

  double? get meanCycleMs {
    final times = cycleTimesMs;
    if (times.isEmpty) return null;
    return times.reduce((a, b) => a + b) / times.length;
  }

  double? get medianCycleMs {
    final times = cycleTimesMs..sort();
    if (times.isEmpty) return null;
    final mid = times.length ~/ 2;
    if (times.length.isOdd) return times[mid].toDouble();
    return (times[mid - 1] + times[mid]) / 2;
  }

  Map<CycleEventKind, int> get countsByKind {
    final counts = <CycleEventKind, int>{
      for (final kind in CycleEventKind.values) kind: 0,
    };
    for (final event in events) {
      counts[event.kind] = counts[event.kind]! + 1;
    }
    return counts;
  }

  int countOf(CycleEventKind kind) => countsByKind[kind]!;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'matchKey': matchKey,
    'team': team,
    'events': events.map((e) => e.toJson()).toList(),
  };

  factory CycleLog.fromJson(Map<String, dynamic> json) {
    final rawEvents = (json['events'] as List?) ?? <dynamic>[];
    return CycleLog(
      matchKey: json['matchKey'] as String,
      team: (json['team'] as num).toInt(),
      events: rawEvents
          .whereType<Map>()
          .map((e) => _tryEvent(e.cast<String, dynamic>()))
          .whereType<CycleEvent>()
          .toList(growable: false),
    );
  }

  static CycleEvent? _tryEvent(Map<String, dynamic> json) {
    try {
      return CycleEvent.fromJson(json);
    } catch (_) {
      return null;
    }
  }
}
