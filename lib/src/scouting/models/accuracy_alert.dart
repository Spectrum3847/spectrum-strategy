class FlaggedField {
  const FlaggedField({
    required this.fieldCode,
    required this.scoutedValue,
    required this.officialValue,
  });

  factory FlaggedField.fromJson(Map<String, dynamic> json) {
    return FlaggedField(
      fieldCode: (json['fieldCode'] as String?) ?? '',
      scoutedValue: json['scoutedValue'],
      officialValue: json['officialValue'],
    );
  }

  final String fieldCode;
  final dynamic scoutedValue;
  final dynamic officialValue;
}

class AccuracyAlert {
  AccuracyAlert({
    required this.entryId,
    required this.teamNumber,
    required this.tbaMatchKey,
    required this.authorUid,
    this.authorDisplayName = '',
    required this.flaggedFields,
    required this.createdAt,
    DateTime? updatedAt,
    this.acknowledged = false,
  }) : updatedAt = updatedAt ?? createdAt;

  factory AccuracyAlert.fromJson(Map<String, dynamic> json) {
    final rawFields = (json['flaggedFields'] as List<dynamic>?) ?? const [];
    final createdAt =
        DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
        DateTime.now().toUtc();
    return AccuracyAlert(
      entryId: (json['entryId'] as String?) ?? '',
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      tbaMatchKey: (json['tbaMatchKey'] as String?) ?? '',
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
      flaggedFields: rawFields
          .map((f) => FlaggedField.fromJson((f as Map).cast<String, dynamic>()))
          .toList(growable: false),
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ?? createdAt,
      acknowledged: (json['acknowledged'] as bool?) ?? false,
    );
  }

  final String entryId;
  final int teamNumber;
  final String tbaMatchKey;
  final String authorUid;
  final String authorDisplayName;
  final List<FlaggedField> flaggedFields;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool acknowledged;
}
