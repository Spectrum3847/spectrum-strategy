import '../models/scout_config.dart';

bool isContradictedNoShow(
  ScoutConfigField field,
  Map<String, dynamic> values,
  ScoutConfig config,
) {
  if (field.type != ScoutFieldType.select) return false;
  final label = field.labelForStored(values[field.code]);
  if (label.toLowerCase().replaceAll(RegExp('[^a-z]'), '') != 'noshow') {
    return false;
  }
  for (final other in config.allFields) {
    final value = values[other.code];
    if (value == null) continue;
    switch (other.type) {
      case ScoutFieldType.counter:
      case ScoutFieldType.multiCounter:
      case ScoutFieldType.range:
        final count = storedCounterValue(value);
        final initial = storedCounterValue(other.effectiveDefault) ?? 0;
        if (count != null && count != initial) return true;
      case ScoutFieldType.boolean:
        final checked = value == true || value.toString() == 'true';
        if (checked != (other.effectiveDefault == true)) return true;
      default:
        break;
    }
  }
  return false;
}
