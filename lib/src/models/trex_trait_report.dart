library;

import 'package:uuid/uuid.dart';

class TrexTraitReport {
  TrexTraitReport({
    String? id,
    required this.trait,
    required this.teamNumber,
    required this.matchNumber,
    this.eventName = '',
    this.report = '',
    List<dynamic>? strokes,
    this.authorUid = '',
    this.authorDisplayName = '',
    required this.updatedAt,
  }) : id = id ?? const Uuid().v4(),
       strokes = strokes ?? const <dynamic>[];

  final String id;

  final String trait;

  final int teamNumber;
  final int matchNumber;
  final String eventName;
  final String report;

  final List<dynamic> strokes;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  bool get isEmpty =>
      report.trim().isEmpty && eventName.trim().isEmpty && strokes.isEmpty;

  TrexTraitReport copyWith({
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
  }) => TrexTraitReport(
    id: id,
    trait: trait,
    teamNumber: teamNumber,
    matchNumber: matchNumber,
    eventName: eventName,
    report: report,
    strokes: strokes,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'trait': trait,
    'teamNumber': teamNumber,
    'matchNumber': matchNumber,
    'eventName': eventName,
    'report': report,
    if (strokes.isNotEmpty) 'strokes': strokes,
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static TrexTraitReport fromJson(Map<String, dynamic> json) {
    final rawStrokes = json['strokes'];
    return TrexTraitReport(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : const Uuid().v4(),
      trait: json['trait'] is String ? json['trait'] as String : '',
      teamNumber: json['teamNumber'] is int
          ? json['teamNumber'] as int
          : int.tryParse('${json['teamNumber']}') ?? 0,
      matchNumber: json['matchNumber'] is int
          ? json['matchNumber'] as int
          : int.tryParse('${json['matchNumber']}') ?? 0,
      eventName: json['eventName'] is String ? json['eventName'] as String : '',
      report: json['report'] is String ? json['report'] as String : '',
      strokes: rawStrokes is List ? rawStrokes : const <dynamic>[],
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
