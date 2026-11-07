library;

class TRexTraitColumn {
  const TRexTraitColumn({
    required this.key,
    required this.name,
    List<String>? names,
  }) : names = names ?? const <String>[];

  final String key;
  final String name;

  final List<String> names;

  TRexTraitColumn copyWith({String? name, List<String>? names}) =>
      TRexTraitColumn(
        key: key,
        name: name ?? this.name,
        names: names ?? this.names,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'name': name,
    'names': names,
  };

  static TRexTraitColumn? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final name = json['name'];
    if (key is! String || key.isEmpty) return null;
    if (name is! String) return null;
    final names = <String>[];
    final rawNames = json['names'];
    if (rawNames is List) {
      for (final entry in rawNames) {
        if (entry is String && entry.trim().isNotEmpty) names.add(entry);
      }
    }
    return TRexTraitColumn(key: key, name: name, names: names);
  }
}

class TRexAssignments {
  const TRexAssignments({
    List<TRexTraitColumn>? columns,
    required this.updatedAt,
    this.authorUid = '',
    this.authorDisplayName = '',
  }) : columns = columns ?? const <TRexTraitColumn>[];

  final List<TRexTraitColumn> columns;
  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  bool get isEmpty => columns.isEmpty;

  TRexTraitColumn? byKey(String key) {
    for (final column in columns) {
      if (column.key == key) return column;
    }
    return null;
  }

  TRexAssignments copyWith({
    List<TRexTraitColumn>? columns,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) => TRexAssignments(
    columns: columns ?? this.columns,
    updatedAt: updatedAt ?? this.updatedAt,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'columns': [for (final column in columns) column.toJson()],
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static TRexAssignments fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return TRexAssignments(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    final columns = <TRexTraitColumn>[];
    final raw = json['columns'];
    if (raw is List) {
      for (final entry in raw) {
        final column = TRexTraitColumn.fromJson(entry);
        if (column != null) columns.add(column);
      }
    }
    return TRexAssignments(
      columns: columns,
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
}
