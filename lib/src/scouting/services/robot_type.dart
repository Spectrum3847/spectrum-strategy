import '../models/pit_scout_entry.dart';
import '../models/scout_config.dart';

class RobotType {
  const RobotType._();

  static const driveTrainCode = 'drivetrainType';
  static const trenchFitCode = 'trenchFit';
  static const launcherTypeCode = 'launcherType';

  static String composeFrom(
    PitScoutEntry? entry, {
    ScoutConfigField? driveTrainField,
  }) {
    if (entry == null) return '';
    final parts = <String>[
      _driveTrain(entry.fieldValues, driveTrainField),
      _trenchFit(entry.fieldValues),
      _text(entry.fieldValues[launcherTypeCode]),
    ].where((part) => part.isNotEmpty);
    return parts.join(' · ');
  }

  static String _driveTrain(
    Map<String, dynamic> fieldValues,
    ScoutConfigField? field,
  ) {
    if (!fieldValues.containsKey(driveTrainCode)) return '';
    final raw = fieldValues[driveTrainCode];
    if (field == null) return _text(raw);
    return field.labelForStored(raw);
  }

  static String _text(dynamic raw) => raw?.toString().trim() ?? '';

  static String _trenchFit(Map<String, dynamic> fieldValues) {
    if (!fieldValues.containsKey(trenchFitCode)) return '';
    final raw = fieldValues[trenchFitCode];
    final fits = raw is bool ? raw : raw?.toString().toLowerCase() == 'true';
    return fits ? 'trench' : 'bump';
  }
}
