library;

class ToolArgumentError implements Exception {
  const ToolArgumentError(this.message);

  final String message;

  @override
  String toString() => message;
}

final RegExp _eventKeyPattern = RegExp(r'^[0-9]{4}[a-z0-9]{2,20}$');

const int maxTeamNumber = 99999;

int requireTeamNumber(Map<String, dynamic> arguments, String key) {
  final value = arguments[key];
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null || number <= 0 || number > maxTeamNumber) {
    throw ToolArgumentError(
      '"$key" must be a positive team number (1-$maxTeamNumber), got: $value',
    );
  }
  return number;
}

int? optionalTeamNumber(Map<String, dynamic> arguments, String key) {
  if (!arguments.containsKey(key) || arguments[key] == null) return null;
  return requireTeamNumber(arguments, key);
}

String requireEventKey(Map<String, dynamic> arguments, String key) {
  final value = arguments[key];
  final text = value is String ? value.trim().toLowerCase() : '';
  if (!_eventKeyPattern.hasMatch(text)) {
    throw ToolArgumentError(
      '"$key" must look like a year-plus-code event key (e.g. "2026txhou"), '
      'got: $value',
    );
  }
  return text;
}

String? optionalEventKey(Map<String, dynamic> arguments, String key) {
  if (!arguments.containsKey(key) || arguments[key] == null) return null;
  return requireEventKey(arguments, key);
}

int? optionalBoundedInt(
  Map<String, dynamic> arguments,
  String key, {
  required int min,
  required int max,
}) {
  if (!arguments.containsKey(key) || arguments[key] == null) return null;
  final value = arguments[key];
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null || number < min || number > max) {
    throw ToolArgumentError(
      '"$key" must be an integer between $min and $max, got: $value',
    );
  }
  return number;
}

String? optionalPlainString(
  Map<String, dynamic> arguments,
  String key, {
  int maxLength = 200,
}) {
  final value = arguments[key];
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxLength) {
    throw ToolArgumentError('"$key" is too long (max $maxLength characters).');
  }
  return trimmed;
}
