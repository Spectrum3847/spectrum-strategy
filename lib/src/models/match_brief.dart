enum RobotRole {
  start('Start'),
  endgame('Endgame'),
  auto('Auto'),
  teleop('Teleop role');

  const RobotRole(this.label);

  final String label;
}

class RobotRoles {
  const RobotRoles([this.values = const <RobotRole, String>{}]);

  static const int maxLength = 80;

  final Map<RobotRole, String> values;

  String of(RobotRole role) => values[role] ?? '';

  bool get isEmpty => values.values.every((v) => v.trim().isEmpty);

  Map<String, dynamic> toJson() => <String, dynamic>{
    for (final entry in values.entries)
      if (entry.value.trim().isNotEmpty) entry.key.name: entry.value,
  };

  static RobotRoles fromJson(Object? json) {
    if (json is! Map) return const RobotRoles();
    return RobotRoles(<RobotRole, String>{
      for (final role in RobotRole.values)
        if (json[role.name] is String) role: json[role.name] as String,
    });
  }
}

class MatchBrief {
  const MatchBrief({
    required this.id,
    required this.eventKey,
    required this.matchId,
    required this.updatedAt,
    this.robotPlans = const <int, String>{},
    this.robotRoles = const <int, RobotRoles>{},
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

  final Map<int, RobotRoles> robotRoles;
  final String keyPoints;

  final bool ready;

  final String authorUid;
  final String authorDisplayName;
  final DateTime updatedAt;

  static String idFor(String eventKey, String matchId) =>
      '${eventKey}_$matchId';

  String planFor(int team) => robotPlans[team] ?? '';

  RobotRoles rolesFor(int team) => robotRoles[team] ?? const RobotRoles();

  bool get isEmpty =>
      keyPoints.trim().isEmpty &&
      robotPlans.values.every((plan) => plan.trim().isEmpty) &&
      robotRoles.values.every((roles) => roles.isEmpty);

  MatchBrief copyWith({
    Map<int, String>? robotPlans,
    Map<int, RobotRoles>? robotRoles,
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
    robotRoles: robotRoles ?? this.robotRoles,
    keyPoints: keyPoints ?? this.keyPoints,
    ready: ready ?? this.ready,
    authorUid: authorUid ?? this.authorUid,
    authorDisplayName: authorDisplayName ?? this.authorDisplayName,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> get _rolesJson => <String, dynamic>{
    for (final entry in robotRoles.entries)
      if (!entry.value.isEmpty) '${entry.key}': entry.value.toJson(),
  };

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'eventKey': eventKey,
    'matchId': matchId,
    'robotPlans': robotPlans.map((team, plan) => MapEntry('$team', plan)),

    if (_rolesJson.isNotEmpty) 'robotRoles': _rolesJson,
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
    final roles = <int, RobotRoles>{};
    final rawRoles = json['robotRoles'];
    if (rawRoles is Map) {
      for (final entry in rawRoles.entries) {
        final team = int.tryParse('${entry.key}');
        if (team != null) roles[team] = RobotRoles.fromJson(entry.value);
      }
    }
    return MatchBrief(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : idFor(eventKey, matchId),
      eventKey: eventKey,
      matchId: matchId,
      robotPlans: plans,
      robotRoles: roles,
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
