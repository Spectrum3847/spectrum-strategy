import '../models/pit_scout_entry.dart';
import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart';
import 'entry_match.dart';
import 'robot_type.dart';
import 'scouting_analysis.dart';
import 'team_incidents.dart';
import 'team_summary_stats.dart';

enum TeamFilterGroup {
  canTheyDoIt('Can they do it?'),
  whatJob('What job?'),
  canWeTrust('Can we trust them?');

  const TeamFilterGroup(this.label);

  final String label;
}

enum TeamFilter {
  trenchFit(
    TeamFilterGroup.canTheyDoIt,
    'Fits under trench',
    'The latest pit entry says the robot fits under the trench.',
  ),
  climbsL3(
    TeamFilterGroup.canTheyDoIt,
    'Climbs L3',
    'At least one scout entry recorded a successful L3 climb.',
  ),
  autoClimb(
    TeamFilterGroup.canTheyDoIt,
    'Auto climb',
    'At least one scout entry recorded a successful auto climb.',
  ),
  defense(
    TeamFilterGroup.whatJob,
    'Plays defense',
    'Defense in at least 30% of scout entries, from 2 or more entries.',
  ),
  passer(
    TeamFilterGroup.whatJob,
    'Passer',
    'Passing in at least 30% of scout entries, from 2 or more entries.',
  ),
  cleanRecord(
    TeamFilterGroup.canWeTrust,
    'Clean record',
    'Scouted at this event with no cards and no deaths.',
  ),
  consistent(
    TeamFilterGroup.canWeTrust,
    'Consistent',
    '3 or more scout entries and score spread within 25% of the mean.',
  ),
  noPitData(
    TeamFilterGroup.canWeTrust,
    'No pit data yet',
    'No pit entry for this team. A to-do for the pit scouts.',
  );

  const TeamFilter(this.group, this.label, this.rule);

  final TeamFilterGroup group;
  final String label;

  final String rule;

  bool get needsPit => this == trenchFit || this == noPitData;
}

class TeamFilterResults {
  const TeamFilterResults(this._passing, this._teams);

  final Map<TeamFilter, Set<int>> _passing;
  final Set<int> _teams;

  int get total => _teams.length;

  int count(TeamFilter filter) => _passing[filter]?.length ?? 0;

  bool passes(int team, Set<TeamFilter> active) {
    for (final filter in active) {
      if (!(_passing[filter]?.contains(team) ?? false)) return false;
    }
    return true;
  }
}

class TeamFilters {
  const TeamFilters._();

  static const _autoClimbCode = 'auLow';
  static const _highClimbCode = 'eHigh';
  static const _defenseCode = 'tRdefense';
  static const _passerCode = 'tRpasser';

  static const _minRoleEntries = 2;
  static const _minConsistentEntries = 3;

  static const _rolePercent = 30;
  static const _maxSpreadRatio = 0.25;

  static TeamFilterResults evaluate({
    required Iterable<int> teams,
    required Iterable<ScoutEntry> entries,
    required Map<int, PitScoutEntry> pitByTeam,
    required String eventKey,
    ScoutConfig? config,
  }) {
    final roster = teams.toSet();
    final scoped = [
      for (final entry in entriesForEvent(entries, eventKey))
        if (roster.contains(entry.teamNumber)) entry,
    ];
    final byTeam = <int, List<ScoutEntry>>{};
    for (final entry in scoped) {
      (byTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }

    final analyses = ScoutingAnalysis.aggregateByTeam(scoped, config: config);
    final incidents = TeamIncidents.byTeam(scoped);
    final autoClimbField = _fieldFor(config, _autoClimbCode);
    final highClimbField = _fieldFor(config, _highClimbCode);

    final passing = <TeamFilter, Set<int>>{
      for (final filter in TeamFilter.values) filter: <int>{},
    };
    for (final team in roster) {
      final teamEntries = byTeam[team] ?? const <ScoutEntry>[];
      final pit = pitByTeam[team];
      void pass(TeamFilter filter, bool ok) {
        if (ok) passing[filter]!.add(team);
      }

      pass(
        TeamFilter.trenchFit,
        pit != null && _isTrue(pit.fieldValues[RobotType.trenchFitCode]),
      );
      pass(TeamFilter.climbsL3, _anySuccess(teamEntries, highClimbField));
      pass(TeamFilter.autoClimb, _anySuccess(teamEntries, autoClimbField));
      pass(TeamFilter.defense, _hasRole(teamEntries, _defenseCode));
      pass(TeamFilter.passer, _hasRole(teamEntries, _passerCode));
      pass(
        TeamFilter.cleanRecord,
        teamEntries.isNotEmpty && (incidents[team]?.isEmpty ?? true),
      );
      pass(TeamFilter.consistent, _isConsistent(analyses[team]));
      pass(TeamFilter.noPitData, pit == null);
    }
    return TeamFilterResults(passing, roster);
  }

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }

  static bool _isTrue(Object? raw) =>
      raw == true || (raw is String && raw.toLowerCase() == 'true');

  static bool _anySuccess(List<ScoutEntry> entries, ScoutConfigField? field) {
    if (field == null) return false;
    return entries.any(
      (entry) =>
          TeamSummaryStats.isClimbSuccess(field, entry.fieldValues[field.code]),
    );
  }

  static bool _hasRole(List<ScoutEntry> entries, String code) {
    if (entries.length < _minRoleEntries) return false;
    final yes = entries.where((e) => _isTrue(e.fieldValues[code])).length;
    return yes * 100 >= entries.length * _rolePercent;
  }

  static bool _isConsistent(TeamAnalysis? analysis) {
    if (analysis == null || analysis.entryCount < _minConsistentEntries) {
      return false;
    }
    final mean = analysis.meanTotalScore;
    if (mean <= 0) return false;
    return analysis.scoreStdDev <= _maxSpreadRatio * mean;
  }
}
