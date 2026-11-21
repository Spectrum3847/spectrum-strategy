import 'scout_config.dart';

List<ScoutConfigField> emptyRequiredFields(
  ScoutConfig config,
  Map<String, dynamic> values,
) {
  if (_isNoShow(config, values)) return const [];
  return [
    for (final field in config.allFields)
      if (field.required &&
          field.isVisible(values) &&
          _isEmpty(field, values[field.code]))
        field,
  ];
}

bool _isNoShow(ScoutConfig config, Map<String, dynamic> values) => config
    .allFields
    .where((f) => f.type == ScoutFieldType.select)
    .any((f) => _normalize(values[f.code]?.toString() ?? '') == 'noshow');

String _normalize(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _isEmpty(ScoutConfigField field, Object? value) {
  switch (field.type) {
    case ScoutFieldType.boolean:
    case ScoutFieldType.counter:
    case ScoutFieldType.multiCounter:
    case ScoutFieldType.range:
    case ScoutFieldType.actionTracker:
      return false;
    case ScoutFieldType.tbaTeamAndRobot:
      if (value is! Map) return true;
      final team = value['teamNumber'];
      final number = team is num ? team.toInt() : int.tryParse('$team');
      return number == null || number <= 0;
    case ScoutFieldType.number:
      final number = num.tryParse(value?.toString().trim() ?? '');
      if (number == null) return true;
      final min = field.min;
      final max = field.max;
      return (min != null && number < min) || (max != null && number > max);
    case ScoutFieldType.text:
    case ScoutFieldType.longText:
    case ScoutFieldType.tbaMatchNumber:
    case ScoutFieldType.select:
    case ScoutFieldType.checkboxSelect:
    case ScoutFieldType.document:
      return value == null || value.toString().trim().isEmpty;
  }
}
