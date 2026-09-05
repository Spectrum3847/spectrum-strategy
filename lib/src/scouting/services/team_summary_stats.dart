import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import '../models/team_analysis.dart';

class TeamSummaryRow {
  const TeamSummaryRow({
    required this.teamNumber,
    this.iqmTeleop,
    this.maxTeleop,
    this.iqmAuto,
    this.maxAuto,
    this.autoClimbRate,
    this.lowClimbRate,
    this.middleClimbRate,
    this.highClimbRate,
  });

  final int teamNumber;

  final double? iqmTeleop;
  final double? maxTeleop;
  final double? iqmAuto;
  final double? maxAuto;

  final double? autoClimbRate;

  final double? lowClimbRate;

  final double? middleClimbRate;

  final double? highClimbRate;
}

class TeamSummaryStats {
  const TeamSummaryStats._();

  static const _teleopFuelCode = 'teleopFuelScored';
  static const _autoFuelCode = 'autoFuelScored';
  static const _autoClimbCode = 'auLow';
  static const _lowClimbCode = 'eLow';
  static const _middleClimbCode = 'eMiddle';
  static const _highClimbCode = 'eHigh';

  static const _successLabels = <String>{
    'Outpost',
    'Middle',
    'Depot',
    'Successful',
  };

  static List<TeamSummaryRow> build(
    Iterable<ScoutEntry> entries, {
    required Iterable<int> teamNumbers,
    ScoutConfig? config,
  }) {
    final byTeam = <int, List<ScoutEntry>>{};
    for (final entry in entries) {
      (byTeam[entry.teamNumber] ??= <ScoutEntry>[]).add(entry);
    }

    final teleopField = _fieldFor(config, _teleopFuelCode);
    final autoField = _fieldFor(config, _autoFuelCode);
    final autoClimbField = _fieldFor(config, _autoClimbCode);
    final lowClimbField = _fieldFor(config, _lowClimbCode);
    final middleClimbField = _fieldFor(config, _middleClimbCode);
    final highClimbField = _fieldFor(config, _highClimbCode);

    final teams = <int>{...teamNumbers, ...byTeam.keys}.toList()..sort();
    return <TeamSummaryRow>[
      for (final team in teams)
        _rowFor(
          team,
          byTeam[team] ?? const <ScoutEntry>[],
          teleopField: teleopField,
          autoField: autoField,
          autoClimbField: autoClimbField,
          lowClimbField: lowClimbField,
          middleClimbField: middleClimbField,
          highClimbField: highClimbField,
        ),
    ];
  }

  static Map<int, double> gradeFractions(
    List<TeamSummaryRow> rows,
    double? Function(TeamSummaryRow row) valueOf,
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

  static TeamSummaryRow _rowFor(
    int team,
    List<ScoutEntry> teamEntries, {
    required ScoutConfigField? teleopField,
    required ScoutConfigField? autoField,
    required ScoutConfigField? autoClimbField,
    required ScoutConfigField? lowClimbField,
    required ScoutConfigField? middleClimbField,
    required ScoutConfigField? highClimbField,
  }) {
    final teleopValues = _numericValues(teamEntries, teleopField);
    final autoValues = _numericValues(teamEntries, autoField);
    return TeamSummaryRow(
      teamNumber: team,
      iqmTeleop: teleopValues.isEmpty ? null : interquartileMean(teleopValues),
      maxTeleop: teleopValues.isEmpty ? null : _max(teleopValues),
      iqmAuto: autoValues.isEmpty ? null : interquartileMean(autoValues),
      maxAuto: autoValues.isEmpty ? null : _max(autoValues),
      autoClimbRate: _successRate(teamEntries, autoClimbField),
      lowClimbRate: _successRate(teamEntries, lowClimbField),
      middleClimbRate: _successRate(teamEntries, middleClimbField),
      highClimbRate: _successRate(teamEntries, highClimbField),
    );
  }

  static double _max(List<double> values) =>
      values.reduce((a, b) => a > b ? a : b);

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }

  static List<double> _numericValues(
    List<ScoutEntry> entries,
    ScoutConfigField? field,
  ) {
    if (field == null) return const <double>[];
    final values = <double>[];
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(field.code)) continue;
      final raw = entry.fieldValues[field.code];
      final value = raw is num
          ? raw.toDouble()
          : num.tryParse(raw?.toString() ?? '')?.toDouble();
      if (value != null) values.add(value);
    }
    return values;
  }

  static double? _successRate(
    List<ScoutEntry> entries,
    ScoutConfigField? field,
  ) {
    if (field == null) return null;
    var withValue = 0;
    var successes = 0;
    for (final entry in entries) {
      if (!entry.fieldValues.containsKey(field.code)) continue;
      final raw = entry.fieldValues[field.code];
      withValue++;
      if (_isSuccess(field, raw)) successes++;
    }
    if (withValue == 0) return null;
    return successes / withValue;
  }

  static bool _isSuccess(ScoutConfigField field, dynamic raw) {
    if (raw == null) return false;
    return _successLabels.contains(field.labelForStored(raw));
  }
}
