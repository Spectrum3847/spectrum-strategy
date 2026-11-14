import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import 'team_filters.dart';
import 'team_incidents.dart';
import 'team_summary_stats.dart';

class ScoutedSummaryLine {
  const ScoutedSummaryLine(this.text, this.matches);

  final String text;

  final List<String> matches;

  String get cited => matches.isEmpty ? text : '$text (${matches.join(', ')})';
}

enum ScoutedTrend { improving, declining, steady }

class ScoutedSummary {
  const ScoutedSummary({
    required this.entryCount,
    this.trend,
    this.strengths = const <ScoutedSummaryLine>[],
    this.concerns = const <ScoutedSummaryLine>[],
    this.roles = const <ScoutedSummaryLine>[],
  });

  final int entryCount;
  final ({ScoutedTrend direction, ScoutedSummaryLine line})? trend;
  final List<ScoutedSummaryLine> strengths;
  final List<ScoutedSummaryLine> concerns;
  final List<ScoutedSummaryLine> roles;

  bool get isEmpty =>
      trend == null && strengths.isEmpty && concerns.isEmpty && roles.isEmpty;
}

class ScoutedSummaryBuilder {
  const ScoutedSummaryBuilder._();

  static const minTrendEntries = 5;

  static const trendWindow = 3;

  static const trendChange = 0.12;

  static const minClimbAttempts = 3;

  static const reliableClimbRate = 0.8;

  static const unreliableClimbRate = 0.5;

  static const _autoFuelCode = 'autoFuelScored';
  static const _teleopFuelCode = 'teleopFuelScored';
  static const _defenseCode = 'tRdefense';
  static const _notAttemptedLabels = {'not attempted', 'n/a'};

  static const _climbLevels = <(String, String)>[
    ('eLow', 'L1'),
    ('eMiddle', 'L2'),
    ('eHigh', 'L3'),
  ];

  static ScoutedSummary build(
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final sorted = entries.toList()..sort(TeamIncidents.compareByMatch);
    if (sorted.isEmpty) return const ScoutedSummary(entryCount: 0);

    final strengths = <ScoutedSummaryLine>[];
    final concerns = <ScoutedSummaryLine>[];
    final roles = <ScoutedSummaryLine>[];

    final incidents = TeamIncidents.byTeam(sorted).values.firstOrNull;
    if (incidents != null) {
      void concern(String text, List<String> matches) {
        if (matches.isNotEmpty) {
          concerns.add(ScoutedSummaryLine(text, matches));
        }
      }

      concern('Died or disconnected', incidents.died);
      concern('Red card', incidents.red);
      concern('Yellow card', incidents.yellow);
      concern('Card, color not recorded', incidents.unknownCard);
    }

    _addClimb(sorted, config, strengths, concerns);
    _addDefense(sorted, roles);

    return ScoutedSummary(
      entryCount: sorted.length,
      trend: _trend(sorted),
      strengths: strengths,
      concerns: concerns,
      roles: roles,
    );
  }

  static void _addClimb(
    List<ScoutEntry> entries,
    ScoutConfig? config,
    List<ScoutedSummaryLine> strengths,
    List<ScoutedSummaryLine> concerns,
  ) {
    final fields = <(ScoutConfigField, String)>[
      for (final (code, label) in _climbLevels)
        if (_fieldFor(config, code) case final field?) (field, label),
    ];
    if (fields.isEmpty) return;

    final failed = <String>[];
    final reached = <String, int>{};
    var attempts = 0;
    var successes = 0;
    for (final entry in entries) {
      var attempted = false;
      String? best;
      for (final (field, level) in fields) {
        final raw = entry.fieldValues[field.code];
        if (raw == null) continue;
        final label = field.labelForStored(raw);
        final normalized = label.trim().toLowerCase();
        if (normalized.isEmpty || _notAttemptedLabels.contains(normalized)) {
          continue;
        }
        attempted = true;
        if (TeamSummaryStats.isClimbSuccess(field, raw)) best = level;
      }
      if (!attempted) continue;
      attempts++;
      if (best == null) {
        failed.add(TeamIncidents.matchLabelOf(entry));
      } else {
        successes++;
        reached[best] = (reached[best] ?? 0) + 1;
      }
    }
    if (attempts < minClimbAttempts) return;

    final rate = successes / attempts;
    final counts = '$successes of $attempts attempts';
    if (rate >= reliableClimbRate) {
      final usual = _usualLevel(reached);
      strengths.add(
        ScoutedSummaryLine(
          'Reliable climb, $counts, usually $usual',
          const <String>[],
        ),
      );
    } else if (rate < unreliableClimbRate) {
      concerns.add(ScoutedSummaryLine('Climb unreliable, $counts', failed));
    }
  }

  static String _usualLevel(Map<String, int> reached) {
    var usual = '';
    var most = 0;
    for (final (_, level) in _climbLevels) {
      final count = reached[level] ?? 0;
      if (count > 0 && count >= most) {
        usual = level;
        most = count;
      }
    }
    return usual;
  }

  static void _addDefense(
    List<ScoutEntry> entries,
    List<ScoutedSummaryLine> roles,
  ) {
    if (entries.length < TeamFilters.minRoleEntries) return;
    final played = [
      for (final entry in entries)
        if (_isTrue(entry.fieldValues[_defenseCode]))
          TeamIncidents.matchLabelOf(entry),
    ];
    if (played.length * 100 < entries.length * TeamFilters.rolePercent) return;
    roles.add(
      ScoutedSummaryLine(
        'Plays defense, ${played.length} of ${entries.length} matches',
        played,
      ),
    );
  }

  static ({ScoutedTrend direction, ScoutedSummaryLine line})? _trend(
    List<ScoutEntry> entries,
  ) {
    final scored = <(ScoutEntry, double)>[];
    for (final entry in entries) {
      final auto = _number(entry.fieldValues[_autoFuelCode]);
      final teleop = _number(entry.fieldValues[_teleopFuelCode]);
      if (auto == null && teleop == null) continue;
      scored.add((entry, (auto ?? 0) + (teleop ?? 0)));
    }
    if (scored.length < minTrendEntries) return null;

    final split = scored.length - trendWindow;
    double mean(Iterable<(ScoutEntry, double)> part) =>
        part.fold(0.0, (sum, e) => sum + e.$2) / part.length;
    final recent = mean(scored.skip(split));
    final before = mean(scored.take(split));

    final change = before == 0
        ? (recent > 0 ? double.infinity : 0.0)
        : (recent - before) / before;
    final cited = [
      for (final (entry, _) in scored.skip(split))
        TeamIncidents.matchLabelOf(entry),
    ];
    if (change > trendChange) {
      return (
        direction: ScoutedTrend.improving,
        line: ScoutedSummaryLine(
          'Improving, last $trendWindow average ${recent.round()} fuel '
          'against ${before.round()} before',
          cited,
        ),
      );
    }
    if (change < -trendChange) {
      return (
        direction: ScoutedTrend.declining,
        line: ScoutedSummaryLine(
          'Declining, last $trendWindow average ${recent.round()} fuel '
          'against ${before.round()} before',
          cited,
        ),
      );
    }
    return (
      direction: ScoutedTrend.steady,
      line: ScoutedSummaryLine(
        'Steady, about ${mean(scored).round()} fuel a match',
        const <String>[],
      ),
    );
  }

  static double? _number(Object? raw) => raw is num
      ? raw.toDouble()
      : num.tryParse(raw?.toString() ?? '')?.toDouble();

  static bool _isTrue(Object? raw) =>
      raw == true || (raw is String && raw.toLowerCase() == 'true');

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }
}
