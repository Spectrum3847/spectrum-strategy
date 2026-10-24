library;

class PostMatchReport {
  const PostMatchReport({
    required this.id,
    required this.eventKey,
    required this.matchId,
    required this.updatedAt,
    this.auto = '',
    this.teleop = '',
    this.endgame = '',
    this.notes = '',
    this.authorUid = '',
    this.authorDisplayName = '',
  });

  final String id;

  final String eventKey;
  final String matchId;

  final String auto;

  final String teleop;

  final String endgame;

  final String notes;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  static String idFor(String eventKey, String matchId) =>
      '${eventKey}_$matchId';

  bool get isEmpty =>
      auto.trim().isEmpty &&
      teleop.trim().isEmpty &&
      endgame.trim().isEmpty &&
      notes.trim().isEmpty;

  PostMatchReport copyWith({
    String? auto,
    String? teleop,
    String? endgame,
    String? notes,
    DateTime? updatedAt,
    String? authorUid,
    String? authorDisplayName,
  }) => PostMatchReport(
    id: id,
    eventKey: eventKey,
    matchId: matchId,
    auto: auto ?? this.auto,
    teleop: teleop ?? this.teleop,
    endgame: endgame ?? this.endgame,
    notes: notes ?? this.notes,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'matchId': matchId,
    'auto': auto,
    'teleop': teleop,
    'endgame': endgame,
    'notes': notes,
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static PostMatchReport fromJson(Map<String, dynamic> json) {
    final eventKey = json['eventKey'] is String
        ? json['eventKey'] as String
        : '';
    final matchId = json['matchId'] is String ? json['matchId'] as String : '';
    return PostMatchReport(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : idFor(eventKey, matchId),
      eventKey: eventKey,
      matchId: matchId,
      auto: json['auto'] is String ? json['auto'] as String : '',
      teleop: json['teleop'] is String ? json['teleop'] as String : '',
      endgame: json['endgame'] is String ? json['endgame'] as String : '',
      notes: json['notes'] is String ? json['notes'] as String : '',
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
