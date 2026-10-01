class PickList {
  const PickList({
    required this.id,
    required this.name,
    required this.teamNumbers,
    required this.updatedAt,
    this.authorUid = '',
    this.authorDisplayName = '',
  });

  final String id;
  final String name;
  final List<int> teamNumbers;
  final DateTime updatedAt;
  final String authorUid;
  final String authorDisplayName;

  PickList copyWith({
    String? name,
    List<int>? teamNumbers,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) {
    return PickList(
      id: id,
      name: name ?? this.name,
      teamNumbers: teamNumbers ?? this.teamNumbers,
      updatedAt: updatedAt ?? this.updatedAt,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'teamNumbers': teamNumbers,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
  };

  factory PickList.fromJson(Map<String, dynamic> json) {
    final rawTeams = (json['teamNumbers'] as List?) ?? <dynamic>[];
    return PickList(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',

      teamNumbers: rawTeams
          .whereType<num>()
          .map((e) => e.toInt())
          .where((n) => n >= 1 && n <= 99999)
          .toList(growable: false),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
    );
  }
}
