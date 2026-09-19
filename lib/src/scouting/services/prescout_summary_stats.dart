import '../models/prescout_entry.dart';
import '../models/team_analysis.dart' show TeamNote, interquartileMean;

class PrescoutSummaryRow {
  const PrescoutSummaryRow({
    required this.teamNumber,
    required this.matchesRecorded,
    this.iqmAutoFuel,
    this.maxAutoFuel,
    this.iqmTeleopFuel,
    this.maxTeleopFuel,
    this.avgFuelAccuracy,
    this.autoClimbRate,
    this.lowClimbRate,
    this.middleClimbRate,
    this.highClimbRate,
  });

  final int teamNumber;

  final int matchesRecorded;

  final double? iqmAutoFuel;
  final double? maxAutoFuel;
  final double? iqmTeleopFuel;
  final double? maxTeleopFuel;
  final double? avgFuelAccuracy;

  final double? autoClimbRate;
  final double? lowClimbRate;
  final double? middleClimbRate;
  final double? highClimbRate;
}

class PrescoutSummaryStats {
  const PrescoutSummaryStats._();

  static const _autoFuelCode = 'autoFuelScored';
  static const _teleopFuelCode = 'teleopFuelScored';
  static const _fuelAccuracyCode = 'fuelAccuracy';
  static const _autoClimbCode = 'autoClimbL1';
  static const _lowClimbCode = 'lowClimbL1';
  static const _middleClimbCode = 'middleClimbL2';
  static const _highClimbCode = 'highClimbL3';

  static const _successValue = 'successful';

  static const commentsCode = 'comments';

  static List<TeamNote> notesForTeam(
    int teamNumber,
    Iterable<PrescoutEntry> entries,
  ) {
    final notes = <TeamNote>[];
    for (final entry in entries.where((e) => e.teamNumber == teamNumber)) {
      final text = (entry.fieldValues[commentsCode] ?? '').toString().trim();
      if (text.isEmpty) continue;
      final match = (entry.fieldValues['matchNumber'] ?? '').toString().trim();
      notes.add(
        TeamNote(
          matchId: match.isEmpty ? entry.id : match,
          text: text,
          author: entry.authorDisplayName,
          updatedAt: entry.updatedAt,
        ),
      );
    }
    notes.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return List<TeamNote>.unmodifiable(notes);
  }

  static List<PrescoutSummaryRow> build(
    Iterable<PrescoutEntry> entries, {
    required Iterable<int> teamNumbers,
  }) {
    final byTeam = <int, List<PrescoutEntry>>{};
    for (final entry in entries) {
      (byTeam[entry.teamNumber] ??= <PrescoutEntry>[]).add(entry);
    }
    final teams = <int>{...teamNumbers, ...byTeam.keys}.toList()..sort();
    return <PrescoutSummaryRow>[
      for (final team in teams) _rowFor(team, byTeam[team] ?? const []),
    ];
  }

  static Map<int, double> gradeFractions(
    List<PrescoutSummaryRow> rows,
    double? Function(PrescoutSummaryRow row) valueOf,
  ) {
    final present = <int, double>{
      for (final row in rows)
        if (valueOf(row) != null) row.teamNumber: valueOf(row)!,
    };
    if (present.length < 2) return const <int, double>{};
    final lo = present.values.reduce((a, b) => a < b ? a : b);
    final hi = present.values.reduce((a, b) => a > b ? a : b);
    if (hi == lo) return const <int, double>{};
    return <int, double>{
      for (final e in present.entries) e.key: (e.value - lo) / (hi - lo),
    };
  }

  static PrescoutSummaryRow _rowFor(int team, List<PrescoutEntry> entries) {
    final autoFuel = _numbers(entries, _autoFuelCode);
    final teleopFuel = _numbers(entries, _teleopFuelCode);
    final accuracy = _numbers(entries, _fuelAccuracyCode);
    return PrescoutSummaryRow(
      teamNumber: team,
      matchesRecorded: entries.length,
      iqmAutoFuel: autoFuel.isEmpty ? null : interquartileMean(autoFuel),
      maxAutoFuel: autoFuel.isEmpty ? null : _max(autoFuel),
      iqmTeleopFuel: teleopFuel.isEmpty ? null : interquartileMean(teleopFuel),
      maxTeleopFuel: teleopFuel.isEmpty ? null : _max(teleopFuel),
      avgFuelAccuracy: accuracy.isEmpty
          ? null
          : accuracy.reduce((a, b) => a + b) / accuracy.length,
      autoClimbRate: _successRate(entries, _autoClimbCode),
      lowClimbRate: _successRate(entries, _lowClimbCode),
      middleClimbRate: _successRate(entries, _middleClimbCode),
      highClimbRate: _successRate(entries, _highClimbCode),
    );
  }

  static double _max(List<double> values) =>
      values.reduce((a, b) => a > b ? a : b);

  static List<double> _numbers(List<PrescoutEntry> entries, String code) {
    final values = <double>[];
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(code)) continue;
      final raw = entry.fieldValues[code];
      final value = raw is num
          ? raw.toDouble()
          : num.tryParse(raw?.toString() ?? '')?.toDouble();
      if (value != null) values.add(value);
    }
    return values;
  }

  static double? _successRate(List<PrescoutEntry> entries, String code) {
    var withValue = 0;
    var successes = 0;
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(code)) continue;
      withValue++;
      if (entry.fieldValues[code]?.toString() == _successValue) successes++;
    }
    if (withValue == 0) return null;
    return successes / withValue;
  }
}
