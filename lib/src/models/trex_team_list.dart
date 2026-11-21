library;

class TRexTeamListColumn {
  const TRexTeamListColumn({
    required this.key,
    required this.name,
    List<String>? teams,
  }) : teams = teams ?? const <String>[];

  final String key;
  final String name;

  final List<String> teams;

  TRexTeamListColumn copyWith({String? name, List<String>? teams}) =>
      TRexTeamListColumn(
        key: key,
        name: name ?? this.name,
        teams: teams ?? this.teams,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'name': name,
    'teams': teams,
  };

  static TRexTeamListColumn? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final name = json['name'];
    if (key is! String || key.isEmpty) return null;
    if (name is! String) return null;
    final teams = <String>[];
    final rawTeams = json['teams'];
    if (rawTeams is List) {
      for (final entry in rawTeams) {
        if (entry is String && entry.trim().isNotEmpty) teams.add(entry);
      }
    }
    return TRexTeamListColumn(key: key, name: name, teams: teams);
  }
}

class TRexTeamList {
  const TRexTeamList({
    this.title = '',
    List<TRexTeamListColumn>? columns,
    required this.updatedAt,
    this.authorUid = '',
    this.authorDisplayName = '',
  }) : columns = columns ?? const <TRexTeamListColumn>[];

  final String title;
  final List<TRexTeamListColumn> columns;
  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  bool get isEmpty => columns.isEmpty;

  int get totalTeams =>
      columns.fold(0, (sum, column) => sum + column.teams.length);

  TRexTeamListColumn? byKey(String key) {
    for (final column in columns) {
      if (column.key == key) return column;
    }
    return null;
  }

  TRexTeamList copyWith({
    String? title,
    List<TRexTeamListColumn>? columns,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) => TRexTeamList(
    title: title ?? this.title,
    columns: columns ?? this.columns,
    updatedAt: updatedAt ?? this.updatedAt,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'columns': [for (final column in columns) column.toJson()],
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static TRexTeamList fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return TRexTeamList(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    final columns = <TRexTeamListColumn>[];
    final raw = json['columns'];
    if (raw is List) {
      for (final entry in raw) {
        final column = TRexTeamListColumn.fromJson(entry);
        if (column != null) columns.add(column);
      }
    }
    return TRexTeamList(
      title: json['title'] is String ? json['title'] as String : '',
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
