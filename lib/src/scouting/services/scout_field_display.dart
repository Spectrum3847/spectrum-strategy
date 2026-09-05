import '../models/scout_config.dart';

String displayFieldValue(ScoutConfigField? field, Object? stored) {
  if (stored == null) return '';
  if (field == null) return stored.toString();
  switch (field.type) {
    case ScoutFieldType.select:
      return field.labelForStored(stored);
    case ScoutFieldType.checkboxSelect:
      final keys = ScoutConfigField.selectedKeys(stored);
      if (keys.isEmpty) return stored.toString();
      return keys.map((String key) => field.choices?[key] ?? key).join(', ');
    default:
      return stored.toString();
  }
}
