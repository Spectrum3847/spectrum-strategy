import 'package:uuid/uuid.dart';

class PrescoutEntry {
  PrescoutEntry({
    String? id,
    required this.teamNumber,
    this.eventKey = '',
    Map<String, dynamic>? fieldValues,
    this.authorUid = '',
    this.authorDisplayName = '',
    DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       fieldValues = fieldValues ?? const <String, dynamic>{},
       updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  final String id;
  final int teamNumber;

  final String eventKey;

  final Map<String, dynamic> fieldValues;

  final String authorUid;

  final String authorDisplayName;

  final DateTime updatedAt;

  PrescoutEntry copyWith({
    int? teamNumber,
    String? eventKey,
    Map<String, dynamic>? fieldValues,
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
  }) {
    return PrescoutEntry(
      id: id,
      teamNumber: teamNumber ?? this.teamNumber,
      eventKey: eventKey ?? this.eventKey,
      fieldValues: fieldValues ?? this.fieldValues,
      authorUid: authorUid ?? this.authorUid,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'teamNumber': teamNumber,
      'eventKey': eventKey,
      'fieldValues': fieldValues,
      'authorUid': authorUid,
      'authorDisplayName': authorDisplayName,
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory PrescoutEntry.fromJson(Map<String, dynamic> json) {
    final rawFieldValues =
        (json['fieldValues'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final rawUpdatedAt = json['updatedAt'] as String? ?? '';
    return PrescoutEntry(
      id: json['id'] as String?,
      teamNumber: (json['teamNumber'] as num?)?.toInt() ?? 0,
      eventKey: (json['eventKey'] as String?) ?? '',
      fieldValues: rawFieldValues,
      authorUid: (json['authorUid'] as String?) ?? '',
      authorDisplayName: (json['authorDisplayName'] as String?) ?? '',
      updatedAt: DateTime.tryParse(rawUpdatedAt) ?? DateTime.now().toUtc(),
    );
  }
}
