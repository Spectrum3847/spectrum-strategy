class MatchBrief {
  const MatchBrief({
    required this.id,
    required this.eventKey,
    required this.matchId,
    required this.updatedAt,
    this.robotPlans = const <int, String>{},
    this.keyPoints = '',
    this.ready = false,
    this.authorUid = '',
    this.authorDisplayName = '',
  });

  static const int maxPlanLength = 280;
  static const int maxKeyPointsLength = 1000;

  final String id;
  final String eventKey;

  final String matchId;

  final Map<int, String> robotPlans;
  final String keyPoints;

  final bool ready;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  static String idFor(String eventKey, String matchId) =>
      '${eventKey}_$matchId';

  String planFor(int team) => robotPlans[team] ?? '';

  bool get isEmpty =>
      keyPoints.trim().isEmpty &&
      robotPlans.values.every((plan) => plan.trim().isEmpty);

  MatchBrief copyWith({
    Map<int, String>? robotPlans,
    String? keyPoints,
    bool? ready,
    String? authorUid,
    String? authorDisplayName,
    DateTime? updatedAt,
  }) => MatchBrief(
    id: id,
    eventKey: eventKey,
    matchId: matchId,
    robotPlans: robotPlans ?? this.robotPlans,
    keyPoints: keyPoints ?? this.keyPoints,
    ready: ready ?? this.ready,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'matchId': matchId,
    'robotPlans': robotPlans.map((team, plan) => MapEntry('$team', plan)),
    'keyPoints': keyPoints,
    'ready': ready,
    'authorUid': authorUid,
    'authorDisplayName': authorDisplayName,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  static MatchBrief fromJson(Map<String, dynamic> json) {
    final eventKey = json['eventKey'] is String
        ? json['eventKey'] as String
        : '';
    final matchId = json['matchId'] is String ? json['matchId'] as String : '';
    final plans = <int, String>{};
    final rawPlans = json['robotPlans'];
    if (rawPlans is Map) {
      for (final entry in rawPlans.entries) {
        final team = int.tryParse('${entry.key}');
        if (team != null && entry.value is String) {
          plans[team] = entry.value as String;
        }
      }
    }
    return MatchBrief(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : idFor(eventKey, matchId),
      eventKey: eventKey,
      matchId: matchId,
      robotPlans: plans,
      keyPoints: json['keyPoints'] is String ? json['keyPoints'] as String : '',
      ready: json['ready'] == true,
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
