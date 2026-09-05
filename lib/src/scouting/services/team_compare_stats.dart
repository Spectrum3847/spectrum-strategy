import '../models/scout_config.dart';
import '../models/scout_entry.dart';
import 'entry_match.dart';

class TeamCompareRow {
  const TeamCompareRow({
    required this.matchLabel,
    required this.startingPosition,
    this.autoFuel,
    required this.autoClimb,
    this.teleopFuel,
    this.fuelAccuracy,
    this.defense,
    this.passerPusher,
    required this.climbPosition,
    required this.lowClimb,
    required this.middleClimb,
    required this.highClimb,
  });

  final String matchLabel;
  final String startingPosition;
  final double? autoFuel;
  final String autoClimb;
  final double? teleopFuel;
  final double? fuelAccuracy;
  final bool? defense;
  final bool? passerPusher;
  final String climbPosition;
  final String lowClimb;
  final String middleClimb;
  final String highClimb;
}

class TeamCompareStats {
  const TeamCompareStats._();

  static const _startingCode = 'starting';
  static const _autoFuelCode = 'autoFuelScored';
  static const _autoClimbCode = 'auLow';
  static const _teleopFuelCode = 'teleopFuelScored';
  static const _fuelAccuracyCode = 'scoringEff';
  static const _defenseCode = 'tRdefense';
  static const _passerCode = 'tRpasser';
  static const _climbPositionCode = 'ePclimb';
  static const _lowClimbCode = 'eLow';
  static const _middleClimbCode = 'eMiddle';
  static const _highClimbCode = 'eHigh';

  static List<TeamCompareRow> rowsFor(
    int teamNumber,
    Iterable<ScoutEntry> entries, {
    ScoutConfig? config,
  }) {
    final teamEntries =
        entries.where((e) => e.teamNumber == teamNumber).toList(growable: false)
          ..sort(_byMatch);

    final startingField = _fieldFor(config, _startingCode);
    final autoClimbField = _fieldFor(config, _autoClimbCode);
    final climbPositionField = _fieldFor(config, _climbPositionCode);
    final lowClimbField = _fieldFor(config, _lowClimbCode);
    final middleClimbField = _fieldFor(config, _middleClimbCode);
    final highClimbField = _fieldFor(config, _highClimbCode);

    return <TeamCompareRow>[
      for (final entry in teamEntries)
        TeamCompareRow(
          matchLabel: matchLabelOfEntry(entry),
          startingPosition: _label(entry, startingField, _startingCode),
          autoFuel: _numericValue(entry.fieldValues[_autoFuelCode]),
          autoClimb: _label(entry, autoClimbField, _autoClimbCode),
          teleopFuel: _numericValue(entry.fieldValues[_teleopFuelCode]),
          fuelAccuracy: _numericValue(entry.fieldValues[_fuelAccuracyCode]),
          defense: _boolValue(entry.fieldValues[_defenseCode]),
          passerPusher: _boolValue(entry.fieldValues[_passerCode]),
          climbPosition: _label(entry, climbPositionField, _climbPositionCode),
          lowClimb: _label(entry, lowClimbField, _lowClimbCode),
          middleClimb: _label(entry, middleClimbField, _middleClimbCode),
          highClimb: _label(entry, highClimbField, _highClimbCode),
        ),
    ];
  }

  static (List<double?>, List<double?>) fuelSeries(List<TeamCompareRow> rows) {
    return (
      [for (final row in rows) row.autoFuel],
      [for (final row in rows) row.teleopFuel],
    );
  }

  static int _byMatch(ScoutEntry a, ScoutEntry b) {
    final na = matchNumberOfEntry(a);
    final nb = matchNumberOfEntry(b);
    if (na != null && nb != null) {
      final byNumber = na.compareTo(nb);
      if (byNumber != 0) return byNumber;
    } else if (na != null) {
      return -1;
    } else if (nb != null) {
      return 1;
    }
    return matchLabelOfEntry(a).compareTo(matchLabelOfEntry(b));
  }

  static ScoutConfigField? _fieldFor(ScoutConfig? config, String code) {
    if (config == null) return null;
    for (final field in config.allFields) {
      if (field.code == code) return field;
    }
    return null;
  }

  static String _label(ScoutEntry entry, ScoutConfigField? field, String code) {
    final raw = entry.fieldValues[code];
    if (raw == null) return '--';
    if (field != null) return field.labelForStored(raw);
    return raw.toString();
  }

  static double? _numericValue(dynamic raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return num.tryParse(raw)?.toDouble();
    return null;
  }

  static bool? _boolValue(dynamic raw) => raw is bool ? raw : null;
}
