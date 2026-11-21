library;

final RegExp _separators = RegExp(r'[\n\r,;\t]+');

List<String> parsePastedNames(String raw) {
  final seen = <String>{};
  final names = <String>[];
  for (final part in raw.split(_separators)) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;
    if (!seen.add(trimmed.toLowerCase())) continue;
    names.add(trimmed);
  }
  return List<String>.unmodifiable(names);
}

List<String> appendNewEntries(List<String> existing, List<String> incoming) {
  final seen = existing.map((e) => e.toLowerCase()).toSet();
  final merged = List<String>.of(existing);
  for (final value in incoming) {
    if (seen.add(value.toLowerCase())) merged.add(value);
  }
  return merged;
}
