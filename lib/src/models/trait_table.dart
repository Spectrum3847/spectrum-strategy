library;

class TraitTable {
  const TraitTable({
    required this.id,
    required this.eventKey,
    required this.matchId,
    required this.updatedAt,
    Map<int, Map<String, String>>? cells,
    this.authorUid = '',
    this.authorDisplayName = '',
  }) : cells = cells ?? const <int, Map<String, String>>{};

  final String id;

  final String eventKey;
  final String matchId;

  final Map<int, Map<String, String>> cells;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  static String idFor(String eventKey, String matchId) =>
      '${eventKey}_$matchId';

  List<int> get teamNumbers => cells.keys.toList()..sort();

  bool get isEmpty =>
      cells.values.every((row) => row.values.every((v) => v.trim().isEmpty));

  String valueFor(int teamNumber, String traitKey) =>
      cells[teamNumber]?[traitKey] ?? '';

  TraitTable withCell({
    required int teamNumber,
    required String traitKey,
    required String value,
    required DateTime updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) {
    final next = <int, Map<String, String>>{
      for (final entry in cells.entries)
        entry.key: Map<String, String>.from(entry.value),
    };
    final row = next.putIfAbsent(teamNumber, () => <String, String>{});
    if (value.trim().isEmpty) {
      row.remove(traitKey);
      if (row.isEmpty) next.remove(teamNumber);
    } else {
      row[traitKey] = value;
    }
    return copyWith(
      cells: next,
      updatedAt: updatedAt,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
    );
  }

  TraitTable copyWith({
    Map<int, Map<String, String>>? cells,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) => TraitTable(
    id: id,
    eventKey: eventKey,
    matchId: matchId,
    cells: cells ?? this.cells,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'matchId': matchId,
    'cells': <String, dynamic>{
      for (final entry in cells.entries)
        if (entry.value.isNotEmpty) '${entry.key}': entry.value,
    },
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static TraitTable fromJson(Map<String, dynamic> json) {
    final eventKey = json['eventKey'] is String
        ? json['eventKey'] as String
        : '';
    final matchId = json['matchId'] is String ? json['matchId'] as String : '';
    return TraitTable(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : idFor(eventKey, matchId),
      eventKey: eventKey,
      matchId: matchId,
      cells: _cells(json['cells']),
      authorUid: json['authorUid'] is String ? json['authorUid'] as String : '',
      authorDisplayName: json['authorDisplayName'] is String
          ? json['authorDisplayName'] as String
          : '',
      updatedAt:
          DateTime.tryParse(
            json['updatedAt'] is String ? json['updatedAt'] as String : '',
          )?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static Map<int, Map<String, String>> _cells(Object? json) {
    if (json is! Map) return const <int, Map<String, String>>{};
    final out = <int, Map<String, String>>{};
    for (final entry in json.entries) {
      final team = int.tryParse('${entry.key}');
      final row = entry.value;
      if (team == null || row is! Map) continue;
      final values = <String, String>{};
      for (final cell in row.entries) {
        final key = '${cell.key}';
        final value = cell.value;
        if (key.isEmpty || value is! String || value.isEmpty) continue;
        values[key] = value;
      }
      if (values.isNotEmpty) out[team] = values;
    }
    return out;
  }
}
