import '../models/scout_entry.dart';

({String? level, int number})? parseMatchLabel(String raw) {
  final text = raw.trim().toLowerCase();
  if (text.isEmpty) return null;

  final tail = text.contains('_') ? text.split('_').last : text;
  final compact = tail.replaceAll(' ', '');

  final withLevel = RegExp(r'^([a-z]+)(\d+)(?:m(\d+))?$').firstMatch(compact);
  if (withLevel != null) {
    final number = int.tryParse(withLevel.group(3) ?? withLevel.group(2)!);
    if (number != null) {
      return (level: _levelAliases[withLevel.group(1)!], number: number);
    }
  }

  final bare = int.tryParse(compact);
  if (bare != null) return (level: null, number: bare);
  return null;
}

int? matchNumberOfEntry(ScoutEntry entry) => _labelOfEntry(entry)?.number;

String matchGroupKeyOfEntry(ScoutEntry entry) {
  final key = entry.tbaMatchKey?.trim() ?? '';
  if (key.isNotEmpty) return key.toLowerCase();
  final label = _labelOfEntry(entry);
  if (label == null) return entry.matchId;
  return '${label.level ?? 'm'}${label.number}';
}

String matchLabelOfEntry(ScoutEntry entry) {
  final label = _labelOfEntry(entry);
  if (label == null) return entry.matchId.isEmpty ? 'No match' : entry.matchId;
  return switch (label.level) {
    'qm' || null => 'Match ${label.number}',
    'qf' => 'Quarterfinal ${label.number}',
    'sf' => 'Semifinal ${label.number}',
    'f' => 'Final ${label.number}',
    final other => '${other.toUpperCase()} ${label.number}',
  };
}

({String? level, int number})? _labelOfEntry(ScoutEntry entry) {
  final key = entry.tbaMatchKey?.trim() ?? '';
  if (key.isNotEmpty) {
    final fromKey = parseMatchLabel(key);
    if (fromKey != null) return fromKey;
  }
  final typed = entry.fieldValues['matchNumber'];
  if (typed is num) return (level: null, number: typed.toInt());
  if (typed is String) {
    final fromField = parseMatchLabel(typed);
    if (fromField != null) return fromField;
  }

  return parseMatchLabel(entry.matchId);
}

const Map<String, String> _levelAliases = <String, String>{
  'qm': 'qm',
  'q': 'qm',
  'qual': 'qm',
  'quals': 'qm',
  'qualification': 'qm',
  'match': 'qm',
  'm': 'qm',
  'qf': 'qf',
  'quarterfinal': 'qf',
  'sf': 'sf',
  'semifinal': 'sf',
  'p': 'sf',
  'playoff': 'sf',
  'f': 'f',
  'final': 'f',
  'finals': 'f',
};
